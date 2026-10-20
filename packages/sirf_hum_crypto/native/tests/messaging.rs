//! Prompt 10: ABI v5 messaging core. Staged commits (D-087), first commit
//! wins (D-088), authenticated routing (D-089), local history (D-090),
//! ordering (D-091), multi-device and revocation. TEST key stores only.

mod common;

use common::*;
use sirf_hum_crypto::{CoreError, Incoming, MessageDirection, MessageState, StagedCommit};

type Msg = (Vec<u8>, u64, Vec<u8>);

/// Four devices, mutually anchored (each its own pinned device):
/// Person A = a1, a2; Person B = b1, b2.
fn fleet() -> (Device, Device, Device, Device) {
    let mut a1 = Device::new("accountA");
    let mut a2 = Device::new("accountA");
    let mut b1 = Device::new("accountB");
    let mut b2 = Device::new("accountB");
    let snapshot: Vec<_> = [&a1, &a2, &b1, &b2]
        .iter()
        .map(|d| d.public.person_key.clone())
        .collect();
    for d in [&mut a1, &mut a2, &mut b1, &mut b2] {
        for k in &snapshot {
            d.core.trust_verified_person_key(k.clone()).unwrap();
        }
    }
    (a1, a2, b1, b2)
}

fn couple_conversation() -> (Device, Device, Vec<u8>) {
    let mut a = Device::new("accountA");
    let mut b = Device::new("accountB");
    a.anchor(&b);
    b.anchor(&a);
    let cid = conversation(1);
    conversation_of(&mut a, &mut [&mut b], &cid);
    (a, b, cid)
}

// ---------------------------------------------------------------- padding

/// D-126 (Prompt 17): the server sees a message's length only to within a
/// 256-byte block, for messages from the creator and from a joiner alike,
/// and receivers get the exact payload back.
#[test]
fn ciphertext_length_hides_the_message_length_within_a_block() {
    fn padded(sender: &mut Device, receiver: &mut Device, cid: &[u8]) {
        let short = sender.send(cid, b"ok");
        let longer = sender.send(cid, &[b'x'; 150]);
        let much_longer = sender.send(cid, &[b'x'; 600]);
        assert_eq!(short.2.len(), longer.2.len(), "same block, same size");
        assert!(much_longer.2.len() >= short.2.len() + 256, "next blocks");
        assert_eq!(receiver.recv(cid, sender, &short).unwrap(), b"ok");
        assert_eq!(
            receiver.recv(cid, sender, &much_longer).unwrap(),
            vec![b'x'; 600]
        );
    }
    let (mut a, mut b, cid) = couple_conversation();
    padded(&mut a, &mut b, &cid); // the group's creator
    padded(&mut b, &mut a, &cid); // a device that joined by Welcome
}

// --------------------------------------------------------- staged commits

#[test]
fn staging_never_advances_the_active_epoch() {
    let (mut a, mut b, cid) = couple_conversation();
    let staged = a.core.stage_self_update(&cid).unwrap();
    assert_eq!(staged.from_epoch, 1);
    assert_eq!(a.core.epoch(&cid).unwrap(), 1, "staged is not active");
    assert_eq!(a.core.staged_commit_epoch(&cid).unwrap(), Some(1));
    // The partner can still talk to us at the active epoch, and we can
    // still process application messages while staged (D-091 flush).
    let m = b.send(&cid, b"hi");
    assert_eq!(a.recv(&cid, &b, &m).unwrap(), b"hi");
    assert_eq!(a.core.confirm_commit(&cid, 1).unwrap(), 2);
    assert_eq!(a.core.staged_commit_epoch(&cid).unwrap(), None);
    b.core
        .process_commit(&cid, 1, a.device_id(), &staged.commit)
        .unwrap();
    assert_eq!(b.core.epoch(&cid).unwrap(), 2);
}

#[test]
fn discard_restores_the_active_state_and_is_idempotent() {
    let (mut a, mut b, cid) = couple_conversation();
    let staged = a.core.stage_self_update(&cid).unwrap();
    a.core.discard_commit(&cid, staged.from_epoch).unwrap();
    a.core.discard_commit(&cid, staged.from_epoch).unwrap();
    assert_eq!(a.core.epoch(&cid).unwrap(), 1);
    assert_eq!(a.core.staged_commit_epoch(&cid).unwrap(), None);
    // Confirming a discarded commit is refused and changes nothing.
    assert_eq!(
        a.core.confirm_commit(&cid, 1).unwrap_err(),
        CoreError::NoStagedCommit
    );
    // Messages still flow both ways at the old epoch.
    let m = a.send(&cid, b"still here");
    assert_eq!(b.recv(&cid, &a, &m).unwrap(), b"still here");
}

#[test]
fn confirm_is_exactly_once_and_names_its_epoch() {
    let (mut a, _b, cid) = couple_conversation();
    a.core.stage_self_update(&cid).unwrap();
    assert_eq!(
        a.core.confirm_commit(&cid, 0).unwrap_err(),
        CoreError::NoStagedCommit,
        "wrong (stale) epoch"
    );
    assert_eq!(
        a.core.confirm_commit(&cid, 2).unwrap_err(),
        CoreError::NoStagedCommit,
        "wrong (future) epoch"
    );
    assert_eq!(a.core.confirm_commit(&cid, 1).unwrap(), 2);
    // Duplicate confirm: idempotent, still epoch 2.
    assert_eq!(a.core.confirm_commit(&cid, 1).unwrap(), 2);
    assert_eq!(a.core.epoch(&cid).unwrap(), 2);
    // A stale confirm for an older epoch is not a duplicate.
    assert_eq!(
        a.core.confirm_commit(&cid, 0).unwrap_err(),
        CoreError::NoStagedCommit
    );
    // Wrong conversation.
    assert_eq!(
        a.core.confirm_commit(&conversation(9), 1).unwrap_err(),
        CoreError::UnknownGroup
    );
}

