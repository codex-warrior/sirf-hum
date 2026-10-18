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
//! Trust comes only from person keys the user verified locally
//! ([`TrustPolicy`]), never from the server. Signing and verification use the
//! OpenMLS crypto provider (Ed25519); no primitive is implemented here.

use std::collections::BTreeSet;

use openmls::prelude::{BasicCredential, Credential, CredentialType};
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
}

impl ProofPurpose {
    pub fn from_u32(value: u32) -> CoreResult<Self> {
        match value {
            1 => Ok(ProofPurpose::Activation),
            2 => Ok(ProofPurpose::Enrollment),
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

/// Which people this device trusts, and which devices are revoked.
#[derive(Clone, Default, PartialEq, Eq)]
pub struct TrustPolicy {
    pub(crate) trusted_people: BTreeSet<PersonKey>,
    pub(crate) revoked_devices: BTreeSet<DeviceId>,
}

/// A credential that passed every check.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ValidatedDevice {
    pub person_key: PersonKey,
    pub device_id: DeviceId,
}

impl TrustPolicy {
    /// Validates an MLS credential plus the leaf's signature key:
    /// basic credential → strict certificate decode → certificate signature
    /// by the person key → person key trusted → device not revoked → the leaf
    /// signature key is the certified device key.
    pub fn validate(
        &self,
        crypto: &impl OpenMlsCrypto,
        credential: &Credential,
        leaf_signature_key: &[u8],
    ) -> CoreResult<ValidatedDevice> {
        if credential.credential_type() != CredentialType::Basic {
            return Err(CoreError::InvalidCredential);
        }
        let cert = DeviceCertificate::decode(credential.serialized_content())?;
        cert.verify_signature(crypto)?;
        if !self.trusted_people.contains(&cert.person_key) {
            return Err(CoreError::UnauthorizedDevice);
        }
        if self.revoked_devices.contains(&cert.device_id) {
            return Err(CoreError::UnauthorizedDevice);
        }
        if cert.device_signature_key != leaf_signature_key {
            return Err(CoreError::InvalidCredential);
        }
        Ok(ValidatedDevice {
            person_key: cert.person_key,
            device_id: cert.device_id,
        })
    }
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
