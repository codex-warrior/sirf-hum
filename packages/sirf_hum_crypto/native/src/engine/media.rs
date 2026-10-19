//! ABI v6 encrypted media (Prompt 11; D-093, D-094, D-096).
//! Docs: `docs/security/E2EE-MEDIA-AND-NOTIFICATIONS.md`.
//!
//! No new construction: media objects are STREAM (Hoang–Reyhanitabar–
//! Rogaway–Vizár 2015, RustCrypto `aead::stream::StreamBE32`) over
//! XChaCha20-Poly1305, the AEAD the sealed records already use. This file is
//! policy only:
//! - a fresh random key, media ID and nonce prefix per object (OS CSPRNG);
//! - the per-chunk AAD, built here and never by the caller, binding the
//!   object to its conversation, media ID, sending device, class and length;
//! - a SHA-256 commitment to the whole object inside the MLS-authenticated
//!   `media_ref` payload, checked before anything is decrypted;
//! - media keys never leave Rust: the full `media_ref` lives only in MLS
//!   ciphertext and sealed history, and Dart gets a key-free view.
//!
//! Plaintext is never written to disk: encryption streams file to file,
//! decryption returns memory.

use std::fs::{self, File};
use std::io::{ErrorKind, Read, Write};
use std::path::{Path, PathBuf};

use chacha20poly1305::aead::stream::{DecryptorBE32, EncryptorBE32};
use chacha20poly1305::XChaCha20Poly1305;
use sha2::{Digest, Sha256};

use super::conversation::{conversation_id, message_id, now_ms, Sent, MESSAGE_ID_LEN};
use super::*;

/// Media AAD schema version (D-093).
pub const MEDIA_SCHEMA_VERSION: u16 = 1;
/// Object format version (header).
pub const MEDIA_FORMAT_VERSION: u16 = 1;
pub const MEDIA_ID_LEN: usize = 16;
/// Plaintext bytes per STREAM chunk; the last chunk holds 1..=this.
pub const MEDIA_CHUNK_BYTES: usize = 64 * 1024;
pub const MEDIA_HEADER_LEN: usize = 4 + 2 + NONCE_PREFIX_LEN;
/// Length of the full `media_ref` payload (MLS and sealed history only).
pub const MEDIA_REF_LEN: usize = 107;
/// Length of the key-free view handed to Dart.
pub const MEDIA_VIEW_LEN: usize = 43;

const MEDIA_KEY_LEN: usize = 32;
/// XChaCha20 nonce (24) minus STREAM's counter (4) and last-block flag (1).
const NONCE_PREFIX_LEN: usize = 19;
const TAG_LEN: usize = 16;
const MAGIC: &[u8; 4] = b"SHMD";
const AAD_CONTEXT: &[u8] = b"SirfHum-MediaAAD";
const AAD_VERSION: u8 = 1;
/// Application payload version and the media kind (text is kind 1, D-089).
pub(crate) const PAYLOAD_VERSION: u8 = 1;
pub(crate) const KIND_MEDIA: u8 = 2;

/// What a media object is, inside the encrypted payload and AAD only. The
/// server never learns it (Storage content type is always octet-stream).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum MediaClass {
    Image = 1,
    Video = 2,
    Audio = 3,
    File = 4,
}

impl MediaClass {
    pub fn from_u32(value: u32) -> CoreResult<Self> {
        match value {
            1 => Ok(Self::Image),
            2 => Ok(Self::Video),
            3 => Ok(Self::Audio),
            4 => Ok(Self::File),
            _ => Err(CoreError::InvalidInput),
        }
    }
}

/// The exact ciphertext object size for a plaintext length.
pub fn media_ciphertext_len(plaintext_len: u64) -> u64 {
    let chunks = plaintext_len.div_ceil(MEDIA_CHUNK_BYTES as u64);
    MEDIA_HEADER_LEN as u64 + plaintext_len + TAG_LEN as u64 * chunks
}

