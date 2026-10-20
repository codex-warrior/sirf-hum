//! Identity and credential boundary (Prompt 06 Part 2, D-045, D-057, D-064).
//!
//! Distinct types so an account ID can never be used where a cryptographic
//! identity is required:
//! - [`AccountId`]: opaque server/session identifier. Stored as metadata only;
//!   never signed into credentials, never trusted for cryptographic decisions.
//! - [`DeviceId`]: random 128-bit identifier generated on the device.
//! - [`PersonKey`]: a person's Ed25519 identity *public* key (PIK).
//! - [`DeviceCertificate`]: the PIK's signature binding a device ID to the
//!   device's MLS signature key. Carried inside the MLS BasicCredential.
//!
//! Trust comes only from what the device verified itself
//! ([`crate::trust::TrustPolicy`], D-085), never from the server. Signing and verification use the
//! OpenMLS crypto provider (Ed25519); no primitive is implemented here.

use std::collections::BTreeSet;

use openmls::prelude::{BasicCredential, Credential};
use openmls_traits::crypto::OpenMlsCrypto;
use openmls_traits::types::SignatureScheme;

use crate::limits::{MAX_ACCOUNT_ID_BYTES, MAX_CERTIFICATE_BYTES};
use crate::{CoreError, CoreResult};

/// Domain separation for certificate signatures.
const CERT_CONTEXT: &[u8] = b"SirfHum-DeviceCertificate-v1";
const CERT_VERSION: u8 = 1;
pub const ED25519_PUBLIC_LEN: usize = 32;
const ED25519_SIGNATURE_LEN: usize = 64;
pub const DEVICE_ID_LEN: usize = 16;

/// Opaque server/session identifier (e.g. Firebase uid). Not a key.
#[derive(Clone, PartialEq, Eq)]
pub struct AccountId(String);

impl AccountId {
    pub fn new(value: &str) -> CoreResult<Self> {
        if value.is_empty() || value.len() > MAX_ACCOUNT_ID_BYTES {
            return Err(CoreError::InvalidInput);
        }
        Ok(Self(value.to_owned()))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct DeviceId(pub [u8; DEVICE_ID_LEN]);

impl DeviceId {
    pub fn from_slice(bytes: &[u8]) -> CoreResult<Self> {
        Ok(Self(bytes.try_into().map_err(|_| CoreError::InvalidInput)?))
    }
}

/// A person's identity public key (Ed25519, 32 bytes).
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct PersonKey(pub Vec<u8>);

impl PersonKey {
    pub fn from_slice(bytes: &[u8]) -> CoreResult<Self> {
        if bytes.len() != ED25519_PUBLIC_LEN {
            return Err(CoreError::InvalidInput);
        }
        Ok(Self(bytes.to_vec()))
    }
}

// Debug never prints key bytes or IDs in full.
impl core::fmt::Debug for AccountId {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "AccountId(<{} bytes>)", self.0.len())
    }
}
impl core::fmt::Debug for DeviceId {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("DeviceId(<redacted>)")
    }
}
impl core::fmt::Debug for PersonKey {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("PersonKey(<redacted>)")
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct DeviceCertificate {
    pub person_key: PersonKey,
    pub device_id: DeviceId,
    pub device_signature_key: Vec<u8>,
    pub issued_at_unix: u64,
    signature: Vec<u8>,
}

impl core::fmt::Debug for DeviceCertificate {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("DeviceCertificate(<redacted>)")
    }
}

impl DeviceCertificate {
    /// The exact bytes the person key signs.
    fn signed_payload(
        person_key: &PersonKey,
        device_id: &DeviceId,
        device_signature_key: &[u8],
        issued_at_unix: u64,
    ) -> Vec<u8> {
        let mut out = Vec::with_capacity(128);
        out.extend_from_slice(CERT_CONTEXT);
        out.push(CERT_VERSION);
        put(&mut out, &person_key.0);
        out.extend_from_slice(&device_id.0);
        put(&mut out, device_signature_key);
        out.extend_from_slice(&issued_at_unix.to_be_bytes());
        out
    }

