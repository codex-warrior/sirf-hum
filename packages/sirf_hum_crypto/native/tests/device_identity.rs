//! Device identity tests (Prompt 07): platform store key, account binding,
//! and device proof of possession (D-070). Uses insecure TEST key stores
//! except where the platform-provided key path is under test.

mod common;

use common::*;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider;
use sirf_hum_crypto::identity::{
    device_proof_payload, verify_device_proof, AccountId, ProofPurpose, CHALLENGE_LEN,
};
use sirf_hum_crypto::keystore::PlatformProvidedKey;
use sirf_hum_crypto::store::FileStore;
use sirf_hum_crypto::{CoreError, CryptoCore};

fn crypto() -> OpenMlsRustCrypto {
    OpenMlsRustCrypto::default()
}

fn account(s: &str) -> AccountId {
    AccountId::new(s).unwrap()
}

// --------------------------------------------------------- account binding

#[test]
fn account_check_matches_only_the_owning_account() {
    let alice = Device::new("account-alice");
    alice.core.check_account(&account("account-alice")).unwrap();
    assert_eq!(
        alice
            .core
            .check_account(&account("account-bob"))
            .unwrap_err(),
        CoreError::AccountMismatch
    );
}

#[test]
fn account_check_without_identity_is_identity_state() {
    let tmp = tempfile::tempdir().unwrap();
    let core = open_dir(tmp.path()).unwrap();
    assert_eq!(
        core.check_account(&account("anyone")).unwrap_err(),
        CoreError::IdentityState
    );
}

#[test]
fn account_binding_survives_restart() {
    let mut alice = Device::new("account-alice");
    alice.restart();
    alice.core.check_account(&account("account-alice")).unwrap();
    assert_eq!(
        alice
            .core
            .check_account(&account("account-bob"))
            .unwrap_err(),
        CoreError::AccountMismatch
    );
}

// ------------------------------------------------------------ device proof

#[test]
fn device_proof_verifies_against_the_certificate() {
    let alice = Device::new("account-alice");
    let challenge = [7u8; CHALLENGE_LEN];
    let proof = alice
        .core
        .device_proof(ProofPurpose::Activation, &challenge)
        .unwrap();
    assert_eq!(proof.len(), 64);
    let p = crypto();
    let cert = verify_device_proof(
        p.crypto(),
        ProofPurpose::Activation,
        &account("account-alice"),
        &alice.public.certificate,
        &challenge,
        &proof,
    )
    .unwrap();
    assert_eq!(cert.device_id, alice.public.device_id);
}

#[test]
fn proof_does_not_verify_for_another_account_challenge_or_certificate() {
    let alice = Device::new("account-alice");
    let bob = Device::new("account-bob");
    let challenge = [1u8; CHALLENGE_LEN];
    let proof = alice
        .core
        .device_proof(ProofPurpose::Activation, &challenge)
        .unwrap();
    let p = crypto();
    let verify = |acct: &str, cert: &[u8], ch: &[u8], sig: &[u8]| {
        verify_device_proof(
            p.crypto(),
            ProofPurpose::Activation,
            &account(acct),
            cert,
            ch,
            sig,
        )
    };
    // Altered account ID (proof replayed under another account).
    assert_eq!(
        verify("account-bob", &alice.public.certificate, &challenge, &proof).unwrap_err(),
        CoreError::AuthenticationFailure
    );
    // Different (e.g. stale or reused) challenge.
    assert_eq!(
        verify(
            "account-alice",
            &alice.public.certificate,
            &[2u8; 32],
            &proof
        )
        .unwrap_err(),
        CoreError::AuthenticationFailure
    );
    // Copied proof presented with another device's certificate.
    assert_eq!(
        verify("account-alice", &bob.public.certificate, &challenge, &proof).unwrap_err(),
        CoreError::AuthenticationFailure
    );
    // Tampered signature.
    let mut bad = proof.clone();
    bad[10] ^= 1;
    assert_eq!(
        verify("account-alice", &alice.public.certificate, &challenge, &bad).unwrap_err(),
        CoreError::AuthenticationFailure
    );
    // Wrong signature length.
    assert_eq!(
        verify(
            "account-alice",
            &alice.public.certificate,
            &challenge,
            &proof[..63]
        )
        .unwrap_err(),
        CoreError::AuthenticationFailure
    );
}