/// The exact per-chunk AAD of a media object (D-093).
pub(crate) fn media_aad(
    conversation: &[u8],
    media: &[u8; MEDIA_ID_LEN],
    sender: &DeviceId,
    class: MediaClass,
    plaintext_len: u64,
    header: &[u8; MEDIA_HEADER_LEN],
) -> Vec<u8> {
    let mut out = Vec::with_capacity(AAD_CONTEXT.len() + 3 + 48 + 9 + MEDIA_HEADER_LEN);
    out.extend_from_slice(AAD_CONTEXT);
    out.push(AAD_VERSION);
    out.extend_from_slice(&MEDIA_SCHEMA_VERSION.to_be_bytes());
    out.extend_from_slice(conversation);
    out.extend_from_slice(media);
    out.extend_from_slice(&sender.0);
    out.push(class as u8);
    out.extend_from_slice(&plaintext_len.to_be_bytes());
    out.extend_from_slice(header);
    out
}

/// The `media_ref` application payload (kind 2). Holds the media key:
/// it exists only inside MLS ciphertext and sealed history.
pub(crate) struct MediaRef {
    pub(crate) client_time_ms: u64,
    pub(crate) media_id: [u8; MEDIA_ID_LEN],
    pub(crate) class: MediaClass,
    pub(crate) plaintext_len: u64,
    pub(crate) ciphertext_len: u64,
    pub(crate) ciphertext_sha256: [u8; 32],
    pub(crate) key: Zeroizing<[u8; MEDIA_KEY_LEN]>,
}

impl core::fmt::Debug for MediaRef {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "MediaRef({:?}, <redacted>)", self.class)
    }
}

impl MediaRef {
    /// `version 1 | kind 2 | client time u64 | media id[16] | class u8 |
    /// plaintext len u64 | ciphertext len u64 | sha256[32] | key[32]`.
    pub(crate) fn encode(&self) -> Zeroizing<Vec<u8>> {
        let mut out = Zeroizing::new(Vec::with_capacity(MEDIA_REF_LEN));
        out.push(PAYLOAD_VERSION);
        out.push(KIND_MEDIA);
        out.extend_from_slice(&self.client_time_ms.to_be_bytes());
        out.extend_from_slice(&self.media_id);
        out.push(self.class as u8);
        out.extend_from_slice(&self.plaintext_len.to_be_bytes());
        out.extend_from_slice(&self.ciphertext_len.to_be_bytes());
        out.extend_from_slice(&self.ciphertext_sha256);
        out.extend_from_slice(&*self.key);
        out
    }

    /// Strict decode: exact length, known version, kind and class, lengths
    /// within limits and consistent with the object format.
    pub(crate) fn decode(bytes: &[u8]) -> Result<Self, ()> {
        if bytes.len() != MEDIA_REF_LEN || !claims_media(bytes) {
            return Err(());
        }
        let mut r = Reader(&bytes[2..]);
        let u64_be = |r: &mut Reader<'_>| -> Result<u64, ()> {
            Ok(u64::from_be_bytes(r.fixed::<8>().map_err(|_| ())?))
        };
        let client_time_ms = u64_be(&mut r)?;
        let media_id = r.fixed::<MEDIA_ID_LEN>().map_err(|_| ())?;
        let class = MediaClass::from_u32(u32::from(r.u8().map_err(|_| ())?)).map_err(|_| ())?;
        let plaintext_len = u64_be(&mut r)?;
        let ciphertext_len = u64_be(&mut r)?;
        let ciphertext_sha256 = r.fixed::<32>().map_err(|_| ())?;
        let key = Zeroizing::new(r.fixed::<MEDIA_KEY_LEN>().map_err(|_| ())?);
        if plaintext_len == 0
            || plaintext_len > MAX_MEDIA_PLAINTEXT_BYTES as u64
            || ciphertext_len != media_ciphertext_len(plaintext_len)
        {
            return Err(());
        }
        Ok(Self {
            client_time_ms,
            media_id,
            class,
            plaintext_len,
            ciphertext_len,
            ciphertext_sha256,
            key,
        })
    }
}

/// True when a payload claims to be a `media_ref` (version 1, kind 2).
pub(crate) fn claims_media(payload: &[u8]) -> bool {
    payload.len() >= 2 && payload[0] == PAYLOAD_VERSION && payload[1] == KIND_MEDIA
}