    /// Issues a certificate signed with the person's private key.
    pub(crate) fn issue(
        crypto: &impl OpenMlsCrypto,
        person_key: PersonKey,
        person_private: &[u8],
        device_id: DeviceId,
        device_signature_key: Vec<u8>,
        issued_at_unix: u64,
    ) -> CoreResult<Self> {
        let payload = Self::signed_payload(
            &person_key,
            &device_id,
            &device_signature_key,
            issued_at_unix,
        );
        let signature = crypto
            .sign(SignatureScheme::ED25519, &payload, person_private)
            .map_err(|_| CoreError::InternalCryptoFailure)?;
        Ok(Self {
            person_key,
            device_id,
            device_signature_key,
            issued_at_unix,
            signature,
        })
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut out = vec![CERT_VERSION];
        put(&mut out, &self.person_key.0);
        out.extend_from_slice(&self.device_id.0);
        put(&mut out, &self.device_signature_key);
        out.extend_from_slice(&self.issued_at_unix.to_be_bytes());
        put(&mut out, &self.signature);
        out
    }

    /// Strict decoder: exact lengths, no trailing bytes.
    pub fn decode(bytes: &[u8]) -> CoreResult<Self> {
        if bytes.len() > MAX_CERTIFICATE_BYTES {
            return Err(CoreError::InvalidCredential);
        }
        let mut r = Reader(bytes);
        if r.u8()? != CERT_VERSION {
            return Err(CoreError::InvalidCredential);
        }
        let person_key = PersonKey(r.var()?.to_vec());
        let device_id = DeviceId(r.fixed::<DEVICE_ID_LEN>()?);
        let device_signature_key = r.var()?.to_vec();
        let issued_at_unix = u64::from_be_bytes(r.fixed::<8>()?);
        let signature = r.var()?.to_vec();
        if !r.0.is_empty()
            || person_key.0.len() != ED25519_PUBLIC_LEN
            || device_signature_key.len() != ED25519_PUBLIC_LEN
            || signature.len() != ED25519_SIGNATURE_LEN
        {
            return Err(CoreError::InvalidCredential);
        }
        Ok(Self {
            person_key,
            device_id,
            device_signature_key,
            issued_at_unix,
            signature,
        })
    }

    pub fn verify_signature(&self, crypto: &impl OpenMlsCrypto) -> CoreResult<()> {
        let payload = Self::signed_payload(
            &self.person_key,
            &self.device_id,
            &self.device_signature_key,
            self.issued_at_unix,
        );
        crypto
            .verify_signature(
                SignatureScheme::ED25519,
                &payload,
                &self.person_key.0,
                &self.signature,
            )
            .map_err(|_| CoreError::InvalidCredential)
    }

    pub fn to_credential(&self) -> Credential {
        BasicCredential::new(self.encode()).into()
    }
}

/// Domain separation for device proofs of possession (D-070). Distinct from
/// the certificate context and from every MLS signature label, so a proof
/// can never be replayed as a certificate or an MLS signature, or vice versa.
const PROOF_CONTEXT: &[u8] = b"SirfHum-DeviceProof-v1";
/// Server challenges are exactly 32 random bytes.
pub const CHALLENGE_LEN: usize = 32;

/// What a device proof is for. Each purpose is a separate signed domain, so a
/// proof made for one purpose is useless for any other.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum ProofPurpose {
    /// Bootstrap activation of an account's first device (Prompt 07).
    Activation = 1,
    /// A new device proving possession while it waits for approval by a
    /// trusted device or the recovery key (Prompt 08, D-075).
    Enrollment = 2,
    /// An active device registering (or clearing) its own push token
    /// (Prompt 11, D-098). The server binds the challenge to the token's
    /// hash, so a proof for one token cannot register another.
    PushToken = 3,
    /// An active device authorizing one step of pairing two accounts into a
    /// couple (Prompt 12, D-102): create, accept, confirm, reject or cancel.
    /// The server binds the challenge to the step and its subject. A new
    /// accepted value only: ABI v6 functions and formats are unchanged.
    Pairing = 4,
}

impl ProofPurpose {
    pub fn from_u32(value: u32) -> CoreResult<Self> {
        match value {
            1 => Ok(ProofPurpose::Activation),
            2 => Ok(ProofPurpose::Enrollment),
            3 => Ok(ProofPurpose::PushToken),
            4 => Ok(ProofPurpose::Pairing),
            _ => Err(CoreError::InvalidInput),
        }
    }
}

