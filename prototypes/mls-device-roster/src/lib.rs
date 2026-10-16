//! EXPERIMENTAL SPIKE — NOT PRODUCTION CODE. Not part of the Sirf Hum app.
//!
//! Question answered (docs/security/E2EE-ARCHITECTURE.md, "Prototype"):
//! can an unmodified, maintained MLS (RFC 9420) implementation express the
//! Sirf Hum model — one group per couple whose members are *devices* of two
//! independent people — with an authenticated, convergent device roster,
//! and with removed devices unable to read later messages?
//!
//! Everything cryptographic is OpenMLS. This file only wires test devices
//! together; it defines no protocol, cipher or message format. Device
//! identities here are plain labels; binding a device to a person's identity
//! key is an open design item (PAIRING-AND-DEVICE-TRUST.md).

use openmls::prelude::{tls_codec::*, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;

/// MLS mandatory-to-implement ciphersuite (RFC 9420 §17.1).
pub const CIPHERSUITE: Ciphersuite =
    Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

/// One device of one person, with its own key material and local state.
pub struct Device {
    pub label: &'static str,
    pub provider: OpenMlsRustCrypto,
    pub signer: SignatureKeyPair,
    pub credential: CredentialWithKey,
}

impl Device {
    pub fn new(label: &'static str) -> Self {
        let provider = OpenMlsRustCrypto::default();
        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())
            .expect("signature key generation");
        signer
            .store(provider.storage())
            .expect("store signature key");
        let credential = CredentialWithKey {
            credential: BasicCredential::new(label.as_bytes().to_vec()).into(),
            signature_key: signer.to_public_vec().into(),
        };
        Self { label, provider, signer, credential }
    }

    /// A fresh, single-use KeyPackage another member can add.
    pub fn key_package(&self) -> KeyPackage {
        KeyPackage::builder()
            .build(CIPHERSUITE, &self.provider, &self.signer, self.credential.clone())
            .expect("key package")
            .key_package()
            .clone()
    }

    pub fn create_group(&self) -> MlsGroup {
        let config = MlsGroupCreateConfig::builder()
            .ciphersuite(CIPHERSUITE)
            .use_ratchet_tree_extension(true)
            .build();
        MlsGroup::new(&self.provider, &self.signer, &config, self.credential.clone())
            .expect("create group")
    }

    pub fn join(&self, welcome: &MlsMessageOut) -> MlsGroup {
        let message = MlsMessageIn::tls_deserialize_exact(welcome.to_bytes().expect("ser"))
            .expect("deserialize welcome");
        let MlsMessageBodyIn::Welcome(welcome) = message.extract() else {
            panic!("expected a Welcome message");
        };
        let config = MlsGroupJoinConfig::builder()
            .use_ratchet_tree_extension(true)
            .build();
        StagedWelcome::new_from_welcome(&self.provider, &config, welcome, None)
            .expect("stage welcome")
            .into_group(&self.provider)
            .expect("join group")
    }
}

/// Simulates the untrusted delivery service: only bytes cross it.
pub fn transport(message: &MlsMessageOut) -> Vec<u8> {
    message.to_bytes().expect("serialize")
}

/// Parses bytes received from the delivery service.
pub fn receive(bytes: &[u8]) -> Result<ProtocolMessage, String> {
    MlsMessageIn::tls_deserialize_exact(bytes)
        .map_err(|e| format!("deserialize: {e:?}"))?
        .try_into_protocol_message()
        .map_err(|e| format!("not a protocol message: {e:?}"))
}

/// Labels of the group's members, as authenticated by the MLS tree.
pub fn roster(group: &MlsGroup) -> Vec<String> {
    let mut labels: Vec<String> = group
        .members()
        .map(|m| String::from_utf8(m.credential.serialized_content().to_vec()).unwrap())
        .collect();
    labels.sort();
    labels
}

pub fn leaf_of(group: &MlsGroup, label: &str) -> LeafNodeIndex {
    group
        .members()
        .find(|m| m.credential.serialized_content() == label.as_bytes())
        .expect("member present")
        .index
}
