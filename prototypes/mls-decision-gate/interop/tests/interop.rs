//! EXPERIMENTAL: one MLS group whose members run different implementations.
//! Only RFC 9420 wire bytes cross between them. Success means both
//! implementations agree on the group state (equal epoch authenticators),
//! not that either is secure.

use backend_mlsrs::MlsRs;
use backend_openmls::OpenMls;
use harness::Backend;

#[test]
fn openmls_group_admits_an_mls_rs_device() {
    let alice = OpenMls::new_device("a/openmls");
    let mut ga = OpenMls::create_group(&alice);
    let bob = MlsRs::new_device("b/mls-rs");

    let (_commit, welcome) = OpenMls::add(&alice, &mut ga, &[MlsRs::key_package(&bob)]);
    let mut gb = MlsRs::join(&bob, &welcome);

    assert_eq!(OpenMls::roster(&ga), MlsRs::roster(&gb));
    assert_eq!(OpenMls::epoch(&ga), MlsRs::epoch(&gb));
    assert_eq!(OpenMls::epoch_authenticator(&ga), MlsRs::epoch_authenticator(&gb));

    let ct = OpenMls::encrypt(&alice, &mut ga, b"hello from openmls");
    assert_eq!(MlsRs::decrypt(&bob, &mut gb, &ct).unwrap(), b"hello from openmls");
    let ct = MlsRs::encrypt(&bob, &mut gb, b"hello from mls-rs");
    assert_eq!(OpenMls::decrypt(&alice, &mut ga, &ct).unwrap(), b"hello from mls-rs");

    // A commit made by mls-rs is applied by OpenMLS; states stay equal.
    let update = MlsRs::update(&bob, &mut gb);
    OpenMls::process_commit(&alice, &mut ga, &update).unwrap();
    assert_eq!(OpenMls::epoch_authenticator(&ga), MlsRs::epoch_authenticator(&gb));
}

#[test]
fn mls_rs_group_admits_an_openmls_device() {
    let bob = MlsRs::new_device("b/mls-rs");
    let mut gb = MlsRs::create_group(&bob);
    let alice = OpenMls::new_device("a/openmls");

    let (_commit, welcome) = MlsRs::add(&bob, &mut gb, &[OpenMls::key_package(&alice)]);
    let mut ga = OpenMls::join(&alice, &welcome);
    assert_eq!(OpenMls::epoch_authenticator(&ga), MlsRs::epoch_authenticator(&gb));

    let ct = MlsRs::encrypt(&bob, &mut gb, b"ping");
    assert_eq!(OpenMls::decrypt(&alice, &mut ga, &ct).unwrap(), b"ping");

    // A removal committed by OpenMLS is applied by mls-rs.
    let carol = MlsRs::new_device("c/mls-rs");
    let (add, welcome) = MlsRs::add(&bob, &mut gb, &[MlsRs::key_package(&carol)]);
    OpenMls::process_commit(&alice, &mut ga, &add).unwrap();
    let mut gc = MlsRs::join(&carol, &welcome);
    let remove = OpenMls::remove(&alice, &mut ga, "c/mls-rs");
    MlsRs::process_commit(&bob, &mut gb, &remove).unwrap();
    assert_eq!(OpenMls::epoch_authenticator(&ga), MlsRs::epoch_authenticator(&gb));
    let after = OpenMls::encrypt(&alice, &mut ga, b"carol removed");
    assert_eq!(MlsRs::decrypt(&bob, &mut gb, &after).unwrap(), b"carol removed");
    assert!(MlsRs::decrypt(&carol, &mut gc, &after).is_err());
}