/// The payload as Dart may see it: a `media_ref` loses its hash and key
/// (the first [`MEDIA_VIEW_LEN`] bytes remain); other payloads pass through.
/// A stored kind-2 payload that does not decode is local corruption.
pub(crate) fn public_payload(payload: Zeroizing<Vec<u8>>) -> CoreResult<Zeroizing<Vec<u8>>> {
    if !claims_media(&payload) {
        return Ok(payload);
    }
    MediaRef::decode(&payload).map_err(|_| CoreError::StateCorruption)?;
    Ok(Zeroizing::new(payload[..MEDIA_VIEW_LEN].to_vec()))
}

/// The file name of a media object in a device's media directory:
/// `<conversation hex>_<media hex>.shm`. The core names the objects it
/// writes, so a queued message's object can always be found again.
pub fn media_object_file_name(conversation: &[u8], media: &[u8; MEDIA_ID_LEN]) -> String {
    format!("{}_{}.shm", hex_lower(conversation), hex_lower(media))
}

fn hex_lower(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push(DIGITS[(b >> 4) as usize] as char);
        s.push(DIGITS[(b & 0x0f) as usize] as char);
    }
    s
}

/// What `send_media` produced: the queued MLS message carrying the key, and
/// the ciphertext object (to upload) at `object_path`.
pub struct SentMedia {
    pub sent: Sent,
    pub media_id: [u8; MEDIA_ID_LEN],
    pub ciphertext_len: u64,
    /// `media_dir` / [`media_object_file_name`].
    pub object_path: PathBuf,
}

impl core::fmt::Debug for SentMedia {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "SentMedia(epoch: {}, <redacted>)", self.sent.epoch)
    }
}

struct Encrypted {
    plaintext_len: u64,
    ciphertext_len: u64,
    sha256: [u8; 32],
}

fn temp_path(output: &Path) -> PathBuf {
    let mut name = output.as_os_str().to_owned();
    name.push(".tmp");
    PathBuf::from(name)
}

fn header(prefix: &[u8; NONCE_PREFIX_LEN]) -> [u8; MEDIA_HEADER_LEN] {
    let mut h = [0u8; MEDIA_HEADER_LEN];
    h[..4].copy_from_slice(MAGIC);
    h[4..6].copy_from_slice(&MEDIA_FORMAT_VERSION.to_be_bytes());
    h[6..].copy_from_slice(prefix);
    h
}

/// Streams `input` (plaintext, read only) into the ciphertext object at
/// `output`: temp file, fsync, rename. Nothing is left at either path on
/// failure. `aad` receives the plaintext length and header.
fn encrypt_file(
    input: &Path,
    output: &Path,
    key: &[u8; MEDIA_KEY_LEN],
    prefix: &[u8; NONCE_PREFIX_LEN],
    aad: impl FnOnce(u64, &[u8; MEDIA_HEADER_LEN]) -> Vec<u8>,
) -> CoreResult<Encrypted> {
    let mut src = File::open(input).map_err(|_| CoreError::InvalidInput)?;
    let meta = src.metadata().map_err(|_| CoreError::InvalidInput)?;
    if !meta.is_file() || meta.len() == 0 {
        return Err(CoreError::InvalidInput);
    }
    let plaintext_len = meta.len();
    limits::check(
        usize::try_from(plaintext_len).unwrap_or(usize::MAX),
        MAX_MEDIA_PLAINTEXT_BYTES,
    )?;
    let header = header(prefix);
    let aad = aad(plaintext_len, &header);
    let tmp = temp_path(output);
    let result = (|| {
        let mut out = File::create(&tmp).map_err(|_| CoreError::PersistenceFailure)?;
        let mut hash = Sha256::new();
        out.write_all(&header)
            .map_err(|_| CoreError::PersistenceFailure)?;
        hash.update(header);
        let mut stream =
            EncryptorBE32::<XChaCha20Poly1305>::new(key.into(), prefix.as_slice().into());
        let mut buf = Zeroizing::new(Vec::with_capacity(MEDIA_CHUNK_BYTES + TAG_LEN));
        let mut remaining = plaintext_len;
        loop {
            let this = remaining.min(MEDIA_CHUNK_BYTES as u64) as usize;
            remaining -= this as u64;
            buf.clear();
            buf.resize(this, 0);
            // A file that shrinks while being read is refused (read_exact).
            src.read_exact(&mut buf)
                .map_err(|_| CoreError::InvalidInput)?;
            if remaining == 0 {
                stream
                    .encrypt_last_in_place(&aad, &mut *buf)
                    .map_err(|_| CoreError::InternalCryptoFailure)?;
                out.write_all(&buf)
                    .map_err(|_| CoreError::PersistenceFailure)?;
                hash.update(&*buf);
                break;
            }
            stream
                .encrypt_next_in_place(&aad, &mut *buf)
                .map_err(|_| CoreError::InternalCryptoFailure)?;
            out.write_all(&buf)
                .map_err(|_| CoreError::PersistenceFailure)?;
            hash.update(&*buf);
        }
        // A file that grew while being read is refused too: the length is
        // bound in the AAD and the payload.
        let mut probe = [0u8; 1];
        match src.read(&mut probe) {
            Ok(0) => {}
            _ => return Err(CoreError::InvalidInput),
        }
        out.sync_all().map_err(|_| CoreError::PersistenceFailure)?;
        drop(out);
        fs::rename(&tmp, output).map_err(|_| CoreError::PersistenceFailure)?;
        Ok(Encrypted {
            plaintext_len,
            ciphertext_len: media_ciphertext_len(plaintext_len),
            sha256: hash.finalize().into(),
        })
    })();
    if result.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    result
}

