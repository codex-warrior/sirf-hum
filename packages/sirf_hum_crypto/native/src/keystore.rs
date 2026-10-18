//! Platform key-storage boundary (Prompt 06 Part 4).
//!
//! The crypto core needs exactly one secret from the platform: a 256-bit
//! key-encryption key (KEK) that seals local records (record.rs). In
//! production the KEK must come from a hardware-backed, non-exportable
//! platform key (Android Keystore / iOS Keychain, KEY-MANAGEMENT.md).
//!
//! **No production adapter exists yet.** The adapters below are for
//! development and tests only and report `is_production_secure() == false`.
//! Replacing them never touches MLS logic: only this trait.

use std::fs;
use std::io::Write;
use std::path::Path;

use chacha20poly1305::aead::{rand_core::RngCore, OsRng};
use zeroize::Zeroizing;

use crate::{CoreError, CoreResult};

pub const KEK_LEN: usize = 32;

pub trait KeyEncryptionKeyProvider: Send {
    /// Returns the KEK. Implementations must never log or persist it in
    /// plaintext (except the explicitly insecure test adapter below).
    fn key_encryption_key(&self) -> CoreResult<Zeroizing<[u8; KEK_LEN]>>;
    /// True only for adapters backed by platform secure hardware/keystores.
    fn is_production_secure(&self) -> bool;
}

/// INSECURE. A random KEK held in process memory only. Data sealed with it
/// cannot be reopened after the process exits. Tests only.
pub struct EphemeralTestKeyStore {
    kek: Zeroizing<[u8; KEK_LEN]>,
}

impl EphemeralTestKeyStore {
    pub fn new() -> Self {
        let mut kek = Zeroizing::new([0u8; KEK_LEN]);
        OsRng.fill_bytes(kek.as_mut());
        Self { kek }
    }
}

impl Default for EphemeralTestKeyStore {
    fn default() -> Self {
        Self::new()
    }
}

impl KeyEncryptionKeyProvider for EphemeralTestKeyStore {
    fn key_encryption_key(&self) -> CoreResult<Zeroizing<[u8; KEK_LEN]>> {
        Ok(self.kek.clone())
    }
    fn is_production_secure(&self) -> bool {
        false
    }
}

/// INSECURE. Stores the KEK **in plaintext** in a file next to the data, so
/// development builds and device tests can reopen state after a restart.
/// Anyone who can read the app directory can decrypt the local state.
/// Development/test only. Never ship; the Dart facade refuses it in release
/// builds.
pub struct InsecureFileTestKeyStore {
    kek: Zeroizing<[u8; KEK_LEN]>,
}

const INSECURE_KEK_FILE: &str = "INSECURE-TEST-ONLY.kek";

impl InsecureFileTestKeyStore {
    pub fn open_or_create(dir: &Path) -> CoreResult<Self> {
        fs::create_dir_all(dir).map_err(|_| CoreError::PersistenceFailure)?;
        let path = dir.join(INSECURE_KEK_FILE);
        let mut kek = Zeroizing::new([0u8; KEK_LEN]);
        match fs::read(&path) {
            Ok(bytes) if bytes.len() == KEK_LEN => kek.copy_from_slice(&bytes),
            Ok(_) => return Err(CoreError::StateCorruption),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                OsRng.fill_bytes(kek.as_mut());
                let mut f = fs::File::create(&path).map_err(|_| CoreError::PersistenceFailure)?;
                f.write_all(kek.as_ref())
                    .map_err(|_| CoreError::PersistenceFailure)?;
                f.sync_all().map_err(|_| CoreError::PersistenceFailure)?;
            }
            Err(_) => return Err(CoreError::PersistenceFailure),
        }
        Ok(Self { kek })
    }

    pub fn delete(dir: &Path) {
        let _ = fs::remove_file(dir.join(INSECURE_KEK_FILE));
    }
}

impl KeyEncryptionKeyProvider for InsecureFileTestKeyStore {
    fn key_encryption_key(&self) -> CoreResult<Zeroizing<[u8; KEK_LEN]>> {
        Ok(self.kek.clone())
    }
    fn is_production_secure(&self) -> bool {
        false
    }
}