/// The exact bytes a device signs to prove it holds the private key of its
/// certified device signature key:
/// `"SirfHum-DeviceProof-v1" | purpose u8 | u32 len | account | device_id[16]
///  | u32 len | certificate | challenge[32]`.
///
/// Binding the account stops a proof from activating the device under a
/// different account; binding the certificate and device ID stops it from
/// vouching for different public material; the single-use challenge stops
/// replay (the server consumes it).
pub fn device_proof_payload(
    purpose: ProofPurpose,
    account: &AccountId,
    device_id: &DeviceId,
    certificate: &[u8],
    challenge: &[u8],
) -> CoreResult<Vec<u8>> {
    if challenge.len() != CHALLENGE_LEN || certificate.len() > MAX_CERTIFICATE_BYTES {
        return Err(CoreError::InvalidInput);
    }
    let mut out = Vec::with_capacity(
        PROOF_CONTEXT.len() + 1 + 4 + account.0.len() + 16 + 4 + certificate.len() + 32,
    );
    out.extend_from_slice(PROOF_CONTEXT);
    out.push(purpose as u8);
    put(&mut out, account.0.as_bytes());
    out.extend_from_slice(&device_id.0);
    put(&mut out, certificate);
    out.extend_from_slice(challenge);
    Ok(out)
}

/// Verifies a device proof the way the server does (functions/src/device):
/// strict certificate decode, person-key signature on the certificate, and
/// the device key's signature over the proof payload. Public-key operations
/// only. Used by tests and available to future peer-side checks.
pub fn verify_device_proof(
    crypto: &impl OpenMlsCrypto,
    purpose: ProofPurpose,
    account: &AccountId,
    certificate: &[u8],
    challenge: &[u8],
    signature: &[u8],
) -> CoreResult<DeviceCertificate> {
    let cert = DeviceCertificate::decode(certificate)?;
    cert.verify_signature(crypto)?;
    if signature.len() != ED25519_SIGNATURE_LEN {
        return Err(CoreError::AuthenticationFailure);
    }
    let payload = device_proof_payload(purpose, account, &cert.device_id, certificate, challenge)?;
    crypto
        .verify_signature(
            SignatureScheme::ED25519,
            &payload,
            &cert.device_signature_key,
            signature,
        )
        .map_err(|_| CoreError::AuthenticationFailure)?;
    Ok(cert)
}

// ------------------------------------------------- multi-device trust (D-075)
//
// Every device keeps its own PIK and device key (D-074: no private key is ever
// shared or transferred). Trust between devices of one account is
// established by *signed statements*, each in its own domain so that no
// signature can be replayed as another kind:
//   - device approval:            an active device's PIK approves a new device
//   - recovery key registration:  an active device's PIK registers a recovery key
//   - recovery approval:          the recovery key approves a new device
// All bind the account, both parties' public identities, a single-use server
// challenge and the server-chosen expiry, plus a protocol version.

/// Version of the approval/recovery statement formats below.
pub const TRUST_PROTOCOL_VERSION: u8 = 1;
const APPROVAL_CONTEXT: &[u8] = b"SirfHum-DeviceApproval-v1";
const RECOVERY_REGISTRATION_CONTEXT: &[u8] = b"SirfHum-RecoveryKeyRegistration-v1";
const RECOVERY_APPROVAL_CONTEXT: &[u8] = b"SirfHum-RecoveryApproval-v1";
const APPROVAL_CODE_CONTEXT: &[u8] = b"SirfHum-ApprovalCode-v1";

fn statement_header(context: &[u8], account: &AccountId) -> Vec<u8> {
    let mut out = Vec::with_capacity(1200);
    out.extend_from_slice(context);
    out.push(TRUST_PROTOCOL_VERSION);
    put(&mut out, account.0.as_bytes());
    out
}

fn check_challenge(challenge: &[u8]) -> CoreResult<()> {
    if challenge.len() != CHALLENGE_LEN {
        return Err(CoreError::InvalidInput);
    }
    Ok(())
}

