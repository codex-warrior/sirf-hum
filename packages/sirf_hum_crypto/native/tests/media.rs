//! Prompt 11: encrypted media objects (ABI v6; D-093, D-094, D-096).
//! Round trips, tampering, binding, replay, limits, failure cleanup,
//! revocation, restart. TEST key stores only.
//!
//! The STREAM/AEAD layer is also tested on its own (hash bypassed) in
//! `src/engine/media.rs`.

mod common;

use std::fs;
use std::path::{Path, PathBuf};

use common::*;
use sirf_hum_crypto::identity::AccountId;
use sirf_hum_crypto::{
    media_ciphertext_len, media_object_file_name, CoreError, CryptoCore, MediaClass, MessageState,
    SentMedia, MEDIA_CHUNK_BYTES, MEDIA_VIEW_LEN,
};

/// Distinctive plaintext: a repeating marker, so a scan for it on disk
/// finds any plaintext copy.
const MARKER: &[u8] = b"SIRF-HUM-PRIVATE-PHOTO-BYTES/";

fn plaintext(len: usize) -> Vec<u8> {
    MARKER.iter().copied().cycle().take(len).collect()
}

struct Media {
    sent: SentMedia,
    object: PathBuf,
    _dir: tempfile::TempDir,
}

impl Media {
    fn message(&self) -> (Vec<u8>, u64, Vec<u8>) {
        (
            self.sent.sent.message_id.to_vec(),
            self.sent.sent.epoch,
            self.sent.sent.ciphertext.clone(),
        )
    }

    fn mid(&self) -> Vec<u8> {
        self.sent.sent.message_id.to_vec()
    }

    /// A copy of the object, as a receiver's download would be.
    fn download(&self) -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("object.shm");
        fs::copy(&self.object, &path).unwrap();
        (dir, path)
    }
}

fn send_media(d: &mut Device, cid: &[u8], data: &[u8], class: MediaClass) -> Media {
    let dir = tempfile::tempdir().unwrap();
    let input = dir.path().join("input.bin");
    fs::write(&input, data).unwrap();
    let sent = d.core.send_media(cid, &input, dir.path(), class).unwrap();
    let object = sent.object_path.clone();
    assert_eq!(
        object,
        dir.path().join(media_object_file_name(cid, &sent.media_id))
    );
    // The caller's plaintext file is not ours to keep; the object is.
    fs::remove_file(&input).unwrap();
    Media {
        sent,
        object,
        _dir: dir,
    }
}

fn open(d: &Device, cid: &[u8], mid: &[u8], path: &Path) -> Result<Vec<u8>, CoreError> {
    d.core.open_media(cid, mid, path).map(|p| p.to_vec())
}

fn couple_conversation() -> (Device, Device, Vec<u8>) {
    let mut a = Device::new("accountA");
    let mut b = Device::new("accountB");
    a.anchor(&b);
    b.anchor(&a);
    let cid = conversation(1);
    conversation_of(&mut a, &mut [&mut b], &cid);
    (a, b, cid)
}

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
}

fn assert_no_plaintext_under(dir: &Path) {
    for entry in fs::read_dir(dir).unwrap().flatten() {
        let path = entry.path();
        if path.is_dir() {
            assert_no_plaintext_under(&path);
        } else {
            let bytes = fs::read(&path).unwrap();
            assert!(!contains(&bytes, MARKER), "plaintext in {path:?}");
        }
    }
}

// ------------------------------------------------------------ round trips

