//! Versioned, sealed local records (Prompt 06 Part 3).
//!
//! Layout (format 1):
//!
//! ```text
//! magic "SHCR" | format u16 BE | kind u8 | reserved u8 | nonce[24] | ciphertext+tag
//! ```
//!
//! Sealed with XChaCha20-Poly1305 (RustCrypto `chacha20poly1305` 0.10.1,
//! already in OpenMLS' dependency tree) under the platform KEK. The
//! associated data is the header plus the record name, so a record cannot be
//! moved to another name or kind without detection. A 192-bit random nonce
//! per write makes random-nonce reuse negligible. Any failure (bad magic,
//! unknown format, wrong kind or name, tag mismatch) is `StateCorruption`:
//! fail closed, never guess.
//!
//! This is a standard AEAD use, not a new construction; it is listed for
//! review in CRYPTO-CORE-ARCHITECTURE.md.

use chacha20poly1305::aead::{Aead, AeadCore, KeyInit, OsRng, Payload};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use zeroize::Zeroizing;

use crate::keystore::KEK_LEN;
use crate::limits::MAX_RECORD_BYTES;
use crate::{CoreError, CoreResult};

const MAGIC: &[u8; 4] = b"SHCR";
pub const FORMAT_VERSION: u16 = 1;
const HEADER_LEN: usize = 4 + 2 + 1 + 1;
const NONCE_LEN: usize = 24;

/// What a record holds. Determines handling and is bound into the AAD.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum RecordKind {
    /// Safe-to-persist public metadata (still integrity protected).
    PublicMetadata = 1,
    /// Private identity key material (person key, device signing key).
    IdentitySecret = 2,
    /// MLS group/key-package state, including epoch secrets.
    MlsState = 3,
    /// Highest server trust epoch this device has seen (D-083).
    TrustEpoch = 4,
}

fn header(kind: RecordKind) -> [u8; HEADER_LEN] {
    let mut h = [0u8; HEADER_LEN];
    h[..4].copy_from_slice(MAGIC);
    h[4..6].copy_from_slice(&FORMAT_VERSION.to_be_bytes());
    h[6] = kind as u8;
    h
}

fn aad(header: &[u8], name: &str) -> Vec<u8> {
    let mut a = header.to_vec();
    a.extend_from_slice(&(name.len() as u32).to_be_bytes());
    a.extend_from_slice(name.as_bytes());
    a
}

pub fn seal(
    kek: &Zeroizing<[u8; KEK_LEN]>,
    kind: RecordKind,
    name: &str,
    plaintext: &[u8],
) -> CoreResult<Vec<u8>> {
    let cipher = XChaCha20Poly1305::new(Key::from_slice(kek.as_ref()));
    let nonce = XChaCha20Poly1305::generate_nonce(&mut OsRng);
    let header = header(kind);
    let ciphertext = cipher
        .encrypt(
            &nonce,
            Payload {
                msg: plaintext,
                aad: &aad(&header, name),
            },
        )
        .map_err(|_| CoreError::InternalCryptoFailure)?;
    let mut out = Vec::with_capacity(HEADER_LEN + NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&header);
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

pub fn open(
    kek: &Zeroizing<[u8; KEK_LEN]>,
    expected_kind: RecordKind,
    name: &str,
    record: &[u8],
) -> CoreResult<Zeroizing<Vec<u8>>> {
    if record.len() > MAX_RECORD_BYTES || record.len() < HEADER_LEN + NONCE_LEN + 16 {
        return Err(CoreError::StateCorruption);
    }
    let (head, rest) = record.split_at(HEADER_LEN);
    if &head[..4] != MAGIC
        || u16::from_be_bytes([head[4], head[5]]) != FORMAT_VERSION
        || head[6] != expected_kind as u8
        || head[7] != 0
    {
        return Err(CoreError::StateCorruption);
    }
    let (nonce, ciphertext) = rest.split_at(NONCE_LEN);
    let cipher = XChaCha20Poly1305::new(Key::from_slice(kek.as_ref()));
    cipher
        .decrypt(
            XNonce::from_slice(nonce),
            Payload {
                msg: ciphertext,
                aad: &aad(head, name),
            },
        )
        .map(Zeroizing::new)
        .map_err(|_| CoreError::StateCorruption)
}
