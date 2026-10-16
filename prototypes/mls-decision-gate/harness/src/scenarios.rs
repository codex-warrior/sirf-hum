//! Scenarios from Prompt 05 §6–§10, generic over the MLS backend.
//! Each function panics (fails the test) if a security expectation breaks.

use crate::{Backend, Bytes};

/// A device plus its local view of the couple group.
pub struct Member<B: Backend> {
    pub label: String,
    pub device: B::Device,
    pub group: B::Group,
}

impl<B: Backend> Member<B> {
    fn founder(label: &str) -> Self {
        let device = B::new_device(label);
        let group = B::create_group(&device);
        Self { label: label.into(), device, group }
    }

    fn send(&mut self, text: &[u8]) -> Bytes {
        B::encrypt(&self.device, &mut self.group, text)
    }

    fn open(&mut self, ct: &[u8]) -> Result<Bytes, String> {
        B::decrypt(&self.device, &mut self.group, ct)
    }

    fn apply(&mut self, commit: &[u8]) {
        B::process_commit(&self.device, &mut self.group, commit)
            .unwrap_or_else(|e| panic!("[{}] {} failed to process commit: {e}", B::NAME, self.label));
    }
}

/// `inviter` adds a new device; every listed existing member processes the
/// commit; the new device joins from the Welcome.
fn add_device<B: Backend>(inviter: &mut Member<B>, others: &mut [&mut Member<B>], label: &str) -> Member<B> {
    let device = B::new_device(label);
    let kp = B::key_package(&device);
    let (commit, welcome) = B::add(&inviter.device, &mut inviter.group, &[kp]);
    for m in others.iter_mut() {
        m.apply(&commit);
    }
    let group = B::join(&device, &welcome);
    Member { label: label.into(), device, group }
}

fn remove_device<B: Backend>(by: &mut Member<B>, others: &mut [&mut Member<B>], label: &str) -> Bytes {
    let commit = B::remove(&by.device, &mut by.group, label);
    for m in others.iter_mut() {
        m.apply(&commit);
    }
    commit
}

/// All members agree on roster, epoch and epoch authenticator.
fn assert_converged<B: Backend>(members: &[&Member<B>], expected_roster: &[&str]) {
    let mut expected: Vec<String> = expected_roster.iter().map(|s| s.to_string()).collect();
    expected.sort();
    let first = members[0];
    for m in members {
        assert_eq!(B::roster(&m.group), expected, "[{}] roster on {}", B::NAME, m.label);
        assert_eq!(B::epoch(&m.group), B::epoch(&first.group), "[{}] epoch on {}", B::NAME, m.label);
        assert_eq!(
            B::epoch_authenticator(&m.group),
            B::epoch_authenticator(&first.group),
            "[{}] epoch authenticator on {}",
            B::NAME,
            m.label
        );
    }
}