#[test]
fn media_round_trips_at_every_chunk_boundary() {
    let (mut a, mut b, cid) = couple_conversation();
    let sizes = [
        1,
        MEDIA_CHUNK_BYTES - 1,
        MEDIA_CHUNK_BYTES,
        MEDIA_CHUNK_BYTES + 1,
        3 * MEDIA_CHUNK_BYTES + 17,
    ];
    for (i, &len) in sizes.iter().enumerate() {
        let data = plaintext(len);
        let m = send_media(&mut a, &cid, &data, MediaClass::Image);
        let object_len = fs::metadata(&m.object).unwrap().len();
        assert_eq!(object_len, m.sent.ciphertext_len);
        assert_eq!(object_len, media_ciphertext_len(len as u64));
        assert!(!contains(&fs::read(&m.object).unwrap(), MARKER));

        // The receiver gets only the key-free view.
        let view = b.recv(&cid, &a, &m.message()).unwrap();
        assert_eq!(view.len(), MEDIA_VIEW_LEN, "size {len}");
        assert_eq!(&view[..2], &[1, 2], "version 1, kind media");
        assert_eq!(&view[10..26], &m.sent.media_id);
        assert_eq!(view[26], MediaClass::Image as u8);
        assert_eq!(
            u64::from_be_bytes(view[27..35].try_into().unwrap()),
            len as u64
        );
        assert_eq!(
            u64::from_be_bytes(view[35..43].try_into().unwrap()),
            m.sent.ciphertext_len
        );

        let (_tmp, copy) = m.download();
        assert_eq!(open(&b, &cid, &m.mid(), &copy).unwrap(), data, "size {len}");
        // The sender can open its own media too (outgoing history).
        assert_eq!(open(&a, &cid, &m.mid(), &m.object).unwrap(), data);
        assert_eq!(a.core.history(&cid).unwrap().len(), i + 1);
    }
}

#[test]
fn every_class_round_trips_and_keys_are_fresh_per_object() {
    let (mut a, mut b, cid) = couple_conversation();
    let data = plaintext(5000);
    let mut objects = Vec::new();
    for class in [
        MediaClass::Image,
        MediaClass::Video,
        MediaClass::Audio,
        MediaClass::File,
    ] {
        let m = send_media(&mut a, &cid, &data, class);
        let view = b.recv(&cid, &a, &m.message()).unwrap();
        assert_eq!(view[26], class as u8);
        assert_eq!(open(&b, &cid, &m.mid(), &m.object).unwrap(), data);
        objects.push(fs::read(&m.object).unwrap());
    }
    // Same plaintext, four objects: fresh key and nonce prefix each time.
    for i in 0..objects.len() {
        for j in i + 1..objects.len() {
            assert_ne!(objects[i][6..25], objects[j][6..25], "nonce prefix reused");
            assert_ne!(objects[i][25..], objects[j][25..], "ciphertext repeated");
        }
    }
}

#[test]
fn history_shows_media_as_the_key_free_view_and_text_unchanged() {
    let (mut a, mut b, cid) = couple_conversation();
    let text = a.send(&cid, b"\x01\x01hello");
    let m = send_media(&mut a, &cid, &plaintext(100), MediaClass::Audio);
    b.recv(&cid, &a, &text).unwrap();
    b.recv(&cid, &a, &m.message()).unwrap();
    for d in [&a, &b] {
        let history = d.core.history(&cid).unwrap();
        let media = history
            .iter()
            .find(|r| r.message_id == m.sent.sent.message_id)
            .unwrap();
        assert_eq!(media.payload.len(), MEDIA_VIEW_LEN);
        let text = history
            .iter()
            .find(|r| r.message_id.to_vec() == text.0)
            .unwrap();
        assert_eq!(text.payload.as_slice(), b"\x01\x01hello");
    }
}

#[test]
fn dart_cannot_send_a_media_reference_itself() {
    // Media references carry keys: only send_media builds them (D-094).
    let (mut a, _b, cid) = couple_conversation();
    for payload in [vec![1u8, 2], vec![1u8, 2, 0, 0, 0], vec![1u8; 2]] {
        let r = a.core.send_message(&cid, &payload);
        if payload[1] == 2 {
            assert_eq!(r.unwrap_err(), CoreError::InvalidInput);
        } else {
            assert!(r.is_ok());
        }
    }
}

// --------------------------------------------------- tampering (end to end)

