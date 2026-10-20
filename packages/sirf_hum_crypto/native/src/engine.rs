//! The crypto core (Prompt 06 Parts 1, 2, 5). One `CryptoCore` = one local
//! device. Thin by design: MLS is OpenMLS 0.9.1; this file adds only
//! - the identity/credential policy (identity.rs) applied *before* merges,
//! - size limits before parsing (limits.rs),
//! - checkpoint/rollback + atomic sealed persistence around every
//!   state-changing operation (`transact`),
//! - safe error mapping (error.rs).
//!
//! It never logs, never talks to the network, and never depends on Firebase.

use std::collections::{BTreeMap, HashMap};
use std::time::{SystemTime, UNIX_EPOCH};

use chacha20poly1305::aead::{rand_core::RngCore, OsRng};
use openmls::prelude::{tls_codec::*, *};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::OpenMlsRustCrypto;
use openmls_traits::crypto::OpenMlsCrypto;
use openmls_traits::types::SignatureScheme;
use zeroize::{Zeroize, Zeroizing};

use crate::error::from_process_error;
use crate::identity::{
    device_approval_payload, device_id_of, device_proof_payload, put, recovery_approval_payload,
    recovery_registration_payload, reset_cancel_payload, revocation_payload, AccountId,
    DeviceCertificate, DeviceId, PersonKey, ProofPurpose, Reader, RevocationReason, DEVICE_ID_LEN,
};
use crate::keystore::{KeyEncryptionKeyProvider, KEK_LEN};
use crate::limits::{self, *};
use crate::record::{self, RecordKind};
use crate::recovery::RecoverySeed;
use crate::store::CryptoStore;
use crate::trust::{TrustPolicy, TrustSource};
use crate::{CoreError, CoreResult};

mod conversation;
mod media;
#[cfg(test)]
mod trust_tests;
pub use conversation::{
    LocalMessage, MessageDirection, MessageState, Received, Sent, StagedCommit,
};
pub use media::{
    media_ciphertext_len, media_object_file_name, MediaClass, SentMedia, MEDIA_CHUNK_BYTES,
    MEDIA_HEADER_LEN, MEDIA_ID_LEN, MEDIA_REF_LEN, MEDIA_VIEW_LEN,
};

/// RFC 9420 ciphersuite 0x0001 (D-042). Fixed per group; changes go through
/// MLS ReInit (D-061).
pub const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;
/// Implementation identifier recorded for crypto agility (D-061).
pub const IMPLEMENTATION: &str = "openmls/0.9.1";

const REC_IDENTITY: &str = "identity_secret";
const REC_STATE: &str = "mls_state";
const REC_METADATA: &str = "public_metadata";
const REC_TRUST_EPOCH: &str = "trust_epoch";
const IDENTITY_VERSION: u16 = 1;
/// v1 (Prompt 06): person-key trust. v2 (Prompt 10, D-085): device-pinned
/// trust policy + staged-commit bookkeeping. v1 still loads.
const STATE_VERSION_V1: u16 = 1;
const STATE_VERSION: u16 = 2;

/// Public, shareable identity of this device.
#[derive(Clone, PartialEq, Eq)]
pub struct PublicIdentity {
    pub device_id: DeviceId,
    pub person_key: PersonKey,
    /// Encoded device certificate (public).
    pub certificate: Vec<u8>,
}

impl core::fmt::Debug for PublicIdentity {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("PublicIdentity(<redacted>)")
    }
}

/// Result of processing one incoming MLS message.
pub enum Incoming {
    /// Decrypted application data (zeroized on drop).
    Application(Zeroizing<Vec<u8>>),
    /// A commit was validated and applied.
    CommitApplied { epoch: u64 },
    /// A commit removed this device from the group; local group state deleted.
    RemovedFromGroup,
}

// Never print decrypted content.
impl core::fmt::Debug for Incoming {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Incoming::Application(_) => f.write_str("Application(<redacted>)"),
            Incoming::CommitApplied { epoch } => write!(f, "CommitApplied {{ epoch: {epoch} }}"),
            Incoming::RemovedFromGroup => f.write_str("RemovedFromGroup"),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RosterEntry {
    pub device_id: DeviceId,
    pub person_key: PersonKey,
}

/// A freshly created recovery key (D-076). `secret` is shown to the user
/// once and then dropped (it is wiped on drop); only `public_key` and the
/// registration signature go to the server.
pub struct RecoveryKeyBundle {
    pub secret: Zeroizing<String>,
    pub public_key: [u8; 32],
    pub registration_signature: Vec<u8>,
}

impl core::fmt::Debug for RecoveryKeyBundle {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("RecoveryKeyBundle(<redacted>)")
    }
}

/// A recovery approval for this device, signed with the user's recovery key.
#[derive(Debug)]
pub struct RecoveryApproval {
    pub signature: Vec<u8>,
    pub recovery_public_key: [u8; 32],
}

/// Expected routing of an ABI v5 message or commit (D-089).
pub(crate) struct Routing {
    pub(crate) group_id: Vec<u8>,
    pub(crate) epoch: u64,
    pub(crate) sender: DeviceId,
    /// `Some` for an application message (its exact AAD); `None` for a commit.
    pub(crate) expected_aad: Option<Vec<u8>>,
}

pub struct AddResult {
    pub commit: Vec<u8>,
    pub welcome: Vec<u8>,
}

impl core::fmt::Debug for AddResult {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("AddResult(<redacted>)")
    }
}

struct Identity {
    account: AccountId,
    person_private: Zeroizing<Vec<u8>>,
    person_key: PersonKey,
    device_private: Zeroizing<Vec<u8>>,
    device_public: Vec<u8>,
    certificate: DeviceCertificate,
}

impl Identity {
    fn signer(&self) -> SignatureKeyPair {
        SignatureKeyPair::from_raw(
            SignatureScheme::ED25519,
            self.device_private.to_vec(),
            self.device_public.clone(),
        )
    }
    fn credential_with_key(&self) -> CredentialWithKey {
        CredentialWithKey {
            credential: self.certificate.to_credential(),
            signature_key: self.device_public.clone().into(),
        }
    }
}

