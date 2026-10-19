//! Multi-device trust (Prompt 08, D-074–D-076): device approval, recovery
//! key, comparison code, and server-generated golden vectors. Uses insecure
//! TEST key stores.

mod common;

use common::*;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider;
use sirf_hum_crypto::identity::{
    approval_code, device_approval_payload, recovery_approval_payload,
    recovery_registration_payload, verify_device_approval, verify_recovery_approval,
    verify_recovery_registration, AccountId, CHALLENGE_LEN,
};
use sirf_hum_crypto::CoreError;

const CHALLENGE: [u8; CHALLENGE_LEN] = [5u8; CHALLENGE_LEN];
const EXPIRES: u64 = 1_800_000_000;

fn account(s: &str) -> AccountId {
    AccountId::new(s).unwrap()
}

/// Two devices of ONE account, each with its own PIK and device key.
fn same_account_devices() -> (Device, Device) {
    (Device::new("accountA"), Device::new("accountA"))
}

// ------------------------------------------------------------- approval

#[test]
fn every_device_has_independent_key_material() {
    let (a, b) = same_account_devices();
    assert_ne!(a.public.device_id, b.public.device_id);
    assert_ne!(a.public.person_key, b.public.person_key, "no shared PIK");
    assert_ne!(a.public.certificate, b.public.certificate);
}

#[test]
fn approval_verifies_and_binds_every_field() {
    let (mut a, b) = same_account_devices();
    let sig = a
        .core
        .approve_device(&b.public.certificate, &CHALLENGE, EXPIRES)
        .unwrap();
    let p = OpenMlsRustCrypto::default();
    let c = p.crypto();
    let acct = account("accountA");
    verify_device_approval(
        c,
        &acct,
        &a.public.certificate,
        &b.public.certificate,
        &CHALLENGE,
        EXPIRES,
        &sig,
    )
    .unwrap();
    let other = Device::new("accountA");
    let fail = |acct: &AccountId, approver: &[u8], new: &[u8], ch: &[u8], exp: u64| {
        verify_device_approval(c, acct, approver, new, ch, exp, &sig).unwrap_err()
    };
    let (ac, bc, oc) = (
        &a.public.certificate,
        &b.public.certificate,
        &other.public.certificate,
    );
    assert_eq!(
        fail(&account("accountB"), ac, bc, &CHALLENGE, EXPIRES),
        CoreError::AuthenticationFailure
    );
    assert_eq!(
        fail(&acct, oc, bc, &CHALLENGE, EXPIRES),
        CoreError::AuthenticationFailure,
        "wrong approver"
    );
    assert_eq!(
        fail(&acct, ac, oc, &CHALLENGE, EXPIRES),
        CoreError::AuthenticationFailure,
        "wrong new device"
    );
    assert_eq!(
        fail(&acct, ac, bc, &[6u8; 32], EXPIRES),
        CoreError::AuthenticationFailure
    );
    assert_eq!(
        fail(&acct, ac, bc, &CHALLENGE, EXPIRES + 1),
        CoreError::AuthenticationFailure
    );
}

#[test]
fn approval_cannot_be_forged_from_a_device_proof() {
    let (a, b) = same_account_devices();
    // A's device proof over the same challenge is a different signed domain
    // and a different key (device key vs PIK).
    let proof = a
        .core
        .device_proof(
            sirf_hum_crypto::identity::ProofPurpose::Enrollment,
            &CHALLENGE,
        )
        .unwrap();
    let p = OpenMlsRustCrypto::default();
    assert_eq!(
        verify_device_approval(
            p.crypto(),
            &account("accountA"),
            &a.public.certificate,
            &b.public.certificate,
            &CHALLENGE,
            EXPIRES,
            &proof
        )
        .unwrap_err(),
        CoreError::AuthenticationFailure
    );
}