#[test]
fn any_modified_object_fails_closed_and_the_genuine_one_still_opens() {
    let (mut a, mut b, cid) = couple_conversation();
    let data = plaintext(2 * MEDIA_CHUNK_BYTES + 10);
    let m = send_media(&mut a, &cid, &data, MediaClass::Video);
    b.recv(&cid, &a, &m.message()).unwrap();
    let genuine = fs::read(&m.object).unwrap();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("tampered.shm");
    let len = genuine.len();
    let positions = [
        0,                           // magic
        4,                           // format version
        10,                          // nonce prefix
        25,                          // first ciphertext byte
        25 + MEDIA_CHUNK_BYTES + 3,  // inside the first tag
        25 + MEDIA_CHUNK_BYTES + 16, // second chunk
        len - 1,                     // last tag byte
    ];
    for pos in positions {
        let mut bytes = genuine.clone();
        bytes[pos] ^= 0x01;
        fs::write(&path, &bytes).unwrap();
        assert_eq!(
            open(&b, &cid, &m.mid(), &path).unwrap_err(),
            CoreError::AuthenticationFailure,
            "byte {pos}"
        );
    }
    let cases: Vec<(&str, Vec<u8>)> = vec![
        ("truncated by one byte", genuine[..len - 1].to_vec()),
        (
            "last chunk dropped",
            genuine[..25 + MEDIA_CHUNK_BYTES * 2 + 32].to_vec(),
        ),
        ("header only", genuine[..25].to_vec()),
        ("empty", Vec::new()),
        ("extended", [genuine.as_slice(), &[0]].concat()),
        (
            "chunks swapped",
            [
                &genuine[..25],
                &genuine[25 + MEDIA_CHUNK_BYTES + 16..25 + 2 * (MEDIA_CHUNK_BYTES + 16)],
                &genuine[25..25 + MEDIA_CHUNK_BYTES + 16],
                &genuine[25 + 2 * (MEDIA_CHUNK_BYTES + 16)..],
            ]
            .concat(),
        ),
    ];
    for (what, bytes) in cases {
        fs::write(&path, &bytes).unwrap();
        assert_eq!(
            open(&b, &cid, &m.mid(), &path).unwrap_err(),
            CoreError::AuthenticationFailure,
            "{what}"
        );
    }
    // Nothing was consumed: the genuine object still opens.
    assert_eq!(open(&b, &cid, &m.mid(), &m.object).unwrap(), data);
}

#[test]
fn another_objects_ciphertext_is_never_accepted() {
    // A malicious server serves object 2 for message 1 (substitution).
    let (mut a, mut b, cid) = couple_conversation();
    let data = plaintext(4000);
    let first = send_media(&mut a, &cid, &data, MediaClass::Image);
    let second = send_media(&mut a, &cid, &data, MediaClass::Image);
    b.recv(&cid, &a, &first.message()).unwrap();
    b.recv(&cid, &a, &second.message()).unwrap();
    assert_eq!(
        open(&b, &cid, &first.mid(), &second.object).unwrap_err(),
        CoreError::AuthenticationFailure
    );
    assert_eq!(open(&b, &cid, &first.mid(), &first.object).unwrap(), data);
}

#[test]
fn objects_are_bound_to_their_conversation() {
    let (mut a, mut b, cid) = couple_conversation();
    let other = conversation(2);
    conversation_of(&mut a, &mut [&mut b], &other);
    let data = plaintext(3000);
    let here = send_media(&mut a, &cid, &data, MediaClass::File);
    let there = send_media(&mut a, &other, &data, MediaClass::File);
    b.recv(&cid, &a, &here.message()).unwrap();
    b.recv(&other, &a, &there.message()).unwrap();
    // Object of the other conversation under this conversation's message.
    assert_eq!(
        open(&b, &cid, &here.mid(), &there.object).unwrap_err(),
        CoreError::AuthenticationFailure
    );
    // A message ID looked up in the wrong conversation has no record.
    assert_eq!(
        open(&b, &other, &here.mid(), &here.object).unwrap_err(),
        CoreError::InvalidInput
    );
    assert_eq!(open(&b, &other, &there.mid(), &there.object).unwrap(), data);
}

#[test]
fn text_messages_and_unknown_ids_are_not_media() {
    let (mut a, mut b, cid) = couple_conversation();
    let m = send_media(&mut a, &cid, &plaintext(10), MediaClass::Image);
    let text = a.send(&cid, b"just text");
    b.recv(&cid, &a, &text).unwrap();
    assert_eq!(
        open(&b, &cid, &text.0, &m.object).unwrap_err(),
        CoreError::InvalidInput
    );
    // Not received yet (stale or unknown reference).
    assert_eq!(
        open(&b, &cid, &m.mid(), &m.object).unwrap_err(),
        CoreError::InvalidInput
    );
    assert_eq!(
        open(&b, &cid, &[0u8; 15], &m.object).unwrap_err(),
        CoreError::InvalidInput
    );
}