struct State {
    provider: OpenMlsRustCrypto,
    groups: BTreeMap<Vec<u8>, MlsGroup>,
    trust: TrustPolicy,
    /// Per group, the epoch from which this device last confirmed a staged
    /// commit (D-087): makes a duplicate confirm idempotent.
    confirmed: BTreeMap<Vec<u8>, u64>,
}

impl State {
    fn empty() -> Self {
        Self {
            provider: OpenMlsRustCrypto::default(),
            groups: BTreeMap::new(),
            trust: TrustPolicy::default(),
            confirmed: BTreeMap::new(),
        }
    }
}

/// In-memory copy of everything `transact` may change. Wiped on drop.
struct Checkpoint {
    values: HashMap<Vec<u8>, Vec<u8>>,
    group_ids: Vec<Vec<u8>>,
    trust: TrustPolicy,
    confirmed: BTreeMap<Vec<u8>, u64>,
}

impl Drop for Checkpoint {
    fn drop(&mut self) {
        for v in self.values.values_mut() {
            v.zeroize();
        }
    }
}

pub struct CryptoCore {
    store: Box<dyn CryptoStore>,
    kek: Zeroizing<[u8; KEK_LEN]>,
    production_secure_keys: bool,
    identity: Option<Identity>,
    state: State,
    /// Set if a rollback failed; every later call returns `RollbackFailure`.
    poisoned: bool,
}

/// Sender-ratchet out-of-order tolerance (D-091): messages within one epoch
/// may arrive up to 32 generations late. The forward distance stays at the
/// OpenMLS default.
const OUT_OF_ORDER_TOLERANCE: u32 = 32;
const MAX_FORWARD_DISTANCE: u32 = 1000;

fn ratchet() -> SenderRatchetConfiguration {
    SenderRatchetConfiguration::new(OUT_OF_ORDER_TOLERANCE, MAX_FORWARD_DISTANCE)
}

/// Every PrivateMessage this device sends (application and handshake) is
/// zero-padded so its encrypted content is a multiple of this many bytes
/// (RFC 9420 §6.3.1, OpenMLS `padding_size`; receivers strip it). The
/// server then learns a message's length only to within 256 bytes, not
/// exactly (Prompt 17, D-126). OpenMLS's default is 0: no padding.
const PADDING_BLOCK: usize = 256;

fn join_config() -> MlsGroupJoinConfig {
    // Past-epoch window stays at the OpenMLS default (0): D-091 makes it
    // safe for messaging by processing each epoch's messages before its
    // commit. Late messages fail closed (StaleEpoch).
    MlsGroupJoinConfig::builder()
        .use_ratchet_tree_extension(true)
        .sender_ratchet_configuration(ratchet())
        .padding_size(PADDING_BLOCK)
        .build()
}

fn create_config() -> MlsGroupCreateConfig {
    MlsGroupCreateConfig::builder()
        .ciphersuite(CIPHERSUITE)
        .use_ratchet_tree_extension(true)
        .sender_ratchet_configuration(ratchet())
        .padding_size(PADDING_BLOCK)
        .build()
}

fn parse(bytes: &[u8]) -> CoreResult<MlsMessageIn> {
    MlsMessageIn::tls_deserialize_exact(bytes).map_err(|_| CoreError::MalformedMessage)
}

fn ser(msg: &MlsMessageOut) -> CoreResult<Vec<u8>> {
    msg.to_bytes().map_err(|_| CoreError::InternalCryptoFailure)
}

impl CryptoCore {
    /// Opens (and if present, restores) the core from `store`, sealing with
    /// the KEK from `keys`.
    pub fn open(
        store: Box<dyn CryptoStore>,
        keys: &dyn KeyEncryptionKeyProvider,
    ) -> CoreResult<Self> {
        let mut core = Self {
            store,
            kek: keys.key_encryption_key()?,
            production_secure_keys: keys.is_production_secure(),
            identity: None,
            state: State::empty(),
            poisoned: false,
        };
        core.load()?;
        Ok(core)
    }

    /// True only when the store key came from the platform keystore adapter
    /// (D-066). This describes the key source; it is not a claim that the
    /// system is production E2EE.
    pub fn uses_production_secure_keys(&self) -> bool {
        self.production_secure_keys
    }

    fn guard(&self) -> CoreResult<()> {
        if self.poisoned {
            Err(CoreError::RollbackFailure)
        } else {
            Ok(())
        }
    }

    fn identity(&self) -> CoreResult<&Identity> {
        self.identity.as_ref().ok_or(CoreError::IdentityState)
    }

    // ---------------------------------------------------------------- identity

    pub fn create_identity(&mut self, account: AccountId) -> CoreResult<PublicIdentity> {
        self.guard()?;
        if self.identity.is_some() {
            return Err(CoreError::IdentityState);
        }
        let crypto = self.state.provider.crypto();
        let (person_private, person_public) = crypto
            .signature_key_gen(SignatureScheme::ED25519)
            .map_err(|_| CoreError::InternalCryptoFailure)?;
        let (device_private, device_public) = crypto
            .signature_key_gen(SignatureScheme::ED25519)
            .map_err(|_| CoreError::InternalCryptoFailure)?;
        let mut id = [0u8; DEVICE_ID_LEN];
        OsRng.fill_bytes(&mut id);
        let person_key =
            PersonKey::from_slice(&person_public).map_err(|_| CoreError::InternalCryptoFailure)?;
        let issued_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let certificate = DeviceCertificate::issue(
            crypto,
            person_key.clone(),
            &person_private,
            DeviceId(id),
            device_public.clone(),
            issued_at,
        )?;
        let identity = Identity {
            account,
            person_private: Zeroizing::new(person_private),
            person_key: person_key.clone(),
            device_private: Zeroizing::new(device_private),
            device_public,
            certificate,
        };
        // Identity first (one atomic record), then trust in the state record.
        self.store
            .put(REC_IDENTITY, &self.seal_identity(&identity)?)?;
        self.store
            .put(REC_METADATA, &self.seal_metadata(&identity)?)?;
        let public = PublicIdentity {
            device_id: identity.certificate.device_id,
            person_key: identity.person_key.clone(),
            certificate: identity.certificate.encode(),
        };
        let own_certificate = public.certificate.clone();
        self.identity = Some(identity);
        self.transact(|core| {
            let State {
                provider, trust, ..
            } = &mut core.state;
            trust.anchor(person_key)?;
            trust.trust_certificate(provider.crypto(), &own_certificate, TrustSource::Own, None)?;
            Ok(())
        })?;
        Ok(public)
    }