#[test]
fn a_staged_commit_blocks_everything_that_would_fork_state() {
    let (mut a, mut b, cid) = couple_conversation();
    let mut c = Device::new("accountC");
    a.anchor(&c);
    a.core.stage_self_update(&cid).unwrap();
    assert_eq!(
        a.core.stage_self_update(&cid).unwrap_err(),
        CoreError::CommitPending
    );
    assert_eq!(
        a.core.stage_add_members(&cid, &[c.kp()]).unwrap_err(),
        CoreError::CommitPending
    );
    assert_eq!(
        a.core.send_message(&cid, b"x").unwrap_err(),
        CoreError::CommitPending
    );
    // ABI v4 membership calls too.
    assert_eq!(
        a.core.add_member(&cid, &c.kp()).unwrap_err(),
        CoreError::CommitPending
    );
    assert_eq!(
        a.core.encrypt(&cid, b"x").unwrap_err(),
        CoreError::CommitPending
    );
    // Another member's commit must wait for discard.
    let theirs = b.core.stage_self_update(&cid).unwrap();
    b.core.confirm_commit(&cid, 1).unwrap();
    assert_eq!(
        a.core
            .process_commit(&cid, 1, b.device_id(), &theirs.commit)
            .unwrap_err(),
        CoreError::CommitPending
    );
    assert_eq!(a.core.epoch(&cid).unwrap(), 1);
}

#[test]
fn concurrent_commits_first_wins_and_the_loser_converges() {
    let (mut a, mut b, cid) = couple_conversation();
    let ours = a.core.stage_self_update(&cid).unwrap();
    let theirs = b.core.stage_self_update(&cid).unwrap();
    assert_eq!(ours.from_epoch, theirs.from_epoch);
    // The server (create-only commits/1) accepted b's.
    b.core.confirm_commit(&cid, 1).unwrap();
    a.core.discard_commit(&cid, 1).unwrap();
    assert_eq!(
        commit_epoch(
            a.core
                .process_commit(&cid, 1, b.device_id(), &theirs.commit)
                .unwrap()
        ),
        2
    );
    assert_eq!(a.core.epoch(&cid).unwrap(), 2);
    assert_eq!(b.core.epoch(&cid).unwrap(), 2);
    // The losing commit can never be applied afterwards.
    assert!(b
        .core
        .process_commit(&cid, 1, a.device_id(), &ours.commit)
        .is_err());
    let m = a.send(&cid, b"converged");
    assert_eq!(b.recv(&cid, &a, &m).unwrap(), b"converged");
}

/// `Incoming` has no PartialEq (it may hold plaintext); compare the epoch.
fn commit_epoch(r: Incoming) -> u64 {
    match r {
        Incoming::CommitApplied { epoch } => epoch,
        _ => u64::MAX,
    }
}

#[test]
fn a_staged_commit_survives_restart_and_resolves_either_way() {
    let (mut a, mut b, cid) = couple_conversation();
    let staged = a.core.stage_self_update(&cid).unwrap();
    a.restart();
    assert_eq!(a.core.staged_commit_epoch(&cid).unwrap(), Some(1));
    assert_eq!(a.core.epoch(&cid).unwrap(), 1);
    assert_eq!(a.core.confirm_commit(&cid, 1).unwrap(), 2);
    a.restart();
    assert_eq!(a.core.epoch(&cid).unwrap(), 2);
    assert_eq!(a.core.confirm_commit(&cid, 1).unwrap(), 2, "idempotent");
    assert_eq!(
        commit_epoch(
            b.core
                .process_commit(&cid, 1, a.device_id(), &staged.commit)
                .unwrap()
        ),
        2
    );

    // Discard path after a restart.
    a.core.stage_self_update(&cid).unwrap();
    a.restart();
    a.core.discard_commit(&cid, 2).unwrap();
    a.restart();
    assert_eq!(a.core.staged_commit_epoch(&cid).unwrap(), None);
    let m = a.send(&cid, b"after restart");
    assert_eq!(b.recv(&cid, &a, &m).unwrap(), b"after restart");
}

#[test]
fn discarding_an_unconfirmed_new_group_deletes_it() {
    let mut a = Device::new("accountA");
    let mut b = Device::new("accountB");
    a.anchor(&b);
    let cid = conversation(3);
    let staged = a.core.create_conversation_group(&cid, &[b.kp()]).unwrap();
    assert_eq!(staged.from_epoch, 0);
    assert_eq!(a.core.epoch(&cid).unwrap(), 0);
    a.core.discard_commit(&cid, 0).unwrap();
    assert_eq!(a.core.epoch(&cid).unwrap_err(), CoreError::UnknownGroup);
    // It can be created again (e.g. after losing the epoch-0 race and the
    // winner's group turned out unusable is NOT this path; this is a retry).
    a.core.create_conversation_group(&cid, &[b.kp()]).unwrap();
}