/// Checks the object's size and SHA-256 against the reference, then
/// decrypts it chunk by chunk into memory. Any mismatch, truncation,
/// extension, reordering or tampering is `AuthenticationFailure` and no
/// plaintext is returned (partial output is wiped).
fn decrypt_file(
    path: &Path,
    mref: &MediaRef,
    aad: impl FnOnce(&[u8; MEDIA_HEADER_LEN]) -> Vec<u8>,
) -> CoreResult<Zeroizing<Vec<u8>>> {
    let open = || {
        File::open(path).map_err(|e| match e.kind() {
            ErrorKind::NotFound => CoreError::InvalidInput,
            _ => CoreError::PersistenceFailure,
        })
    };
    let mut file = open()?;
    let len = file
        .metadata()
        .map_err(|_| CoreError::PersistenceFailure)?
        .len();
    if len != mref.ciphertext_len {
        return Err(CoreError::AuthenticationFailure);
    }

    // Pass 1: the commitment, before any decryption.
    let mut hash = Sha256::new();
    let mut buf = vec![0u8; MEDIA_CHUNK_BYTES + TAG_LEN];
    let mut left = len;
    while left > 0 {
        let n = left.min(buf.len() as u64) as usize;
        file.read_exact(&mut buf[..n])
            .map_err(|_| CoreError::AuthenticationFailure)?;
        hash.update(&buf[..n]);
        left -= n as u64;
    }
    let digest: [u8; 32] = hash.finalize().into();
    if digest != mref.ciphertext_sha256 {
        return Err(CoreError::AuthenticationFailure);
    }

    // Pass 2: decrypt. The file is re-read, so a change between the passes
    // still fails the AEAD.
    let mut file = open()?;
    let mut header = [0u8; MEDIA_HEADER_LEN];
    file.read_exact(&mut header)
        .map_err(|_| CoreError::AuthenticationFailure)?;
    if &header[..4] != MAGIC || header[4..6] != MEDIA_FORMAT_VERSION.to_be_bytes() {
        return Err(CoreError::AuthenticationFailure);
    }
    let prefix: [u8; NONCE_PREFIX_LEN] = header[6..].try_into().map_err(|_| CoreError::Internal)?;
    let aad = aad(&header);
    let mut stream =
        DecryptorBE32::<XChaCha20Poly1305>::new((&*mref.key).into(), prefix.as_slice().into());
    let total = usize::try_from(mref.plaintext_len).map_err(|_| CoreError::InputTooLarge)?;
    // Exact capacity: never reallocated, so no unwiped copy is left behind
    // (and the FFI hands this exact buffer over without shrinking it).
    let mut plaintext = Zeroizing::new(Vec::with_capacity(total));
    let mut chunk = Zeroizing::new(Vec::with_capacity(MEDIA_CHUNK_BYTES + TAG_LEN));
    let mut remaining = mref.plaintext_len;
    loop {
        let this = remaining.min(MEDIA_CHUNK_BYTES as u64) as usize;
        remaining -= this as u64;
        chunk.clear();
        chunk.resize(this + TAG_LEN, 0);
        file.read_exact(&mut chunk)
            .map_err(|_| CoreError::AuthenticationFailure)?;
        if remaining == 0 {
            stream
                .decrypt_last_in_place(&aad, &mut *chunk)
                .map_err(|_| CoreError::AuthenticationFailure)?;
            plaintext.extend_from_slice(&chunk);
            break;
        }
        stream
            .decrypt_next_in_place(&aad, &mut *chunk)
            .map_err(|_| CoreError::AuthenticationFailure)?;
        plaintext.extend_from_slice(&chunk);
    }
    if plaintext.len() != total {
        return Err(CoreError::AuthenticationFailure);
    }
    Ok(plaintext)
}

