//! Prompt 09: signed revocation (D-081), identity-reset cancellation
//! (D-082), trust epoch (D-083) and peer-side lineage verification (D-084).
//! Uses insecure TEST key stores.

mod common;

use common::*;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::OpenMlsProvider;
use sirf_hum_crypto::identity::{
    reset_cancel_payload, revocation_payload, verify_lineage, verify_reset_cancel,
    verify_revocation, AccountId, DeviceId, RecoveryRegistrationEvidence, RevocationEvidence,
    RevocationReason, TrustLink, TRUST_PROTOCOL_VERSION,
};
use sirf_hum_crypto::limits::MAX_LINEAGE_BYTES;
use sirf_hum_crypto::CoreError;

const CH: [u8; 32] = [9u8; 32];
const EXP: u64 = 1_900_000_000;

fn acct() -> AccountId {
    AccountId::new("accountA").unwrap()
}

fn devices(n: usize) -> Vec<Device> {
    (0..n).map(|_| Device::new("accountA")).collect()
}

// ------------------------------------------------------------ revocation

#[test]
fn revocation_verifies_and_binds_every_field() {
    let d = devices(3);
    let (a, b, c) = (&d[0], &d[1], &d[2]);
    let sig = a
        .core
        .sign_revocation(&b.public.certificate, RevocationReason::Stolen, &CH, EXP)
        .unwrap();
    let p = OpenMlsRustCrypto::default();
    let x = p.crypto();
    let (ac, bc, cc) = (
        &a.public.certificate,
        &b.public.certificate,
        &c.public.certificate,
    );
    verify_revocation(x, &acct(), ac, bc, RevocationReason::Stolen, &CH, EXP, &sig).unwrap();
    let other = AccountId::new("accountB").unwrap();
    for (account, revoker, revoked, reason, ch, exp) in [
        (&other, ac, bc, RevocationReason::Stolen, CH, EXP),
        (&acct(), cc, bc, RevocationReason::Stolen, CH, EXP),
        (&acct(), ac, cc, RevocationReason::Stolen, CH, EXP),
        (&acct(), ac, bc, RevocationReason::Lost, CH, EXP),
        (&acct(), ac, bc, RevocationReason::Stolen, [8u8; 32], EXP),
        (&acct(), ac, bc, RevocationReason::Stolen, CH, EXP + 1),
    ] {
        assert_eq!(
            verify_revocation(x, account, revoker, revoked, reason, &ch, exp, &sig).unwrap_err(),
            CoreError::AuthenticationFailure
        );
    }
}

#[test]
fn self_revocation_is_signed_by_the_device_itself() {
    let d = devices(1);
    let a = &d[0];
    let sig = a
        .core
        .sign_revocation(&a.public.certificate, RevocationReason::Removed, &CH, EXP)
        .unwrap();
    let p = OpenMlsRustCrypto::default();
    verify_revocation(
        p.crypto(),
        &acct(),
        &a.public.certificate,
        &a.public.certificate,
        RevocationReason::Removed,
        &CH,
        EXP,
        &sig,
    )
    .unwrap();
}

#[test]
fn revocations_and_approvals_are_separate_signed_domains() {
    let d = devices(2);
    let (mut a, b) = (d.into_iter().next().unwrap(), Device::new("accountA"));
    let approval = a
        .core
        .approve_device(&b.public.certificate, &CH, EXP)
        .unwrap();
    let p = OpenMlsRustCrypto::default();
    assert!(verify_revocation(
        p.crypto(),
        &acct(),
        &a.public.certificate,
        &b.public.certificate,
        RevocationReason::Removed,
        &CH,
        EXP,
        &approval
    )
    .is_err());
    let payload = revocation_payload(
        &acct(),
        &a.public.certificate,
        &b.public.certificate,
        RevocationReason::Lost,
        &CH,
        EXP,
    )
    .unwrap();
    assert!(payload.starts_with(b"SirfHum-DeviceRevocation-v1\x01"));
    assert_eq!(
        RevocationReason::from_u8(0).unwrap_err(),
        CoreError::InvalidInput
    );
    assert_eq!(
        RevocationReason::from_u8(5).unwrap_err(),
        CoreError::InvalidInput
    );
}

// --------------------------------------------------------- reset cancel

#[test]
fn reset_cancellation_verifies_only_for_its_device_and_account() {
    let d = devices(2);
    let (a, b) = (&d[0], &d[1]);
    let sig = a.core.sign_reset_cancellation(&CH, EXP).unwrap();
    let p = OpenMlsRustCrypto::default();
    verify_reset_cancel(p.crypto(), &acct(), &a.public.certificate, &CH, EXP, &sig).unwrap();
    assert!(
        verify_reset_cancel(p.crypto(), &acct(), &b.public.certificate, &CH, EXP, &sig).is_err()
    );
    assert!(verify_reset_cancel(
        p.crypto(),
        &AccountId::new("accountB").unwrap(),
        &a.public.certificate,
        &CH,
        EXP,
        &sig
    )
    .is_err());
    assert!(
        reset_cancel_payload(&acct(), &a.public.certificate, &CH, EXP)
            .unwrap()
            .starts_with(b"SirfHum-IdentityResetCancel-v1\x01")
    );
}