#[test]
fn a_missing_object_is_reported_not_faked() {
    let (mut a, mut b, cid) = couple_conversation();
    let m = send_media(&mut a, &cid, &plaintext(10), MediaClass::Image);
    b.recv(&cid, &a, &m.message()).unwrap();
    let gone = tempfile::tempdir()
        .unwrap()
        .path()
        .join("never-downloaded.shm");
    assert_eq!(
        open(&b, &cid, &m.mid(), &gone).unwrap_err(),
        CoreError::InvalidInput
    );
}

// ------------------------------------------------- replay, accounts, state

#[test]
fn a_replayed_media_message_is_a_duplicate_and_still_opens() {
    let (mut a, mut b, cid) = couple_conversation();
    let data = plaintext(777);
    let m = send_media(&mut a, &cid, &data, MediaClass::Image);
    b.recv(&cid, &a, &m.message()).unwrap();
    let again = b
        .core
        .receive_message(
            &cid,
            &m.mid(),
            a.device_id(),
            m.sent.sent.epoch,
            1,
            1,
            &m.sent.sent.ciphertext,
            0,
        )
        .unwrap();
    assert!(again.duplicate);
    assert!(again.payload.is_empty());
    assert_eq!(open(&b, &cid, &m.mid(), &m.object).unwrap(), data);
}

#[test]
fn another_account_cannot_open_the_media() {
    // Wrong-account cache: account C's core has no record of the message,
    // whatever object it is given.
    let (mut a, mut b, cid) = couple_conversation();
    let mut c = Device::new("accountC");
    c.anchor(&a);
    let m = send_media(&mut a, &cid, &plaintext(100), MediaClass::Image);
    b.recv(&cid, &a, &m.message()).unwrap();
    assert_eq!(
        open(&c, &cid, &m.mid(), &m.object).unwrap_err(),
        CoreError::InvalidInput
    );
    // Not a member either: it cannot receive the key.
    assert!(c.recv(&cid, &a, &m.message()).is_err());
}

#[test]
fn media_survives_restart_and_a_stale_epoch_resend() {
    let (mut a, mut b, cid) = couple_conversation();
    let data = plaintext(MEDIA_CHUNK_BYTES + 5);
    let m = send_media(&mut a, &cid, &data, MediaClass::Video);
    // The server refused the upload as stale: b committed first.
    let theirs = b.core.stage_self_update(&cid).unwrap();
    b.core.confirm_commit(&cid, 1).unwrap();
    a.restart();
    a.core
        .process_commit(&cid, 1, b.device_id(), &theirs.commit)
        .unwrap();
    let again = a.core.reencrypt_message(&cid, &m.mid()).unwrap();
    assert_eq!(again.epoch, 2);
    let view = b
        .recv(&cid, &a, &(m.mid(), again.epoch, again.ciphertext))
        .unwrap();
    assert_eq!(view.len(), MEDIA_VIEW_LEN);
    // Same object, same key: still opens on both sides after restarts.
    b.restart();
    assert_eq!(open(&b, &cid, &m.mid(), &m.object).unwrap(), data);
    assert_eq!(open(&a, &cid, &m.mid(), &m.object).unwrap(), data);
    let queued = a
        .core
        .history(&cid)
        .unwrap()
        .into_iter()
        .find(|r| r.message_id == m.sent.sent.message_id)
        .unwrap();
    assert_eq!(queued.state, MessageState::Queued);
    assert_eq!(queued.payload.len(), MEDIA_VIEW_LEN);
}

#[test]
fn no_plaintext_reaches_disk_through_send_or_open() {
    let (mut a, mut b, cid) = couple_conversation();
    let data = plaintext(3 * MEDIA_CHUNK_BYTES);
    let m = send_media(&mut a, &cid, &data, MediaClass::Image);
    b.recv(&cid, &a, &m.message()).unwrap();
    assert_eq!(open(&b, &cid, &m.mid(), &m.object).unwrap(), data);
    // The sender's input file was removed by the helper; what remains of
    // the transfer and both devices' state is ciphertext or sealed.
    assert_no_plaintext_under(m._dir.path());
    assert_no_plaintext_under(&a.dir);
    assert_no_plaintext_under(&b.dir);
}

// ------------------------------------------------------------ revocation

