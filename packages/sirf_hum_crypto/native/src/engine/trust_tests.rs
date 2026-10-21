//! D-085 adversarial tests: the trust unit is the exact device certificate.
//! In-crate so a test can act as a revoked device that still holds its PIK
//! (forge certificates, build KeyPackages with them). TEST key stores only.

use std::sync::{Arc, Mutex};

use super::*;
use crate::identity::{device_approval_payload, RevocationReason};
use crate::keystore::EphemeralTestKeyStore;
use crate::store::MemoryStore;

const CH: [u8; 32] = [3u8; 32];
const EXP: u64 = 1_900_000_000;

fn device(account: &str) -> CryptoCore {
    let mut c = CryptoCore::open(
        Box::new(MemoryStore::default()),
        &EphemeralTestKeyStore::new(),
    )
    .unwrap();
    c.create_identity(AccountId::new(account).unwrap()).unwrap();
    c
}

fn cert(c: &CryptoCore) -> Vec<u8> {
    c.public_identity().unwrap().certificate
}

fn pik(c: &CryptoCore) -> PersonKey {
    c.public_identity().unwrap().person_key
}

fn id(c: &CryptoCore) -> DeviceId {
    c.public_identity().unwrap().device_id
}

fn put_bytes(out: &mut Vec<u8>, b: &[u8]) {
    out.extend_from_slice(&(b.len() as u32).to_be_bytes());
    out.extend_from_slice(b);
}

struct Link {
    approver: Vec<u8>,
    new: Vec<u8>,
    expires: u64,
    sig: Vec<u8>,
}

struct Rev {
    revoker: Vec<u8>,
    revoked: Vec<u8>,
    sig: Vec<u8>,
}

/// lineage.rs wire format.
fn blob(account: &str, root: &[u8], links: &[&Link], revs: &[&Rev]) -> Vec<u8> {
    let mut out = vec![1u8];
    put_bytes(&mut out, account.as_bytes());
    put_bytes(&mut out, root);
    out.extend_from_slice(&(links.len() as u32).to_be_bytes());
    for l in links {
        out.extend_from_slice(&[1, 1]);
        put_bytes(&mut out, &l.approver);
        put_bytes(&mut out, &l.new);
        put_bytes(&mut out, &CH);
        out.extend_from_slice(&l.expires.to_be_bytes());
        put_bytes(&mut out, &l.sig);
    }
    out.extend_from_slice(&(revs.len() as u32).to_be_bytes());
    for r in revs {
        out.push(1);
        put_bytes(&mut out, &r.revoker);
        put_bytes(&mut out, &r.revoked);
        out.push(RevocationReason::Compromised as u8);
        put_bytes(&mut out, &CH);
        out.extend_from_slice(&EXP.to_be_bytes());
        put_bytes(&mut out, &r.sig);
    }
    out.extend_from_slice(&0u32.to_be_bytes());
    out
}

fn approve(approver: &mut CryptoCore, new: &CryptoCore) -> Link {
    Link {
        approver: cert(approver),
        new: cert(new),
        expires: EXP,
        sig: approver.approve_device(&cert(new), &CH, EXP).unwrap(),
    }
}

fn revoke(revoker: &CryptoCore, revoked: &CryptoCore) -> Rev {
    Rev {
        revoker: cert(revoker),
        revoked: cert(revoked),
        sig: revoker
            .sign_revocation(&cert(revoked), RevocationReason::Compromised, &CH, EXP)
            .unwrap(),
    }
}

/// Runs the MLS credential check exactly as an Add/Welcome/sender check
/// would, against a KeyPackage.
fn check(c: &mut CryptoCore, key_package: &[u8]) -> CoreResult<DeviceId> {
    let MlsMessageBodyIn::KeyPackage(kp) = parse(key_package)?.extract() else {
        return Err(CoreError::MalformedMessage);
    };
    let State {
        provider, trust, ..
    } = &mut c.state;
    let kp = kp
        .validate(provider.crypto(), ProtocolVersion::Mls10)
        .map_err(|_| CoreError::InvalidCredential)?;
    let leaf = kp.leaf_node();
    trust
        .validate(
            provider.crypto(),
            leaf.credential(),
            leaf.signature_key().as_slice(),
        )
        .map(|v| v.device_id)
}

