//! Crypto-core test matrix (Prompt 06 Part 11). Uses insecure TEST key stores.

mod common;

use std::fs;

use common::*;
use sirf_hum_crypto::identity::{AccountId, DeviceId, PersonKey};
use sirf_hum_crypto::keystore::EphemeralTestKeyStore;
use sirf_hum_crypto::limits::*;
use sirf_hum_crypto::{CoreError, CryptoCore, Incoming};

// ------------------------------------------------------------------ identity

#[test]
fn identity_is_created_and_reloaded_after_restart() {
    let mut alice = Device::new("account-a");
    let before = alice.core.public_identity().unwrap();
    alice.restart();
    assert_eq!(alice.core.public_identity().unwrap(), before);
}

#[test]
fn identity_cannot_be_created_twice_or_used_before_creation() {
    let mut alice = Device::new("account-a");
    assert_eq!(
        alice
            .core
            .create_identity(AccountId::new("x").unwrap())
            .unwrap_err(),
        CoreError::IdentityState
    );
    let tmp = tempfile::tempdir().unwrap();
    let mut empty = open_dir(tmp.path()).unwrap();
    assert_eq!(
        empty.public_identity().unwrap_err(),
        CoreError::IdentityState
    );
    assert_eq!(empty.key_package().unwrap_err(), CoreError::IdentityState);
}

#[test]
fn account_id_is_validated_and_is_not_a_device_identity() {
    assert_eq!(AccountId::new("").unwrap_err(), CoreError::InvalidInput);
    assert_eq!(
        AccountId::new(&"x".repeat(MAX_ACCOUNT_ID_BYTES + 1)).unwrap_err(),
        CoreError::InvalidInput
    );
    // Device identities are random and unrelated to the account string.
    let a = Device::new("same-account");
    let b = Device::new("same-account");
    assert_ne!(a.device_id(), b.device_id());
    assert_ne!(a.public.person_key, b.public.person_key);
}

#[test]
fn trusted_partner_credentials_are_accepted() {
    let (_alice, _bob, _gid) = couple();
}