#[test]
fn a_revoked_sender_cannot_deliver_new_media_but_old_media_stays() {
    let (mut a, mut b, cid) = couple_conversation();
    let data = plaintext(100);
    let before = send_media(&mut a, &cid, &data, MediaClass::Image);
    b.recv(&cid, &a, &before.message()).unwrap();
    b.core.revoke_device(a.device_id()).unwrap();
    let after = send_media(&mut a, &cid, &data, MediaClass::Image);
    assert_eq!(
        b.recv(&cid, &a, &after.message()).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // No key delivered: the object cannot be opened.
    assert_eq!(
        open(&b, &cid, &after.mid(), &after.object).unwrap_err(),
        CoreError::InvalidInput
    );
    // Accepted before the revocation: still readable (as for text).
    assert_eq!(open(&b, &cid, &before.mid(), &before.object).unwrap(), data);
}

#[test]
fn a_revoked_recipient_gets_no_key_for_media_sent_after_its_removal() {
    let mut a = Device::new("accountA");
    let mut b1 = Device::new("accountB");
    let mut b2 = Device::new("accountB");
    a.anchor(&b1);
    a.anchor(&b2);
    b1.anchor(&a);
    b1.anchor(&b2);
    b2.anchor(&a);
    b2.anchor(&b1);
    let cid = conversation(3);
    conversation_of(&mut a, &mut [&mut b1, &mut b2], &cid);
    let data = plaintext(2000);
    let before = send_media(&mut a, &cid, &data, MediaClass::Image);
    b2.recv(&cid, &a, &before.message()).unwrap();

    // B2 is revoked: the sender refuses to encrypt to it until removed.
    a.core.revoke_device(b2.device_id()).unwrap();
    b1.core.revoke_device(b2.device_id()).unwrap();
    let dir = tempfile::tempdir().unwrap();
    let input = dir.path().join("in.bin");
    fs::write(&input, &data).unwrap();
    assert_eq!(
        a.core
            .send_media(&cid, &input, dir.path(), MediaClass::Image)
            .unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    assert_eq!(
        fs::read_dir(dir.path()).unwrap().count(),
        1,
        "no orphan object after a refused send"
    );

    let removal = a
        .core
        .stage_remove_members(&cid, &[b2.device_id()])
        .unwrap();
    a.core.confirm_commit(&cid, 1).unwrap();
    b1.core
        .process_commit(&cid, 1, a.device_id(), &removal.commit)
        .unwrap();
    b2.core
        .process_commit(&cid, 1, a.device_id(), &removal.commit)
        .unwrap();
    let after = send_media(&mut a, &cid, &data, MediaClass::Image);
    b1.recv(&cid, &a, &after.message()).unwrap();
    assert!(b2.recv(&cid, &a, &after.message()).is_err());
    assert_eq!(
        open(&b2, &cid, &after.mid(), &after.object).unwrap_err(),
        CoreError::InvalidInput,
        "no key, no media"
    );
    assert_eq!(open(&b1, &cid, &after.mid(), &after.object).unwrap(), data);
    // What it received before stays on the device: revocation cannot
    // delete it remotely (documented).
    assert_eq!(
        open(&b2, &cid, &before.mid(), &before.object).unwrap(),
        data
    );
}

// ------------------------------------------------------ limits and failures

#[test]
fn inputs_are_bounded_and_failures_leave_nothing_behind() {
    let (mut a, _b, cid) = couple_conversation();
    let inputs = tempfile::tempdir().unwrap();
    let media = tempfile::tempdir().unwrap();
    let out = media.path();
    let send = |a: &mut Device, input: &Path, out: &Path| {
        a.core.send_media(&cid, input, out, MediaClass::File)
    };
    let empty = inputs.path().join("empty.bin");
    fs::write(&empty, b"").unwrap();
    assert_eq!(
        send(&mut a, &empty, out).unwrap_err(),
        CoreError::InvalidInput
    );
    let missing = inputs.path().join("missing.bin");
    assert_eq!(
        send(&mut a, &missing, out).unwrap_err(),
        CoreError::InvalidInput
    );
    assert_eq!(
        send(&mut a, inputs.path(), out).unwrap_err(),
        CoreError::InvalidInput
    );
    // One byte over 64 MiB (sparse where supported).
    let big = inputs.path().join("big.bin");
    let f = fs::File::create(&big).unwrap();
    f.set_len(64 * 1024 * 1024 + 1).unwrap();
    drop(f);
    assert_eq!(
        send(&mut a, &big, out).unwrap_err(),
        CoreError::InputTooLarge
    );
    // Unwritable media directory.
    let input = inputs.path().join("in.bin");
    fs::write(&input, plaintext(10)).unwrap();
    let nowhere = inputs.path().join("no-such-dir");
    assert_eq!(
        send(&mut a, &input, &nowhere).unwrap_err(),
        CoreError::PersistenceFailure
    );
    // Unknown conversation and staged commit: refused before encrypting.
    assert_eq!(
        a.core
            .send_media(&conversation(9), &input, out, MediaClass::File)
            .unwrap_err(),
        CoreError::UnknownGroup
    );
    a.core.stage_self_update(&cid).unwrap();
    assert_eq!(
        send(&mut a, &input, out).unwrap_err(),
        CoreError::CommitPending
    );
    a.core.discard_commit(&cid, 1).unwrap();
    // Every failure above left no object, no temp file and no message.
    assert_eq!(fs::read_dir(out).unwrap().count(), 0);
    assert!(a.core.history(&cid).unwrap().is_empty());
    let sent = send(&mut a, &input, out).unwrap();
    let names: Vec<_> = fs::read_dir(out)
        .unwrap()
        .flatten()
        .map(|e| e.file_name().into_string().unwrap())
        .collect();
    assert_eq!(names, vec![media_object_file_name(&cid, &sent.media_id)]);
    assert_eq!(a.core.history(&cid).unwrap().len(), 1);
}

#[test]
fn a_persistence_failure_removes_the_object_and_queues_nothing() {
    let store = FaultyStore::new();
    let keys = sirf_hum_crypto::keystore::EphemeralTestKeyStore::new();
    let mut core = CryptoCore::open(Box::new(store.clone()), &keys).unwrap();
    let public = core
        .create_identity(AccountId::new("accountA").unwrap())
        .unwrap();
    let mut b = Device::new("accountB");
    core.trust_verified_person_key(b.public.person_key.clone())
        .unwrap();
    b.core
        .trust_verified_person_key(public.person_key.clone())
        .unwrap();
    let cid = conversation(4);
    let staged = core.create_conversation_group(&cid, &[b.kp()]).unwrap();
    core.confirm_commit(&cid, staged.from_epoch).unwrap();

    let inputs = tempfile::tempdir().unwrap();
    let input = inputs.path().join("in.bin");
    fs::write(&input, plaintext(5000)).unwrap();
    let media = tempfile::tempdir().unwrap();
    store.set_failing(true);
    assert_eq!(
        core.send_media(&cid, &input, media.path(), MediaClass::Image)
            .unwrap_err(),
        CoreError::PersistenceFailure
    );
    store.set_failing(false);
    assert_eq!(
        fs::read_dir(media.path()).unwrap().count(),
        0,
        "object removed with the failed message"
    );
    assert!(core.history(&cid).unwrap().is_empty());
    // The core is not poisoned: the next send works.
    let sent = core
        .send_media(&cid, &input, media.path(), MediaClass::Image)
        .unwrap();
    assert!(sent.object_path.exists());
}

#[test]
fn debug_output_is_redacted() {
    let (mut a, _b, cid) = couple_conversation();
    let m = send_media(&mut a, &cid, &plaintext(10), MediaClass::Image);
    let shown = format!("{:?}", m.sent);
    assert!(shown.starts_with("SentMedia(epoch: 1"), "{shown}");
    assert!(shown.contains("<redacted>"));
}

// ------------------------------------------------ performance baseline

/// `cargo test --release --test media -- --ignored --nocapture`
#[test]
#[ignore]
fn media_baseline() {
    use std::time::Instant;
    let (mut a, mut b, cid) = couple_conversation();
    for mib in [1usize, 16, 64] {
        let data = plaintext(mib * 1024 * 1024);
        let start = Instant::now();
        let m = send_media(&mut a, &cid, &data, MediaClass::Video);
        let enc = start.elapsed().as_secs_f64();
        b.recv(&cid, &a, &m.message()).unwrap();
        let start = Instant::now();
        let back = open(&b, &cid, &m.mid(), &m.object).unwrap();
        let dec = start.elapsed().as_secs_f64();
        assert_eq!(back.len(), data.len());
        println!(
            "media {mib} MiB: encrypt+hash+seal {:.0} ms ({:.0} MiB/s), hash+decrypt {:.0} ms ({:.0} MiB/s), object {} B",
            enc * 1000.0,
            mib as f64 / enc,
            dec * 1000.0,
            mib as f64 / dec,
            m.sent.ciphertext_len
        );
    }
}
