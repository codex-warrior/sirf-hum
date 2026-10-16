//! EXPERIMENTAL — NOT PRODUCTION. mls-rs 0.56.0 behind the harness trait.
//! Credentials are plain labels; device↔person binding is out of scope.
//! (mls-rs itself documents BasicCredential as not recommended for
//! production; Sirf Hum would supply its own IdentityProvider.)

use std::collections::{BTreeMap, HashMap};
use std::convert::Infallible;
use std::sync::{Arc, Mutex};

use harness::{Backend, Bytes};
use mls_rs::client_builder::{BaseConfig, WithCryptoProvider, WithGroupStateStorage, WithIdentityProvider};
use mls_rs::group::ReceivedMessage;
use mls_rs::identity::basic::{BasicCredential, BasicIdentityProvider};
use mls_rs::identity::SigningIdentity;
use mls_rs::{CipherSuite, CipherSuiteProvider, Client, CryptoProvider, Group, GroupStateStorage, MlsMessage};
use mls_rs_core::crypto::{SignaturePublicKey, SignatureSecretKey};
use mls_rs_core::group::{EpochRecord, GroupState};
use mls_rs_crypto_rustcrypto::RustCryptoProvider;
use zeroize::Zeroizing;

/// RFC 9420 ciphersuite 0x0001, same as the OpenMLS backend.
pub const CIPHERSUITE: CipherSuite = CipherSuite::CURVE25519_AES128;

/// Minimal local group-state store: the persistence abstraction mls-rs asks
/// applications to provide. Writes happen only on `write_to_storage`.
#[derive(Clone, Default)]
pub struct SnapStore {
    inner: Arc<Mutex<HashMap<Vec<u8>, StoredGroup>>>,
}

#[derive(Clone, Default)]
struct StoredGroup {
    state: Vec<u8>,
    epochs: BTreeMap<u64, Vec<u8>>,
}

impl GroupStateStorage for SnapStore {
    type Error = Infallible;

    fn state(&self, group_id: &[u8]) -> Result<Option<Zeroizing<Vec<u8>>>, Infallible> {
        let map = self.inner.lock().unwrap();
        Ok(map.get(group_id).map(|g| Zeroizing::new(g.state.clone())))
    }

    fn epoch(&self, group_id: &[u8], epoch_id: u64) -> Result<Option<Zeroizing<Vec<u8>>>, Infallible> {
        let map = self.inner.lock().unwrap();
        Ok(map
            .get(group_id)
            .and_then(|g| g.epochs.get(&epoch_id))
            .map(|e| Zeroizing::new(e.clone())))
    }

    fn write(
        &mut self,
        state: GroupState,
        epoch_inserts: Vec<EpochRecord>,
        epoch_updates: Vec<EpochRecord>,
    ) -> Result<(), Infallible> {
        // One lock for the whole update: the "atomic write" the trait asks for.
        let mut map = self.inner.lock().unwrap();
        let entry = map.entry(state.id.clone()).or_default();
        entry.state = state.data.to_vec();
        for record in epoch_inserts.into_iter().chain(epoch_updates) {
            entry.epochs.insert(record.id, record.data.to_vec());
        }
        Ok(())
    }

    fn max_epoch_id(&self, group_id: &[u8]) -> Result<Option<u64>, Infallible> {
        let map = self.inner.lock().unwrap();
        Ok(map.get(group_id).and_then(|g| g.epochs.keys().next_back().copied()))
    }
}

pub type Config = WithCryptoProvider<
    RustCryptoProvider,
    WithIdentityProvider<BasicIdentityProvider, WithGroupStateStorage<SnapStore, BaseConfig>>,
>;

pub struct Device {
    label: String,
    client: Client<Config>,
    store: SnapStore,
    secret: SignatureSecretKey,
    public: SignaturePublicKey,
}

pub struct MlsRs;

fn build_client(label: &str, store: SnapStore, secret: SignatureSecretKey, public: SignaturePublicKey) -> Client<Config> {
    let identity = SigningIdentity::new(BasicCredential::new(label.as_bytes().to_vec()).into_credential(), public);
    Client::builder()
        .group_state_storage(store)
        .identity_provider(BasicIdentityProvider)
        .crypto_provider(RustCryptoProvider::default())
        .signing_identity(identity, secret, CIPHERSUITE)
        .build()
}

fn parse(bytes: &[u8]) -> Result<MlsMessage, String> {
    MlsMessage::from_bytes(bytes).map_err(|e| format!("decode: {e:?}"))
}

fn label_of(member: &mls_rs::group::Member) -> String {
    member
        .signing_identity
        .credential
        .as_basic()
        .map(|c| String::from_utf8_lossy(c.identifier()).into_owned())
        .unwrap_or_default()
}

impl Backend for MlsRs {
    const NAME: &'static str = "mls-rs-0.56.0";
    type Device = Device;
    type Group = Group<Config>;

    fn new_device(label: &str) -> Device {
        let suite = RustCryptoProvider::default()
            .cipher_suite_provider(CIPHERSUITE)
            .expect("ciphersuite supported");
        let (secret, public) = suite.signature_key_generate().expect("keygen");
        let store = SnapStore::default();
        let client = build_client(label, store.clone(), secret.clone(), public.clone());
        Device { label: label.into(), client, store, secret, public }
    }