// ------------------------------------------------------------ trust epoch

#[test]
fn trust_epoch_only_moves_forward_and_survives_restart() {
    let mut d = devices(1).pop().unwrap();
    assert_eq!(d.core.observe_trust_epoch(3).unwrap(), 0);
    assert_eq!(d.core.observe_trust_epoch(3).unwrap(), 3, "equal is fine");
    assert_eq!(d.core.observe_trust_epoch(7).unwrap(), 3);
    assert_eq!(
        d.core.observe_trust_epoch(6).unwrap_err(),
        CoreError::TrustStateStale
    );
    d.restart();
    assert_eq!(
        d.core.observe_trust_epoch(5).unwrap_err(),
        CoreError::TrustStateStale
    );
    assert_eq!(d.core.observe_trust_epoch(8).unwrap(), 7);
}

#[test]
fn wipe_forgets_the_trust_epoch() {
    let mut d = devices(1).pop().unwrap();
    d.core.observe_trust_epoch(10).unwrap();
    d.core.wipe().unwrap();
    assert_eq!(d.core.observe_trust_epoch(1).unwrap(), 0);
}

// ---------------------------------------------------------------- lineage

struct Chain {
    a: Device,
    b: Device,
    c: Device,
    ab: Vec<u8>,
    bc: Vec<u8>,
}

/// A root; A approves B; B approves C.
fn chain() -> Chain {
    let mut d = devices(3);
    let c = d.pop().unwrap();
    let mut b = d.pop().unwrap();
    let mut a = d.pop().unwrap();
    let ab = a
        .core
        .approve_device(&b.public.certificate, &[1u8; 32], EXP)
        .unwrap();
    let bc = b
        .core
        .approve_device(&c.public.certificate, &[2u8; 32], EXP)
        .unwrap();
    Chain { a, b, c, ab, bc }
}

fn approval<'a>(approver: &'a [u8], new: &'a [u8], ch: &'a [u8], sig: &'a [u8]) -> TrustLink<'a> {
    TrustLink::Approval {
        protocol_version: TRUST_PROTOCOL_VERSION,
        approver_certificate: approver,
        new_certificate: new,
        challenge: ch,
        expires_at_unix: EXP,
        signature: sig,
    }
}

fn ids(certs: &[sirf_hum_crypto::identity::DeviceCertificate]) -> Vec<DeviceId> {
    certs.iter().map(|c| c.device_id).collect()
}

#[test]
fn a_valid_chain_verifies_on_the_device() {
    let k = chain();
    let p = OpenMlsRustCrypto::default();
    let (ac, bc, cc) = (
        &k.a.public.certificate,
        &k.b.public.certificate,
        &k.c.public.certificate,
    );
    let links = [
        approval(ac, bc, &[1u8; 32], &k.ab),
        approval(bc, cc, &[2u8; 32], &k.bc),
    ];
    let trusted = verify_lineage(p.crypto(), &acct(), ac, &links, &[], &[]).unwrap();
    assert_eq!(
        ids(&trusted),
        vec![
            k.a.public.device_id,
            k.b.public.device_id,
            k.c.public.device_id
        ]
    );
}

#[test]
fn signed_revocation_removes_a_device_but_not_those_it_approved() {
    let k = chain();
    let p = OpenMlsRustCrypto::default();
    let (ac, bc, cc) = (
        &k.a.public.certificate,
        &k.b.public.certificate,
        &k.c.public.certificate,
    );
    let links = [
        approval(ac, bc, &[1u8; 32], &k.ab),
        approval(bc, cc, &[2u8; 32], &k.bc),
    ];
    let sig =
        k.a.core
            .sign_revocation(bc, RevocationReason::Lost, &[3u8; 32], EXP)
            .unwrap();
    let revocation = RevocationEvidence {
        protocol_version: TRUST_PROTOCOL_VERSION,
        revoker_certificate: ac,
        revoked_certificate: bc,
        reason: RevocationReason::Lost,
        challenge: &[3u8; 32],
        expires_at_unix: EXP,
        signature: &sig,
    };
    let trusted = verify_lineage(p.crypto(), &acct(), ac, &links, &[revocation], &[]).unwrap();
    // No cascade (D-080): C, approved by B before B's revocation, stays.
    assert_eq!(
        ids(&trusted),
        vec![k.a.public.device_id, k.c.public.device_id]
    );
    // Server-asserted revocations (identity reset) are honoured too.
    let trusted = verify_lineage(
        p.crypto(),
        &acct(),
        ac,
        &links,
        &[],
        &[k.a.public.device_id],
    )
    .unwrap();
    assert_eq!(
        ids(&trusted),
        vec![k.b.public.device_id, k.c.public.device_id]
    );
}