    pub fn public_identity(&self) -> CoreResult<PublicIdentity> {
        self.guard()?;
        let id = self.identity()?;
        Ok(PublicIdentity {
            device_id: id.certificate.device_id,
            person_key: id.person_key.clone(),
            certificate: id.certificate.encode(),
        })
    }

    /// Fails with `AccountMismatch` unless the local identity belongs to
    /// `account` (`IdentityState` if there is no identity). Callers check this
    /// on every open so one account's identity is never used for another
    /// (DEVICE-IDENTITY.md, account switching).
    pub fn check_account(&self, account: &AccountId) -> CoreResult<()> {
        self.guard()?;
        if self.identity()?.account != *account {
            return Err(CoreError::AccountMismatch);
        }
        Ok(())
    }

    /// Signs a server challenge with the device signature key to prove
    /// possession (D-070). The core builds the payload itself from its own
    /// account and certificate, so callers cannot make it sign arbitrary
    /// bytes. No state changes; the private key never leaves Rust.
    pub fn device_proof(&self, purpose: ProofPurpose, challenge: &[u8]) -> CoreResult<Vec<u8>> {
        self.guard()?;
        let id = self.identity()?;
        let payload = device_proof_payload(
            purpose,
            &id.account,
            &id.certificate.device_id,
            &id.certificate.encode(),
            challenge,
        )?;
        self.state
            .provider
            .crypto()
            .sign(SignatureScheme::ED25519, &payload, &id.device_private)
            .map_err(|_| CoreError::InternalCryptoFailure)
    }

    // ------------------------------------------------- multi-device (D-075)

    /// Approves another device of this account: signs the approval statement
    /// (identity::device_approval_payload) with this device's PIK, and trusts
    /// the new device's person key locally so this device accepts it in MLS.
    /// The server decides whether the approval counts (approver active,
    /// challenge valid, not expired); the core only signs what the user
    /// approved.
    pub fn approve_device(
        &mut self,
        new_certificate: &[u8],
        challenge: &[u8],
        expires_at_unix: u64,
    ) -> CoreResult<Vec<u8>> {
        self.guard()?;
        let new = DeviceCertificate::decode(new_certificate)?;
        new.verify_signature(self.state.provider.crypto())?;
        let id = self.identity()?;
        if new.device_id == id.certificate.device_id || new.person_key == id.person_key {
            return Err(CoreError::InvalidInput);
        }
        if self.state.trust.revoked_devices.contains(&new.device_id)
            || self.state.trust.revoked_people.contains(&new.person_key)
        {
            return Err(CoreError::UnauthorizedDevice);
        }
        let payload = device_approval_payload(
            &id.account,
            &id.certificate.encode(),
            new_certificate,
            challenge,
            expires_at_unix,
        )?;
        let signature = self
            .state
            .provider
            .crypto()
            .sign(SignatureScheme::ED25519, &payload, &id.person_private)
            .map_err(|_| CoreError::InternalCryptoFailure)?;
        // D-085: trust the exact approved certificate (pinning its PIK),
        // never the PIK on its own.
        let approved = new_certificate.to_vec();
        self.transact(|core| {
            let State {
                provider, trust, ..
            } = &mut core.state;
            trust.trust_certificate(provider.crypto(), &approved, TrustSource::Approved, None)?;
            Ok(())
        })?;
        Ok(signature)
    }

    /// Creates a new recovery key and signs its registration with this
    /// device's PIK. The secret leaves the core exactly once, for display.
    pub fn create_recovery_key(
        &self,
        challenge: &[u8],
        expires_at_unix: u64,
    ) -> CoreResult<RecoveryKeyBundle> {
        self.guard()?;
        let id = self.identity()?;
        let crypto = self.state.provider.crypto();
        let seed = RecoverySeed::generate();
        let public_key = seed.public_key();
        let payload = recovery_registration_payload(
            &id.account,
            &id.certificate.encode(),
            &public_key,
            challenge,
            expires_at_unix,
        )?;
        let registration_signature = crypto
            .sign(SignatureScheme::ED25519, &payload, &id.person_private)
            .map_err(|_| CoreError::InternalCryptoFailure)?;
        Ok(RecoveryKeyBundle {
            secret: seed.encode(crypto)?,
            public_key,
            registration_signature,
        })
    }

    /// Signs a recovery approval for THIS device with the user-typed recovery
    /// key. The decoded seed is wiped when this returns.
    pub fn recovery_approval(
        &self,
        recovery_key: &str,
        challenge: &[u8],
        expires_at_unix: u64,
    ) -> CoreResult<RecoveryApproval> {
        self.guard()?;
        let id = self.identity()?;
        let crypto = self.state.provider.crypto();
        let seed = RecoverySeed::decode(crypto, recovery_key)?;
        let recovery_public_key = seed.public_key();
        let payload = recovery_approval_payload(
            &id.account,
            &recovery_public_key,
            &id.certificate.encode(),
            challenge,
            expires_at_unix,
        )?;
        let signature = crypto
            .sign(SignatureScheme::ED25519, &payload, seed.seed())
            .map_err(|_| CoreError::InternalCryptoFailure)?;
        Ok(RecoveryApproval {
            signature,
            recovery_public_key,
        })
    }