#[test]
fn self_approval_tampered_or_revoked_targets_are_refused() {
    let (mut a, b) = same_account_devices();
    let own = a.public.certificate.clone();
    assert_eq!(
        a.core
            .approve_device(&own, &CHALLENGE, EXPIRES)
            .unwrap_err(),
        CoreError::InvalidInput
    );
    let mut tampered = b.public.certificate.clone();
    tampered[40] ^= 1;
    assert!(a
        .core
        .approve_device(&tampered, &CHALLENGE, EXPIRES)
        .is_err());
    assert_eq!(
        a.core
            .approve_device(&b.public.certificate, &[0u8; 31], EXPIRES)
            .unwrap_err(),
        CoreError::InvalidInput
    );
    a.core.revoke_device(b.public.device_id).unwrap();
    assert_eq!(
        a.core
            .approve_device(&b.public.certificate, &CHALLENGE, EXPIRES)
            .unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

#[test]
fn approving_lets_the_approver_add_the_new_device_to_mls() {
    // Before approval A rejects B's KeyPackage (B's PIK is unknown to A);
    // after approval A accepts it. The approval is what extends trust.
    let (mut a, mut b) = same_account_devices();
    let gid = a.core.create_group().unwrap();
    let kp = b.core.key_package().unwrap();
    assert_eq!(
        a.core.add_member(&gid, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    a.core
        .approve_device(&b.public.certificate, &CHALLENGE, EXPIRES)
        .unwrap();
    let added = a.core.add_member(&gid, &kp).unwrap();
    // B trusts A once it has verified A (future: from the approval itself).
    b.trust(&a);
    assert_eq!(b.core.join(&added.welcome).unwrap(), gid);
}

#[test]
fn approval_trust_survives_restart() {
    let (mut a, b) = same_account_devices();
    a.core
        .approve_device(&b.public.certificate, &CHALLENGE, EXPIRES)
        .unwrap();
    a.restart();
    let mut b = b;
    let gid = a.core.create_group().unwrap();
    let kp = b.core.key_package().unwrap();
    a.core.add_member(&gid, &kp).unwrap();
}

// -------------------------------------------------------- recovery key

#[test]
fn recovery_key_round_trip_registration_and_approval() {
    let (a, c) = same_account_devices();
    let bundle = a.core.create_recovery_key(&CHALLENGE, EXPIRES).unwrap();
    assert!(bundle.secret.starts_with("SHRK1-"));
    assert_eq!(format!("{bundle:?}"), "RecoveryKeyBundle(<redacted>)");
    let p = OpenMlsRustCrypto::default();
    let acct = account("accountA");
    verify_recovery_registration(
        p.crypto(),
        &acct,
        &a.public.certificate,
        &bundle.public_key,
        &CHALLENGE,
        EXPIRES,
        &bundle.registration_signature,
    )
    .unwrap();
    // A new device C, with only the typed recovery key.
    let approval = c
        .core
        .recovery_approval(&bundle.secret, &[7u8; 32], EXPIRES + 10)
        .unwrap();
    assert_eq!(approval.recovery_public_key, bundle.public_key);
    verify_recovery_approval(
        p.crypto(),
        &acct,
        &bundle.public_key,
        &c.public.certificate,
        &[7u8; 32],
        EXPIRES + 10,
        &approval.signature,
    )
    .unwrap();
    // The approval names C: it cannot approve another device.
    assert_eq!(
        verify_recovery_approval(
            p.crypto(),
            &acct,
            &bundle.public_key,
            &a.public.certificate,
            &[7u8; 32],
            EXPIRES + 10,
            &approval.signature,
        )
        .unwrap_err(),
        CoreError::AuthenticationFailure
    );
}

#[test]
fn each_recovery_key_is_fresh_and_typos_are_caught() {
    let (a, c) = same_account_devices();
    let k1 = a.core.create_recovery_key(&CHALLENGE, EXPIRES).unwrap();
    let k2 = a.core.create_recovery_key(&CHALLENGE, EXPIRES).unwrap();
    assert_ne!(k1.public_key, k2.public_key);
    let mut typo = k1.secret.to_string();
    let last = typo.pop().unwrap();
    typo.push(if last == 'A' { 'B' } else { 'A' });
    assert_eq!(
        c.core
            .recovery_approval(&typo, &CHALLENGE, EXPIRES)
            .unwrap_err(),
        CoreError::RecoveryKeyInvalid
    );
    assert_eq!(
        c.core
            .recovery_approval("not a key", &CHALLENGE, EXPIRES)
            .unwrap_err(),
        CoreError::RecoveryKeyInvalid
    );
}

#[test]
fn recovery_registration_by_the_wrong_device_does_not_verify() {
    let (a, other) = same_account_devices();
    let bundle = a.core.create_recovery_key(&CHALLENGE, EXPIRES).unwrap();
    let p = OpenMlsRustCrypto::default();
    assert_eq!(
        verify_recovery_registration(
            p.crypto(),
            &account("accountA"),
            &other.public.certificate,
            &bundle.public_key,
            &CHALLENGE,
            EXPIRES,
            &bundle.registration_signature,
        )
        .unwrap_err(),
        CoreError::AuthenticationFailure
    );
}

// ------------------------------------------------- comparison code + vectors

#[test]
fn comparison_code_is_six_digits_and_bound() {
    let (a, b) = same_account_devices();
    let p = OpenMlsRustCrypto::default();
    let code = approval_code(p.crypto(), &b.public.certificate, &CHALLENGE).unwrap();
    assert!(code < 1_000_000);
    assert_eq!(
        approval_code(p.crypto(), &b.public.certificate, &CHALLENGE).unwrap(),
        code
    );
    assert_ne!(
        approval_code(p.crypto(), &a.public.certificate, &CHALLENGE).unwrap(),
        code
    );
}

/// Golden vectors produced by the server implementation
/// (functions/test/vectors/generate.mjs): the Rust and server encodings of
/// all three statements, and the comparison code, agree byte for byte.
#[test]
fn server_generated_trust_vectors_verify_in_rust() {
    let json = include_str!("../../../../functions/test/vectors/device_trust_v1.json");
    let field = |name: &str| -> String {
        let key = format!("\"{name}\": \"");
        let start = json.find(&key).unwrap_or_else(|| panic!("missing {name}")) + key.len();
        let end = start + json[start..].find('"').unwrap();
        json[start..end].to_owned()
    };
    let hex = |name: &str| -> Vec<u8> {
        let s = field(name);
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    };
    let acct = account(&field("accountId"));
    let approver = hex("approverCertificateHex");
    let new = hex("newCertificateHex");
    let recovery = hex("recoveryPublicKeyHex");
    let challenge = hex("challengeHex");
    let expires: u64 = field("expiresAtUnix").parse().unwrap();
    let p = OpenMlsRustCrypto::default();
    let c = p.crypto();

    assert_eq!(
        device_approval_payload(&acct, &approver, &new, &challenge, expires).unwrap(),
        hex("approvalPayloadHex")
    );
    verify_device_approval(
        c,
        &acct,
        &approver,
        &new,
        &challenge,
        expires,
        &hex("approvalSignatureHex"),
    )
    .unwrap();
    assert_eq!(
        recovery_registration_payload(&acct, &approver, &recovery, &challenge, expires).unwrap(),
        hex("registrationPayloadHex")
    );
    verify_recovery_registration(
        c,
        &acct,
        &approver,
        &recovery,
        &challenge,
        expires,
        &hex("registrationSignatureHex"),
    )
    .unwrap();
    assert_eq!(
        recovery_approval_payload(&acct, &recovery, &new, &challenge, expires).unwrap(),
        hex("recoveryPayloadHex")
    );
    verify_recovery_approval(
        c,
        &acct,
        &recovery,
        &new,
        &challenge,
        expires,
        &hex("recoverySignatureHex"),
    )
    .unwrap();
    assert_eq!(
        format!("{:06}", approval_code(c, &new, &challenge).unwrap()),
        field("approvalCode")
    );
    // Seed → public key agreement (Node vs Rust) is tested in recovery.rs.
}
