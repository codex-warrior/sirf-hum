//! User-held recovery key (D-076): an Ed25519 key whose 32-byte seed the user
//! keeps offline. Only its public half is ever registered with the server.
//!
//! Text format v1 (`SHRK1-XXXX-...`):
//!   bytes  = version 0x01 | seed[32] | checksum[4]
//!   checksum = SHA-256("SirfHum-RecoveryKey-v1" | version | seed)[..4]
//!   text   = "SHRK1-" + RFC 4648 base32 (no padding) of bytes, groups of 4
//!
//! The checksum only catches typos (a 2^-32 false-accept rate for random
//! errors); it adds no secrecy. All security comes from the 256-bit random
//! seed. Decoding is case-insensitive and ignores spaces and hyphens.

use chacha20poly1305::aead::{rand_core::RngCore, OsRng};
use openmls_traits::crypto::OpenMlsCrypto;
use openmls_traits::types::HashType;
use zeroize::{Zeroize, Zeroizing};

use crate::{CoreError, CoreResult};

pub const RECOVERY_KEY_PREFIX: &str = "SHRK1";
const FORMAT_VERSION: u8 = 1;
const CHECKSUM_CONTEXT: &[u8] = b"SirfHum-RecoveryKey-v1";
const SEED_LEN: usize = 32;
const PAYLOAD_LEN: usize = 1 + SEED_LEN + 4;
const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/// A decoded recovery key seed; wiped on drop.
pub struct RecoverySeed(pub(crate) Zeroizing<[u8; SEED_LEN]>);

impl core::fmt::Debug for RecoverySeed {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("RecoverySeed(<redacted>)")
    }
}

impl RecoverySeed {
    pub fn generate() -> Self {
        let mut seed = Zeroizing::new([0u8; SEED_LEN]);
        OsRng.fill_bytes(seed.as_mut());
        Self(seed)
    }

    /// The Ed25519 public key for this seed (RFC 8032 derivation).
    pub fn public_key(&self) -> [u8; 32] {
        ed25519_dalek::SigningKey::from_bytes(&self.0)
            .verifying_key()
            .to_bytes()
    }

    /// The raw seed, for signing through the OpenMLS provider.
    pub(crate) fn seed(&self) -> &[u8] {
        self.0.as_ref()
    }

    pub fn encode(&self, crypto: &impl OpenMlsCrypto) -> CoreResult<Zeroizing<String>> {
        let mut bytes = Zeroizing::new(Vec::with_capacity(PAYLOAD_LEN));
        bytes.push(FORMAT_VERSION);
        bytes.extend_from_slice(self.0.as_ref());
        let checksum = checksum(crypto, &bytes)?;
        bytes.extend_from_slice(&checksum);
        let body = base32_encode(&bytes);
        let mut out = Zeroizing::new(String::with_capacity(
            RECOVERY_KEY_PREFIX.len() + body.len() * 5 / 4 + 1,
        ));
        out.push_str(RECOVERY_KEY_PREFIX);
        for (i, c) in body.chars().enumerate() {
            if i % 4 == 0 {
                out.push('-');
            }
            out.push(c);
        }
        Ok(out)
    }

    pub fn decode(crypto: &impl OpenMlsCrypto, text: &str) -> CoreResult<Self> {
        let invalid = || CoreError::RecoveryKeyInvalid;
        if text.len() > 256 {
            return Err(invalid());
        }
        let mut normalized = Zeroizing::new(String::with_capacity(text.len()));
        for c in text.chars() {
            if c == '-' || c.is_whitespace() {
                continue;
            }
            normalized.push(c.to_ascii_uppercase());
        }
        let body = normalized
            .strip_prefix(RECOVERY_KEY_PREFIX)
            .ok_or_else(invalid)?;
        let bytes = base32_decode(body).ok_or_else(invalid)?;
        if bytes.len() != PAYLOAD_LEN || bytes[0] != FORMAT_VERSION {
            return Err(invalid());
        }
        let expected = checksum(crypto, &bytes[..1 + SEED_LEN])?;
        if bytes[1 + SEED_LEN..] != expected {
            return Err(invalid());
        }
        let mut seed = Zeroizing::new([0u8; SEED_LEN]);
        seed.copy_from_slice(&bytes[1..1 + SEED_LEN]);
        Ok(Self(seed))
    }
}

fn checksum(crypto: &impl OpenMlsCrypto, versioned_seed: &[u8]) -> CoreResult<[u8; 4]> {
    let mut data = Zeroizing::new(Vec::with_capacity(
        CHECKSUM_CONTEXT.len() + versioned_seed.len(),
    ));
    data.extend_from_slice(CHECKSUM_CONTEXT);
    data.extend_from_slice(versioned_seed);
    let digest = crypto
        .hash(HashType::Sha2_256, &data)
        .map_err(|_| CoreError::InternalCryptoFailure)?;
    digest[..4].try_into().map_err(|_| CoreError::Internal)
}

/// RFC 4648 base32, no padding. An encoding, not cryptography.
fn base32_encode(bytes: &[u8]) -> Zeroizing<String> {
    let mut out = Zeroizing::new(String::with_capacity(bytes.len().div_ceil(5) * 8));
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for &b in bytes {
        buffer = (buffer << 8) | u32::from(b);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(ALPHABET[((buffer >> bits) & 31) as usize] as char);
        }
    }
    if bits > 0 {
        out.push(ALPHABET[((buffer << (5 - bits)) & 31) as usize] as char);
    }
    buffer.zeroize();
    out
}