    /// Signs a revocation of `revoked_certificate` (another device of this
    /// account, or this device itself) with this device's PIK (D-081). The
    /// server decides whether this device may revoke (it must be active).
    pub fn sign_revocation(
        &self,
        revoked_certificate: &[u8],
        reason: RevocationReason,
        challenge: &[u8],
        expires_at_unix: u64,
    ) -> CoreResult<Vec<u8>> {
        self.guard()?;
        DeviceCertificate::decode(revoked_certificate)?
            .verify_signature(self.state.provider.crypto())?;
        let id = self.identity()?;
        let payload = revocation_payload(
            &id.account,
            &id.certificate.encode(),
            revoked_certificate,
            reason,
            challenge,
            expires_at_unix,
        )?;
        self.state
            .provider
            .crypto()
            .sign(SignatureScheme::ED25519, &payload, &id.person_private)
            .map_err(|_| CoreError::InternalCryptoFailure)
    }

    /// Signs a cancellation of a pending identity reset (D-082): proof that
    /// this (trusted) device still exists and objects.
    pub fn sign_reset_cancellation(
        &self,
        challenge: &[u8],
        expires_at_unix: u64,
    ) -> CoreResult<Vec<u8>> {
        self.guard()?;
        let id = self.identity()?;
        let payload = reset_cancel_payload(
            &id.account,
            &id.certificate.encode(),
            challenge,
            expires_at_unix,
        )?;
        self.state
            .provider
            .crypto()
            .sign(SignatureScheme::ED25519, &payload, &id.person_private)
            .map_err(|_| CoreError::InternalCryptoFailure)
    }

    /// Records the server's account trust epoch (D-083). Epochs only grow:
    /// an epoch below the highest this device has seen means a stale or
    /// rolled-back server view, so this fails with `TrustStateStale` and
    /// stores nothing. Returns the previously seen epoch (0 if none).
    ///
    /// This protects against stale *server* views. It cannot detect a
    /// rollback of this device's own files (the stored epoch rolls back with
    /// them): that remains open (D-079).
    pub fn observe_trust_epoch(&mut self, epoch: u64) -> CoreResult<u64> {
        self.guard()?;
        let previous = match self.store.get(REC_TRUST_EPOCH)? {
            Some(raw) => {
                let plain = record::open(&self.kek, RecordKind::TrustEpoch, REC_TRUST_EPOCH, &raw)?;
                let bytes: [u8; 8] = plain
                    .as_slice()
                    .try_into()
                    .map_err(|_| CoreError::StateCorruption)?;
                u64::from_be_bytes(bytes)
            }
            None => 0,
        };
        if epoch < previous {
            return Err(CoreError::TrustStateStale);
        }
        if epoch > previous {
            let sealed = record::seal(
                &self.kek,
                RecordKind::TrustEpoch,
                REC_TRUST_EPOCH,
                &epoch.to_be_bytes(),
            )?;
            self.store.put(REC_TRUST_EPOCH, &sealed)?;
        }
        Ok(previous)
    }

    /// Anchors a person key verified out of band (PAIRING-AND-DEVICE-TRUST.md);
    /// the server is never the authority for this. Since D-085 an anchor
    /// roots lineage verification and admits only its own single (pinned)
    /// device; it no longer trusts every certificate the key signs.
    pub fn trust_verified_person_key(&mut self, key: PersonKey) -> CoreResult<()> {
        self.guard()?;
        self.identity()?;
        self.transact(|core| core.state.trust.anchor(key))
    }

    /// Verifies an account's lineage blob (lineage.rs, D-084) and applies it
    /// to the trust policy (D-085). The root's person key must be anchored,
    /// and `trust_epoch` (the server's `accountTrust.trustEpoch`) must not be
    /// older than one already applied for that account. Returns how many
    /// devices of that account are now trusted.
    pub fn trust_lineage(&mut self, blob: &[u8], trust_epoch: u64) -> CoreResult<u32> {
        self.guard()?;
        self.identity()?;
        let outcome = crate::lineage::decode_and_verify(self.state.provider.crypto(), blob)?;
        let account = outcome.account.as_str().to_owned();
        self.transact(|core| {
            core.state.trust.apply_lineage(&outcome, trust_epoch)?;
            Ok(core
                .state
                .trust
                .devices
                .values()
                .filter(|d| d.account.as_deref() == Some(account.as_str()))
                .count() as u32)
        })
    }

    /// Marks a device as revoked: its credentials are rejected from now on,
    /// and so is its person key (D-085). Removing it from groups is a
    /// separate, explicit commit.
    pub fn revoke_device(&mut self, device: DeviceId) -> CoreResult<()> {
        self.guard()?;
        self.identity()?;
        if device == self.identity()?.certificate.device_id {
            return Err(CoreError::InvalidInput);
        }
        self.transact(|core| {
            core.state.trust.revoke(device, None);
            Ok(())
        })
    }

    // ------------------------------------------------------------------ groups

    pub fn key_package(&mut self) -> CoreResult<Vec<u8>> {
        self.guard()?;
        self.transact(|core| {
            let id = core.identity()?;
            let bundle = KeyPackage::builder()
                .build(
                    CIPHERSUITE,
                    &core.state.provider,
                    &id.signer(),
                    id.credential_with_key(),
                )
                .map_err(|_| CoreError::InternalCryptoFailure)?;
            ser(&MlsMessageOut::from(bundle.key_package().clone()))
        })
    }

    pub fn create_group(&mut self) -> CoreResult<Vec<u8>> {
        self.guard()?;
        self.transact(|core| {
            let id = core.identity()?;
            let group = MlsGroup::new(
                &core.state.provider,
                &id.signer(),
                &create_config(),
                id.credential_with_key(),
            )
            .map_err(|_| CoreError::InternalCryptoFailure)?;
            let gid = group.group_id().as_slice().to_vec();
            core.state.groups.insert(gid.clone(), group);
            Ok(gid)
        })
    }

