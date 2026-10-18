//! Shared helpers for the crypto-core tests. TEST ONLY: uses the insecure
//! test key stores.
#![allow(dead_code)]

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use sirf_hum_crypto::identity::{AccountId, DeviceId};
use sirf_hum_crypto::keystore::InsecureFileTestKeyStore;
use sirf_hum_crypto::store::{CryptoStore, FileStore, MemoryStore};
use sirf_hum_crypto::{CoreError, CoreResult, CryptoCore, Incoming, PublicIdentity};

pub struct Device {
    pub core: CryptoCore,
    pub dir: PathBuf,
    pub public: PublicIdentity,
    _tmp: Option<tempfile::TempDir>,
}

pub fn open_dir(dir: &Path) -> CoreResult<CryptoCore> {
    let keys = InsecureFileTestKeyStore::open_or_create(dir)?;
    CryptoCore::open(Box::new(FileStore::open(dir)?), &keys)
}

impl Device {
    pub fn new(account: &str) -> Self {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().to_path_buf();
        let mut core = open_dir(&dir).unwrap();
        let public = core
            .create_identity(AccountId::new(account).unwrap())
            .unwrap();
        Self {
            core,
            dir,
            public,
            _tmp: Some(tmp),
        }
    }

    /// Simulates an app restart: drop the core and reopen from disk.
    pub fn restart(&mut self) {
        let dir = self.dir.clone();
        // Drop first so no two cores share the directory.
        let placeholder = CryptoCore::open(
            Box::new(MemoryStore::default()),
            &sirf_hum_crypto::keystore::EphemeralTestKeyStore::new(),
        )
        .unwrap();
        drop(std::mem::replace(&mut self.core, placeholder));
        self.core = open_dir(&dir).unwrap();
    }

    pub fn device_id(&self) -> DeviceId {
        self.public.device_id
    }

    pub fn trust(&mut self, other: &Device) {
        self.core
            .trust_verified_person_key(other.public.person_key.clone())
            .unwrap();
    }

    pub fn open(&mut self, ct: &[u8]) -> Result<Vec<u8>, CoreError> {
        match self.core.process_incoming(ct)? {
            Incoming::Application(pt) => Ok(pt.to_vec()),
            _ => Err(CoreError::InvalidInput),
        }
    }

    pub fn apply(&mut self, commit: &[u8]) -> Result<Incoming, CoreError> {
        self.core.process_incoming(commit)
    }
}

/// Alice (creator) and Bob, mutually trusted, in one group.
pub fn couple() -> (Device, Device, Vec<u8>) {
    let mut alice = Device::new("account-alice");
    let mut bob = Device::new("account-bob");
    alice.trust(&bob);
    bob.trust(&alice);
    let gid = alice.core.create_group().unwrap();
    let kp = bob.core.key_package().unwrap();
    let added = alice.core.add_member(&gid, &kp).unwrap();
    let joined = bob.core.join(&added.welcome).unwrap();
    assert_eq!(joined, gid);
    (alice, bob, gid)
}

/// A memory store whose writes can be made to fail on demand.
#[derive(Clone)]
pub struct FaultyStore {
    pub fail_puts: Arc<AtomicBool>,
    inner: Arc<std::sync::Mutex<MemoryStore>>,
}

impl FaultyStore {
    pub fn new() -> Self {
        Self {
            fail_puts: Arc::new(AtomicBool::new(false)),
            inner: Arc::new(std::sync::Mutex::new(MemoryStore::default())),
        }
    }
    pub fn set_failing(&self, failing: bool) {
        self.fail_puts.store(failing, Ordering::SeqCst);
    }
}

impl CryptoStore for FaultyStore {
    fn put(&mut self, name: &str, record: &[u8]) -> CoreResult<()> {
        if self.fail_puts.load(Ordering::SeqCst) {
            return Err(CoreError::PersistenceFailure);
        }
        self.inner.lock().unwrap().put(name, record)
    }
    fn get(&self, name: &str) -> CoreResult<Option<Vec<u8>>> {
        self.inner.lock().unwrap().get(name)
    }
    fn delete(&mut self, name: &str) -> CoreResult<()> {
        self.inner.lock().unwrap().delete(name)
    }
    fn exists(&self, name: &str) -> CoreResult<bool> {
        self.inner.lock().unwrap().exists(name)
    }
    fn wipe_all(&mut self) -> CoreResult<()> {
        self.inner.lock().unwrap().wipe_all()
    }
}

pub fn record_path(dir: &Path, name: &str) -> PathBuf {
    dir.join(format!("{name}.shrec"))
}
