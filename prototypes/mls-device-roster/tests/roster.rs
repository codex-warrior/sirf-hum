//! EXPERIMENTAL SPIKE TESTS. These probe OpenMLS behaviour in the Sirf Hum
//! couple/device model. Cryptographic correctness itself is covered by
//! OpenMLS' own RFC 9420 test-vector and interop suites, not here.

use openmls::prelude::*;
use sirf_hum_mls_device_roster_spike::*;

// Runs the same tests natively and under wasm-bindgen-test (Node), as
// OpenMLS does in its own wasm32 CI.

struct Couple {
    alice_phone: Device,
    alice_laptop: Device,
    bob_phone: Device,
    g_alice_phone: MlsGroup,
    g_alice_laptop: MlsGroup,
    g_bob_phone: MlsGroup,
}

/// Alice's phone creates the couple group and adds her laptop and Bob's
/// phone in one commit (each added device is a separate MLS member).
fn couple() -> Couple {
    let alice_phone = Device::new("alice/phone");
    let alice_laptop = Device::new("alice/laptop");
    let bob_phone = Device::new("bob/phone");

    let mut g_alice_phone = alice_phone.create_group();
    let (_commit, welcome, _info) = g_alice_phone
        .add_members(
            &alice_phone.provider,
            &alice_phone.signer,
            &[alice_laptop.key_package(), bob_phone.key_package()],
        )
        .expect("add devices");
    g_alice_phone
        .merge_pending_commit(&alice_phone.provider)
        .expect("merge add");

    let g_alice_laptop = alice_laptop.join(&welcome);
    let g_bob_phone = bob_phone.join(&welcome);
    Couple { alice_phone, alice_laptop, bob_phone, g_alice_phone, g_alice_laptop, g_bob_phone }
}

fn send(device: &Device, group: &mut MlsGroup, text: &[u8]) -> Vec<u8> {
    transport(
        &group
            .create_message(&device.provider, &device.signer, text)
            .expect("encrypt"),
    )
}

fn open(device: &Device, group: &mut MlsGroup, bytes: &[u8]) -> Result<Vec<u8>, String> {
    let processed = group
        .process_message(&device.provider, receive(bytes)?)
        .map_err(|e| format!("{e:?}"))?;
    match processed.into_content() {
        ProcessedMessageContent::ApplicationMessage(m) => Ok(m.into_bytes()),
        other => Err(format!("unexpected content: {other:?}")),
    }
}

fn apply_commit(device: &Device, group: &mut MlsGroup, bytes: &[u8]) {
    let processed = group
        .process_message(&device.provider, receive(bytes).expect("parse commit"))
        .expect("process commit");
    match processed.into_content() {
        ProcessedMessageContent::StagedCommitMessage(staged) => group
            .merge_staged_commit(&device.provider, *staged)
            .expect("merge commit"),
        other => panic!("expected commit, got {other:?}"),
    }
}

#[cfg_attr(not(target_arch = "wasm32"), test)]
#[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
fn every_device_converges_on_the_same_authenticated_roster() {
    let c = couple();
    let expected = vec!["alice/laptop", "alice/phone", "bob/phone"];
    assert_eq!(roster(&c.g_alice_phone), expected);
    assert_eq!(roster(&c.g_alice_laptop), expected);
    assert_eq!(roster(&c.g_bob_phone), expected);
    // Same epoch authenticator = same view of group state, including roster.
    let auth = c.g_alice_phone.epoch_authenticator().as_slice().to_vec();
    assert_eq!(c.g_alice_laptop.epoch_authenticator().as_slice(), auth);
    assert_eq!(c.g_bob_phone.epoch_authenticator().as_slice(), auth);
}

#[cfg_attr(not(target_arch = "wasm32"), test)]
#[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
fn a_message_reaches_every_device_and_names_its_sender_device() {
    let mut c = couple();
    let bytes = send(&c.bob_phone, &mut c.g_bob_phone, b"hello");

    let processed = c
        .g_alice_laptop
        .process_message(&c.alice_laptop.provider, receive(&bytes).unwrap())
        .unwrap();
    assert_eq!(processed.credential().serialized_content(), b"bob/phone");
    assert_eq!(open(&c.alice_phone, &mut c.g_alice_phone, &bytes).unwrap(), b"hello");
}

#[cfg_attr(not(target_arch = "wasm32"), test)]
#[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
fn a_removed_device_cannot_read_messages_sent_after_its_removal() {
    let mut c = couple();
    let laptop = leaf_of(&c.g_alice_phone, "alice/laptop");
    let (commit, _welcome, _info) = c
        .g_alice_phone
        .remove_members(&c.alice_phone.provider, &c.alice_phone.signer, &[laptop])
        .expect("remove laptop");
    c.g_alice_phone
        .merge_pending_commit(&c.alice_phone.provider)
        .unwrap();
    let commit = transport(&commit);
    apply_commit(&c.bob_phone, &mut c.g_bob_phone, &commit);
    assert_eq!(roster(&c.g_bob_phone), vec!["alice/phone", "bob/phone"]);

    let after = send(&c.bob_phone, &mut c.g_bob_phone, b"after removal");
    assert_eq!(
        open(&c.alice_phone, &mut c.g_alice_phone, &after).unwrap(),
        b"after removal"
    );

    // Case 1: the removed laptop was offline and never saw its removal.
    assert!(open(&c.alice_laptop, &mut c.g_alice_laptop, &after).is_err());

    // Case 2: it then processes the commit that removes it.
    apply_commit(&c.alice_laptop, &mut c.g_alice_laptop, &commit);
    assert!(!c.g_alice_laptop.is_active());
    assert!(open(&c.alice_laptop, &mut c.g_alice_laptop, &after).is_err());
}

#[cfg_attr(not(target_arch = "wasm32"), test)]
#[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
fn a_replayed_message_is_rejected() {
    let mut c = couple();
    let bytes = send(&c.bob_phone, &mut c.g_bob_phone, b"once");
    assert_eq!(open(&c.alice_phone, &mut c.g_alice_phone, &bytes).unwrap(), b"once");
    assert!(
        open(&c.alice_phone, &mut c.g_alice_phone, &bytes).is_err(),
        "the same ciphertext must not be accepted twice"
    );
}

#[cfg_attr(not(target_arch = "wasm32"), test)]
#[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
fn a_tampered_ciphertext_is_rejected() {
    let mut c = couple();
    let mut bytes = send(&c.bob_phone, &mut c.g_bob_phone, b"integrity");
    let last = bytes.len() - 1;
    bytes[last] ^= 0x01; // inside the AEAD ciphertext/tag
    assert!(open(&c.alice_phone, &mut c.g_alice_phone, &bytes).is_err());
}

#[cfg_attr(not(target_arch = "wasm32"), test)]
#[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
fn a_device_outside_the_group_cannot_read_group_messages() {
    let mut c = couple();
    let stranger = Device::new("mallory/phone");
    let mut g_stranger = stranger.create_group();
    let bytes = send(&c.bob_phone, &mut c.g_bob_phone, b"private");
    assert!(open(&stranger, &mut g_stranger, &bytes).is_err());
}