#[test]
fn proof_purposes_are_separate_signed_domains() {
    // A push-token proof (Prompt 11, D-098) is useless as an activation or
    // enrollment proof for the same challenge, and vice versa.
    let alice = Device::new("account-alice");
    let challenge = [9u8; CHALLENGE_LEN];
    let p = crypto();
    let purposes = [
        ProofPurpose::Activation,
        ProofPurpose::Enrollment,
        ProofPurpose::PushToken,
    ];
    for made in purposes {
        let proof = alice.core.device_proof(made, &challenge).unwrap();
        for checked in purposes {
            let ok = verify_device_proof(
                p.crypto(),
                checked,
                &account("account-alice"),
                &alice.public.certificate,
                &challenge,
                &proof,
            )
            .is_ok();
            assert_eq!(ok, made == checked, "{made:?} verified as {checked:?}");
        }
    }
}

#[test]
fn altered_certificate_is_rejected_before_the_proof() {
    let alice = Device::new("account-alice");
    let challenge = [3u8; CHALLENGE_LEN];
    let proof = alice
        .core
        .device_proof(ProofPurpose::Activation, &challenge)
        .unwrap();
    let p = crypto();
    for pos in 0..alice.public.certificate.len() {
        let mut cert = alice.public.certificate.clone();
        cert[pos] ^= 1;
        assert!(
            verify_device_proof(
                p.crypto(),
                ProofPurpose::Activation,
                &account("account-alice"),
                &cert,
                &challenge,
                &proof
            )
            .is_err(),
            "certificate byte {pos} accepted"
        );
    }
}

#[test]
fn challenge_must_be_exactly_32_bytes() {
    let alice = Device::new("account-alice");
    for len in [0usize, 31, 33, 64] {
        assert_eq!(
            alice
                .core
                .device_proof(ProofPurpose::Activation, &vec![0u8; len])
                .unwrap_err(),
            CoreError::InvalidInput
        );
    }
    assert_eq!(
        ProofPurpose::from_u32(0).unwrap_err(),
        CoreError::InvalidInput
    );
    // Prompt 08 added purpose 2 (enrollment), Prompt 11 purpose 3 (push
    // token, D-098); anything else stays invalid.
    assert_eq!(ProofPurpose::from_u32(2).unwrap(), ProofPurpose::Enrollment);
    assert_eq!(ProofPurpose::from_u32(3).unwrap(), ProofPurpose::PushToken);
    assert_eq!(
        ProofPurpose::from_u32(4).unwrap_err(),
        CoreError::InvalidInput
    );
}

#[test]
fn proof_needs_an_identity_and_changes_no_state() {
    let tmp = tempfile::tempdir().unwrap();
    let core = open_dir(tmp.path()).unwrap();
    assert_eq!(
        core.device_proof(ProofPurpose::Activation, &[0u8; 32])
            .unwrap_err(),
        CoreError::IdentityState
    );
    let (alice, _bob, gid) = couple();
    let before = std::fs::read(record_path(&alice.dir, "mls_state")).unwrap();
    let epoch = alice.core.epoch(&gid).unwrap();
    alice
        .core
        .device_proof(ProofPurpose::Activation, &[9u8; 32])
        .unwrap();
    assert_eq!(alice.core.epoch(&gid).unwrap(), epoch);
    assert_eq!(
        std::fs::read(record_path(&alice.dir, "mls_state")).unwrap(),
        before
    );
}

#[test]
fn proof_payload_is_domain_separated_and_bound() {
    let alice = Device::new("account-alice");
    let payload = device_proof_payload(
        ProofPurpose::Activation,
        &account("account-alice"),
        &alice.public.device_id,
        &alice.public.certificate,
        &[0u8; 32],
    )
    .unwrap();
    assert!(payload.starts_with(b"SirfHum-DeviceProof-v1\x01"));
    // Distinct from the certificate's signed domain.
    assert!(!payload.starts_with(b"SirfHum-DeviceCertificate-v1"));
}