/// §7 lifecycle: A1,B1 → +A2 → +B2 → A2 revoked → B1 replaced by B3 →
/// A1 offline while traffic and a commit happen → A1 reconnects.
pub fn device_lifecycle<B: Backend>() {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    assert_converged(&[&a1, &b1], &["a/1", "b/1"]);

    let mut a2 = add_device(&mut a1, &mut [&mut b1], "a/2");
    assert_converged(&[&a1, &a2, &b1], &["a/1", "a/2", "b/1"]);

    let mut b2 = add_device(&mut b1, &mut [&mut a1, &mut a2], "b/2");
    assert_converged(&[&a1, &a2, &b1, &b2], &["a/1", "a/2", "b/1", "b/2"]);

    // A2 revoked by A1.
    remove_device(&mut a1, &mut [&mut b1, &mut b2, &mut a2], "a/2");
    assert_converged(&[&a1, &b1, &b2], &["a/1", "b/1", "b/2"]);
    let after_a2 = b1.send(b"after a2 revoked");
    assert!(a2.open(&after_a2).is_err(), "[{}] revoked A2 decrypted later content", B::NAME);
    assert_eq!(a1.open(&after_a2).unwrap(), b"after a2 revoked");
    assert_eq!(b2.open(&after_a2).unwrap(), b"after a2 revoked");

    // B1 replaced: B2 adds B3, then removes B1.
    let mut b3 = add_device(&mut b2, &mut [&mut a1, &mut b1], "b/3");
    remove_device(&mut b2, &mut [&mut a1, &mut b3, &mut b1], "b/1");
    assert_converged(&[&a1, &b2, &b3], &["a/1", "b/2", "b/3"]);
    let after_b1 = b3.send(b"after b1 replaced");
    assert!(b1.open(&after_b1).is_err(), "[{}] replaced B1 decrypted later content", B::NAME);
    assert_eq!(a1.open(&after_b1).unwrap(), b"after b1 replaced");
    assert_eq!(b2.open(&after_b1).unwrap(), b"after b1 replaced");

    // A1 offline: B2 sends m1 (epoch e), B3 commits an update (e+1), B3 sends m2.
    let m1 = b2.send(b"while a1 offline");
    let update = B::update(&b3.device, &mut b3.group);
    b2.apply(&update);
    let m2 = b3.send(b"after update");
    assert_eq!(b2.open(&m2).unwrap(), b"after update");

    // A1 reconnects and processes in delivery-service order.
    assert_eq!(a1.open(&m1).unwrap(), b"while a1 offline");
    a1.apply(&update);
    assert_eq!(a1.open(&m2).unwrap(), b"after update");
    assert_converged(&[&a1, &b2, &b3], &["a/1", "b/2", "b/3"]);
}

/// §6: two people × three devices in one group; every message reaches the
/// five other devices.
pub fn six_device_couple<B: Backend>() {
    let labels = ["a/android", "a/iphone", "a/web-later", "b/android", "b/iphone", "b/web-later"];
    let mut founder = Member::<B>::founder(labels[0]);
    let devices: Vec<B::Device> = labels[1..].iter().map(|l| B::new_device(l)).collect();
    let kps: Vec<Bytes> = devices.iter().map(|d| B::key_package(d)).collect();
    let (_commit, welcome) = B::add(&founder.device, &mut founder.group, &kps);
    let mut members = vec![];
    for (device, label) in devices.into_iter().zip(&labels[1..]) {
        let group = B::join(&device, &welcome);
        members.push(Member::<B> { label: label.to_string(), device, group });
    }
    members.insert(0, founder);
    assert_converged(&members.iter().collect::<Vec<_>>(), &labels);

    for sender in 0..members.len() {
        let text = format!("from {}", members[sender].label).into_bytes();
        let ct = members[sender].send(&text);
        for (i, m) in members.iter_mut().enumerate() {
            if i != sender {
                assert_eq!(m.open(&ct).unwrap(), text, "[{}] {} reading", B::NAME, m.label);
            }
        }
    }
}

/// §8 revocation, including the documented limit: removal cannot erase
/// plaintext the device already decrypted.
pub fn revocation<B: Backend>() {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    let mut a2 = add_device(&mut a1, &mut [&mut b1], "a/2");

    let before = b1.send(b"before removal");
    let kept_by_a2 = a2.open(&before).unwrap();
    assert_eq!(a1.open(&before).unwrap(), b"before removal");

    let epoch_before = B::epoch(&a1.group);
    remove_device(&mut a1, &mut [&mut b1], "a/2");
    assert_eq!(B::epoch(&a1.group), epoch_before + 1, "[{}] removal must advance the epoch", B::NAME);

    let after = b1.send(b"after removal");
    // Removed device never processed its removal (offline): still rejects.
    assert!(a2.open(&after).is_err(), "[{}] removed (offline) device decrypted", B::NAME);
    assert_eq!(a1.open(&after).unwrap(), b"after removal");

    // LIMITATION (documented, not a defect): plaintext already decrypted
    // before removal remains on the removed device.
    assert_eq!(kept_by_a2, b"before removal");
}