    pub fn add_member(&mut self, group_id: &[u8], key_package: &[u8]) -> CoreResult<AddResult> {
        self.guard()?;
        self.require_no_staged_commit(group_id)?;
        limits::check(key_package.len(), MAX_KEY_PACKAGE_BYTES)?;
        let MlsMessageBodyIn::KeyPackage(kp_in) = parse(key_package)?.extract() else {
            return Err(CoreError::MalformedMessage);
        };
        self.transact(|core| {
            let State {
                provider,
                groups,
                trust,
                ..
            } = &mut core.state;
            let kp = kp_in
                .validate(provider.crypto(), ProtocolVersion::Mls10)
                .map_err(|_| CoreError::InvalidCredential)?;
            let leaf = kp.leaf_node();
            trust.validate(
                provider.crypto(),
                leaf.credential(),
                leaf.signature_key().as_slice(),
            )?;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            if group.members().count() >= MAX_GROUP_MEMBERS {
                return Err(CoreError::Unsupported);
            }
            let signer = core
                .identity
                .as_ref()
                .ok_or(CoreError::IdentityState)?
                .signer();
            let (commit, welcome, _info) = group
                .add_members(provider, &signer, std::slice::from_ref(&kp))
                .map_err(|_| CoreError::ProtocolViolation)?;
            group
                .merge_pending_commit(provider)
                .map_err(|_| CoreError::PersistenceFailure)?;
            Ok(AddResult {
                commit: ser(&commit)?,
                welcome: ser(&welcome)?,
            })
        })
    }

    pub fn remove_member(&mut self, group_id: &[u8], device: DeviceId) -> CoreResult<Vec<u8>> {
        self.guard()?;
        self.require_no_staged_commit(group_id)?;
        if device == self.identity()?.certificate.device_id {
            return Err(CoreError::InvalidInput);
        }
        self.transact(|core| {
            let State {
                provider, groups, ..
            } = &mut core.state;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            let leaf = group
                .members()
                .find(|m| device_id_of(&m.credential) == Some(device))
                .ok_or(CoreError::InvalidInput)?
                .index;
            let signer = core
                .identity
                .as_ref()
                .ok_or(CoreError::IdentityState)?
                .signer();
            let (commit, _w, _i) = group
                .remove_members(provider, &signer, &[leaf])
                .map_err(|_| CoreError::ProtocolViolation)?;
            group
                .merge_pending_commit(provider)
                .map_err(|_| CoreError::PersistenceFailure)?;
            ser(&commit)
        })
    }

    /// Commits a self update (fresh leaf keys: post-compromise healing).
    pub fn self_update(&mut self, group_id: &[u8]) -> CoreResult<Vec<u8>> {
        self.guard()?;
        self.require_no_staged_commit(group_id)?;
        self.transact(|core| {
            let State {
                provider, groups, ..
            } = &mut core.state;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            let signer = core
                .identity
                .as_ref()
                .ok_or(CoreError::IdentityState)?
                .signer();
            let bundle = group
                .self_update(provider, &signer, LeafNodeParameters::default())
                .map_err(|_| CoreError::ProtocolViolation)?;
            group
                .merge_pending_commit(provider)
                .map_err(|_| CoreError::PersistenceFailure)?;
            let (commit, _w, _i) = bundle.into_messages();
            ser(&commit)
        })
    }

    /// Joins a group from a Welcome. Every member's credential is validated
    /// *before* the group is accepted.
    pub fn join(&mut self, welcome: &[u8]) -> CoreResult<Vec<u8>> {
        self.join_with(welcome, None)
    }

    /// [`Self::join`], refusing a Welcome for any group other than
    /// `expected_group` (`EnvelopeMismatch`) or for a group already held.
    pub(crate) fn join_with(
        &mut self,
        welcome: &[u8],
        expected_group: Option<&[u8]>,
    ) -> CoreResult<Vec<u8>> {
        self.guard()?;
        self.identity()?;
        limits::check(welcome.len(), MAX_WELCOME_BYTES)?;
        if expected_group.is_some_and(|g| self.state.groups.contains_key(g)) {
            // Already a member: a second Welcome means nothing.
            return Err(CoreError::InvalidInput);
        }
        let MlsMessageBodyIn::Welcome(welcome) = parse(welcome)?.extract() else {
            return Err(CoreError::MalformedMessage);
        };
        self.transact(|core| {
            let State {
                provider,
                groups,
                trust,
                ..
            } = &mut core.state;
            let staged = StagedWelcome::new_from_welcome(provider, &join_config(), welcome, None)
                .map_err(|_| CoreError::ProtocolViolation)?;
            let mut count = 0usize;
            for member in staged.members() {
                count += 1;
                trust.validate(provider.crypto(), &member.credential, &member.signature_key)?;
            }
            if count > MAX_GROUP_MEMBERS {
                return Err(CoreError::Unsupported);
            }
            if let Some(expected) = expected_group {
                if staged.group_context().group_id().as_slice() != expected {
                    return Err(CoreError::EnvelopeMismatch);
                }
            }
            let group = staged
                .into_group(provider)
                .map_err(|_| CoreError::ProtocolViolation)?;
            let gid = group.group_id().as_slice().to_vec();
            groups.insert(gid.clone(), group);
            Ok(gid)
        })
    }

    // ---------------------------------------------------------------- messages

    pub fn encrypt(&mut self, group_id: &[u8], plaintext: &[u8]) -> CoreResult<Vec<u8>> {
        self.guard()?;
        self.require_no_staged_commit(group_id)?;
        limits::check(plaintext.len(), MAX_PLAINTEXT_BYTES)?;
        self.transact(|core| {
            let State {
                provider, groups, ..
            } = &mut core.state;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            let signer = core
                .identity
                .as_ref()
                .ok_or(CoreError::IdentityState)?
                .signer();
            let out = group
                .create_message(provider, &signer, plaintext)
                .map_err(|_| CoreError::ProtocolViolation)?;
            ser(&out)
        })
    }