/// Golden vector produced by the server implementation
/// (functions/src/device/proof.ts via functions/test/vectors/generate.mjs):
/// proves the Rust and server encodings agree byte for byte.
#[test]
fn server_generated_golden_vector_verifies_in_rust() {
    let v: serde_like::Vector = serde_like::load(include_str!(
        "../../../../functions/test/vectors/device_proof_v1.json"
    ));
    let p = crypto();
    let cert = verify_device_proof(
        p.crypto(),
        ProofPurpose::Activation,
        &account(&v.account_id),
        &v.certificate,
        &v.challenge,
        &v.signature,
    )
    .expect("server-generated proof must verify in Rust");
    assert_eq!(cert.device_id.0.to_vec(), v.device_id);
    let payload = device_proof_payload(
        ProofPurpose::Activation,
        &account(&v.account_id),
        &cert.device_id,
        &v.certificate,
        &v.challenge,
    )
    .unwrap();
    assert_eq!(payload, v.payload, "payload encoding differs from server");
}

/// Minimal JSON reader for the vector (hex strings only), to avoid a JSON
/// dependency in the crypto core.
mod serde_like {
    pub struct Vector {
        pub account_id: String,
        pub device_id: Vec<u8>,
        pub certificate: Vec<u8>,
        pub challenge: Vec<u8>,
        pub signature: Vec<u8>,
        pub payload: Vec<u8>,
    }

    fn field<'a>(json: &'a str, name: &str) -> &'a str {
        let key = format!("\"{name}\": \"");
        let start = json.find(&key).unwrap_or_else(|| panic!("missing {name}")) + key.len();
        let end = start + json[start..].find('"').unwrap();
        &json[start..end]
    }

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    pub fn load(json: &str) -> Vector {
        Vector {
            account_id: field(json, "accountId").to_owned(),
            device_id: hex(field(json, "deviceIdHex")),
            certificate: hex(field(json, "certificateHex")),
            challenge: hex(field(json, "challengeHex")),
            signature: hex(field(json, "signatureHex")),
            payload: hex(field(json, "payloadHex")),
        }
    }
}

// ------------------------------------------------------ platform store key

#[test]
fn platform_key_opens_restores_and_rejects_other_keys() {
    let tmp = tempfile::tempdir().unwrap();
    let key = [42u8; 32];
    let device_id = {
        let mut core = CryptoCore::open(
            Box::new(FileStore::open(tmp.path()).unwrap()),
            &PlatformProvidedKey::from_slice(&key).unwrap(),
        )
        .unwrap();
        assert!(core.uses_production_secure_keys());
        core.create_identity(account("account-alice"))
            .unwrap()
            .device_id
    };
    // Same key: identity restored.
    let core = CryptoCore::open(
        Box::new(FileStore::open(tmp.path()).unwrap()),
        &PlatformProvidedKey::from_slice(&key).unwrap(),
    )
    .unwrap();
    assert_eq!(core.public_identity().unwrap().device_id, device_id);
    drop(core);
    // Another key (e.g. state restored onto another device): fails closed.
    let err = CryptoCore::open(
        Box::new(FileStore::open(tmp.path()).unwrap()),
        &PlatformProvidedKey::from_slice(&[43u8; 32]).unwrap(),
    )
    .err()
    .unwrap();
    assert_eq!(err, CoreError::StateCorruption);
}

#[test]
fn platform_key_must_be_32_nonzero_bytes() {
    for bad in [vec![1u8; 31], vec![1u8; 33], vec![], vec![0u8; 32]] {
        assert_eq!(
            PlatformProvidedKey::from_slice(&bad).err(),
            Some(CoreError::InvalidInput)
        );
    }
}

#[test]
fn test_key_stores_never_claim_platform_protection() {
    let alice = Device::new("account-alice");
    assert!(!alice.core.uses_production_secure_keys());
}
