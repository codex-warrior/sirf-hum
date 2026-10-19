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
    fn list(&self, prefix: &str) -> CoreResult<Vec<String>> {
        self.inner.lock().unwrap().list(prefix)
    }
}

pub fn record_path(dir: &Path, name: &str) -> PathBuf {
    dir.join(format!("{name}.shrec"))
}

// ------------------------------------------------- Prompt 10 helpers

/// One approval link: (approver cert, new cert, challenge, expires, signature).
pub type Link = (Vec<u8>, Vec<u8>, Vec<u8>, u64, Vec<u8>);
/// One signed revocation: (revoker cert, revoked cert, reason, challenge, expires, signature).
pub type Revocation = (Vec<u8>, Vec<u8>, u8, Vec<u8>, u64, Vec<u8>);

fn put(out: &mut Vec<u8>, b: &[u8]) {
    out.extend_from_slice(&(b.len() as u32).to_be_bytes());
    out.extend_from_slice(b);
}

/// Encodes a lineage blob in the `lineage.rs` wire format (approval links only).
pub fn lineage_blob(
    account: &str,
    root: &[u8],
    links: &[Link],
    revocations: &[Revocation],
    revoked_ids: &[DeviceId],
) -> Vec<u8> {
    let mut out = vec![1u8];
    put(&mut out, account.as_bytes());
    put(&mut out, root);
    out.extend_from_slice(&(links.len() as u32).to_be_bytes());
    for (approver, new, ch, exp, sig) in links {
        out.extend_from_slice(&[1, 1]);
        put(&mut out, approver);
        put(&mut out, new);
        put(&mut out, ch);
        out.extend_from_slice(&exp.to_be_bytes());
        put(&mut out, sig);
    }
    out.extend_from_slice(&(revocations.len() as u32).to_be_bytes());
    for (revoker, revoked, reason, ch, exp, sig) in revocations {
        out.push(1);
        put(&mut out, revoker);
        put(&mut out, revoked);
        out.push(*reason);
        put(&mut out, ch);
        out.extend_from_slice(&exp.to_be_bytes());
        put(&mut out, sig);
    }
    out.extend_from_slice(&(revoked_ids.len() as u32).to_be_bytes());
    for id in revoked_ids {
        out.extend_from_slice(&id.0);
    }
    out
}

pub const CHALLENGE: [u8; 32] = [7u8; 32];
pub const EXPIRES: u64 = 1_900_000_000;

/// `approver` approves `new` (same account) and returns the lineage link.
pub fn approve(approver: &mut Device, new: &Device) -> Link {
    let sig = approver
        .core
        .approve_device(&new.public.certificate, &CHALLENGE, EXPIRES)
        .unwrap();
    (
        approver.public.certificate.clone(),
        new.public.certificate.clone(),
        CHALLENGE.to_vec(),
        EXPIRES,
        sig,
    )
}

/// A conversation ID (16 bytes) for tests.
pub fn conversation(byte: u8) -> Vec<u8> {
    vec![byte; 16]
}

impl Device {
    /// Anchors another device's PIK (the v4 path: its single pinned device).
    pub fn anchor(&mut self, other: &Device) {
        self.trust(other);
    }

    pub fn kp(&mut self) -> Vec<u8> {
        self.core.key_package().unwrap()
    }

    /// Sends a text payload; returns (message id, epoch, ciphertext).
    pub fn send(&mut self, cid: &[u8], text: &[u8]) -> (Vec<u8>, u64, Vec<u8>) {
        let sent = self.core.send_message(cid, text).unwrap();
        (sent.message_id.to_vec(), sent.epoch, sent.ciphertext)
    }

    /// Receives a message from `from` with honest envelope fields.
    pub fn recv(
        &mut self,
        cid: &[u8],
        from: &Device,
        msg: &(Vec<u8>, u64, Vec<u8>),
    ) -> Result<Vec<u8>, CoreError> {
        self.core
            .receive_message(cid, &msg.0, from.device_id(), msg.1, 1, 1, &msg.2, 0)
            .map(|r| r.payload.to_vec())
    }
}

/// `creator` creates conversation `cid` adding `others`, the server accepts,
/// everyone joins. Every device must already trust every other.
pub fn conversation_of(creator: &mut Device, others: &mut [&mut Device], cid: &[u8]) {
    let kps: Vec<Vec<u8>> = others.iter_mut().map(|d| d.kp()).collect();
    let staged = creator.core.create_conversation_group(cid, &kps).unwrap();
    assert_eq!(staged.from_epoch, 0);
    assert_eq!(creator.core.confirm_commit(cid, 0).unwrap(), 1);
    let welcome = staged.welcome.unwrap();
    for d in others.iter_mut() {
        assert_eq!(d.core.join_conversation(cid, &welcome).unwrap(), 1);
    }
}