    /// Processes one incoming MLS message under checkpoint/rollback: if it is
    /// rejected for *any* reason, local state is exactly as before the call
    /// (D-056), so a forged copy cannot destroy the genuine message.
    pub fn process_incoming(&mut self, message: &[u8]) -> CoreResult<Incoming> {
        self.guard()?;
        self.identity()?;
        limits::check(message.len(), MAX_INCOMING_MESSAGE_BYTES)?;
        self.process_inner(message, None, |_, _| Ok(()))
    }

    /// Shared processing path. With `routing` (ABI v5 messaging), the
    /// message must be for that group and epoch, of the expected kind, from
    /// that sender device, and (for application messages) carry exactly the
    /// expected authenticated data. `after` runs inside the same transaction
    /// (e.g. writing local history), so any failure rolls everything back.
    pub(crate) fn process_inner(
        &mut self,
        message: &[u8],
        routing: Option<&Routing>,
        after: impl FnOnce(&mut Self, &Incoming) -> CoreResult<()>,
    ) -> CoreResult<Incoming> {
        let protocol = parse(message)?
            .try_into_protocol_message()
            .map_err(|_| CoreError::MalformedMessage)?;
        let gid = protocol.group_id().as_slice().to_vec();
        if let Some(r) = routing {
            if gid != r.group_id {
                return Err(CoreError::EnvelopeMismatch);
            }
            if protocol.epoch().as_u64() != r.epoch {
                return Err(CoreError::EnvelopeMismatch);
            }
        }
        let local_epoch = self
            .state
            .groups
            .get(&gid)
            .ok_or(CoreError::UnknownGroup)?
            .epoch()
            .as_u64();
        if routing.is_some() {
            let epoch = protocol.epoch().as_u64();
            if epoch > local_epoch {
                return Err(CoreError::FutureEpoch);
            }
            if epoch < local_epoch {
                return Err(CoreError::StaleEpoch);
            }
        }
        self.transact(|core| {
            let State {
                provider,
                groups,
                trust,
                ..
            } = &mut core.state;
            let group = groups.get_mut(&gid).ok_or(CoreError::UnknownGroup)?;
            let processed = group
                .process_message(provider, protocol)
                .map_err(from_process_error)?;

            // Defence in depth: the sender must be a current member with a
            // valid, trusted credential.
            let sender_index = match processed.sender() {
                Sender::Member(index) => *index,
                _ => return Err(CoreError::UnauthorizedDevice),
            };
            let sender = group
                .members()
                .find(|m| m.index == sender_index)
                .ok_or(CoreError::UnauthorizedDevice)?;
            let validated =
                trust.validate(provider.crypto(), &sender.credential, &sender.signature_key)?;
            if let Some(r) = routing {
                // D-089: the authenticated sender must be the envelope's.
                if validated.device_id != r.sender {
                    return Err(CoreError::EnvelopeMismatch);
                }
            }
            let aad = processed.aad().to_vec();

            let incoming = match processed.into_content() {
                ProcessedMessageContent::ApplicationMessage(m) => {
                    if let Some(r) = routing {
                        match &r.expected_aad {
                            Some(expected) if *expected == aad => {}
                            Some(_) => return Err(CoreError::EnvelopeMismatch),
                            // A commit was expected (process_commit).
                            None => return Err(CoreError::ProtocolViolation),
                        }
                    }
                    Incoming::Application(Zeroizing::new(m.into_bytes()))
                }
                ProcessedMessageContent::StagedCommitMessage(staged) => {
                    if routing.is_some_and(|r| r.expected_aad.is_some()) {
                        return Err(CoreError::ProtocolViolation);
                    }
                    // D-087: another member's commit while ours is staged
                    // must go through discard first.
                    if group.pending_commit().is_some() {
                        return Err(CoreError::CommitPending);
                    }
                    for add in staged.add_proposals() {
                        let leaf = add.add_proposal().key_package().leaf_node();
                        trust.validate(
                            provider.crypto(),
                            leaf.credential(),
                            leaf.signature_key().as_slice(),
                        )?;
                    }
                    for update in staged.update_proposals() {
                        let leaf = update.update_proposal().leaf_node();
                        trust.validate(
                            provider.crypto(),
                            leaf.credential(),
                            leaf.signature_key().as_slice(),
                        )?;
                    }
                    if let Some(leaf) = staged.update_path_leaf_node() {
                        trust.validate(
                            provider.crypto(),
                            leaf.credential(),
                            leaf.signature_key().as_slice(),
                        )?;
                    }
                    let adds = staged.add_proposals().count();
                    if group.members().count() + adds > MAX_GROUP_MEMBERS {
                        return Err(CoreError::Unsupported);
                    }
                    let removed_self = staged.self_removed();
                    group
                        .merge_staged_commit(provider, *staged)
                        .map_err(|_| CoreError::ProtocolViolation)?;
                    if removed_self {
                        let _ = group.delete(provider.storage());
                        groups.remove(&gid);
                        Incoming::RemovedFromGroup
                    } else {
                        Incoming::CommitApplied {
                            epoch: group.epoch().as_u64(),
                        }
                    }
                }
                // By-reference proposals and external joins are not used yet.
                _ => return Err(CoreError::Unsupported),
            };
            after(core, &incoming)?;
            Ok(incoming)
        })
    }

    // ------------------------------------------------------------- inspection

    pub fn epoch(&self, group_id: &[u8]) -> CoreResult<u64> {
        self.guard()?;
        Ok(self
            .state
            .groups
            .get(group_id)
            .ok_or(CoreError::UnknownGroup)?
            .epoch()
            .as_u64())
    }

    pub fn roster(&self, group_id: &[u8]) -> CoreResult<Vec<RosterEntry>> {
        self.guard()?;
        let group = self
            .state
            .groups
            .get(group_id)
            .ok_or(CoreError::UnknownGroup)?;
        group
            .members()
            .map(|m| {
                let cert = DeviceCertificate::decode(m.credential.serialized_content())
                    .map_err(|_| CoreError::StateCorruption)?;
                Ok(RosterEntry {
                    device_id: cert.device_id,
                    person_key: cert.person_key,
                })
            })
            .collect()
    }