/// Strict inverse of [`base32_encode`]: unknown characters or non-zero
/// trailing bits fail (so every key has exactly one valid spelling).
fn base32_decode(text: &str) -> Option<Zeroizing<Vec<u8>>> {
    let mut out = Zeroizing::new(Vec::with_capacity(text.len() * 5 / 8));
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for c in text.bytes() {
        let value = ALPHABET.iter().position(|&a| a == c)? as u32;
        buffer = (buffer << 5) | value;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
        }
    }
    let trailing_zero = bits < 5 && (buffer & ((1 << bits) - 1)) == 0;
    buffer.zeroize();
    trailing_zero.then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use openmls_rust_crypto::OpenMlsRustCrypto;
    use openmls_traits::OpenMlsProvider;

    #[test]
    fn base32_matches_rfc4648_vectors() {
        // RFC 4648 §10 (padding removed).
        for (plain, encoded) in [
            ("", ""),
            ("f", "MY"),
            ("fo", "MZXQ"),
            ("foo", "MZXW6"),
            ("foob", "MZXW6YQ"),
            ("fooba", "MZXW6YTB"),
            ("foobar", "MZXW6YTBOI"),
        ] {
            assert_eq!(base32_encode(plain.as_bytes()).as_str(), encoded);
            assert_eq!(base32_decode(encoded).unwrap().as_slice(), plain.as_bytes());
        }
        assert!(base32_decode("MZ").is_none(), "non-zero trailing bits");
        assert!(
            base32_decode("mzxq").is_none(),
            "decoder input is pre-normalised"
        );
        assert!(base32_decode("MZX1").is_none(), "unknown symbol");
    }

    #[test]
    fn round_trip_and_normalisation() {
        let provider = OpenMlsRustCrypto::default();
        let crypto = provider.crypto();
        let seed = RecoverySeed::generate();
        let text = seed.encode(crypto).unwrap();
        assert!(text.starts_with("SHRK1-"));
        let decoded = RecoverySeed::decode(crypto, &text).unwrap();
        assert_eq!(decoded.public_key(), seed.public_key());
        let sloppy = text.to_ascii_lowercase().replace('-', " ");
        assert_eq!(
            RecoverySeed::decode(crypto, &sloppy).unwrap().public_key(),
            seed.public_key()
        );
    }

    #[test]
    fn typos_and_wrong_formats_are_rejected() {
        let provider = OpenMlsRustCrypto::default();
        let crypto = provider.crypto();
        let text = RecoverySeed::generate().encode(crypto).unwrap();
        // Every single-character substitution in the body is caught.
        let body_start = RECOVERY_KEY_PREFIX.len();
        for (i, c) in text.char_indices().skip(body_start) {
            if c == '-' {
                continue;
            }
            let replacement = if c == 'A' { 'B' } else { 'A' };
            let mut typo = text.to_string();
            typo.replace_range(i..i + 1, &replacement.to_string());
            assert_eq!(
                RecoverySeed::decode(crypto, &typo).err(),
                Some(CoreError::RecoveryKeyInvalid),
                "typo at {i} accepted"
            );
        }
        for bad in [
            "",
            "SHRK1",
            "SHRK2-AAAA",
            "nonsense",
            &text[..text.len() - 1],
        ] {
            assert_eq!(
                RecoverySeed::decode(crypto, bad).err(),
                Some(CoreError::RecoveryKeyInvalid)
            );
        }
        assert!(RecoverySeed::decode(crypto, &"A".repeat(300)).is_err());
    }

    /// The server's golden vector derives the recovery public key from a
    /// fixed seed with node:crypto; Rust (ed25519-dalek) must agree.
    #[test]
    fn public_key_derivation_matches_the_server_vector() {
        let json = include_str!("../../../../functions/test/vectors/device_trust_v1.json");
        let field = |name: &str| -> Vec<u8> {
            let key = format!("\"{name}\": \"");
            let start = json.find(&key).unwrap() + key.len();
            let end = start + json[start..].find('"').unwrap();
            let s = &json[start..end];
            (0..s.len())
                .step_by(2)
                .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
                .collect()
        };
        let mut seed = Zeroizing::new([0u8; SEED_LEN]);
        seed.copy_from_slice(&field("recoverySeedHex"));
        let derived = RecoverySeed(seed).public_key();
        assert_eq!(derived.to_vec(), field("recoveryPublicKeyHex"));
    }

    #[test]
    fn public_key_matches_the_provider_signature() {
        let provider = OpenMlsRustCrypto::default();
        let crypto = provider.crypto();
        let seed = RecoverySeed::generate();
        let sig = crypto
            .sign(
                openmls_traits::types::SignatureScheme::ED25519,
                b"m",
                seed.seed(),
            )
            .unwrap();
        crypto
            .verify_signature(
                openmls_traits::types::SignatureScheme::ED25519,
                b"m",
                &seed.public_key(),
                &sig,
            )
            .unwrap();
        assert_eq!(format!("{seed:?}"), "RecoverySeed(<redacted>)");
    }
}
