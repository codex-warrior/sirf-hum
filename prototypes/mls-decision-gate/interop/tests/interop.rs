//! EXPERIMENTAL: one MLS group whose members run different implementations.
//! Only RFC 9420 wire bytes cross between them. Each step's outcome is
//! printed (INTEROP lines) so one CI run records every result; the test then
//! fails if any step failed. Success would mean both implementations agree
//! on group state and can read each other's messages, not that either is
//! secure.

use backend_mlsrs::MlsRs;
use backend_openmls::OpenMls;
use harness::Backend;

struct Steps(Vec<(&'static str, Result<(), String>)>);

impl Steps {
    fn record(&mut self, name: &'static str, r: Result<(), String>) {
        println!("INTEROP {name}: {}", match &r { Ok(()) => "ok".into(), Err(e) => format!("FAILED {e}") });
        self.0.push((name, r));
    }
    fn finish(self) {
        let failed: Vec<_> = self.0.iter().filter(|(_, r)| r.is_err()).map(|(n, _)| *n).collect();
        assert!(failed.is_empty(), "interop steps failed: {failed:?}");
    }
}

fn eq(a: &[u8], b: &[u8]) -> Result<(), String> {
    if a == b { Ok(()) } else { Err("values differ".into()) }
}

fn opened(r: Result<Vec<u8>, String>, want: &[u8]) -> Result<(), String> {
    r.and_then(|pt| eq(&pt, want))
}

#[test]
fn openmls_group_admits_an_mls_rs_device() {
    let mut s = Steps(vec![]);
    let alice = OpenMls::new_device("a/openmls");
    let mut ga = OpenMls::create_group(&alice);
    let bob = MlsRs::new_device("b/mls-rs");

    let (_commit, welcome) = OpenMls::add(&alice, &mut ga, &[MlsRs::key_package(&bob)]);
    let mut gb = MlsRs::join(&bob, &welcome);
    s.record("om->rs welcome join + roster", eq(OpenMls::roster(&ga).join(",").as_bytes(), MlsRs::roster(&gb).join(",").as_bytes()));
    s.record("om->rs epoch authenticator after join", eq(&OpenMls::epoch_authenticator(&ga), &MlsRs::epoch_authenticator(&gb)));

    let ct = OpenMls::encrypt(&alice, &mut ga, b"hello from openmls");
    s.record("om->rs application message", opened(MlsRs::decrypt(&bob, &mut gb, &ct), b"hello from openmls"));
    let ct = MlsRs::encrypt(&bob, &mut gb, b"hello from mls-rs");
    s.record("rs->om application message", opened(OpenMls::decrypt(&alice, &mut ga, &ct), b"hello from mls-rs"));

    let update = MlsRs::update(&bob, &mut gb);
    s.record("rs commit (update) applied by openmls", OpenMls::process_commit(&alice, &mut ga, &update));
    s.record("epoch authenticator after rs commit", eq(&OpenMls::epoch_authenticator(&ga), &MlsRs::epoch_authenticator(&gb)));

    let ct = OpenMls::encrypt(&alice, &mut ga, b"after update");
    s.record("om->rs application message after update", opened(MlsRs::decrypt(&bob, &mut gb, &ct), b"after update"));
    s.finish();
}

#[test]
fn mls_rs_group_admits_an_openmls_device() {
    let mut s = Steps(vec![]);
    let bob = MlsRs::new_device("b/mls-rs");
    let mut gb = MlsRs::create_group(&bob);
    let alice = OpenMls::new_device("a/openmls");

    let (_commit, welcome) = MlsRs::add(&bob, &mut gb, &[OpenMls::key_package(&alice)]);
    let mut ga = OpenMls::join(&alice, &welcome);
    s.record("rs->om welcome join, epoch authenticator", eq(&OpenMls::epoch_authenticator(&ga), &MlsRs::epoch_authenticator(&gb)));

    let ct = MlsRs::encrypt(&bob, &mut gb, b"ping");
    s.record("rs->om application message", opened(OpenMls::decrypt(&alice, &mut ga, &ct), b"ping"));
    let ct = OpenMls::encrypt(&alice, &mut ga, b"pong");
    s.record("om->rs application message", opened(MlsRs::decrypt(&bob, &mut gb, &ct), b"pong"));

    let carol = MlsRs::new_device("c/mls-rs");
    let (add, welcome) = MlsRs::add(&bob, &mut gb, &[MlsRs::key_package(&carol)]);
    s.record("rs commit (add) applied by openmls", OpenMls::process_commit(&alice, &mut ga, &add));
    let mut gc = MlsRs::join(&carol, &welcome);
    let remove = OpenMls::remove(&alice, &mut ga, "c/mls-rs");
    s.record("om commit (remove) applied by mls-rs", MlsRs::process_commit(&bob, &mut gb, &remove));
    s.record("epoch authenticator after om commit", eq(&OpenMls::epoch_authenticator(&ga), &MlsRs::epoch_authenticator(&gb)));
    let after = OpenMls::encrypt(&alice, &mut ga, b"carol removed");
    s.record("om->rs message after remove", opened(MlsRs::decrypt(&bob, &mut gb, &after), b"carol removed"));
    s.record("removed rs device rejects later message", match MlsRs::decrypt(&carol, &mut gc, &after) {
        Err(_) => Ok(()),
        Ok(_) => Err("removed device decrypted".into()),
    });
    s.finish();
}