/// A KeyPackage for an arbitrary (possibly forged) certificate, signed by a
/// fresh device key whose public half is `device_public`.
fn key_package_with(certificate: &DeviceCertificate, signer: &SignatureKeyPair) -> Vec<u8> {
    let provider = OpenMlsRustCrypto::default();
    let bundle = KeyPackage::builder()
        .build(
            CIPHERSUITE,
            &provider,
            signer,
            CredentialWithKey {
                credential: certificate.to_credential(),
                signature_key: signer.public().to_vec().into(),
            },
        )
        .unwrap();
    ser(&MlsMessageOut::from(bundle.key_package().clone())).unwrap()
}

/// What a device holding `holder`'s PIK can certify: any device ID, any key.
fn forge(holder: &CryptoCore, device_id: DeviceId) -> (DeviceCertificate, SignatureKeyPair) {
    let signer = SignatureKeyPair::new(SignatureScheme::ED25519).unwrap();
    let id = holder.identity.as_ref().unwrap();
    let cert = DeviceCertificate::issue(
        holder.state.provider.crypto(),
        id.person_key.clone(),
        &id.person_private,
        device_id,
        signer.public().to_vec(),
        1_800_000_000,
    )
    .unwrap();
    (cert, signer)
}

/// Person A: a1 (root) approved a2. Person B: b1 anchors a1's PIK and
/// verifies A's lineage.
struct World {
    a1: CryptoCore,
    a2: CryptoCore,
    b1: CryptoCore,
    a1_a2: Link,
}

fn world() -> World {
    let mut a1 = device("accountA");
    let a2 = device("accountA");
    let mut b1 = device("accountB");
    let a1_a2 = approve(&mut a1, &a2);
    b1.trust_verified_person_key(pik(&a1)).unwrap();
    b1.trust_lineage(&blob("accountA", &cert(&a1), &[&a1_a2], &[]), 3)
        .unwrap();
    World { a1, a2, b1, a1_a2 }
}

// 1
#[test]
fn a_device_proven_by_lineage_is_trusted_for_its_account() {
    let mut w = world();
    let kp = w.a2.key_package().unwrap();
    assert_eq!(check(&mut w.b1, &kp).unwrap(), id(&w.a2));
    assert_eq!(
        w.b1.device_account(&id(&w.a2)).unwrap().as_deref(),
        Some("accountA")
    );
    let kp = w.a1.key_package().unwrap();
    assert_eq!(check(&mut w.b1, &kp).unwrap(), id(&w.a1));
}

// 2
#[test]
fn a_revoked_device_cannot_approve_a_new_trusted_device() {
    let mut w = world();
    let rev = revoke(&w.a1, &w.a2);
    w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[&rev]), 4)
        .unwrap();
    // A2 still holds its PIK and signs an approval of A3. The server refuses
    // it (approver not active), so an honest lineage never carries it.
    let a3 = device("accountA");
    let _sig = w.a2.approve_device(&cert(&a3), &CH, EXP).unwrap();
    let kp = {
        let mut a3 = a3;
        a3.key_package().unwrap()
    };
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    let kp = w.a2.key_package().unwrap();
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

// 3
#[test]
fn a_revoked_device_cannot_mint_a_new_device_id_with_its_old_pik() {
    let mut w = world();
    // b2 saw the lineage *before* the revocation: the pin alone stops it.
    let mut b2 = device("accountB");
    b2.trust_verified_person_key(pik(&w.a1)).unwrap();
    b2.trust_lineage(&blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[]), 3)
        .unwrap();
    let rev = revoke(&w.a1, &w.a2);
    w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[&rev]), 4)
        .unwrap();
    let (fresh, signer) = forge(&w.a2, DeviceId([0x42; 16]));
    let kp = key_package_with(&fresh, &signer);
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice,
        "revoked PIK"
    );
    assert_eq!(
        check(&mut b2, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice,
        "PIK pinned to A2"
    );
    // The same forged certificate inside a lineage link (a colluding server
    // presenting A1's approval of it would need A1's signature; with A2 as
    // approver after revocation it is refused as above).
    assert!(w.b1.state.trust.revoked_people.contains(&pik(&w.a2)));
}