impl CryptoCore {
    /// Encrypts the file at `input` into a new ciphertext object in
    /// `media_dir` (named by [`media_object_file_name`]) under a fresh key,
    /// then queues the MLS message that delivers the key (`media_ref`),
    /// sealed into history in one transaction (D-094). The caller uploads
    /// the object, then the message. On any failure no object and no
    /// message remain; a crash between the two leaves at most an orphan
    /// object, never a queued message without its object.
    pub fn send_media(
        &mut self,
        conversation: &[u8],
        input: &Path,
        media_dir: &Path,
        class: MediaClass,
    ) -> CoreResult<SentMedia> {
        self.guard()?;
        let own = self.identity()?.certificate.device_id;
        let cid = conversation_id(conversation)?.to_vec();
        // Fail before the (possibly long) encryption when sending is
        // impossible anyway; the transaction checks again.
        let group = self.state.groups.get(&cid).ok_or(CoreError::UnknownGroup)?;
        if group.pending_commit().is_some() {
            return Err(CoreError::CommitPending);
        }
        let mut media_id = [0u8; MEDIA_ID_LEN];
        OsRng.fill_bytes(&mut media_id);
        let mut key = Zeroizing::new([0u8; MEDIA_KEY_LEN]);
        OsRng.fill_bytes(&mut *key);
        let mut prefix = [0u8; NONCE_PREFIX_LEN];
        OsRng.fill_bytes(&mut prefix);
        let output = media_dir.join(media_object_file_name(&cid, &media_id));
        let enc = encrypt_file(input, &output, &key, &prefix, |len, header| {
            media_aad(&cid, &media_id, &own, class, len, header)
        })?;
        let mref = MediaRef {
            client_time_ms: now_ms(),
            media_id,
            class,
            plaintext_len: enc.plaintext_len,
            ciphertext_len: enc.ciphertext_len,
            ciphertext_sha256: enc.sha256,
            key,
        };
        let mut mid = [0u8; MESSAGE_ID_LEN];
        OsRng.fill_bytes(&mut mid);
        let payload = mref.encode();
        match self.transact(|core| core.encrypt_into_history(&cid, mid, payload, now_ms())) {
            Ok(sent) => Ok(SentMedia {
                sent,
                media_id,
                ciphertext_len: enc.ciphertext_len,
                object_path: output,
            }),
            Err(e) => {
                let _ = fs::remove_file(&output);
                Err(e)
            }
        }
    }