#[test]
fn broken_or_forged_chains_fail_closed() {
    let k = chain();
    let outsider = Device::new("accountA");
    let p = OpenMlsRustCrypto::default();
    let x = p.crypto();
    let (ac, bc, cc) = (
        &k.a.public.certificate,
        &k.b.public.certificate,
        &k.c.public.certificate,
    );
    let invalid = CoreError::TrustChainInvalid;
    // Missing link: C's approver B is not (yet) in the chain.
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            ac,
            &[approval(bc, cc, &[2u8; 32], &k.bc)],
            &[],
            &[]
        )
        .unwrap_err(),
        invalid
    );
    // Wrong root: the server cannot pick another root and keep the links.
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            &outsider.public.certificate,
            &[approval(ac, bc, &[1u8; 32], &k.ab)],
            &[],
            &[]
        )
        .unwrap_err(),
        invalid
    );
    // Wrong account.
    assert_eq!(
        verify_lineage(
            x,
            &AccountId::new("accountB").unwrap(),
            ac,
            &[approval(ac, bc, &[1u8; 32], &k.ab)],
            &[],
            &[]
        )
        .unwrap_err(),
        invalid
    );
    // Tampered signature / wrong challenge.
    let mut bad = k.ab.clone();
    bad[0] ^= 1;
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            ac,
            &[approval(ac, bc, &[1u8; 32], &bad)],
            &[],
            &[]
        )
        .unwrap_err(),
        invalid
    );
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            ac,
            &[approval(ac, bc, &[7u8; 32], &k.ab)],
            &[],
            &[]
        )
        .unwrap_err(),
        invalid
    );
    // Unsupported protocol version.
    let v2 = TrustLink::Approval {
        protocol_version: 2,
        approver_certificate: ac,
        new_certificate: bc,
        challenge: &[1u8; 32],
        expires_at_unix: EXP,
        signature: &k.ab,
    };
    assert_eq!(
        verify_lineage(x, &acct(), ac, &[v2], &[], &[]).unwrap_err(),
        invalid
    );
    // The same device twice.
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            ac,
            &[
                approval(ac, bc, &[1u8; 32], &k.ab),
                approval(ac, bc, &[1u8; 32], &k.ab)
            ],
            &[],
            &[]
        )
        .unwrap_err(),
        invalid
    );
    // A revocation signed by a device outside the chain.
    let sig = outsider
        .core
        .sign_revocation(bc, RevocationReason::Removed, &[4u8; 32], EXP)
        .unwrap();
    let foreign = RevocationEvidence {
        protocol_version: TRUST_PROTOCOL_VERSION,
        revoker_certificate: &outsider.public.certificate,
        revoked_certificate: bc,
        reason: RevocationReason::Removed,
        challenge: &[4u8; 32],
        expires_at_unix: EXP,
        signature: &sig,
    };
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            ac,
            &[approval(ac, bc, &[1u8; 32], &k.ab)],
            &[foreign],
            &[]
        )
        .unwrap_err(),
        invalid
    );
}

/// A recovery link: `registrar_cert` claims to have registered the key.
fn recovery_link<'a>(
    registrar_cert: &'a [u8],
    recovery_public_key: &'a [u8],
    registration_signature: &'a [u8],
    new_cert: &'a [u8],
    recovery_signature: &'a [u8],
) -> TrustLink<'a> {
    TrustLink::Recovery {
        protocol_version: TRUST_PROTOCOL_VERSION,
        registration: RecoveryRegistrationEvidence {
            registrar_certificate: registrar_cert,
            recovery_public_key,
            challenge: &[5u8; 32],
            expires_at_unix: EXP,
            signature: registration_signature,
        },
        new_certificate: new_cert,
        challenge: &[6u8; 32],
        expires_at_unix: EXP,
        signature: recovery_signature,
    }
}