// 4
#[test]
fn a_revoked_device_cannot_reuse_its_old_certificate() {
    let mut w = world();
    let rev = revoke(&w.a1, &w.a2);
    w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[&rev]), 4)
        .unwrap();
    let kp = w.a2.key_package().unwrap();
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // Even a later lineage that "forgets" the revocation cannot undo it.
    w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[]), 5)
        .unwrap();
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

// 5
#[test]
fn a_forged_certificate_claiming_another_pik_fails_its_signature() {
    let mut w = world();
    let (mut forged, signer) = forge(&w.a2, DeviceId([0x55; 16]));
    forged.person_key = pik(&w.a1);
    let kp = key_package_with(&forged, &signer);
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::InvalidCredential
    );
}

// 6
#[test]
fn stale_lineage_and_stale_approvals_are_refused() {
    let mut w = world();
    let rev = revoke(&w.a1, &w.a2);
    let with_rev = blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[&rev]);
    w.b1.trust_lineage(&with_rev, 4).unwrap();
    // An older server view (epoch 3) is refused and changes nothing.
    let without = blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[]);
    assert_eq!(
        w.b1.trust_lineage(&without, 3).unwrap_err(),
        CoreError::TrustStateStale
    );
    // An approval that expired before the approved certificate was issued
    // was made for another device generation.
    let mut b2 = device("accountB");
    b2.trust_verified_person_key(pik(&w.a1)).unwrap();
    let a3 = device("accountA");
    let sig = w.a1.approve_device(&cert(&a3), &CH, 1_000).unwrap();
    let stale = Link {
        approver: cert(&w.a1),
        new: cert(&a3),
        expires: 1_000,
        sig,
    };
    assert_eq!(
        b2.trust_lineage(&blob("accountA", &cert(&w.a1), &[&stale], &[]), 1)
            .unwrap_err(),
        CoreError::TrustChainInvalid
    );
}

// 7
#[test]
fn a_valid_approval_by_a_device_outside_the_chain_is_refused() {
    let mut w = world();
    let mut outsider = device("accountA");
    let a3 = device("accountA");
    let link = approve(&mut outsider, &a3);
    assert_eq!(
        w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[&w.a1_a2, &link], &[]), 5)
            .unwrap_err(),
        CoreError::TrustChainInvalid
    );
    // Valid statement, wrong account: B's own device approving into A's chain.
    let mut b9 = device("accountB");
    let a4 = device("accountA");
    let cross = approve(&mut b9, &a4);
    assert_eq!(
        w.b1.trust_lineage(&blob("accountA", &cert(&b9), &[&cross], &[]), 5)
            .unwrap_err(),
        CoreError::TrustChainInvalid,
        "the statement is bound to account B"
    );
    // A chain whose root is not anchored is refused even when it verifies.
    let mut c1 = device("accountC");
    let c2 = device("accountC");
    let c_link = approve(&mut c1, &c2);
    assert_eq!(
        w.b1.trust_lineage(&blob("accountC", &cert(&c1), &[&c_link], &[]), 1)
            .unwrap_err(),
        CoreError::UnauthorizedDevice,
        "root not anchored"
    );
    // Failed applications changed nothing: A2 is still trusted.
    let kp = w.a2.key_package().unwrap();
    assert!(check(&mut w.b1, &kp).is_ok());
}