#[test]
fn group_creation_race_loser_joins_the_winner() {
    let mut a = Device::new("accountA");
    let mut b = Device::new("accountB");
    a.anchor(&b);
    b.anchor(&a);
    let cid = conversation(4);
    let a_staged = a.core.create_conversation_group(&cid, &[b.kp()]).unwrap();
    let _b_staged = b.core.create_conversation_group(&cid, &[a.kp()]).unwrap();
    // Server: commits/0 from a wins.
    a.core.confirm_commit(&cid, 0).unwrap();
    b.core.discard_commit(&cid, 0).unwrap();
    assert_eq!(
        b.core
            .join_conversation(&cid, a_staged.welcome.as_ref().unwrap())
            .unwrap(),
        1
    );
    let m = b.send(&cid, b"we are one group");
    assert_eq!(a.recv(&cid, &b, &m).unwrap(), b"we are one group");
}

#[test]
fn group_id_is_the_conversation_id_and_welcomes_cannot_be_redirected() {
    let mut a = Device::new("accountA");
    let mut b = Device::new("accountB");
    a.anchor(&b);
    b.anchor(&a);
    let cid = conversation(5);
    let staged = a.core.create_conversation_group(&cid, &[b.kp()]).unwrap();
    a.core.confirm_commit(&cid, 0).unwrap();
    let welcome = staged.welcome.unwrap();
    assert_eq!(
        b.core
            .join_conversation(&conversation(6), &welcome)
            .unwrap_err(),
        CoreError::EnvelopeMismatch
    );
    assert_eq!(b.core.join_conversation(&cid, &welcome).unwrap(), 1);
    assert_eq!(
        b.core.join_conversation(&cid, &welcome).unwrap_err(),
        CoreError::InvalidInput,
        "already joined"
    );
    assert_eq!(
        a.core
            .create_conversation_group(&[1u8; 15], &[b.kp()])
            .unwrap_err(),
        CoreError::InvalidInput,
        "conversation IDs are 16 bytes"
    );
}

// ---------------------------------------------------- multi-device (§10)

fn four_device_conversation() -> (Device, Device, Device, Device, Vec<u8>) {
    let (mut a1, mut a2, mut b1, mut b2) = fleet();
    let cid = conversation(7);
    conversation_of(&mut a1, &mut [&mut a2, &mut b1, &mut b2], &cid);
    (a1, a2, b1, b2, cid)
}

#[test]
fn every_device_reaches_every_other_device() {
    let (mut a1, mut a2, mut b1, mut b2, cid) = four_device_conversation();
    let m = a1.send(&cid, b"a1");
    assert_eq!(b1.recv(&cid, &a1, &m).unwrap(), b"a1");
    assert_eq!(b2.recv(&cid, &a1, &m).unwrap(), b"a1");
    assert_eq!(a2.recv(&cid, &a1, &m).unwrap(), b"a1", "own other device");
    let m = a2.send(&cid, b"a2");
    assert_eq!(b1.recv(&cid, &a2, &m).unwrap(), b"a2");
    assert_eq!(b2.recv(&cid, &a2, &m).unwrap(), b"a2");
    assert_eq!(a1.recv(&cid, &a2, &m).unwrap(), b"a2");
    let m = b2.send(&cid, b"b2");
    for d in [&mut a1, &mut a2, &mut b1] {
        assert_eq!(d.recv(&cid, &b2, &m).unwrap(), b"b2");
    }
}