    /// Decrypts the media object of message `message` (sent or received,
    /// in this device's history) from the ciphertext file at `path`. The
    /// AAD comes from the history record, i.e. from the authenticated
    /// message that delivered the key. Returns plaintext in memory only.
    pub fn open_media(
        &self,
        conversation: &[u8],
        message: &[u8],
        path: &Path,
    ) -> CoreResult<Zeroizing<Vec<u8>>> {
        self.guard()?;
        self.identity()?;
        let cid = conversation_id(conversation)?;
        let mid = message_id(message)?;
        let record = self
            .load_history(cid, &mid)?
            .ok_or(CoreError::InvalidInput)?;
        if !claims_media(&record.payload) {
            return Err(CoreError::InvalidInput);
        }
        let mref = MediaRef::decode(&record.payload).map_err(|_| CoreError::StateCorruption)?;
        decrypt_file(path, &mref, |header| {
            media_aad(
                cid,
                &mref.media_id,
                &record.sender_device_id,
                mref.class,
                mref.plaintext_len,
                header,
            )
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    /// Shared with `packages/sirf_hum_crypto/test/media_types_test.dart`:
    /// the key-free view of the `media_ref` below.
    pub(crate) const MEDIA_VIEW_HEX: &str = concat!(
        "01",
        "02",
        "00000000000003e8",
        "44444444444444444444444444444444",
        "02",
        "0000000000011170",
        "00000000000111a9",
    );

    /// The media AAD for conversation 0x11.., media 0x44.., sender 0x33..,
    /// image, 65,536 bytes, nonce prefix 0x55.. (built only in Rust).
    pub(crate) const MEDIA_AAD_HEX: &str = concat!(
        "5369726648756d2d4d6564696141414401",
        "0001",
        "11111111111111111111111111111111",
        "44444444444444444444444444444444",
        "33333333333333333333333333333333",
        "01",
        "0000000000010000",
        "53484d440001",
        "55555555555555555555555555555555555555",
    );

    #[test]
    fn aad_and_payload_match_the_golden_vectors() {
        let prefix = [0x55; NONCE_PREFIX_LEN];
        let aad = media_aad(
            &[0x11; 16],
            &[0x44; 16],
            &DeviceId([0x33; 16]),
            MediaClass::Image,
            65_536,
            &header(&prefix),
        );
        assert_eq!(hex(&aad), MEDIA_AAD_HEX);
        // Shared with media_types_test.dart (`mediaObjectFileName`).
        assert_eq!(
            media_object_file_name(&[0x11; 16], &[0x44; 16]),
            "11111111111111111111111111111111_44444444444444444444444444444444.shm"
        );

        let mref = MediaRef {
            client_time_ms: 1000,
            media_id: [0x44; 16],
            class: MediaClass::Video,
            plaintext_len: 70_000,
            ciphertext_len: media_ciphertext_len(70_000),
            ciphertext_sha256: [0xaa; 32],
            key: Zeroizing::new([0xbb; 32]),
        };
        let full = mref.encode();
        assert_eq!(full.len(), MEDIA_REF_LEN);
        let back = MediaRef::decode(&full).unwrap();
        assert_eq!(back.plaintext_len, 70_000);
        assert_eq!(*back.key, [0xbb; 32]);
        let view = public_payload(full.clone()).unwrap();
        assert_eq!(view.len(), MEDIA_VIEW_LEN);
        assert_eq!(hex(&view), MEDIA_VIEW_HEX);
        assert_eq!(&view[..], &full[..MEDIA_VIEW_LEN]);
        assert!(
            !view.windows(32).any(|w| w == [0xbb; 32]),
            "the key never reaches the view"
        );
        assert!(!view.windows(32).any(|w| w == [0xaa; 32]));
        assert_eq!(format!("{mref:?}"), "MediaRef(Video, <redacted>)");
    }

    #[test]
    fn sizes_follow_the_format() {
        assert_eq!(media_ciphertext_len(1), 25 + 1 + 16);
        assert_eq!(media_ciphertext_len(65_536), 25 + 65_536 + 16);
        assert_eq!(media_ciphertext_len(65_537), 25 + 65_537 + 32);
        assert_eq!(
            media_ciphertext_len(MAX_MEDIA_PLAINTEXT_BYTES as u64),
            MAX_MEDIA_CIPHERTEXT_BYTES as u64
        );
    }

    // ---- the STREAM/AEAD layer on its own: the hash is recomputed for
    // every modified object, as if the commitment were bypassed.

    const CID: [u8; 16] = [0x11; 16];
    const MEDIA: [u8; 16] = [0x44; 16];
    const SENDER: DeviceId = DeviceId([0x33; 16]);
    const KEY: [u8; 32] = [0x07; 32];
    const PREFIX: [u8; NONCE_PREFIX_LEN] = [0x09; NONCE_PREFIX_LEN];

    type Aad = Box<dyn FnOnce(&[u8; MEDIA_HEADER_LEN]) -> Vec<u8>>;

    struct Object {
        _dir: tempfile::TempDir,
        path: PathBuf,
        data: Vec<u8>,
    }

    fn encrypted(len: usize) -> Object {
        let dir = tempfile::tempdir().unwrap();
        let input = dir.path().join("in");
        let data: Vec<u8> = (0..len).map(|i| (i % 251) as u8).collect();
        fs::write(&input, &data).unwrap();
        let path = dir.path().join("obj");
        encrypt_file(&input, &path, &KEY, &PREFIX, |n, h| {
            media_aad(&CID, &MEDIA, &SENDER, MediaClass::Image, n, h)
        })
        .unwrap();
        Object {
            _dir: dir,
            path,
            data,
        }
    }

    fn sha(bytes: &[u8]) -> [u8; 32] {
        Sha256::digest(bytes).into()
    }

    /// A reference that matches whatever is at `path` now (hash bypassed).
    fn matching_ref(path: &Path, plaintext_len: u64, key: [u8; 32]) -> MediaRef {
        let bytes = fs::read(path).unwrap();
        MediaRef {
            client_time_ms: 0,
            media_id: MEDIA,
            class: MediaClass::Image,
            plaintext_len,
            ciphertext_len: bytes.len() as u64,
            ciphertext_sha256: sha(&bytes),
            key: Zeroizing::new(key),
        }
    }

    fn aad_with(edit: impl FnOnce(&mut Vec<u8>) + 'static, len: u64) -> Aad {
        Box::new(move |h| {
            let mut aad = media_aad(&CID, &MEDIA, &SENDER, MediaClass::Image, len, h);
            edit(&mut aad);
            aad
        })
    }

    fn honest(len: u64) -> Aad {
        aad_with(|_| {}, len)
    }

    #[test]
    fn stream_layer_round_trips_and_rejects_wrong_bindings() {
        let len = 2 * MEDIA_CHUNK_BYTES + 5;
        let obj = encrypted(len);
        let n = len as u64;
        let ok = decrypt_file(&obj.path, &matching_ref(&obj.path, n, KEY), honest(n)).unwrap();
        assert_eq!(&ok[..], &obj.data[..]);

        let fail = |key: [u8; 32], aad: Aad| {
            decrypt_file(&obj.path, &matching_ref(&obj.path, n, key), aad).unwrap_err()
        };
        let auth = CoreError::AuthenticationFailure;
        let other = [0x55u8; 16];
        // Offsets into the AAD (see media_aad).
        let at = AAD_CONTEXT.len();
        let cases: Vec<(&str, [u8; 32], Aad)> = vec![
            ("wrong key", [0x08; 32], honest(n)),
            ("wrong AAD version", KEY, aad_with(move |a| a[at] = 2, n)),
            (
                "wrong schema version",
                KEY,
                aad_with(move |a| a[at + 2] ^= 1, n),
            ),
            (
                "wrong conversation",
                KEY,
                aad_with(move |a| a[at + 3..at + 19].copy_from_slice(&other), n),
            ),
            (
                "wrong media ID",
                KEY,
                aad_with(move |a| a[at + 19..at + 35].copy_from_slice(&other), n),
            ),
            (
                "wrong sender device (re-attribution)",
                KEY,
                aad_with(move |a| a[at + 35..at + 51].copy_from_slice(&other), n),
            ),
            ("wrong class", KEY, aad_with(move |a| a[at + 51] = 2, n)),
            ("wrong length", KEY, honest(n + 1)),
        ];
        for (what, key, aad) in cases {
            assert_eq!(fail(key, aad), auth, "{what}");
        }
    }

    #[test]
    fn stream_layer_detects_reordering_and_truncation_by_itself() {
        let len = 3 * MEDIA_CHUNK_BYTES;
        let obj = encrypted(len);
        let n = len as u64;
        let genuine = fs::read(&obj.path).unwrap();
        let c = MEDIA_CHUNK_BYTES + TAG_LEN;
        let chunk = |i: usize| &genuine[MEDIA_HEADER_LEN + i * c..MEDIA_HEADER_LEN + (i + 1) * c];
        let head = &genuine[..MEDIA_HEADER_LEN];
        let check = |bytes: Vec<u8>, claimed: u64, what: &str| {
            fs::write(&obj.path, bytes).unwrap();
            assert_eq!(
                decrypt_file(&obj.path, &matching_ref(&obj.path, claimed, KEY), honest(n))
                    .unwrap_err(),
                CoreError::AuthenticationFailure,
                "{what}"
            );
        };
        check([head, chunk(1), chunk(0), chunk(2)].concat(), n, "swapped");
        check([head, chunk(0), chunk(0), chunk(2)].concat(), n, "repeated");
        // Last chunk dropped and the reference claims two chunks: only the
        // STREAM last-block flag catches it (the AAD is the honest one).
        check(
            [head, chunk(0), chunk(1)].concat(),
            2 * MEDIA_CHUNK_BYTES as u64,
            "truncated at a chunk boundary",
        );
        let mut reprefixed = genuine.clone();
        reprefixed[10] ^= 1;
        check(reprefixed, n, "nonce prefix changed");
    }

    #[test]
    fn encryption_writes_the_committed_object_atomically() {
        let dir = tempfile::tempdir().unwrap();
        let input = dir.path().join("in");
        fs::write(&input, [1u8; 10]).unwrap();
        let out = dir.path().join("obj");
        let enc = encrypt_file(&input, &out, &KEY, &PREFIX, |n, h| {
            media_aad(&CID, &MEDIA, &SENDER, MediaClass::Image, n, h)
        })
        .unwrap();
        assert_eq!(enc.plaintext_len, 10);
        assert_eq!(enc.ciphertext_len, fs::metadata(&out).unwrap().len());
        assert_eq!(enc.sha256, sha(&fs::read(&out).unwrap()));
        assert!(!temp_path(&out).exists());
    }

    #[test]
    fn media_refs_decode_strictly() {
        let good = MediaRef {
            client_time_ms: 1,
            media_id: [1; 16],
            class: MediaClass::Image,
            plaintext_len: 10,
            ciphertext_len: media_ciphertext_len(10),
            ciphertext_sha256: [2; 32],
            key: Zeroizing::new([3; 32]),
        }
        .encode();
        assert!(MediaRef::decode(&good).is_ok());
        let mutate = |at: usize, value: u8| {
            let mut b = good.to_vec();
            b[at] = value;
            MediaRef::decode(&b).is_err()
        };
        assert!(mutate(0, 2), "unknown version");
        assert!(mutate(1, 1), "not media");
        assert!(mutate(26, 0), "class 0");
        assert!(mutate(26, 5), "unknown class");
        assert!(mutate(34, 0), "ciphertext length inconsistent");
        assert!(MediaRef::decode(&good[..106]).is_err(), "truncated");
        let mut long = good.to_vec();
        long.push(0);
        assert!(MediaRef::decode(&long).is_err(), "trailing bytes");
        let mut zero = good.to_vec();
        zero[27..35].copy_from_slice(&0u64.to_be_bytes());
        zero[35..43].copy_from_slice(&media_ciphertext_len(0).to_be_bytes());
        assert!(MediaRef::decode(&zero).is_err(), "empty media");
        let mut big = good.to_vec();
        let n = MAX_MEDIA_PLAINTEXT_BYTES as u64 + 1;
        big[27..35].copy_from_slice(&n.to_be_bytes());
        big[35..43].copy_from_slice(&media_ciphertext_len(n).to_be_bytes());
        assert!(MediaRef::decode(&big).is_err(), "over the limit");
        // A corrupted stored ref is local corruption, never shown.
        assert_eq!(
            public_payload(Zeroizing::new(good[..50].to_vec())).unwrap_err(),
            CoreError::StateCorruption
        );
        // Text payloads pass through untouched.
        let text = Zeroizing::new(vec![1u8, 1, 0, 0]);
        assert_eq!(&public_payload(text).unwrap()[..], &[1, 1, 0, 0]);
    }
}