    pub fn group_ids(&self) -> Vec<Vec<u8>> {
        self.state.groups.keys().cloned().collect()
    }

    /// Deletes every local record and forgets all in-memory state.
    fn require_no_staged_commit(&self, group_id: &[u8]) -> CoreResult<()> {
        if let Some(group) = self.state.groups.get(group_id) {
            if group.pending_commit().is_some() {
                return Err(CoreError::CommitPending);
            }
        }
        Ok(())
    }

    pub fn wipe(&mut self) -> CoreResult<()> {
        self.store.wipe_all()?;
        self.zeroize_state();
        self.identity = None;
        self.state = State::empty();
        self.poisoned = false;
        Ok(())
    }

    // ---------------------------------------------------- checkpoint/rollback

    fn checkpoint(&self) -> CoreResult<Checkpoint> {
        let values = self
            .state
            .provider
            .storage()
            .values
            .read()
            .map_err(|_| CoreError::Internal)?
            .clone();
        Ok(Checkpoint {
            values,
            group_ids: self.state.groups.keys().cloned().collect(),
            trust: self.state.trust.clone(),
            confirmed: self.state.confirmed.clone(),
        })
    }

    fn rollback(&mut self, checkpoint: &Checkpoint) -> CoreResult<()> {
        {
            let mut values = self
                .state
                .provider
                .storage()
                .values
                .write()
                .map_err(|_| CoreError::Internal)?;
            for v in values.values_mut() {
                v.zeroize();
            }
            *values = checkpoint.values.clone();
        }
        self.state.trust = checkpoint.trust.clone();
        self.state.confirmed = checkpoint.confirmed.clone();
        let mut groups = BTreeMap::new();
        for gid in &checkpoint.group_ids {
            let group = MlsGroup::load(self.state.provider.storage(), &GroupId::from_slice(gid))
                .map_err(|_| CoreError::RollbackFailure)?
                .ok_or(CoreError::RollbackFailure)?;
            groups.insert(gid.clone(), group);
        }
        self.state.groups = groups;
        Ok(())
    }

    /// checkpoint → attempt → (accept: persist atomically) | (reject: roll back).
    /// A persistence failure after success also rolls back, so memory never
    /// runs ahead of disk.
    fn transact<T>(&mut self, op: impl FnOnce(&mut Self) -> CoreResult<T>) -> CoreResult<T> {
        let checkpoint = self.checkpoint()?;
        let result = op(self).and_then(|value| {
            self.persist_state()
                .map_err(|_| CoreError::PersistenceFailure)?;
            Ok(value)
        });
        match result {
            Ok(value) => Ok(value),
            Err(err) => match self.rollback(&checkpoint) {
                Ok(()) => Err(err),
                Err(_) => {
                    self.poisoned = true;
                    Err(CoreError::RollbackFailure)
                }
            },
        }
    }

    // ------------------------------------------------------------- persistence

    fn persist_state(&mut self) -> CoreResult<()> {
        let mut out = Zeroizing::new(Vec::new());
        out.extend_from_slice(&STATE_VERSION.to_be_bytes());
        {
            let values = self
                .state
                .provider
                .storage()
                .values
                .read()
                .map_err(|_| CoreError::Internal)?;
            out.extend_from_slice(&(values.len() as u32).to_be_bytes());
            for (k, v) in values.iter() {
                put(&mut out, k);
                put(&mut out, v);
            }
        }
        out.extend_from_slice(&(self.state.groups.len() as u32).to_be_bytes());
        for gid in self.state.groups.keys() {
            put(&mut out, gid);
        }
        self.state.trust.encode(&mut out);
        out.extend_from_slice(&(self.state.confirmed.len() as u32).to_be_bytes());
        for (gid, epoch) in &self.state.confirmed {
            put(&mut out, gid);
            out.extend_from_slice(&epoch.to_be_bytes());
        }
        let sealed = record::seal(&self.kek, RecordKind::MlsState, REC_STATE, &out)?;
        self.store.put(REC_STATE, &sealed)
    }

    fn seal_identity(&self, id: &Identity) -> CoreResult<Vec<u8>> {
        let mut out = Zeroizing::new(Vec::new());
        out.extend_from_slice(&IDENTITY_VERSION.to_be_bytes());
        put(&mut out, id.account.as_str().as_bytes());
        put(&mut out, &id.person_private);
        put(&mut out, &id.person_key.0);
        put(&mut out, &id.device_private);
        put(&mut out, &id.device_public);
        put(&mut out, &id.certificate.encode());
        record::seal(&self.kek, RecordKind::IdentitySecret, REC_IDENTITY, &out)
    }

    fn seal_metadata(&self, id: &Identity) -> CoreResult<Vec<u8>> {
        let mut out = Vec::new();
        out.extend_from_slice(&IDENTITY_VERSION.to_be_bytes());
        put(&mut out, id.account.as_str().as_bytes());
        put(&mut out, IMPLEMENTATION.as_bytes());
        record::seal(&self.kek, RecordKind::PublicMetadata, REC_METADATA, &out)
    }