/// `"SirfHum-DeviceApproval-v1" | version | u32 len | account
///  | approver device id[16] | u32 len | approver certificate
///  | new device id[16] | u32 len | new certificate | challenge[32] | expires_at u64 BE`
/// signed by the approver's PIK.
pub fn device_approval_payload(
    account: &AccountId,
    approver_certificate: &[u8],
    new_certificate: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
) -> CoreResult<Vec<u8>> {
    check_challenge(challenge)?;
    let approver = DeviceCertificate::decode(approver_certificate)?;
    let new = DeviceCertificate::decode(new_certificate)?;
    let mut out = statement_header(APPROVAL_CONTEXT, account);
    out.extend_from_slice(&approver.device_id.0);
    put(&mut out, approver_certificate);
    out.extend_from_slice(&new.device_id.0);
    put(&mut out, new_certificate);
    out.extend_from_slice(challenge);
    out.extend_from_slice(&expires_at_unix.to_be_bytes());
    Ok(out)
}

/// Verifies both certificates and the approver PIK's signature. Expiry and
/// approver status are server/policy checks, done by the caller.
pub fn verify_device_approval(
    crypto: &impl OpenMlsCrypto,
    account: &AccountId,
    approver_certificate: &[u8],
    new_certificate: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
    signature: &[u8],
) -> CoreResult<()> {
    let approver = DeviceCertificate::decode(approver_certificate)?;
    approver.verify_signature(crypto)?;
    let new = DeviceCertificate::decode(new_certificate)?;
    new.verify_signature(crypto)?;
    if approver.device_id == new.device_id {
        return Err(CoreError::InvalidInput);
    }
    let payload = device_approval_payload(
        account,
        approver_certificate,
        new_certificate,
        challenge,
        expires_at_unix,
    )?;
    verify_ed25519(crypto, &approver.person_key.0, &payload, signature)
}

/// `"SirfHum-RecoveryKeyRegistration-v1" | version | u32 len | account
///  | registrar device id[16] | u32 len | registrar certificate
///  | recovery public key[32] | challenge[32] | expires_at u64 BE`
/// signed by the registering (active) device's PIK.
pub fn recovery_registration_payload(
    account: &AccountId,
    registrar_certificate: &[u8],
    recovery_public_key: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
) -> CoreResult<Vec<u8>> {
    check_challenge(challenge)?;
    if recovery_public_key.len() != ED25519_PUBLIC_LEN {
        return Err(CoreError::InvalidInput);
    }
    let registrar = DeviceCertificate::decode(registrar_certificate)?;
    let mut out = statement_header(RECOVERY_REGISTRATION_CONTEXT, account);
    out.extend_from_slice(&registrar.device_id.0);
    put(&mut out, registrar_certificate);
    out.extend_from_slice(recovery_public_key);
    out.extend_from_slice(challenge);
    out.extend_from_slice(&expires_at_unix.to_be_bytes());
    Ok(out)
}

pub fn verify_recovery_registration(
    crypto: &impl OpenMlsCrypto,
    account: &AccountId,
    registrar_certificate: &[u8],
    recovery_public_key: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
    signature: &[u8],
) -> CoreResult<()> {
    let registrar = DeviceCertificate::decode(registrar_certificate)?;
    registrar.verify_signature(crypto)?;
    let payload = recovery_registration_payload(
        account,
        registrar_certificate,
        recovery_public_key,
        challenge,
        expires_at_unix,
    )?;
    verify_ed25519(crypto, &registrar.person_key.0, &payload, signature)
}

/// `"SirfHum-RecoveryApproval-v1" | version | u32 len | account
///  | recovery public key[32] | new device id[16] | u32 len | new certificate
///  | challenge[32] | expires_at u64 BE`
/// signed by the recovery key.
pub fn recovery_approval_payload(
    account: &AccountId,
    recovery_public_key: &[u8],
    new_certificate: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
) -> CoreResult<Vec<u8>> {
    check_challenge(challenge)?;
    if recovery_public_key.len() != ED25519_PUBLIC_LEN {
        return Err(CoreError::InvalidInput);
    }
    let new = DeviceCertificate::decode(new_certificate)?;
    let mut out = statement_header(RECOVERY_APPROVAL_CONTEXT, account);
    out.extend_from_slice(recovery_public_key);
    out.extend_from_slice(&new.device_id.0);
    put(&mut out, new_certificate);
    out.extend_from_slice(challenge);
    out.extend_from_slice(&expires_at_unix.to_be_bytes());
    Ok(out)
}