#[test]
fn untrusted_person_key_is_rejected_when_adding() {
    let mut alice = Device::new("a");
    let mut mallory = Device::new("m");
    let gid = alice.core.create_group().unwrap();
    let kp = mallory.core.key_package().unwrap();
    assert_eq!(
        alice.core.add_member(&gid, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    assert_eq!(
        alice.core.epoch(&gid).unwrap(),
        0,
        "rejected add must not change state"
    );
}

#[test]
fn untrusted_member_in_welcome_is_rejected_before_joining() {
    let mut mallory = Device::new("m");
    let mut bob = Device::new("b");
    mallory.trust(&bob); // Mallory trusts Bob; Bob does NOT trust Mallory.
    let gid = mallory.core.create_group().unwrap();
    let added = mallory
        .core
        .add_member(&gid, &bob.core.key_package().unwrap())
        .unwrap();
    assert_eq!(
        bob.core.join(&added.welcome).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    assert!(bob.core.group_ids().is_empty());
}

#[test]
fn revoked_device_cannot_be_added_again() {
    let (mut alice, mut bob, gid) = couple();
    alice.core.remove_member(&gid, bob.device_id()).unwrap();
    alice.core.revoke_device(bob.device_id()).unwrap();
    let kp = bob.core.key_package().unwrap();
    assert_eq!(
        alice.core.add_member(&gid, &kp).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
}

#[test]
fn malformed_key_package_and_person_key_are_rejected() {
    let mut alice = Device::new("a");
    let gid = alice.core.create_group().unwrap();
    assert_eq!(
        alice
            .core
            .add_member(&gid, b"not a key package")
            .unwrap_err(),
        CoreError::MalformedMessage
    );
    assert_eq!(
        PersonKey::from_slice(&[1u8; 31]).unwrap_err(),
        CoreError::InvalidInput
    );
    assert_eq!(
        DeviceId::from_slice(&[1u8; 15]).unwrap_err(),
        CoreError::InvalidInput
    );
}

// --------------------------------------------------------------- persistence

#[test]
fn state_round_trips_through_restart_and_conversation_continues() {
    let (mut alice, mut bob, gid) = couple();
    let ct = alice.core.encrypt(&gid, b"before restart").unwrap();
    assert_eq!(bob.open(&ct).unwrap(), b"before restart");
    bob.restart();
    alice.restart();
    let ct = alice.core.encrypt(&gid, b"after restart").unwrap();
    assert_eq!(bob.open(&ct).unwrap(), b"after restart");
    let reply = bob.core.encrypt(&gid, b"reply").unwrap();
    assert_eq!(alice.open(&reply).unwrap(), b"reply");
}

#[test]
fn overwrite_replaces_previous_state() {
    let (mut alice, _bob, gid) = couple();
    let epoch = alice.core.epoch(&gid).unwrap();
    alice.core.self_update(&gid).unwrap();
    alice.restart();
    assert_eq!(alice.core.epoch(&gid).unwrap(), epoch + 1);
}

#[test]
fn failed_write_rolls_back_and_core_stays_usable() {
    let store = FaultyStore::new();
    let mut core =
        CryptoCore::open(Box::new(store.clone()), &EphemeralTestKeyStore::new()).unwrap();
    core.create_identity(AccountId::new("a").unwrap()).unwrap();
    let gid = core.create_group().unwrap();
    let epoch = core.epoch(&gid).unwrap();

    store.set_failing(true);
    assert_eq!(
        core.self_update(&gid).unwrap_err(),
        CoreError::PersistenceFailure
    );
    assert_eq!(
        core.epoch(&gid).unwrap(),
        epoch,
        "memory must not run ahead of disk"
    );
    assert_eq!(
        core.encrypt(&gid, b"x").unwrap_err(),
        CoreError::PersistenceFailure
    );

    store.set_failing(false);
    core.self_update(&gid).unwrap();
    assert_eq!(core.epoch(&gid).unwrap(), epoch + 1);
}

#[test]
fn corrupted_record_is_detected_on_open() {
    let alice = Device::new("a");
    let path = record_path(&alice.dir, "identity_secret");
    let mut bytes = fs::read(&path).unwrap();
    let last = bytes.len() - 1;
    bytes[last] ^= 1;
    fs::write(&path, bytes).unwrap();
    assert_eq!(open_dir(&alice.dir).err(), Some(CoreError::StateCorruption));
}

#[test]
fn unknown_record_version_fails_closed() {
    let alice = Device::new("a");
    let path = record_path(&alice.dir, "mls_state");
    let mut bytes = fs::read(&path).unwrap();
    bytes[5] = 99; // format version (u16 BE at offset 4..6)
    fs::write(&path, bytes).unwrap();
    assert_eq!(open_dir(&alice.dir).err(), Some(CoreError::StateCorruption));
}

#[test]
fn record_moved_to_another_name_is_rejected() {
    let alice = Device::new("a");
    let id = fs::read(record_path(&alice.dir, "identity_secret")).unwrap();
    fs::write(record_path(&alice.dir, "mls_state"), id).unwrap();
    assert_eq!(open_dir(&alice.dir).err(), Some(CoreError::StateCorruption));
}

#[test]
fn wrong_key_encryption_key_cannot_open_state() {
    let alice = Device::new("a");
    let other_keys = EphemeralTestKeyStore::new();
    let opened = CryptoCore::open(
        Box::new(sirf_hum_crypto::store::FileStore::open(&alice.dir).unwrap()),
        &other_keys,
    );
    assert_eq!(opened.err(), Some(CoreError::StateCorruption));
}

#[test]
fn wipe_deletes_everything() {
    let (mut alice, _bob, _gid) = couple();
    alice.core.wipe().unwrap();
    assert_eq!(
        alice.core.public_identity().unwrap_err(),
        CoreError::IdentityState
    );
    assert!(alice.core.group_ids().is_empty());
    assert!(!record_path(&alice.dir, "identity_secret").exists());
    assert!(!record_path(&alice.dir, "mls_state").exists());
    alice.restart();
    assert_eq!(
        alice.core.public_identity().unwrap_err(),
        CoreError::IdentityState
    );
}

// ------------------------------------------------------------------------ MLS

#[test]
fn group_add_commit_encrypt_decrypt() {
    let (mut alice, mut bob, gid) = couple();
    assert_eq!(alice.core.epoch(&gid).unwrap(), 1);
    assert_eq!(bob.core.epoch(&gid).unwrap(), 1);
    let roster = alice.core.roster(&gid).unwrap();
    assert_eq!(roster.len(), 2);
    assert_eq!(roster, bob.core.roster(&gid).unwrap());

    let ct = bob.core.encrypt(&gid, b"hello").unwrap();
    assert_eq!(alice.open(&ct).unwrap(), b"hello");

    let commit = bob.core.self_update(&gid).unwrap();
    assert!(matches!(
        alice.apply(&commit).unwrap(),
        Incoming::CommitApplied { epoch: 2 }
    ));
    let ct = alice.core.encrypt(&gid, b"after update").unwrap();
    assert_eq!(bob.open(&ct).unwrap(), b"after update");
}

#[test]
fn replay_is_rejected() {
    let (mut alice, mut bob, gid) = couple();
    let ct = bob.core.encrypt(&gid, b"once").unwrap();
    assert_eq!(alice.open(&ct).unwrap(), b"once");
    assert_eq!(alice.open(&ct).unwrap_err(), CoreError::Replay);
}

#[test]
fn tampering_anywhere_is_rejected() {
    let (mut alice, mut bob, gid) = couple();
    let ct = bob.core.encrypt(&gid, b"integrity").unwrap();
    for pos in (0..ct.len()).step_by(3).chain([ct.len() - 1]) {
        let mut forged = ct.clone();
        forged[pos] ^= 1;
        assert!(alice.open(&forged).is_err(), "byte {pos} accepted");
    }
    assert_eq!(alice.open(&ct).unwrap(), b"integrity");
}

#[test]
fn outsider_message_is_rejected() {
    let (mut alice, _bob, _gid) = couple();
    let mut mallory = Device::new("m");
    let mgid = mallory.core.create_group().unwrap();
    let ct = mallory.core.encrypt(&mgid, b"spam").unwrap();
    assert_eq!(alice.open(&ct).unwrap_err(), CoreError::UnknownGroup);
}

#[test]
fn late_message_from_previous_epoch_fails_closed() {
    let (mut alice, mut bob, gid) = couple();
    let late = bob.core.encrypt(&gid, b"epoch 1").unwrap();
    let update = bob.core.self_update(&gid).unwrap();
    alice.apply(&update).unwrap();
    assert_eq!(alice.open(&late).unwrap_err(), CoreError::StaleEpoch);
}

#[test]
fn removed_device_cannot_decrypt_new_epoch() {
    let (mut alice, mut bob, gid) = couple();
    let mut laptop = Device::new("account-alice-laptop");
    // Same person in reality; here a second trusted key for simplicity.
    alice.trust(&laptop);
    bob.trust(&laptop);
    laptop.trust(&alice);
    laptop.trust(&bob);
    let added = alice
        .core
        .add_member(&gid, &laptop.core.key_package().unwrap())
        .unwrap();
    bob.apply(&added.commit).unwrap();
    laptop.core.join(&added.welcome).unwrap();

    let before = bob.core.encrypt(&gid, b"before").unwrap();
    let kept = laptop.open(&before).unwrap();
    alice.open(&before).unwrap();

    let removal = alice.core.remove_member(&gid, laptop.device_id()).unwrap();
    bob.apply(&removal).unwrap();
    let after = bob.core.encrypt(&gid, b"after").unwrap();
    assert_eq!(alice.open(&after).unwrap(), b"after");

    // Offline (never saw its removal): cannot decrypt.
    assert!(laptop.open(&after).is_err());
    // Processes its removal: group deleted locally.
    assert!(matches!(
        laptop.apply(&removal).unwrap(),
        Incoming::RemovedFromGroup
    ));
    assert_eq!(laptop.open(&after).unwrap_err(), CoreError::UnknownGroup);
    // Documented limitation: plaintext decrypted before removal stays.
    assert_eq!(kept, b"before");
}

#[test]
fn restored_pre_removal_state_cannot_decrypt_new_epoch() {
    let (mut alice, mut bob, gid) = couple();
    // Copy Bob's on-disk state before he is removed.
    let saved = tempfile::tempdir().unwrap();
    for entry in fs::read_dir(&bob.dir).unwrap() {
        let e = entry.unwrap();
        fs::copy(e.path(), saved.path().join(e.file_name())).unwrap();
    }
    alice.core.remove_member(&gid, bob.device_id()).unwrap();
    let after = alice.core.encrypt(&gid, b"after removal").unwrap();

    let mut stale = open_dir(saved.path()).unwrap();
    assert!(stale.process_incoming(&after).is_err());
    assert!(bob.open(&after).is_err());
}

// ------------------------------------------------------------------ rollback

#[test]
fn forged_then_valid_message_still_decrypts() {
    let (mut alice, mut bob, gid) = couple();
    let ct = bob.core.encrypt(&gid, b"genuine").unwrap();
    // Every position that poisoned state in Prompt 05 (content ciphertext).
    for pos in (ct.len() / 2..ct.len()).step_by(3) {
        let mut forged = ct.clone();
        forged[pos] ^= 1;
        assert!(alice.open(&forged).is_err());
    }
    assert_eq!(
        alice.open(&ct).unwrap(),
        b"genuine",
        "rollback must preserve the genuine message"
    );
    assert_eq!(
        alice.open(&ct).unwrap_err(),
        CoreError::Replay,
        "replay protection kept"
    );
}

#[test]
fn malformed_then_valid_message_still_decrypts() {
    let (mut alice, mut bob, gid) = couple();
    let ct = bob.core.encrypt(&gid, b"genuine").unwrap();
    assert_eq!(
        alice.open(b"\x00\x01garbage").unwrap_err(),
        CoreError::MalformedMessage
    );
    assert_eq!(
        alice.open(&ct[..ct.len() / 2]).unwrap_err(),
        CoreError::MalformedMessage
    );
    assert_eq!(alice.open(&ct).unwrap(), b"genuine");
}

#[test]
fn malformed_input_cannot_corrupt_persistent_state() {
    let (mut alice, mut bob, gid) = couple();
    let ct = bob.core.encrypt(&gid, b"after junk").unwrap();
    let mut junk = ct.clone();
    let mid = junk.len() / 2;
    junk[mid] ^= 0xff;
    let _ = alice.open(&junk);
    let _ = alice.open(b"junk");
    alice.restart(); // state on disk must still be valid and unpoisoned
    assert_eq!(alice.open(&ct).unwrap(), b"after junk");
}

#[test]
fn persistence_failure_during_processing_rolls_back() {
    let store = FaultyStore::new();
    let mut alice_core =
        CryptoCore::open(Box::new(store.clone()), &EphemeralTestKeyStore::new()).unwrap();
    let alice_pub = alice_core
        .create_identity(AccountId::new("a").unwrap())
        .unwrap();
    let mut bob = Device::new("b");
    bob.core
        .trust_verified_person_key(alice_pub.person_key.clone())
        .unwrap();
    alice_core
        .trust_verified_person_key(bob.public.person_key.clone())
        .unwrap();
    let gid = alice_core.create_group().unwrap();
    let added = alice_core
        .add_member(&gid, &bob.core.key_package().unwrap())
        .unwrap();
    bob.core.join(&added.welcome).unwrap();

    let ct = bob.core.encrypt(&gid, b"retry me").unwrap();
    store.set_failing(true);
    assert_eq!(
        alice_core.process_incoming(&ct).err().unwrap(),
        CoreError::PersistenceFailure
    );
    store.set_failing(false);
    match alice_core.process_incoming(&ct).unwrap() {
        Incoming::Application(pt) => assert_eq!(pt.as_slice(), b"retry me"),
        _ => panic!("expected application message"),
    }
}

// --------------------------------------------------------------------- limits

#[test]
fn plaintext_limit_is_exact() {
    let (mut alice, mut bob, gid) = couple();
    let at_limit = vec![7u8; MAX_PLAINTEXT_BYTES];
    let ct = alice.core.encrypt(&gid, &at_limit).unwrap();
    assert!(
        ct.len() <= MAX_INCOMING_MESSAGE_BYTES,
        "a max plaintext must fit the incoming limit"
    );
    assert_eq!(bob.open(&ct).unwrap().len(), MAX_PLAINTEXT_BYTES);
    assert_eq!(
        alice
            .core
            .encrypt(&gid, &vec![7u8; MAX_PLAINTEXT_BYTES + 1])
            .unwrap_err(),
        CoreError::InputTooLarge
    );
}

#[test]
fn oversized_inputs_are_rejected_before_parsing() {
    let (mut alice, _bob, gid) = couple();
    let huge = vec![0u8; MAX_INCOMING_MESSAGE_BYTES + 1];
    assert_eq!(
        alice.core.process_incoming(&huge).err().unwrap(),
        CoreError::InputTooLarge
    );
    assert_eq!(
        alice
            .core
            .add_member(&gid, &vec![0u8; MAX_KEY_PACKAGE_BYTES + 1])
            .unwrap_err(),
        CoreError::InputTooLarge
    );
    assert_eq!(
        alice
            .core
            .join(&vec![0u8; MAX_WELCOME_BYTES + 1])
            .unwrap_err(),
        CoreError::InputTooLarge
    );
    // Exactly at the incoming limit is parsed (and rejected as malformed).
    let at_limit = vec![0u8; MAX_INCOMING_MESSAGE_BYTES];
    assert_eq!(
        alice.core.process_incoming(&at_limit).err().unwrap(),
        CoreError::MalformedMessage
    );
}

// --------------------------------------------------------------------- errors

#[test]
fn error_codes_are_stable_unique_and_safe() {
    let expected = [
        (CoreError::InvalidInput, -1, "invalid_input"),
        (CoreError::InputTooLarge, -2, "input_too_large"),
        (CoreError::InvalidCredential, -3, "invalid_credential"),
        (CoreError::UnauthorizedDevice, -4, "unauthorized_device"),
        (CoreError::MalformedMessage, -5, "malformed_message"),
        (
            CoreError::AuthenticationFailure,
            -6,
            "authentication_failure",
        ),
        (CoreError::Replay, -7, "replay"),
        (CoreError::StaleEpoch, -8, "stale_epoch"),
        (CoreError::UnknownGroup, -9, "unknown_group"),
        (CoreError::ProtocolViolation, -10, "protocol_violation"),
        (CoreError::StateCorruption, -11, "state_corruption"),
        (CoreError::PersistenceFailure, -12, "persistence_failure"),
        (CoreError::RollbackFailure, -13, "rollback_failure"),
        (CoreError::Unsupported, -14, "unsupported"),
        (
            CoreError::InternalCryptoFailure,
            -15,
            "internal_crypto_failure",
        ),
        (CoreError::IdentityState, -16, "identity_state"),
        (CoreError::Internal, -17, "internal"),
    ];
    assert_eq!(CoreError::ALL.len(), expected.len());
    for (e, code, name) in expected {
        assert_eq!(e.code(), code);
        assert_eq!(e.name(), name);
        assert_eq!(e.to_string(), name);
        assert_eq!(format!("{e:?}").len() < 40, true);
    }
}

#[test]
fn identities_never_print_key_material() {
    let alice = Device::new("a");
    let text = format!("{:?}", alice.public);
    assert!(text.contains("redacted"));
    let hex: String = alice
        .public
        .person_key
        .0
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    assert!(!text.contains(&hex[..16]));
}

// -------------------------------------------------------------------- logging

#[test]
fn crypto_core_source_contains_no_logging_or_printing() {
    let src = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let forbidden = [
        "println!",
        "eprintln!",
        "print!(",
        "eprint!(",
        "dbg!",
        "log::",
        "tracing::",
        "debug!(",
        "info!(",
        "warn!(",
    ];
    for entry in fs::read_dir(src).unwrap() {
        let path = entry.unwrap().path();
        let text = fs::read_to_string(&path).unwrap();
        for f in forbidden {
            assert!(
                !text.contains(f),
                "{} contains forbidden `{f}`",
                path.display()
            );
        }
    }
}
