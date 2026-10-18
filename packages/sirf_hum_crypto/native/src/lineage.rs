//! Wire format for peer-side lineage verification (D-084): Dart assembles
//! the account's stored trust evidence into one blob; Rust decodes it
//! strictly and verifies it with `identity::verify_lineage`.
//!
//! ```text
//! version u8 = 1 | u32 len | account | u32 len | root certificate
//! | u32 n | n × link | u32 m | m × revocation | u32 k | k × revoked id[16]
//! link (approval) = 1 | protocol u8 | len|approver cert | len|new cert
//!                   | len|challenge | expires u64 BE | len|signature
//! link (recovery) = 2 | protocol u8 | len|registrar cert | len|recovery key
//!                   | len|reg challenge | reg expires u64 | len|reg signature
//!                   | len|new cert | len|challenge | expires u64 | len|signature
//! revocation      = protocol u8 | len|revoker cert | len|revoked cert | reason u8
//!                   | len|challenge | expires u64 | len|signature
//! ```
//! Output: `u32 count | count × device id[16]` of the still-trusted devices.

use openmls_traits::crypto::OpenMlsCrypto;

use crate::identity::{
    verify_lineage_detailed, AccountId, DeviceId, LineageOutcome, Reader,
    RecoveryRegistrationEvidence, RevocationEvidence, RevocationReason, TrustLink, DEVICE_ID_LEN,
};
use crate::limits::{check, MAX_LINEAGE_BYTES, MAX_LINEAGE_ITEMS};
use crate::{CoreError, CoreResult};

const FORMAT_VERSION: u8 = 1;
const KIND_APPROVAL: u8 = 1;
const KIND_RECOVERY: u8 = 2;

fn count(r: &mut Reader<'_>) -> CoreResult<usize> {
    let n = u32::from_be_bytes(r.fixed::<4>()?) as usize;
    if n > MAX_LINEAGE_ITEMS {
        return Err(CoreError::TrustChainInvalid);
    }
    Ok(n)
}

fn u64_be(r: &mut Reader<'_>) -> CoreResult<u64> {
    Ok(u64::from_be_bytes(r.fixed::<8>()?))
}

/// Decodes and verifies; returns the encoded list of trusted device IDs.
pub fn verify_encoded(crypto: &impl OpenMlsCrypto, blob: &[u8]) -> CoreResult<Vec<u8>> {
    let outcome = decode_and_verify(crypto, blob)?;
    let mut out = (outcome.trusted.len() as u32).to_be_bytes().to_vec();
    for (_, cert) in &outcome.trusted {
        out.extend_from_slice(&cert.device_id.0);
    }
    Ok(out)
}

/// Decodes and verifies; returns everything the trust policy needs (D-085).
pub fn decode_and_verify(crypto: &impl OpenMlsCrypto, blob: &[u8]) -> CoreResult<LineageOutcome> {
    check(blob.len(), MAX_LINEAGE_BYTES)?;
    let invalid = |_| CoreError::TrustChainInvalid;
    let mut r = Reader(blob);
    if r.u8().map_err(invalid)? != FORMAT_VERSION {
        return Err(CoreError::TrustChainInvalid);
    }
    let account =
        std::str::from_utf8(r.var().map_err(invalid)?).map_err(|_| CoreError::TrustChainInvalid)?;
    let account = AccountId::new(account).map_err(invalid)?;
    let root = r.var().map_err(invalid)?;

    let mut links = Vec::new();
    for _ in 0..count(&mut r).map_err(invalid)? {
        let kind = r.u8().map_err(invalid)?;
        let protocol_version = r.u8().map_err(invalid)?;
        links.push(match kind {
            KIND_APPROVAL => TrustLink::Approval {
                protocol_version,
                approver_certificate: r.var().map_err(invalid)?,
                new_certificate: r.var().map_err(invalid)?,
                challenge: r.var().map_err(invalid)?,
                expires_at_unix: u64_be(&mut r).map_err(invalid)?,
                signature: r.var().map_err(invalid)?,
            },
            KIND_RECOVERY => TrustLink::Recovery {
                protocol_version,
                registration: RecoveryRegistrationEvidence {
                    registrar_certificate: r.var().map_err(invalid)?,
                    recovery_public_key: r.var().map_err(invalid)?,
                    challenge: r.var().map_err(invalid)?,
                    expires_at_unix: u64_be(&mut r).map_err(invalid)?,
                    signature: r.var().map_err(invalid)?,
                },
                new_certificate: r.var().map_err(invalid)?,
                challenge: r.var().map_err(invalid)?,
                expires_at_unix: u64_be(&mut r).map_err(invalid)?,
                signature: r.var().map_err(invalid)?,
            },
            _ => return Err(CoreError::TrustChainInvalid),
        });
    }

    let mut revocations = Vec::new();
    for _ in 0..count(&mut r).map_err(invalid)? {
        revocations.push(RevocationEvidence {
            protocol_version: r.u8().map_err(invalid)?,
            revoker_certificate: r.var().map_err(invalid)?,
            revoked_certificate: r.var().map_err(invalid)?,
            reason: RevocationReason::from_u8(r.u8().map_err(invalid)?).map_err(invalid)?,
            challenge: r.var().map_err(invalid)?,
            expires_at_unix: u64_be(&mut r).map_err(invalid)?,
            signature: r.var().map_err(invalid)?,
        });
    }

    let mut revoked_ids = Vec::new();
    for _ in 0..count(&mut r).map_err(invalid)? {
        revoked_ids.push(DeviceId(r.fixed::<DEVICE_ID_LEN>().map_err(invalid)?));
    }
    if !r.0.is_empty() {
        return Err(CoreError::TrustChainInvalid);
    }

    verify_lineage_detailed(crypto, &account, root, &links, &revocations, &revoked_ids)
}