// 8
#[test]
fn an_anchored_pik_certifies_only_its_one_device() {
    let mut w = world();
    let (other_id, signer) = forge(&w.a1, DeviceId([0x88; 16]));
    let kp = key_package_with(&other_id, &signer);
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // A device that only anchored A1 (v4 path) pins A1 on first sight and
    // then refuses any second device ID under the same PIK.
    let mut b2 = device("accountB");
    b2.trust_verified_person_key(pik(&w.a1)).unwrap();
    let real = w.a1.key_package().unwrap();
    assert_eq!(check(&mut b2, &real).unwrap(), id(&w.a1));
    assert_eq!(
        check(&mut b2, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

// 9
#[test]
fn a_trusted_device_id_under_another_pik_is_refused() {
    let mut w = world();
    let attacker = device("accountA");
    let (stolen_id, signer) = forge(&attacker, id(&w.a2));
    let kp = key_package_with(&stolen_id, &signer);
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // Same device ID and PIK, but a different device key: different bytes.
    let (rekeyed, signer) = forge(&w.a2, id(&w.a2));
    let kp = key_package_with(&rekeyed, &signer);
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

// 10
#[test]
fn a_valid_certificate_with_an_invalid_lineage_is_not_trusted() {
    let mut a1 = device("accountA");
    let mut a2 = device("accountA");
    let mut b1 = device("accountB");
    b1.trust_verified_person_key(pik(&a1)).unwrap();
    let mut link = approve(&mut a1, &a2);
    link.sig[0] ^= 1;
    assert_eq!(
        b1.trust_lineage(&blob("accountA", &cert(&a1), &[&link], &[]), 2)
            .unwrap_err(),
        CoreError::TrustChainInvalid
    );
    let kp = a2.key_package().unwrap();
    assert_eq!(
        check(&mut b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

/// Review finding (Prompt 10 Part 2): a root-only lineage verifies without
/// proving its account, so a server could present a trusted device under
/// the other account's label. The first binding is permanent.
#[test]
fn a_device_is_never_relabelled_to_another_account() {
    let mut w = world();
    // A1 (anchored root of A) presented as the root of "accountB".
    assert_eq!(
        w.b1.trust_lineage(&blob("accountB", &cert(&w.a1), &[], &[]), 9)
            .unwrap_err(),
        CoreError::TrustChainInvalid
    );
    assert_eq!(
        w.b1.device_account(&id(&w.a1)).unwrap().as_deref(),
        Some("accountA")
    );
    // Omitted from A's lineage first, then offered under B's label: still A.
    w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[], &[]), 4)
        .unwrap();
    assert_eq!(
        w.b1.trust_lineage(&blob("accountB", &cert(&w.a1), &[], &[]), 9)
            .unwrap_err(),
        CoreError::TrustChainInvalid
    );
    let a2 = w.a2.key_package().unwrap();
    assert_eq!(
        check(&mut w.b1, &a2).unwrap_err(),
        CoreError::UnauthorizedDevice,
        "A2 was dropped by the omission, never re-labelled"
    );
}

#[test]
fn server_omission_drops_trust_but_never_adds_it() {
    let mut w = world();
    w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[], &[]), 4)
        .unwrap();
    let kp = w.a2.key_package().unwrap();
    assert_eq!(
        check(&mut w.b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // Not revoked: a later complete lineage restores it.
    w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[&w.a1_a2], &[]), 5)
        .unwrap();
    assert!(check(&mut w.b1, &kp).is_ok());
}

#[test]
fn approval_trusts_the_exact_certificate_not_the_pik() {
    let mut a1 = device("accountA");
    let a2 = device("accountA");
    approve(&mut a1, &a2);
    assert!(!a1.state.trust.anchors.contains(&pik(&a2)));
    let (sibling, signer) = forge(&a2, DeviceId([0x99; 16]));
    let kp = key_package_with(&sibling, &signer);
    assert_eq!(
        check(&mut a1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // A revoked PIK cannot become an anchor again.
    a1.revoke_device(id(&a2)).unwrap();
    assert_eq!(
        a1.trust_verified_person_key(pik(&a2)).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    assert_eq!(
        a1.approve_device(&cert(&a2), &CH, EXP).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

/// The accepted D-084 limit, kept honest: peers trust the server's ordering
/// of statements. A colluding server that presents a link signed by a
/// device *before* listing its revocation gets that link accepted ("no
/// cascade", D-080); the server itself refuses such approvals at
/// submission (approver must be active).
#[test]
fn documented_limit_peers_rely_on_server_ordering_for_revoked_approvers() {
    let mut w = world();
    let mut a3 = device("accountA");
    let a2_a3 = approve(&mut w.a2, &a3);
    let rev = revoke(&w.a1, &w.a2);
    w.b1.trust_lineage(
        &blob("accountA", &cert(&w.a1), &[&w.a1_a2, &a2_a3], &[&rev]),
        6,
    )
    .unwrap();
    let kp = a3.key_package().unwrap();
    assert!(check(&mut w.b1, &kp).is_ok());
}

#[test]
fn approval_payload_binds_the_account() {
    let w = world();
    let p1 = device_approval_payload(
        &AccountId::new("accountA").unwrap(),
        &cert(&w.a1),
        &cert(&w.a2),
        &CH,
        EXP,
    )
    .unwrap();
    let p2 = device_approval_payload(
        &AccountId::new("accountB").unwrap(),
        &cert(&w.a1),
        &cert(&w.a2),
        &CH,
        EXP,
    )
    .unwrap();
    assert_ne!(p1, p2);
}

// ------------------------------------------------- persistence of D-085

#[derive(Clone, Default)]
struct SharedStore(Arc<Mutex<MemoryStore>>);

impl CryptoStore for SharedStore {
    fn put(&mut self, name: &str, record: &[u8]) -> CoreResult<()> {
        self.0.lock().unwrap().put(name, record)
    }
    fn get(&self, name: &str) -> CoreResult<Option<Vec<u8>>> {
        self.0.lock().unwrap().get(name)
    }
    fn delete(&mut self, name: &str) -> CoreResult<()> {
        self.0.lock().unwrap().delete(name)
    }
    fn exists(&self, name: &str) -> CoreResult<bool> {
        self.0.lock().unwrap().exists(name)
    }
    fn wipe_all(&mut self) -> CoreResult<()> {
        self.0.lock().unwrap().wipe_all()
    }
    fn list(&self, prefix: &str) -> CoreResult<Vec<String>> {
        self.0.lock().unwrap().list(prefix)
    }
}

#[test]
fn trust_policy_survives_restart_exactly() {
    let store = SharedStore::default();
    let keys = EphemeralTestKeyStore::new();
    let mut b1 = CryptoCore::open(Box::new(store.clone()), &keys).unwrap();
    b1.create_identity(AccountId::new("accountB").unwrap())
        .unwrap();
    let mut a1 = device("accountA");
    let mut a2 = device("accountA");
    let link = approve(&mut a1, &a2);
    b1.trust_verified_person_key(pik(&a1)).unwrap();
    let rev = revoke(&a1, &a2);
    b1.trust_lineage(&blob("accountA", &cert(&a1), &[&link], &[&rev]), 9)
        .unwrap();
    let before = b1.state.trust.clone();
    drop(b1);
    let mut b1 = CryptoCore::open(Box::new(store), &keys).unwrap();
    assert!(b1.state.trust == before);
    let kp = a2.key_package().unwrap();
    assert_eq!(
        check(&mut b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    assert_eq!(
        b1.trust_lineage(&blob("accountA", &cert(&a1), &[&link], &[]), 8)
            .unwrap_err(),
        CoreError::TrustStateStale
    );
}

// ------------------------------------------------------ Prompt 17 review

/// D-122: A1 revokes A2, but A3 (approved by A1 earlier) has not refreshed
/// lineage, so its own `approve_device` guard does not know. A2's holder
/// certifies a fresh device ID with A2's retained PIK and A3 approves it.
/// Before D-122 the chain verified, the static verifier listed the new
/// device as proven, and only `apply_lineage` skipped it (and it could then
/// approve others). One PIK may certify one device: the chain is invalid.
#[test]
fn a_revoked_pik_cannot_return_through_an_unaware_approver() {
    let mut w = world();
    let mut a3 = device("accountA");
    let a1_a3 = approve(&mut w.a1, &a3);
    let rev = revoke(&w.a1, &w.a2);
    let (reborn, _) = forge(&w.a2, DeviceId([0x5a; 16]));
    let reborn = reborn.encode();
    let a3_reborn = Link {
        approver: cert(&a3),
        new: reborn.clone(),
        expires: EXP,
        sig: a3.approve_device(&reborn, &CH, EXP).unwrap(),
    };
    let lineage = blob(
        "accountA",
        &cert(&w.a1),
        &[&w.a1_a2, &a1_a3, &a3_reborn],
        &[&rev],
    );
    assert_eq!(
        crate::lineage::verify_encoded(w.b1.state.provider.crypto(), &lineage).unwrap_err(),
        CoreError::TrustChainInvalid
    );
    assert_eq!(
        w.b1.trust_lineage(&lineage, 5).unwrap_err(),
        CoreError::TrustChainInvalid
    );
    // The root's PIK is no exception.
    let (twin, _) = forge(&w.a1, DeviceId([0x5b; 16]));
    let twin = twin.encode();
    let a3_twin = Link {
        approver: cert(&a3),
        new: twin.clone(),
        expires: EXP,
        sig: a3.approve_device(&twin, &CH, EXP).unwrap(),
    };
    assert_eq!(
        w.b1.trust_lineage(&blob("accountA", &cert(&w.a1), &[&a1_a3, &a3_twin], &[]), 5)
            .unwrap_err(),
        CoreError::TrustChainInvalid
    );
    // A refused lineage changes nothing: the last good one still holds.
    let kp = w.a2.key_package().unwrap();
    assert!(check(&mut w.b1, &kp).is_ok());
}

/// D-079, documented limit (Prompt 17): an older copy of the whole state
/// is NOT detected. The restored files forget a revocation and the newer
/// trust epoch, so stale server views are accepted again, until the next
/// refresh with the server's current lineage re-learns the revocation. If
/// this test starts failing because the restore IS detected, update D-079.
#[test]
fn documented_limit_a_restored_older_state_is_not_detected_until_refreshed() {
    let store = SharedStore::default();
    let keys = EphemeralTestKeyStore::new();
    let mut b1 = CryptoCore::open(Box::new(store.clone()), &keys).unwrap();
    b1.create_identity(AccountId::new("accountB").unwrap())
        .unwrap();
    let mut a1 = device("accountA");
    let mut a2 = device("accountA");
    let link = approve(&mut a1, &a2);
    b1.trust_verified_person_key(pik(&a1)).unwrap();
    b1.trust_lineage(&blob("accountA", &cert(&a1), &[&link], &[]), 3)
        .unwrap();
    b1.observe_trust_epoch(3).unwrap();
    let snapshot: Vec<(String, Vec<u8>)> = store
        .list("")
        .unwrap()
        .into_iter()
        .map(|name| {
            let record = store.get(&name).unwrap().unwrap();
            (name, record)
        })
        .collect();

    let rev = revoke(&a1, &a2);
    let current = blob("accountA", &cert(&a1), &[&link], &[&rev]);
    b1.trust_lineage(&current, 4).unwrap();
    b1.observe_trust_epoch(4).unwrap();
    let kp = a2.key_package().unwrap();
    assert_eq!(
        check(&mut b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    drop(b1);

    // Someone with write access to the app's files puts the old copy back
    // (same device: the store key is unchanged).
    let mut files = store.clone();
    files.wipe_all().unwrap();
    for (name, record) in &snapshot {
        files.put(name, record).unwrap();
    }
    let mut b1 = CryptoCore::open(Box::new(store), &keys).unwrap();
    assert!(check(&mut b1, &kp).is_ok(), "revocation forgotten");
    assert_eq!(b1.observe_trust_epoch(3).unwrap(), 3, "floor rolled back");
    b1.trust_lineage(&blob("accountA", &cert(&a1), &[&link], &[]), 3)
        .unwrap();
    // What bounds it: the server's current lineage re-learns the
    // revocation, permanently.
    b1.trust_lineage(&current, 4).unwrap();
    assert_eq!(
        check(&mut b1, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

#[test]
fn version_1_state_loads_with_person_keys_as_anchors() {
    let store = SharedStore::default();
    let keys = EphemeralTestKeyStore::new();
    let partner = device("accountB");
    {
        let mut core = CryptoCore::open(Box::new(store.clone()), &keys).unwrap();
        core.create_identity(AccountId::new("accountA").unwrap())
            .unwrap();
        // Overwrite the state record with a v1 encoding (Prompt 06–09):
        // empty storage map, no groups, trusted person keys, one revoked ID.
        let mut v1 = Vec::new();
        v1.extend_from_slice(&1u16.to_be_bytes());
        v1.extend_from_slice(&0u32.to_be_bytes());
        v1.extend_from_slice(&0u32.to_be_bytes());
        v1.extend_from_slice(&1u32.to_be_bytes());
        put_bytes(&mut v1, &pik(&partner).0);
        v1.extend_from_slice(&1u32.to_be_bytes());
        v1.extend_from_slice(&[0xee; 16]);
        let sealed = record::seal(&core.kek, RecordKind::MlsState, REC_STATE, &v1).unwrap();
        core.store.put(REC_STATE, &sealed).unwrap();
    }
    let core = CryptoCore::open(Box::new(store), &keys).unwrap();
    let t = &core.state.trust;
    assert!(t.anchors.contains(&pik(&partner)));
    assert!(t.revoked_devices.contains(&DeviceId([0xee; 16])));
    assert!(t.devices.contains_key(&id(&core)), "own device re-trusted");
    assert!(
        !t.devices.contains_key(&id(&partner)),
        "anchors are not devices"
    );
}