/// §9: a membership change moves to a new epoch with a new authenticator;
/// stale state from the old epoch cannot decrypt new-epoch messages; a
/// removed member restoring a pre-removal snapshot does not regain access.
pub fn epoch_rotation_and_stale_state<B: Backend>() {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    let mut a2 = add_device(&mut a1, &mut [&mut b1], "a/2");

    let epoch_n = B::epoch(&b1.group);
    let auth_n = B::epoch_authenticator(&b1.group);
    let b1_at_n = B::snapshot(&b1.device, &mut b1.group);
    let a2_before_removal = B::snapshot(&a2.device, &mut a2.group);

    remove_device(&mut a1, &mut [&mut b1], "a/2");
    assert_eq!(B::epoch(&b1.group), epoch_n + 1);
    assert_ne!(B::epoch_authenticator(&b1.group), auth_n, "[{}] epoch secrets did not change", B::NAME);

    let new_epoch_msg = a1.send(b"epoch n+1");
    assert_eq!(b1.open(&new_epoch_msg).unwrap(), b"epoch n+1");

    // Stale state of a still-valid member (wrong epoch): reject.
    let (stale_dev, mut stale_group) = B::restore(&b1_at_n);
    assert_eq!(B::epoch(&stale_group), epoch_n);
    assert!(
        B::decrypt(&stale_dev, &mut stale_group, &new_epoch_msg).is_err(),
        "[{}] stale epoch-N state decrypted an epoch-N+1 message",
        B::NAME
    );

    // Removed member with pre-removal state: reject.
    let (old_a2, mut old_a2_group) = B::restore(&a2_before_removal);
    assert!(
        B::decrypt(&old_a2, &mut old_a2_group, &new_epoch_msg).is_err(),
        "[{}] removed member regained access with stale state",
        B::NAME
    );
}

pub fn replay_is_rejected<B: Backend>() {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    let ct = b1.send(b"once");
    assert_eq!(a1.open(&ct).unwrap(), b"once");
    assert!(a1.open(&ct).is_err(), "[{}] replay accepted", B::NAME);
}

pub fn tamper_positions(len: usize) -> Vec<usize> {
    (0..len).step_by(3).chain([len - 1]).collect()
}

/// Integrity: flips one bit at many positions across the whole message
/// (framing, header, authenticated data, sender data, ciphertext, tag).
/// Every variant must be rejected. Each attempt runs on a fresh copy of the
/// receiver's state so one attempt cannot influence the next.
pub fn tampering_is_rejected<B: Backend>() {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    let ct = b1.send(b"integrity matters");
    let receiver = B::snapshot(&a1.device, &mut a1.group);
    for pos in tamper_positions(ct.len()) {
        let (dev, mut group) = B::restore(&receiver);
        let mut forged = ct.clone();
        forged[pos] ^= 0x01;
        if let Ok(pt) = B::decrypt(&dev, &mut group, &forged) {
            panic!("[{}] tampered byte {pos} accepted, plaintext {pt:?}", B::NAME);
        }
    }
    // The untouched message still decrypts on the original state.
    assert_eq!(a1.open(&ct).unwrap(), b"integrity matters");
}

/// Robustness (observation, Prompt 05 finding): after a *rejected* forgery,
/// can the receiver still decrypt the genuine message? If not, whoever can
/// inject a forged copy before the real one (the delivery service, or a
/// member) can make that message undecryptable: a denial of service, not a
/// confidentiality or integrity break. Returns the positions that poisoned
/// the state and the error the genuine message then produced.
pub fn rejected_forgery_poisoning<B: Backend>() -> (usize, Vec<usize>, Option<String>) {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    let ct = b1.send(b"genuine");
    let receiver = B::snapshot(&a1.device, &mut a1.group);
    let (mut poisoned, mut first_error) = (vec![], None);
    for pos in tamper_positions(ct.len()) {
        let (dev, mut group) = B::restore(&receiver);
        let mut forged = ct.clone();
        forged[pos] ^= 0x01;
        assert!(B::decrypt(&dev, &mut group, &forged).is_err());
        match B::decrypt(&dev, &mut group, &ct) {
            Ok(pt) => assert_eq!(pt, b"genuine"),
            Err(e) => {
                poisoned.push(pos);
                first_error.get_or_insert(e);
            }
        }
    }
    (ct.len(), poisoned, first_error)
}

