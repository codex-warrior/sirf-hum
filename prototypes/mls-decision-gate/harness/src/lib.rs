//! EXPERIMENTAL — NOT PRODUCTION CODE. Not part of the Sirf Hum app.
//!
//! A backend-neutral harness so OpenMLS and mls-rs run the *same* scenarios
//! (Prompt 05 decision gate). Everything that crosses a device boundary is
//! bytes, exactly as it would cross an untrusted delivery service. No
//! cryptography is implemented here; backends delegate to their library.

pub mod bench;
pub mod scenarios;

pub type Bytes = Vec<u8>;

/// One MLS implementation, driven through the operations Sirf Hum needs.
///
/// Conventions:
/// - The device that issues a commit applies it locally before returning
///   (as after the delivery service accepted it).
/// - `decrypt` must return `Err` for anything it cannot authenticate; it must
///   never return attacker-chosen or partially decrypted plaintext.
pub trait Backend {
    const NAME: &'static str;
    type Device;
    type Group;

    fn new_device(label: &str) -> Self::Device;
    /// A fresh single-use KeyPackage as an MLSMessage (RFC 9420 wire format).
    fn key_package(device: &Self::Device) -> Bytes;
    fn create_group(device: &Self::Device) -> Self::Group;
    /// Commits Add for every KeyPackage; returns (commit, welcome).
    fn add(device: &Self::Device, group: &mut Self::Group, key_packages: &[Bytes]) -> (Bytes, Bytes);
    fn join(device: &Self::Device, welcome: &[u8]) -> Self::Group;
    /// Commits Remove of the member whose credential label is `label`.
    fn remove(device: &Self::Device, group: &mut Self::Group, label: &str) -> Bytes;
    /// Commits an empty-proposal commit with a path (a self update).
    fn update(device: &Self::Device, group: &mut Self::Group) -> Bytes;
    fn process_commit(device: &Self::Device, group: &mut Self::Group, commit: &[u8]) -> Result<(), String>;
    fn encrypt(device: &Self::Device, group: &mut Self::Group, plaintext: &[u8]) -> Bytes;
    fn decrypt(device: &Self::Device, group: &mut Self::Group, ciphertext: &[u8]) -> Result<Bytes, String>;

    fn roster(group: &Self::Group) -> Vec<String>;
    fn epoch(group: &Self::Group) -> u64;
    fn epoch_authenticator(group: &Self::Group) -> Bytes;

    /// Serializes everything a device needs to resume this group after a
    /// restart (TEST ONLY: contains key material; production state goes
    /// through the encrypted local store defined in Prompt 05 docs).
    fn snapshot(device: &Self::Device, group: &mut Self::Group) -> Bytes;
    fn restore(snapshot: &[u8]) -> (Self::Device, Self::Group);
}