    fn load(&mut self) -> CoreResult<()> {
        let corrupt = |_| CoreError::StateCorruption;
        if let Some(raw) = self.store.get(REC_IDENTITY)? {
            let plain = record::open(&self.kek, RecordKind::IdentitySecret, REC_IDENTITY, &raw)?;
            let mut r = Reader(&plain);
            if u16::from_be_bytes(r.fixed::<2>().map_err(corrupt)?) != IDENTITY_VERSION {
                return Err(CoreError::StateCorruption);
            }
            let account = AccountId::new(
                std::str::from_utf8(r.var().map_err(corrupt)?)
                    .map_err(|_| CoreError::StateCorruption)?,
            )
            .map_err(corrupt)?;
            let person_private = Zeroizing::new(r.var().map_err(corrupt)?.to_vec());
            let person_key = PersonKey::from_slice(r.var().map_err(corrupt)?).map_err(corrupt)?;
            let device_private = Zeroizing::new(r.var().map_err(corrupt)?.to_vec());
            let device_public = r.var().map_err(corrupt)?.to_vec();
            let certificate =
                DeviceCertificate::decode(r.var().map_err(corrupt)?).map_err(corrupt)?;
            if !r.0.is_empty()
                || certificate.person_key != person_key
                || certificate.device_signature_key != device_public
            {
                return Err(CoreError::StateCorruption);
            }
            self.identity = Some(Identity {
                account,
                person_private,
                person_key,
                device_private,
                device_public,
                certificate,
            });
        }
        if let Some(raw) = self.store.get(REC_STATE)? {
            let plain = record::open(&self.kek, RecordKind::MlsState, REC_STATE, &raw)?;
            let mut r = Reader(&plain);
            let version = u16::from_be_bytes(r.fixed::<2>().map_err(corrupt)?);
            if version != STATE_VERSION && version != STATE_VERSION_V1 {
                return Err(CoreError::StateCorruption);
            }
            let n = u32::from_be_bytes(r.fixed::<4>().map_err(corrupt)?);
            let mut values = HashMap::new();
            for _ in 0..n {
                let k = r.var().map_err(corrupt)?.to_vec();
                let v = r.var().map_err(corrupt)?.to_vec();
                values.insert(k, v);
            }
            let g = u32::from_be_bytes(r.fixed::<4>().map_err(corrupt)?);
            let mut group_ids = Vec::new();
            for _ in 0..g {
                group_ids.push(r.var().map_err(corrupt)?.to_vec());
            }
            let mut confirmed = BTreeMap::new();
            let trust = if version == STATE_VERSION_V1 {
                // v1 person-key trust: the keys become anchors (D-085), so an
                // upgraded device re-admits only one pinned device per key.
                let mut trust = TrustPolicy::default();
                let t = u32::from_be_bytes(r.fixed::<4>().map_err(corrupt)?);
                for _ in 0..t {
                    trust
                        .anchors
                        .insert(PersonKey::from_slice(r.var().map_err(corrupt)?).map_err(corrupt)?);
                }
                let rv = u32::from_be_bytes(r.fixed::<4>().map_err(corrupt)?);
                for _ in 0..rv {
                    trust
                        .revoked_devices
                        .insert(DeviceId(r.fixed::<DEVICE_ID_LEN>().map_err(corrupt)?));
                }
                trust
            } else {
                let trust = TrustPolicy::decode(&mut r)?;
                let n = u32::from_be_bytes(r.fixed::<4>().map_err(corrupt)?);
                for _ in 0..n {
                    let gid = r.var().map_err(corrupt)?.to_vec();
                    confirmed.insert(gid, u64::from_be_bytes(r.fixed::<8>().map_err(corrupt)?));
                }
                trust
            };
            if !r.0.is_empty() {
                return Err(CoreError::StateCorruption);
            }
            let checkpoint = Checkpoint {
                values,
                group_ids,
                trust,
                confirmed,
            };
            self.rollback(&checkpoint)
                .map_err(|_| CoreError::StateCorruption)?;
        }
        if let Some(id) = &self.identity {
            // The device's own certificate is always trusted (and its person
            // key anchored), also after a v1 upgrade.
            let own = id.certificate.encode();
            let trust = &mut self.state.trust;
            trust.anchors.insert(id.person_key.clone());
            trust
                .trust_certificate(self.state.provider.crypto(), &own, TrustSource::Own, None)
                .map_err(|_| CoreError::StateCorruption)?;
        }
        Ok(())
    }

    fn zeroize_state(&mut self) {
        if let Ok(mut values) = self.state.provider.storage().values.write() {
            for v in values.values_mut() {
                v.zeroize();
            }
            values.clear();
        }
    }
}

impl Drop for CryptoCore {
    fn drop(&mut self) {
        self.zeroize_state();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::keystore::EphemeralTestKeyStore;
    use crate::store::MemoryStore;

    fn device(name: &str) -> (CryptoCore, PublicIdentity) {
        let mut c = CryptoCore::open(
            Box::new(MemoryStore::default()),
            &EphemeralTestKeyStore::new(),
        )
        .unwrap();
        let p = c.create_identity(AccountId::new(name).unwrap()).unwrap();
        (c, p)
    }

    /// A compromised member bypasses its own policy and commits an Add for a
    /// device whose person key the receiver never trusted. The receiver must
    /// reject the commit and keep its state.
    #[test]
    fn commit_adding_untrusted_device_is_rejected_by_receiver() {
        let (mut alice, pa) = device("a");
        let (mut bob, pb) = device("b");
        let (mut mallory, _pm) = device("m");
        alice
            .trust_verified_person_key(pb.person_key.clone())
            .unwrap();
        bob.trust_verified_person_key(pa.person_key.clone())
            .unwrap();
        let gid = alice.create_group().unwrap();
        let added = alice.add_member(&gid, &bob.key_package().unwrap()).unwrap();
        bob.join(&added.welcome).unwrap();

        // Bob's client skips validation (direct OpenMLS use) to add Mallory.
        let kp_bytes = mallory.key_package().unwrap();
        let MlsMessageBodyIn::KeyPackage(kp_in) = parse(&kp_bytes).unwrap().extract() else {
            panic!("expected key package");
        };
        let kp = kp_in
            .validate(bob.state.provider.crypto(), ProtocolVersion::Mls10)
            .unwrap();
        let signer = bob.identity.as_ref().unwrap().signer();
        let group = bob.state.groups.get_mut(&gid).unwrap();
        let (commit, _w, _i) = group
            .add_members(&bob.state.provider, &signer, &[kp])
            .unwrap();
        let commit = ser(&commit).unwrap();

        let epoch = alice.epoch(&gid).unwrap();
        assert_eq!(
            alice.process_incoming(&commit).err(),
            Some(CoreError::UnauthorizedDevice)
        );
        assert_eq!(
            alice.epoch(&gid).unwrap(),
            epoch,
            "rejected commit must not advance the epoch"
        );
        assert_eq!(alice.roster(&gid).unwrap().len(), 2);
    }
}