pub fn outsider_is_rejected<B: Backend>() {
    let mut a1 = Member::<B>::founder("a/1");
    let mut _b1 = add_device(&mut a1, &mut [], "b/1");
    let mut outsider = Member::<B>::founder("mallory/1");
    let ct = a1.send(b"private");
    assert!(outsider.open(&ct).is_err(), "[{}] outsider decrypted", B::NAME);
}

/// §19: state survives a simulated restart and the conversation continues
/// in both directions.
pub fn persistence_round_trip<B: Backend>() {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    let first = a1.send(b"before restart");
    assert_eq!(b1.open(&first).unwrap(), b"before restart");

    let (device, group) = B::restore(&B::snapshot(&b1.device, &mut b1.group));
    let mut b1 = Member::<B> { label: "b/1".into(), device, group };
    let second = a1.send(b"after restart");
    assert_eq!(b1.open(&second).unwrap(), b"after restart");
    let reply = b1.send(b"reply after restart");
    assert_eq!(a1.open(&reply).unwrap(), b"reply after restart");
}

/// Observation (no single correct answer in RFC 9420): a message from epoch
/// N delivered *after* the receiver merged the commit to N+1. Allowed
/// outcomes: correct plaintext (prior-epoch secrets retained) or rejection.
/// Returns true if it was decrypted.
pub fn late_message_across_epoch<B: Backend>() -> bool {
    let mut a1 = Member::<B>::founder("a/1");
    let mut b1 = add_device(&mut a1, &mut [], "b/1");
    let late = b1.send(b"sent in epoch n");
    let update = B::update(&b1.device, &mut b1.group);
    a1.apply(&update);
    match a1.open(&late) {
        Ok(pt) => {
            assert_eq!(pt, b"sent in epoch n", "[{}] wrong plaintext for late message", B::NAME);
            true
        }
        Err(_) => false,
    }
}

/// Generates one `#[test]` per scenario for a backend, native and wasm32.
#[macro_export]
macro_rules! scenario_tests {
    ($backend:ty) => {
        macro_rules! t {
            ($name:ident) => {
                #[cfg_attr(not(target_arch = "wasm32"), test)]
                #[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
                fn $name() {
                    $crate::scenarios::$name::<$backend>();
                }
            };
        }
        t!(device_lifecycle);
        t!(six_device_couple);
        t!(revocation);
        t!(epoch_rotation_and_stale_state);
        t!(replay_is_rejected);
        t!(tampering_is_rejected);
        t!(outsider_is_rejected);
        t!(persistence_round_trip);

        #[cfg_attr(not(target_arch = "wasm32"), test)]
        #[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
        fn rejected_forgery_poisoning_is_measured() {
            let (len, poisoned, err) = $crate::scenarios::rejected_forgery_poisoning::<$backend>();
            let err: String = err.unwrap_or_default().chars().take(240).collect();
            println!(
                "OBSERVATION {} rejected_forgery_poisoning message_len={len} poisoned_positions={} of {} first={:?} error={err}",
                <$backend as $crate::Backend>::NAME,
                poisoned.len(),
                $crate::scenarios::tamper_positions(len).len(),
                &poisoned[..poisoned.len().min(12)],
            );
        }

        #[cfg_attr(not(target_arch = "wasm32"), test)]
        #[cfg_attr(target_arch = "wasm32", wasm_bindgen_test::wasm_bindgen_test)]
        fn late_message_across_epoch_is_decrypted_or_rejected() {
            let decrypted = $crate::scenarios::late_message_across_epoch::<$backend>();
            // Recorded in the CI log for the comparison document.
            println!("OBSERVATION {} late_message_across_epoch decrypted={decrypted}", <$backend as $crate::Backend>::NAME);
        }
    };
}