#[test]
fn revoked_device_is_removed_and_cannot_rejoin_or_send() {
    let (mut a1, mut a2, mut b1, mut b2, cid) = four_device_conversation();
    let a2_id = a2.device_id();
    // A2 is revoked. Every other device learns it (here: local revocation;
    // through lineage in trust_binding tests).
    for d in [&mut a1, &mut b1, &mut b2] {
        d.core.revoke_device(a2_id).unwrap();
    }
    // Firebase authorization is not MLS membership: until the Remove commit,
    // A2 is still in the roster, so senders refuse to encrypt to it.
    assert_eq!(
        b1.core.send_message(&cid, b"not to a2").unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // A2's messages are rejected by devices that know of the revocation.
    let from_a2 = a2.send(&cid, b"still trusted?");
    assert_eq!(
        b1.recv(&cid, &a2, &from_a2).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // B1 removes A2 (staged → server accepts → confirm); others apply it.
    let removal = b1.core.stage_remove_members(&cid, &[a2_id]).unwrap();
    assert_eq!(b1.core.confirm_commit(&cid, removal.from_epoch).unwrap(), 2);
    for d in [&mut a1, &mut b2] {
        assert_eq!(
            commit_epoch(
                d.core
                    .process_commit(&cid, 1, b1.device_id(), &removal.commit)
                    .unwrap()
            ),
            2
        );
    }
    // A2 processes its own removal and loses the group.
    assert!(matches!(
        a2.core
            .process_commit(&cid, 1, b1.device_id(), &removal.commit)
            .unwrap(),
        Incoming::RemovedFromGroup
    ));
    assert_eq!(a2.core.epoch(&cid).unwrap_err(), CoreError::UnknownGroup);
    // New messages reach the remaining devices only.
    let m = b1.send(&cid, b"after removal");
    assert_eq!(a1.recv(&cid, &b1, &m).unwrap(), b"after removal");
    assert_eq!(b2.recv(&cid, &b1, &m).unwrap(), b"after removal");
    // A2 cannot re-enter: its KeyPackage is refused everywhere.
    let kp = a2.kp();
    assert_eq!(
        a1.core.stage_add_members(&cid, &[kp]).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    // An old A2 message replayed at the old epoch fails closed.
    assert_eq!(
        b2.recv(&cid, &a2, &from_a2).unwrap_err(),
        CoreError::StaleEpoch
    );
}

#[test]
fn stale_state_of_a_removed_device_cannot_decrypt_or_regain_trust() {
    let (mut a1, a2, mut b1, mut b2, cid) = four_device_conversation();
    let a2_id = a2.device_id();
    // Snapshot A2's on-disk state before removal (restored-backup attack).
    let snapshot = tempfile::tempdir().unwrap();
    for e in std::fs::read_dir(&a2.dir).unwrap().flatten() {
        std::fs::copy(e.path(), snapshot.path().join(e.file_name())).unwrap();
    }
    for d in [&mut a1, &mut b1, &mut b2] {
        d.core.revoke_device(a2_id).unwrap();
    }
    let removal = a1.core.stage_remove_members(&cid, &[a2_id]).unwrap();
    a1.core.confirm_commit(&cid, 1).unwrap();
    for d in [&mut b1, &mut b2] {
        d.core
            .process_commit(&cid, 1, a1.device_id(), &removal.commit)
            .unwrap();
    }
    let m = a1.send(&cid, b"new epoch secret");
    let mut stale = open_dir(snapshot.path()).unwrap();
    let r = stale.receive_message(&cid, &m.0, a1.device_id(), m.1, 1, 1, &m.2, 0);
    assert_eq!(r.unwrap_err(), CoreError::FutureEpoch);
    // Applying the removal only removes it.
    assert!(matches!(
        stale
            .process_commit(&cid, 1, a1.device_id(), &removal.commit)
            .unwrap(),
        Incoming::RemovedFromGroup
    ));
    assert!(stale
        .receive_message(&cid, &m.0, a1.device_id(), m.1, 1, 1, &m.2, 0)
        .is_err());
}

#[test]
fn a_new_trusted_device_joins_later_and_reads_only_from_then() {
    let (mut a1, mut a2, mut b1, mut b2, cid) = four_device_conversation();
    let before = b1.send(&cid, b"before b3");
    let mut b3 = Device::new("accountB");
    for d in [&mut a1, &mut a2, &mut b1, &mut b2] {
        d.anchor(&b3);
    }
    for d in [&a1, &a2, &b1, &b2] {
        b3.anchor(d);
    }
    let add = b1.core.stage_add_members(&cid, &[b3.kp()]).unwrap();
    b1.core.confirm_commit(&cid, 1).unwrap();
    for d in [&mut a1, &mut a2, &mut b2] {
        d.recv(&cid, &b1, &before).unwrap();
        d.core
            .process_commit(&cid, 1, b1.device_id(), &add.commit)
            .unwrap();
    }
    assert_eq!(
        b3.core
            .join_conversation(&cid, add.welcome.as_ref().unwrap())
            .unwrap(),
        2
    );
    // No history: the pre-join message is from an earlier epoch.
    assert_eq!(
        b3.recv(&cid, &b1, &before).unwrap_err(),
        CoreError::StaleEpoch
    );
    let after = a2.send(&cid, b"welcome b3");
    assert_eq!(b3.recv(&cid, &a2, &after).unwrap(), b"welcome b3");
    assert_eq!(b3.core.roster(&cid).unwrap().len(), 5);
}

// ------------------------------------------- authenticated routing (§9)

#[test]
fn every_envelope_field_is_cryptographically_bound() {
    let (mut a, mut b, cid) = couple_conversation();
    let (mid, epoch, ct) = a.send(&cid, b"bound");
    let me = a.device_id();
    let mut other_mid = mid.clone();
    other_mid[0] ^= 1;
    let cases: Vec<(&str, Result<_, CoreError>)> = vec![
        (
            "message id",
            b.core
                .receive_message(&cid, &other_mid, me, epoch, 1, 1, &ct, 0)
                .map(|_| ()),
        ),
        (
            "protocol version",
            b.core
                .receive_message(&cid, &mid, me, epoch, 1, 2, &ct, 0)
                .map(|_| ()),
        ),
        (
            "schema version",
            b.core
                .receive_message(&cid, &mid, me, epoch, 2, 1, &ct, 0)
                .map(|_| ()),
        ),
        (
            "epoch",
            b.core
                .receive_message(&cid, &mid, me, epoch + 1, 1, 1, &ct, 0)
                .map(|_| ()),
        ),
        (
            "conversation",
            b.core
                .receive_message(&conversation(2), &mid, me, epoch, 1, 1, &ct, 0)
                .map(|_| ()),
        ),
    ];
    for (field, result) in cases {
        assert_eq!(result.unwrap_err(), CoreError::EnvelopeMismatch, "{field}");
    }
    // Sender rewritten to another device's ID.
    let c = Device::new("accountB");
    assert_eq!(
        b.core
            .receive_message(&cid, &mid, c.device_id(), epoch, 1, 1, &ct, 0)
            .unwrap_err(),
        CoreError::EnvelopeMismatch,
        "sender"
    );
    // After all those rejections the genuine message still decrypts once.
    assert_eq!(
        b.core
            .receive_message(&cid, &mid, me, epoch, 1, 1, &ct, 0)
            .unwrap()
            .payload
            .to_vec(),
        b"bound"
    );
}

#[test]
fn ciphertext_copied_into_another_conversation_fails() {
    let mut a = Device::new("accountA");
    let mut b = Device::new("accountB");
    a.anchor(&b);
    b.anchor(&a);
    let (c1, c2) = (conversation(0x11), conversation(0x22));
    conversation_of(&mut a, &mut [&mut b], &c1);
    conversation_of(&mut a, &mut [&mut b], &c2);
    let (mid, epoch, ct) = a.send(&c1, b"for c1 only");
    assert_eq!(
        b.core
            .receive_message(&c2, &mid, a.device_id(), epoch, 1, 1, &ct, 0)
            .unwrap_err(),
        CoreError::EnvelopeMismatch
    );
    assert_eq!(
        b.core
            .receive_message(&c1, &mid, a.device_id(), epoch, 1, 1, &ct, 0)
            .unwrap()
            .payload
            .to_vec(),
        b"for c1 only"
    );
}

#[test]
fn tampered_ciphertext_fails_and_never_consumes_the_key() {
    let (mut a, mut b, cid) = couple_conversation();
    let msg = a.send(&cid, b"integrity");
    for i in [0usize, 10, msg.2.len() / 2, msg.2.len() - 1] {
        let mut bad = msg.clone();
        bad.2[i] ^= 0x01;
        assert!(b.recv(&cid, &a, &bad).is_err(), "byte {i}");
    }
    let mut truncated = msg.clone();
    truncated.2.truncate(20);
    assert!(b.recv(&cid, &a, &truncated).is_err());
    assert_eq!(b.recv(&cid, &a, &msg).unwrap(), b"integrity");
}

#[test]
fn own_device_and_unknown_inputs_fail_closed() {
    let (mut a, mut b, cid) = couple_conversation();
    let msg = a.send(&cid, b"mine");
    let own = a.device_id();
    assert_eq!(
        a.core
            .receive_message(&cid, &msg.0, own, msg.1, 1, 1, &msg.2, 0)
            .unwrap_err(),
        CoreError::EnvelopeMismatch,
        "a server cannot feed us our own message as someone else's"
    );
    let garbage = (vec![1u8; 16], 1, vec![0u8; 64]);
    assert_eq!(
        b.recv(&cid, &a, &garbage).unwrap_err(),
        CoreError::MalformedMessage
    );
    assert_eq!(
        b.core
            .receive_message(&cid, &[1u8; 15], a.device_id(), 1, 1, 1, &msg.2, 0)
            .unwrap_err(),
        CoreError::InvalidInput
    );
}

// --------------------------------------------- replay, order, epochs (§11)

#[test]
fn duplicates_are_reported_and_replays_rejected() {
    let (mut a, mut b, cid) = couple_conversation();
    let msg = a.send(&cid, b"once");
    assert_eq!(b.recv(&cid, &a, &msg).unwrap(), b"once");
    let again = b
        .core
        .receive_message(&cid, &msg.0, a.device_id(), msg.1, 1, 1, &msg.2, 0)
        .unwrap();
    assert!(again.duplicate);
    assert!(again.payload.is_empty());
    // Even without the local record, MLS refuses the reused key.
    b.core.delete_local_message(&cid, &msg.0).unwrap();
    assert_eq!(b.recv(&cid, &a, &msg).unwrap_err(), CoreError::Replay);
}

#[test]
fn reordered_and_delayed_messages_within_an_epoch_decrypt() {
    let (mut a, mut b, cid) = couple_conversation();
    let msgs: Vec<Msg> = (0..30u8).map(|i| a.send(&cid, &[b'm', i])).collect();
    for (i, m) in msgs.iter().enumerate().rev() {
        assert_eq!(b.recv(&cid, &a, m).unwrap(), vec![b'm', i as u8]);
    }
}

#[test]
fn concurrent_senders_at_one_epoch_both_arrive() {
    let (mut a1, mut a2, mut b1, _b2, cid) = four_device_conversation();
    let x = a1.send(&cid, b"x");
    let y = a2.send(&cid, b"y");
    assert_eq!(b1.recv(&cid, &a2, &y).unwrap(), b"y");
    assert_eq!(b1.recv(&cid, &a1, &x).unwrap(), b"x");
}

#[test]
fn future_epoch_waits_for_the_commit_and_stale_epoch_fails_closed() {
    let (mut a, mut b, cid) = couple_conversation();
    let old = a.send(&cid, b"epoch 1");
    let update = a.core.stage_self_update(&cid).unwrap();
    a.core.confirm_commit(&cid, 1).unwrap();
    let new = a.send(&cid, b"epoch 2");
    // B has not applied the commit yet: keep and retry later.
    assert_eq!(b.recv(&cid, &a, &new).unwrap_err(), CoreError::FutureEpoch);
    // Correct order (D-091): epoch 1 messages, then commit 1.
    assert_eq!(b.recv(&cid, &a, &old).unwrap(), b"epoch 1");
    b.core
        .process_commit(&cid, 1, a.device_id(), &update.commit)
        .unwrap();
    assert_eq!(b.recv(&cid, &a, &new).unwrap(), b"epoch 2");
    // A commit for a wrong epoch or from a wrong sender is refused.
    let next = a.core.stage_self_update(&cid).unwrap();
    a.core.confirm_commit(&cid, 2).unwrap();
    assert_eq!(
        b.core
            .process_commit(&cid, 3, a.device_id(), &next.commit)
            .unwrap_err(),
        CoreError::EnvelopeMismatch
    );
    assert_eq!(
        b.core
            .process_commit(&cid, 2, b.device_id(), &next.commit)
            .unwrap_err(),
        CoreError::EnvelopeMismatch
    );
    let late = (old.0.clone(), old.1, old.2.clone());
    b.core.delete_local_message(&cid, &late.0).unwrap();
    b.core
        .process_commit(&cid, 2, a.device_id(), &next.commit)
        .unwrap();
    assert_eq!(b.recv(&cid, &a, &late).unwrap_err(), CoreError::StaleEpoch);
    // A commit replayed after it was applied is stale.
    assert_eq!(
        b.core
            .process_commit(&cid, 2, a.device_id(), &next.commit)
            .unwrap_err(),
        CoreError::StaleEpoch
    );
    // An application message where a commit was expected is refused.
    let m = a.send(&cid, b"not a commit");
    assert_eq!(
        b.core
            .process_commit(&cid, 3, a.device_id(), &m.2)
            .unwrap_err(),
        CoreError::ProtocolViolation
    );
    assert_eq!(b.recv(&cid, &a, &m).unwrap(), b"not a commit");
}

#[test]
fn committer_flushes_its_epoch_before_confirming() {
    // D-091: B sends at epoch 1 while A's commit for epoch 1 is staged and
    // then accepted; the server accepted B's message first. A processes it
    // before confirming, so no past-epoch secrets are needed.
    let (mut a, mut b, cid) = couple_conversation();
    let staged = a.core.stage_self_update(&cid).unwrap();
    let racing = b.send(&cid, b"racing the commit");
    assert_eq!(a.recv(&cid, &b, &racing).unwrap(), b"racing the commit");
    a.core.confirm_commit(&cid, staged.from_epoch).unwrap();
    b.core
        .process_commit(&cid, 1, a.device_id(), &staged.commit)
        .unwrap();
    let m = b.send(&cid, b"epoch 2");
    assert_eq!(a.recv(&cid, &b, &m).unwrap(), b"epoch 2");
}

// ------------------------------------------------ offline / retry (§11)

#[test]
fn offline_send_is_queued_sealed_and_reencrypted_after_a_stale_refusal() {
    let (mut a, mut b, cid) = couple_conversation();
    // Offline: encrypted at compose, queued in sealed history.
    let queued = a.core.send_message(&cid, b"written offline").unwrap();
    let h = a.core.history(&cid).unwrap();
    assert_eq!(h.len(), 1);
    assert_eq!(h[0].state, MessageState::Queued);
    assert_eq!(
        h[0].ciphertext.as_deref(),
        Some(queued.ciphertext.as_slice())
    );
    // Meanwhile B's commit moved the conversation to epoch 2.
    let update = b.core.stage_self_update(&cid).unwrap();
    b.core.confirm_commit(&cid, 1).unwrap();
    a.restart();
    a.core
        .process_commit(&cid, 1, b.device_id(), &update.commit)
        .unwrap();
    // The server refused the stale upload; re-encrypt the same ID.
    let again = a.core.reencrypt_message(&cid, &queued.message_id).unwrap();
    assert_eq!(again.message_id, queued.message_id);
    assert_eq!(again.epoch, 2);
    let msg = (again.message_id.to_vec(), again.epoch, again.ciphertext);
    assert_eq!(b.recv(&cid, &a, &msg).unwrap(), b"written offline");
    a.core
        .mark_message_sent(&cid, &queued.message_id, 1234)
        .unwrap();
    a.core
        .mark_message_sent(&cid, &queued.message_id, 1234)
        .unwrap();
    let h = a.core.history(&cid).unwrap();
    assert_eq!(h[0].state, MessageState::Sent);
    assert!(h[0].ciphertext.is_none());
    assert_eq!(h[0].server_time_ms, 1234);
    // Only queued messages can be re-encrypted.
    assert_eq!(
        a.core
            .reencrypt_message(&cid, &queued.message_id)
            .unwrap_err(),
        CoreError::InvalidInput
    );
}

// --------------------------------------------------- local history (§13)

#[test]
fn history_is_sealed_persistent_and_ordered_by_the_caller() {
    let (mut a, mut b, cid) = couple_conversation();
    let m1 = a.send(&cid, b"one");
    b.recv(&cid, &a, &m1).unwrap();
    let m2 = b.send(&cid, b"two");
    a.recv(&cid, &b, &m2).unwrap();
    a.restart();
    let h = a.core.history(&cid).unwrap();
    assert_eq!(h.len(), 2);
    let out = h
        .iter()
        .find(|m| m.direction == MessageDirection::Outgoing)
        .unwrap();
    let inc = h
        .iter()
        .find(|m| m.direction == MessageDirection::Incoming)
        .unwrap();
    assert_eq!(out.payload.as_slice(), b"one");
    assert_eq!(inc.payload.as_slice(), b"two");
    assert_eq!(inc.sender_device_id, b.device_id());
    assert_eq!(inc.state, MessageState::Received);
    // Plaintext never appears in any file on disk.
    for e in std::fs::read_dir(&a.dir).unwrap().flatten() {
        let bytes = std::fs::read(e.path()).unwrap();
        assert!(!bytes.windows(3).any(|w| w == b"one" || w == b"two"));
    }
    assert!(format!("{out:?}").contains("redacted"));
    // Delete for me removes it locally only.
    a.core.delete_local_message(&cid, &m1.0).unwrap();
    assert_eq!(a.core.history(&cid).unwrap().len(), 1);
}

#[test]
fn history_fails_closed_on_corruption_swap_or_wrong_key() {
    let (mut a, mut b, cid) = couple_conversation();
    let m1 = a.send(&cid, b"first");
    let m2 = a.send(&cid, b"second");
    b.recv(&cid, &a, &m1).unwrap();
    b.recv(&cid, &a, &m2).unwrap();
    let names: Vec<_> = std::fs::read_dir(&b.dir)
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.file_name().unwrap().to_str().unwrap().starts_with("msg_"))
        .collect();
    assert_eq!(names.len(), 2);
    // Swap the two sealed records: AAD binds the name.
    let (x, y) = (
        std::fs::read(&names[0]).unwrap(),
        std::fs::read(&names[1]).unwrap(),
    );
    std::fs::write(&names[0], &y).unwrap();
    std::fs::write(&names[1], &x).unwrap();
    assert_eq!(
        b.core.history(&cid).unwrap_err(),
        CoreError::StateCorruption
    );
    // One flipped byte.
    std::fs::write(&names[0], &x).unwrap();
    let mut z = y.clone();
    let last = z.len() - 1;
    z[last] ^= 1;
    std::fs::write(&names[1], &z).unwrap();
    assert_eq!(
        b.core.history(&cid).unwrap_err(),
        CoreError::StateCorruption
    );
    // A record sealed under another device's key.
    let foreign: Vec<_> = std::fs::read_dir(&a.dir)
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.file_name().unwrap().to_str().unwrap().starts_with("msg_"))
        .collect();
    std::fs::write(&names[1], std::fs::read(&foreign[0]).unwrap()).unwrap();
    assert_eq!(
        b.core.history(&cid).unwrap_err(),
        CoreError::StateCorruption
    );
}

#[test]
fn history_is_scoped_to_the_account_slot_and_wiped_with_it() {
    let (mut a, mut b, cid) = couple_conversation();
    let m = a.send(&cid, b"private");
    b.recv(&cid, &a, &m).unwrap();
    // Another account on the same installation has its own slot: nothing.
    let other = Device::new("accountZ");
    assert_eq!(
        other.core.history(&cid).unwrap().len(),
        0,
        "no cross-account leakage"
    );
    b.core.wipe().unwrap();
    assert!(std::fs::read_dir(&b.dir).unwrap().flatten().all(|e| !e
        .file_name()
        .to_str()
        .unwrap()
        .starts_with("msg_")));
}

#[test]
fn a_failed_history_write_rolls_back_the_receive() {
    let mut a = Device::new("accountA");
    let store = FaultyStore::new();
    let keys = sirf_hum_crypto::keystore::EphemeralTestKeyStore::new();
    let mut b_core = sirf_hum_crypto::CryptoCore::open(Box::new(store.clone()), &keys).unwrap();
    let b_public = b_core
        .create_identity(sirf_hum_crypto::identity::AccountId::new("accountB").unwrap())
        .unwrap();
    a.core
        .trust_verified_person_key(b_public.person_key.clone())
        .unwrap();
    b_core
        .trust_verified_person_key(a.public.person_key.clone())
        .unwrap();
    let cid = conversation(8);
    let staged = a
        .core
        .create_conversation_group(&cid, &[b_core.key_package().unwrap()])
        .unwrap();
    a.core.confirm_commit(&cid, 0).unwrap();
    b_core
        .join_conversation(&cid, staged.welcome.as_ref().unwrap())
        .unwrap();
    let m = a.send(&cid, b"durable");
    store.set_failing(true);
    assert_eq!(
        b_core
            .receive_message(&cid, &m.0, a.device_id(), m.1, 1, 1, &m.2, 0)
            .unwrap_err(),
        CoreError::PersistenceFailure
    );
    store.set_failing(false);
    assert_eq!(b_core.history(&cid).unwrap().len(), 0);
    // The key was not consumed: the retry succeeds.
    assert_eq!(
        b_core
            .receive_message(&cid, &m.0, a.device_id(), m.1, 1, 1, &m.2, 0)
            .unwrap()
            .payload
            .to_vec(),
        b"durable"
    );
    assert_eq!(b_core.history(&cid).unwrap().len(), 1);
}

// ------------------------------------------------------------- limits

#[test]
fn size_limits_are_exact() {
    let (mut a, mut b, cid) = couple_conversation();
    let max = sirf_hum_crypto::limits::MAX_MESSAGE_PAYLOAD_BYTES;
    let m = a.send(&cid, &vec![b'x'; max]);
    assert_eq!(b.recv(&cid, &a, &m).unwrap().len(), max);
    assert_eq!(
        a.core.send_message(&cid, &vec![b'x'; max + 1]).unwrap_err(),
        CoreError::InputTooLarge
    );
    assert_eq!(
        a.core.send_message(&cid, b"").unwrap_err(),
        CoreError::InvalidInput
    );
    let huge = vec![0u8; sirf_hum_crypto::limits::MAX_MESSAGE_CIPHERTEXT_BYTES + 1];
    assert_eq!(
        b.core
            .receive_message(&cid, &[1u8; 16], a.device_id(), 1, 1, 1, &huge, 0)
            .unwrap_err(),
        CoreError::InputTooLarge
    );
    // A full-size message ciphertext stays under the receive limit.
    assert!(m.2.len() <= sirf_hum_crypto::limits::MAX_MESSAGE_CIPHERTEXT_BYTES);
}

#[test]
fn staged_outputs_never_print_content() {
    let (mut a, _b, cid) = couple_conversation();
    let staged: StagedCommit = a.core.stage_self_update(&cid).unwrap();
    assert_eq!(
        format!("{staged:?}"),
        "StagedCommit(from_epoch: 1, <redacted>)"
    );
    a.core.discard_commit(&cid, 1).unwrap();
    let sent = a.core.send_message(&cid, b"secret").unwrap();
    assert!(!format!("{sent:?}").contains("secret"));
}

// ------------------------------------------------ performance baseline

/// `cargo test --release --test messaging -- --ignored --nocapture`
#[test]
#[ignore]
fn performance_baseline() {
    use std::time::Instant;
    let (mut a, mut b, cid) = couple_conversation();
    for size in [64usize, 1024, 16 * 1024] {
        let text = vec![b'x'; size];
        let n = 200;
        let start = Instant::now();
        let msgs: Vec<Msg> = (0..n).map(|_| a.send(&cid, &text)).collect();
        let enc = start.elapsed();
        let start = Instant::now();
        for m in &msgs {
            b.recv(&cid, &a, m).unwrap();
        }
        let dec = start.elapsed();
        println!(
            "payload {size} B: encrypt+seal {:.2} ms/msg, verify+decrypt+seal {:.2} ms/msg, ciphertext {} B",
            enc.as_secs_f64() * 1000.0 / n as f64,
            dec.as_secs_f64() * 1000.0 / n as f64,
            msgs[0].2.len()
        );
    }
    let start = Instant::now();
    let h = b.core.history(&cid).unwrap();
    println!(
        "history load: {} records in {:.1} ms",
        h.len(),
        start.elapsed().as_secs_f64() * 1000.0
    );
}

// ------------------------------------ lineage-only trust, end to end (D-085)

#[test]
fn lineage_trust_and_signed_revocation_drive_mls_membership() {
    use sirf_hum_crypto::identity::RevocationReason;
    // Each person: root + one approved device. Partners anchor only each
    // other's ROOT PIK (out-of-band) and learn the rest from lineage.
    let mut a1 = Device::new("accountA");
    let mut a2 = Device::new("accountA");
    let mut b1 = Device::new("accountB");
    let mut b2 = Device::new("accountB");
    let a_link = approve(&mut a1, &a2);
    let b_link = approve(&mut b1, &b2);
    let a_lineage = lineage_blob(
        "accountA",
        &a1.public.certificate,
        std::slice::from_ref(&a_link),
        &[],
        &[],
    );
    let b_lineage = lineage_blob(
        "accountB",
        &b1.public.certificate,
        std::slice::from_ref(&b_link),
        &[],
        &[],
    );
    let (a_root, b_root) = (a1.public.person_key.clone(), b1.public.person_key.clone());
    for d in [&mut a1, &mut a2, &mut b1, &mut b2] {
        d.core.trust_verified_person_key(a_root.clone()).unwrap();
        d.core.trust_verified_person_key(b_root.clone()).unwrap();
        d.core.trust_lineage(&a_lineage, 2).unwrap();
        assert_eq!(d.core.trust_lineage(&b_lineage, 2).unwrap(), 2);
    }
    assert_eq!(
        b1.core.device_account(&a2.device_id()).unwrap().as_deref(),
        Some("accountA")
    );
    let cid = conversation(0x33);
    conversation_of(&mut b1, &mut [&mut a1, &mut a2, &mut b2], &cid);
    let m = a2.send(&cid, b"via lineage");
    assert_eq!(b2.recv(&cid, &a2, &m).unwrap(), b"via lineage");

    // A1 signs A2's revocation; the next lineage carries it.
    let sig = a1
        .core
        .sign_revocation(
            &a2.public.certificate,
            RevocationReason::Lost,
            &CHALLENGE,
            EXPIRES,
        )
        .unwrap();
    let rev = (
        a1.public.certificate.clone(),
        a2.public.certificate.clone(),
        RevocationReason::Lost as u8,
        CHALLENGE.to_vec(),
        EXPIRES,
        sig,
    );
    let a_lineage = lineage_blob("accountA", &a1.public.certificate, &[a_link], &[rev], &[]);
    for d in [&mut a1, &mut b1, &mut b2] {
        assert_eq!(d.core.trust_lineage(&a_lineage, 3).unwrap(), 1);
    }
    // MLS membership is still stale: sending is refused until removal.
    assert_eq!(
        b2.core.send_message(&cid, b"x").unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    let m = a2.send(&cid, b"revoked sender");
    assert_eq!(
        b1.recv(&cid, &a2, &m).unwrap_err(),
        CoreError::UnauthorizedDevice
    );
    let removal = a1
        .core
        .stage_remove_members(&cid, &[a2.device_id()])
        .unwrap();
    a1.core.confirm_commit(&cid, 1).unwrap();
    for d in [&mut b1, &mut b2] {
        d.core
            .process_commit(&cid, 1, a1.device_id(), &removal.commit)
            .unwrap();
    }
    let m = b2.send(&cid, b"after removal");
    assert_eq!(a1.recv(&cid, &b2, &m).unwrap(), b"after removal");
    assert_eq!(b1.recv(&cid, &b2, &m).unwrap(), b"after removal");
    assert_eq!(a2.recv(&cid, &b2, &m).unwrap_err(), CoreError::FutureEpoch);
    // A stale (older) lineage without the revocation is refused outright.
    let old = lineage_blob("accountA", &a1.public.certificate, &[], &[], &[]);
    assert_eq!(
        b1.core.trust_lineage(&old, 2).unwrap_err(),
        CoreError::TrustStateStale
    );
}