    fn key_package(d: &Device) -> Bytes {
        d.client
            .generate_key_package_message(Default::default(), Default::default(), None)
            .expect("key package")
            .to_bytes()
            .expect("ser")
    }

    fn create_group(d: &Device) -> Group<Config> {
        d.client.group_builder().expect("builder").build().expect("create group")
    }

    fn add(_d: &Device, g: &mut Group<Config>, key_packages: &[Bytes]) -> (Bytes, Bytes) {
        let mut builder = g.commit_builder();
        for kp in key_packages {
            builder = builder.add_member(parse(kp).expect("kp")).expect("add");
        }
        let out = builder.build().expect("commit");
        g.apply_pending_commit().expect("apply");
        (
            out.commit_message.to_bytes().expect("ser"),
            out.welcome_messages[0].to_bytes().expect("ser"),
        )
    }

    fn join(d: &Device, welcome: &[u8]) -> Group<Config> {
        let (group, _info) = d
            .client
            .join_group(None, &parse(welcome).expect("welcome"), None)
            .expect("join");
        group
    }

    fn remove(_d: &Device, g: &mut Group<Config>, label: &str) -> Bytes {
        let index = g
            .roster()
            .members()
            .iter()
            .find(|m| label_of(m) == label)
            .expect("member")
            .index;
        let out = g
            .commit_builder()
            .remove_member(index)
            .expect("remove")
            .build()
            .expect("commit");
        g.apply_pending_commit().expect("apply");
        out.commit_message.to_bytes().expect("ser")
    }

    fn update(_d: &Device, g: &mut Group<Config>) -> Bytes {
        let out = g.commit_builder().build().expect("empty commit (update path)");
        g.apply_pending_commit().expect("apply");
        out.commit_message.to_bytes().expect("ser")
    }

    fn process_commit(_d: &Device, g: &mut Group<Config>, commit: &[u8]) -> Result<(), String> {
        match g.process_incoming_message(parse(commit)?).map_err(|e| format!("{e:?}"))? {
            ReceivedMessage::Commit(_) => Ok(()),
            other => Err(format!("expected commit, got {other:?}")),
        }
    }

    fn encrypt(_d: &Device, g: &mut Group<Config>, plaintext: &[u8]) -> Bytes {
        g.encrypt_application_message(plaintext, Vec::new())
            .expect("encrypt")
            .to_bytes()
            .expect("ser")
    }

    fn decrypt(_d: &Device, g: &mut Group<Config>, ciphertext: &[u8]) -> Result<Bytes, String> {
        match g.process_incoming_message(parse(ciphertext)?).map_err(|e| format!("{e:?}"))? {
            ReceivedMessage::ApplicationMessage(m) => Ok(m.data().to_vec()),
            other => Err(format!("not an application message: {other:?}")),
        }
    }

    fn roster(g: &Group<Config>) -> Vec<String> {
        let mut labels: Vec<String> = g.roster().members().iter().map(label_of).collect();
        labels.sort();
        labels
    }

    fn epoch(g: &Group<Config>) -> u64 {
        g.current_epoch()
    }

    fn epoch_authenticator(g: &Group<Config>) -> Bytes {
        g.epoch_authenticator().expect("authenticator").as_bytes().to_vec()
    }

    /// Format: label | signer secret | signer public | group id | store.
    fn snapshot(d: &Device, g: &mut Group<Config>) -> Bytes {
        g.write_to_storage().expect("write state");
        let mut out = vec![];
        put(&mut out, d.label.as_bytes());
        put(&mut out, d.secret.as_bytes());
        put(&mut out, d.public.as_bytes());
        put(&mut out, g.group_id());
        let map = d.store.inner.lock().unwrap();
        let stored = map.get(g.group_id()).expect("written");
        put(&mut out, &stored.state);
        out.extend((stored.epochs.len() as u32).to_be_bytes());
        for (id, data) in &stored.epochs {
            out.extend(id.to_be_bytes());
            put(&mut out, data);
        }
        out
    }

    fn restore(snapshot: &[u8]) -> (Device, Group<Config>) {
        let mut r = snapshot;
        let label = String::from_utf8(take(&mut r).to_vec()).expect("label");
        let secret = SignatureSecretKey::new(take(&mut r).to_vec());
        let public = SignaturePublicKey::new(take(&mut r).to_vec());
        let group_id = take(&mut r).to_vec();
        let mut stored = StoredGroup { state: take(&mut r).to_vec(), ..Default::default() };
        let n = u32::from_be_bytes(r[..4].try_into().unwrap());
        r = &r[4..];
        for _ in 0..n {
            let id = u64::from_be_bytes(r[..8].try_into().unwrap());
            r = &r[8..];
            stored.epochs.insert(id, take(&mut r).to_vec());
        }
        let store = SnapStore::default();
        store.inner.lock().unwrap().insert(group_id.clone(), stored);
        let client = build_client(&label, store.clone(), secret.clone(), public.clone());
        let group = client.load_group(&group_id).expect("load group");
        (Device { label, client, store, secret, public }, group)
    }
}

fn put(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend((bytes.len() as u32).to_be_bytes());
    out.extend_from_slice(bytes);
}

fn take<'a>(r: &mut &'a [u8]) -> &'a [u8] {
    let n = u32::from_be_bytes(r[..4].try_into().unwrap()) as usize;
    let (v, rest) = r[4..].split_at(n);
    *r = rest;
    v
}
