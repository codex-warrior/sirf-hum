//! EXPERIMENTAL — NOT PRODUCTION. OpenMLS 0.9.1 behind the harness trait.
//! Credentials are plain labels; device↔person binding is out of scope.

use harness::{Backend, Bytes};
use openmls::prelude::{tls_codec::*, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider as _;

pub const CIPHERSUITE: Ciphersuite =
    Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

pub struct Device {
    label: String,
    provider: OpenMlsRustCrypto,
    signer: SignatureKeyPair,
    credential: CredentialWithKey,
}

pub struct OpenMls;

fn credential_for(label: &str, public_key: Vec<u8>) -> CredentialWithKey {
    CredentialWithKey {
        credential: BasicCredential::new(label.as_bytes().to_vec()).into(),
        signature_key: public_key.into(),
    }
}

fn parse(bytes: &[u8]) -> Result<MlsMessageIn, String> {
    MlsMessageIn::tls_deserialize_exact(bytes).map_err(|e| format!("decode: {e:?}"))
}

fn label_of(m: &Member) -> String {
    String::from_utf8_lossy(m.credential.serialized_content()).into_owned()
}

fn create_config() -> MlsGroupCreateConfig {
    MlsGroupCreateConfig::builder()
        .ciphersuite(CIPHERSUITE)
        .use_ratchet_tree_extension(true)
        .build()
}

impl Backend for OpenMls {
    const NAME: &'static str = "openmls-0.9.1";
    type Device = Device;
    type Group = MlsGroup;

    fn new_device(label: &str) -> Device {
        let provider = OpenMlsRustCrypto::default();
        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm()).expect("keygen");
        signer.store(provider.storage()).expect("store signer");
        let credential = credential_for(label, signer.to_public_vec());
        Device { label: label.into(), provider, signer, credential }
    }

    fn key_package(d: &Device) -> Bytes {
        let bundle = KeyPackage::builder()
            .build(CIPHERSUITE, &d.provider, &d.signer, d.credential.clone())
            .expect("key package");
        MlsMessageOut::from(bundle.key_package().clone()).to_bytes().expect("ser")
    }

    fn create_group(d: &Device) -> MlsGroup {
        MlsGroup::new(&d.provider, &d.signer, &create_config(), d.credential.clone())
            .expect("create group")
    }

    fn add(d: &Device, g: &mut MlsGroup, key_packages: &[Bytes]) -> (Bytes, Bytes) {
        let kps: Vec<KeyPackage> = key_packages
            .iter()
            .map(|b| {
                let MlsMessageBodyIn::KeyPackage(kp) = parse(b).expect("kp").extract() else {
                    panic!("not a key package");
                };
                kp.validate(d.provider.crypto(), ProtocolVersion::Mls10).expect("valid kp")
            })
            .collect();
        let (commit, welcome, _info) = g.add_members(&d.provider, &d.signer, &kps).expect("add");
        g.merge_pending_commit(&d.provider).expect("merge");
        (commit.to_bytes().expect("ser"), welcome.to_bytes().expect("ser"))
    }

    fn join(d: &Device, welcome: &[u8]) -> MlsGroup {
        let MlsMessageBodyIn::Welcome(welcome) = parse(welcome).expect("welcome").extract() else {
            panic!("not a welcome");
        };
        let config = MlsGroupJoinConfig::builder().use_ratchet_tree_extension(true).build();
        StagedWelcome::new_from_welcome(&d.provider, &config, welcome, None)
            .expect("stage welcome")
            .into_group(&d.provider)
            .expect("join")
    }

    fn remove(d: &Device, g: &mut MlsGroup, label: &str) -> Bytes {
        let leaf = g.members().find(|m| label_of(m) == label).expect("member").index;
        let (commit, _w, _i) = g.remove_members(&d.provider, &d.signer, &[leaf]).expect("remove");
        g.merge_pending_commit(&d.provider).expect("merge");
        commit.to_bytes().expect("ser")
    }

    fn update(d: &Device, g: &mut MlsGroup) -> Bytes {
        let bundle = g
            .self_update(&d.provider, &d.signer, LeafNodeParameters::default())
            .expect("self update");
        g.merge_pending_commit(&d.provider).expect("merge");
        let (commit, _w, _i) = bundle.into_messages();
        commit.to_bytes().expect("ser")
    }

    fn process_commit(d: &Device, g: &mut MlsGroup, commit: &[u8]) -> Result<(), String> {
        let msg = parse(commit)?.try_into_protocol_message().map_err(|e| format!("{e:?}"))?;
        let processed = g.process_message(&d.provider, msg).map_err(|e| format!("{e:?}"))?;
        match processed.into_content() {
            ProcessedMessageContent::StagedCommitMessage(staged) => {
                g.merge_staged_commit(&d.provider, *staged).map_err(|e| format!("{e:?}"))
            }
            other => Err(format!("expected commit, got {other:?}")),
        }
    }

    fn encrypt(d: &Device, g: &mut MlsGroup, plaintext: &[u8]) -> Bytes {
        g.create_message(&d.provider, &d.signer, plaintext)
            .expect("encrypt")
            .to_bytes()
            .expect("ser")
    }

    fn decrypt(d: &Device, g: &mut MlsGroup, ciphertext: &[u8]) -> Result<Bytes, String> {
        let msg = parse(ciphertext)?.try_into_protocol_message().map_err(|e| format!("{e:?}"))?;
        let processed = g.process_message(&d.provider, msg).map_err(|e| format!("{e:?}"))?;
        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(m) => Ok(m.into_bytes()),
            other => Err(format!("not an application message: {other:?}")),
        }
    }

    fn roster(g: &MlsGroup) -> Vec<String> {
        let mut labels: Vec<String> = g.members().map(|m| label_of(&m)).collect();
        labels.sort();
        labels
    }

    fn epoch(g: &MlsGroup) -> u64 {
        g.epoch().as_u64()
    }

    fn epoch_authenticator(g: &MlsGroup) -> Bytes {
        g.epoch_authenticator().as_slice().to_vec()
    }

    /// Format: label | signer public key | group id | provider key/value
    /// store (OpenMLS persists all group and key state through it).
    fn snapshot(d: &Device, g: &mut MlsGroup) -> Bytes {
        let mut out = vec![];
        put(&mut out, d.label.as_bytes());
        put(&mut out, d.signer.public());
        put(&mut out, g.group_id().as_slice());
        let values = d.provider.storage().values.read().expect("lock");
        out.extend((values.len() as u32).to_be_bytes());
        for (k, v) in values.iter() {
            put(&mut out, k);
            put(&mut out, v);
        }
        out
    }

    fn restore(snapshot: &[u8]) -> (Device, MlsGroup) {
        let mut r = snapshot;
        let label = String::from_utf8(take(&mut r).to_vec()).expect("label");
        let public = take(&mut r).to_vec();
        let group_id = GroupId::from_slice(take(&mut r));
        let provider = OpenMlsRustCrypto::default();
        {
            let n = u32::from_be_bytes(r[..4].try_into().unwrap());
            r = &r[4..];
            let mut values = provider.storage().values.write().expect("lock");
            for _ in 0..n {
                let k = take(&mut r).to_vec();
                let v = take(&mut r).to_vec();
                values.insert(k, v);
            }
        }
        let signer = SignatureKeyPair::read(provider.storage(), &public, CIPHERSUITE.signature_algorithm())
            .expect("signer in store");
        let group = MlsGroup::load(provider.storage(), &group_id)
            .expect("load")
            .expect("group in store");
        let credential = credential_for(&label, public);
        (Device { label, provider, signer, credential }, group)
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