pub fn verify_recovery_approval(
    crypto: &impl OpenMlsCrypto,
    account: &AccountId,
    recovery_public_key: &[u8],
    new_certificate: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
    signature: &[u8],
) -> CoreResult<()> {
    DeviceCertificate::decode(new_certificate)?.verify_signature(crypto)?;
    let payload = recovery_approval_payload(
        account,
        recovery_public_key,
        new_certificate,
        challenge,
        expires_at_unix,
    )?;
    verify_ed25519(crypto, recovery_public_key, &payload, signature)
}

/// Six-digit code both devices show so the user approves the device in
/// their hand, not an attacker's pending device:
/// SHA-256("SirfHum-ApprovalCode-v1" | u32 len | new certificate | challenge),
/// first 4 bytes big-endian, mod 10^6. A comparison code (like a Bluetooth
/// or Signal SAS), not a secret; the modulo bias (< 2^-12) is irrelevant for
/// visual comparison. Guessing a matching code costs ~10^6 server-issued,
/// rate-limited challenges.
pub fn approval_code(
    crypto: &impl OpenMlsCrypto,
    new_certificate: &[u8],
    challenge: &[u8],
) -> CoreResult<u32> {
    check_challenge(challenge)?;
    if new_certificate.len() > MAX_CERTIFICATE_BYTES {
        return Err(CoreError::InvalidInput);
    }
    let mut data = Vec::with_capacity(APPROVAL_CODE_CONTEXT.len() + 4 + new_certificate.len() + 32);
    data.extend_from_slice(APPROVAL_CODE_CONTEXT);
    put(&mut data, new_certificate);
    data.extend_from_slice(challenge);
    let digest = crypto
        .hash(openmls_traits::types::HashType::Sha2_256, &data)
        .map_err(|_| CoreError::InternalCryptoFailure)?;
    let head: [u8; 4] = digest[..4].try_into().map_err(|_| CoreError::Internal)?;
    Ok(u32::from_be_bytes(head) % 1_000_000)
}

// ------------------------------------------- revocation and reset (D-081, D-082)

const REVOCATION_CONTEXT: &[u8] = b"SirfHum-DeviceRevocation-v1";
const RESET_CANCEL_CONTEXT: &[u8] = b"SirfHum-IdentityResetCancel-v1";

/// Why a device was revoked. Stable wire values; extend by appending.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum RevocationReason {
    /// Removed by its owner (unwanted, replaced, sold).
    Removed = 1,
    /// Reported lost.
    Lost = 2,
    /// Reported stolen.
    Stolen = 3,
    /// Suspected compromised.
    Compromised = 4,
}

impl RevocationReason {
    pub fn from_u8(value: u8) -> CoreResult<Self> {
        match value {
            1 => Ok(Self::Removed),
            2 => Ok(Self::Lost),
            3 => Ok(Self::Stolen),
            4 => Ok(Self::Compromised),
            _ => Err(CoreError::InvalidInput),
        }
    }
}

/// `"SirfHum-DeviceRevocation-v1" | version | u32 len | account
///  | revoker device id[16] | u32 len | revoker certificate
///  | revoked device id[16] | u32 len | revoked certificate | reason u8
///  | challenge[32] | expires_at u64 BE`
/// signed by the revoker's PIK (an active device, possibly the revoked
/// device itself). The single-use challenge is the revocation's unique ID.
pub fn revocation_payload(
    account: &AccountId,
    revoker_certificate: &[u8],
    revoked_certificate: &[u8],
    reason: RevocationReason,
    challenge: &[u8],
    expires_at_unix: u64,
) -> CoreResult<Vec<u8>> {
    check_challenge(challenge)?;
    let revoker = DeviceCertificate::decode(revoker_certificate)?;
    let revoked = DeviceCertificate::decode(revoked_certificate)?;
    let mut out = statement_header(REVOCATION_CONTEXT, account);
    out.extend_from_slice(&revoker.device_id.0);
    put(&mut out, revoker_certificate);
    out.extend_from_slice(&revoked.device_id.0);
    put(&mut out, revoked_certificate);
    out.push(reason as u8);
    out.extend_from_slice(challenge);
    out.extend_from_slice(&expires_at_unix.to_be_bytes());
    Ok(out)
}