#[test]
fn recovery_links_need_a_registration_by_a_chain_device() {
    let k = chain();
    let p = OpenMlsRustCrypto::default();
    let x = p.crypto();
    let (ac, bc, cc) = (
        &k.a.public.certificate,
        &k.b.public.certificate,
        &k.c.public.certificate,
    );
    // B registers a recovery key; the key recovers C.
    let bundle = k.b.core.create_recovery_key(&[5u8; 32], EXP).unwrap();
    let rec =
        k.c.core
            .recovery_approval(&bundle.secret, &[6u8; 32], EXP)
            .unwrap();
    let (pk, reg, sig) = (
        &bundle.public_key[..],
        &bundle.registration_signature[..],
        &rec.signature[..],
    );
    let trusted = verify_lineage(
        x,
        &acct(),
        ac,
        &[
            approval(ac, bc, &[1u8; 32], &k.ab),
            recovery_link(bc, pk, reg, cc, sig),
        ],
        &[],
        &[],
    )
    .unwrap();
    assert_eq!(ids(&trusted).last(), Some(&k.c.public.device_id));
    // Without B in the chain, the registration is not anchored.
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            ac,
            &[recovery_link(bc, pk, reg, cc, sig)],
            &[],
            &[]
        )
        .unwrap_err(),
        CoreError::TrustChainInvalid
    );
    // Claiming A registered it (the signature is B's) fails.
    assert_eq!(
        verify_lineage(
            x,
            &acct(),
            ac,
            &[recovery_link(ac, pk, reg, cc, sig)],
            &[],
            &[]
        )
        .unwrap_err(),
        CoreError::TrustChainInvalid
    );
}

// ------------------------------------------------- wire format + vectors

fn vector() -> &'static str {
    include_str!("../../../../functions/test/vectors/device_trust_v2.json")
}

fn field(name: &str) -> String {
    let json = vector();
    let key = format!("\"{name}\": \"");
    let start = json.find(&key).unwrap_or_else(|| panic!("missing {name}")) + key.len();
    let end = start + json[start..].find('"').unwrap();
    json[start..end].to_owned()
}

fn hex(name: &str) -> Vec<u8> {
    let s = field(name);
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

#[test]
fn server_generated_v2_vectors_verify_in_rust() {
    let p = OpenMlsRustCrypto::default();
    let x = p.crypto();
    let account = AccountId::new(&field("accountId")).unwrap();
    let exp: u64 = field("expiresAtUnix").parse().unwrap();
    let (a, b, c) = (hex("certAHex"), hex("certBHex"), hex("certCHex"));
    assert_eq!(
        revocation_payload(&account, &a, &b, RevocationReason::Stolen, &[0x74; 32], exp).unwrap(),
        hex("revocationPayloadHex")
    );
    verify_revocation(
        x,
        &account,
        &a,
        &b,
        RevocationReason::Stolen,
        &[0x74; 32],
        exp,
        &hex("revocationSignatureHex"),
    )
    .unwrap();
    assert_eq!(
        reset_cancel_payload(&account, &c, &[0x75; 32], exp).unwrap(),
        hex("resetCancelPayloadHex")
    );
    verify_reset_cancel(
        x,
        &account,
        &c,
        &[0x75; 32],
        exp,
        &hex("resetCancelSignatureHex"),
    )
    .unwrap();
    // The full encoded lineage: A, C trusted (B revoked).
    assert_eq!(
        sirf_hum_crypto::lineage::verify_encoded(x, &hex("lineageBlobHex")).unwrap(),
        hex("lineageResultHex")
    );
}

#[test]
fn malformed_lineage_blobs_fail_closed() {
    let p = OpenMlsRustCrypto::default();
    let x = p.crypto();
    let blob = hex("lineageBlobHex");
    // Truncated at every length, and with trailing bytes.
    for len in [0, 1, 5, blob.len() / 2, blob.len() - 1] {
        assert_eq!(
            sirf_hum_crypto::lineage::verify_encoded(x, &blob[..len]).unwrap_err(),
            CoreError::TrustChainInvalid,
            "truncated to {len}"
        );
    }
    let mut extended = blob.clone();
    extended.push(0);
    assert_eq!(
        sirf_hum_crypto::lineage::verify_encoded(x, &extended).unwrap_err(),
        CoreError::TrustChainInvalid
    );
    let mut wrong_version = blob.clone();
    wrong_version[0] = 2;
    assert_eq!(
        sirf_hum_crypto::lineage::verify_encoded(x, &wrong_version).unwrap_err(),
        CoreError::TrustChainInvalid
    );
    assert_eq!(
        sirf_hum_crypto::lineage::verify_encoded(x, &vec![1u8; MAX_LINEAGE_BYTES + 1]).unwrap_err(),
        CoreError::InputTooLarge
    );
    // Any single flipped byte is rejected (or changes nothing verifiable).
    for i in (0..blob.len()).step_by(7) {
        let mut b = blob.clone();
        b[i] ^= 0x01;
        assert!(
            sirf_hum_crypto::lineage::verify_encoded(x, &b)
                .map(|r| r != hex("lineageResultHex"))
                .unwrap_or(true),
            "byte {i} produced the same trusted set"
        );
    }
}