#[allow(clippy::too_many_arguments)]
pub fn verify_revocation(
    crypto: &impl OpenMlsCrypto,
    account: &AccountId,
    revoker_certificate: &[u8],
    revoked_certificate: &[u8],
    reason: RevocationReason,
    challenge: &[u8],
    expires_at_unix: u64,
    signature: &[u8],
) -> CoreResult<()> {
    let revoker = DeviceCertificate::decode(revoker_certificate)?;
    revoker.verify_signature(crypto)?;
    DeviceCertificate::decode(revoked_certificate)?.verify_signature(crypto)?;
    let payload = revocation_payload(
        account,
        revoker_certificate,
        revoked_certificate,
        reason,
        challenge,
        expires_at_unix,
    )?;
    verify_ed25519(crypto, &revoker.person_key.0, &payload, signature)
}

/// `"SirfHum-IdentityResetCancel-v1" | version | u32 len | account
///  | device id[16] | u32 len | certificate | challenge[32] | expires_at u64 BE`
/// signed by an active device's PIK: proof that a trusted device still
/// exists and objects to the pending identity reset.
pub fn reset_cancel_payload(
    account: &AccountId,
    certificate: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
) -> CoreResult<Vec<u8>> {
    check_challenge(challenge)?;
    let cert = DeviceCertificate::decode(certificate)?;
    let mut out = statement_header(RESET_CANCEL_CONTEXT, account);
    out.extend_from_slice(&cert.device_id.0);
    put(&mut out, certificate);
    out.extend_from_slice(challenge);
    out.extend_from_slice(&expires_at_unix.to_be_bytes());
    Ok(out)
}

pub fn verify_reset_cancel(
    crypto: &impl OpenMlsCrypto,
    account: &AccountId,
    certificate: &[u8],
    challenge: &[u8],
    expires_at_unix: u64,
    signature: &[u8],
) -> CoreResult<()> {
    let cert = DeviceCertificate::decode(certificate)?;
    cert.verify_signature(crypto)?;
    let payload = reset_cancel_payload(account, certificate, challenge, expires_at_unix)?;
    verify_ed25519(crypto, &cert.person_key.0, &payload, signature)
}

// ------------------------------------------------ peer-side lineage (D-084)

/// Evidence that a recovery key was registered by a device of the chain.
pub struct RecoveryRegistrationEvidence<'a> {
    pub registrar_certificate: &'a [u8],
    pub recovery_public_key: &'a [u8],
    pub challenge: &'a [u8],
    pub expires_at_unix: u64,
    pub signature: &'a [u8],
}

/// One activation in an account's trust chain, as stored by the server
/// next to the activated device (DEVICE-IDENTITY §4).
pub enum TrustLink<'a> {
    /// `new_certificate` approved by `approver_certificate`'s PIK.
    Approval {
        protocol_version: u8,
        approver_certificate: &'a [u8],
        new_certificate: &'a [u8],
        challenge: &'a [u8],
        expires_at_unix: u64,
        signature: &'a [u8],
    },
    /// `new_certificate` approved by a recovery key that a chain device registered.
    Recovery {
        protocol_version: u8,
        registration: RecoveryRegistrationEvidence<'a>,
        new_certificate: &'a [u8],
        challenge: &'a [u8],
        expires_at_unix: u64,
        signature: &'a [u8],
    },
}

/// A signed revocation as stored by the server.
pub struct RevocationEvidence<'a> {
    pub protocol_version: u8,
    pub revoker_certificate: &'a [u8],
    pub revoked_certificate: &'a [u8],
    pub reason: RevocationReason,
    pub challenge: &'a [u8],
    pub expires_at_unix: u64,
    pub signature: &'a [u8],
}

/// Verifies an account's trust chain on the device, without trusting the
/// server: starting from `root_certificate` (the account's first device,
/// whose own trust comes from partner verification of its PIK, never from
/// the server), every link must be signed by a key that is already part of
/// the chain, and every statement must bind this account. Then applies
/// signed revocations whose revoker is in the chain, plus `revoked_ids`
/// (server-asserted revocations, e.g. identity reset; honoured because
/// revocation only reduces trust).
///
/// Every device in a chain has its own PIK (D-074) and a PIK certifies
/// exactly one device ID (D-085), so a chain in which one person key
/// certifies two devices is invalid as a whole (Prompt 17, D-122): it is how
/// a revoked device's retained PIK would re-enter through an approver that
/// had not yet learned of the revocation.
///
/// Returns the certificates still trusted, in chain order. Fails closed on
/// any broken link. Freshness (expiry) is enforced by the server at the
/// time of use; peers check the expiry is not before the certificate was
/// issued, which catches statements made for another device generation.
pub fn verify_lineage(
    crypto: &impl OpenMlsCrypto,
    account: &AccountId,
    root_certificate: &[u8],
    links: &[TrustLink<'_>],
    revocations: &[RevocationEvidence<'_>],
    revoked_ids: &[DeviceId],
) -> CoreResult<Vec<DeviceCertificate>> {
    Ok(verify_lineage_detailed(
        crypto,
        account,
        root_certificate,
        links,
        revocations,
        revoked_ids,
    )?
    .trusted
    .into_iter()
    .map(|(_, c)| c)
    .collect())
}

/// What a verified lineage proves (D-084, D-085).
pub struct LineageOutcome {
    pub account: AccountId,
    /// The root certificate (the account's first device of this identity).
    pub root: DeviceCertificate,
    /// Still-trusted certificates, in chain order, with their exact bytes.
    pub trusted: Vec<(Vec<u8>, DeviceCertificate)>,
    /// Revoked devices, with their person key when the certificate is known
    /// (signed revocations always; server-asserted ones when in the chain).
    pub revoked: Vec<(DeviceId, Option<PersonKey>)>,
}

impl core::fmt::Debug for LineageOutcome {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("LineageOutcome(<redacted>)")
    }
}

/// [`verify_lineage`], also reporting the root and what was revoked.
pub fn verify_lineage_detailed(
    crypto: &impl OpenMlsCrypto,
    account: &AccountId,
    root_certificate: &[u8],
    links: &[TrustLink<'_>],
    revocations: &[RevocationEvidence<'_>],
    revoked_ids: &[DeviceId],
) -> CoreResult<LineageOutcome> {
    let invalid = |_| CoreError::TrustChainInvalid;
    let root = DeviceCertificate::decode(root_certificate).map_err(invalid)?;
    root.verify_signature(crypto).map_err(invalid)?;
    let mut chain: Vec<(Vec<u8>, DeviceCertificate)> = vec![(root_certificate.to_vec(), root)];
    let member =
        |chain: &[(Vec<u8>, DeviceCertificate)], cert: &[u8]| chain.iter().any(|(c, _)| c == cert);

    for link in links {
        let new_cert = match link {
            TrustLink::Approval {
                protocol_version,
                approver_certificate,
                new_certificate,
                challenge,
                expires_at_unix,
                signature,
            } => {
                if *protocol_version != TRUST_PROTOCOL_VERSION
                    || !member(&chain, approver_certificate)
                {
                    return Err(CoreError::TrustChainInvalid);
                }
                verify_device_approval(
                    crypto,
                    account,
                    approver_certificate,
                    new_certificate,
                    challenge,
                    *expires_at_unix,
                    signature,
                )
                .map_err(invalid)?;
                (*new_certificate, *expires_at_unix)
            }
            TrustLink::Recovery {
                protocol_version,
                registration,
                new_certificate,
                challenge,
                expires_at_unix,
                signature,
            } => {
                if *protocol_version != TRUST_PROTOCOL_VERSION
                    || !member(&chain, registration.registrar_certificate)
                {
                    return Err(CoreError::TrustChainInvalid);
                }
                verify_recovery_registration(
                    crypto,
                    account,
                    registration.registrar_certificate,
                    registration.recovery_public_key,
                    registration.challenge,
                    registration.expires_at_unix,
                    registration.signature,
                )
                .map_err(invalid)?;
                verify_recovery_approval(
                    crypto,
                    account,
                    registration.recovery_public_key,
                    new_certificate,
                    challenge,
                    *expires_at_unix,
                    signature,
                )
                .map_err(invalid)?;
                (*new_certificate, *expires_at_unix)
            }
        };
        let (new_bytes, expires_at) = new_cert;
        let cert = DeviceCertificate::decode(new_bytes).map_err(invalid)?;
        if expires_at < cert.issued_at_unix
            || chain
                .iter()
                .any(|(_, c)| c.device_id == cert.device_id || c.person_key == cert.person_key)
        {
            return Err(CoreError::TrustChainInvalid);
        }
        chain.push((new_bytes.to_vec(), cert));
    }

    let root = chain[0].1.clone();
    let mut revoked: BTreeSet<DeviceId> = revoked_ids.iter().copied().collect();
    let mut revoked_keys: Vec<(DeviceId, Option<PersonKey>)> = revoked_ids
        .iter()
        .map(|id| {
            let key = chain
                .iter()
                .find(|(_, c)| c.device_id == *id)
                .map(|(_, c)| c.person_key.clone());
            (*id, key)
        })
        .collect();
    for r in revocations {
        if r.protocol_version != TRUST_PROTOCOL_VERSION || !member(&chain, r.revoker_certificate) {
            return Err(CoreError::TrustChainInvalid);
        }
        verify_revocation(
            crypto,
            account,
            r.revoker_certificate,
            r.revoked_certificate,
            r.reason,
            r.challenge,
            r.expires_at_unix,
            r.signature,
        )
        .map_err(invalid)?;
        let revoked_cert = DeviceCertificate::decode(r.revoked_certificate).map_err(invalid)?;
        revoked.insert(revoked_cert.device_id);
        revoked_keys.push((revoked_cert.device_id, Some(revoked_cert.person_key)));
    }
    Ok(LineageOutcome {
        account: account.clone(),
        root,
        trusted: chain
            .into_iter()
            .filter(|(_, c)| !revoked.contains(&c.device_id))
            .collect(),
        revoked: revoked_keys,
    })
}

fn verify_ed25519(
    crypto: &impl OpenMlsCrypto,
    public_key: &[u8],
    payload: &[u8],
    signature: &[u8],
) -> CoreResult<()> {
    if signature.len() != ED25519_SIGNATURE_LEN || public_key.len() != ED25519_PUBLIC_LEN {
        return Err(CoreError::AuthenticationFailure);
    }
    crypto
        .verify_signature(SignatureScheme::ED25519, payload, public_key, signature)
        .map_err(|_| CoreError::AuthenticationFailure)
}

/// Extracts the device ID from a credential *without* trusting it (used only
/// to locate a member for removal; trust decisions always use `validate`).
pub(crate) fn device_id_of(credential: &Credential) -> Option<DeviceId> {
    DeviceCertificate::decode(credential.serialized_content())
        .ok()
        .map(|c| c.device_id)
}

pub(crate) fn put(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
    out.extend_from_slice(bytes);
}

/// Bounds-checked reader for our own encodings.
pub(crate) struct Reader<'a>(pub(crate) &'a [u8]);

impl<'a> Reader<'a> {
    pub(crate) fn u8(&mut self) -> CoreResult<u8> {
        let (&b, rest) = self.0.split_first().ok_or(CoreError::InvalidCredential)?;
        self.0 = rest;
        Ok(b)
    }
    pub(crate) fn fixed<const N: usize>(&mut self) -> CoreResult<[u8; N]> {
        if self.0.len() < N {
            return Err(CoreError::InvalidCredential);
        }
        let (head, rest) = self.0.split_at(N);
        self.0 = rest;
        Ok(head.try_into().expect("length checked"))
    }
    pub(crate) fn var(&mut self) -> CoreResult<&'a [u8]> {
        let len = u32::from_be_bytes(self.fixed::<4>()?) as usize;
        if self.0.len() < len {
            return Err(CoreError::InvalidCredential);
        }
        let (head, rest) = self.0.split_at(len);
        self.0 = rest;
        Ok(head)
    }
}
