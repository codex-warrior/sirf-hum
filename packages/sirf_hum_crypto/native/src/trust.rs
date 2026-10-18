//! Device trust policy (D-085). **The trust unit is an exact device
//! certificate, never a person key on its own.**
//!
//! Since D-074 every device has its own person key (PIK), and a PIK can sign
//! any number of certificates. Trusting a PIK would let a revoked device
//! certify a fresh device ID with its old key. So:
//!
//! - `devices` maps each trusted device ID to its exact certificate bytes;
//! - `anchors` are PIKs verified out of band (own key, partner root). An
//!   anchor roots lineage verification; on its own it is accepted only for
//!   its single pinned device;
//! - `pinned` binds each PIK to the one device ID it certifies;
//! - revoking a device also revokes its PIK, permanently;
//! - lineage (D-084) is applied per account with a monotonic trust epoch.
//!
//! No cryptographic primitive is implemented here: certificate signatures
//! are verified by `identity.rs` through the OpenMLS provider.

use std::collections::{BTreeMap, BTreeSet};

use openmls::prelude::{Credential, CredentialType};
use openmls_traits::crypto::OpenMlsCrypto;

use crate::identity::{put, DeviceCertificate, DeviceId, LineageOutcome, PersonKey, Reader};
use crate::{CoreError, CoreResult};

/// How a device came to be trusted. Wire values are part of the sealed state
/// format: never renumber.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum TrustSource {
    /// This device.
    Own = 1,
    /// Approved by this device (D-075).
    Approved = 2,
    /// The single device of an out-of-band verified person key.
    Anchor = 3,
    /// Proven by a verified account lineage (D-084).
    Lineage = 4,
}

impl TrustSource {
    fn from_u8(v: u8) -> CoreResult<Self> {
        Ok(match v {
            1 => Self::Own,
            2 => Self::Approved,
            3 => Self::Anchor,
            4 => Self::Lineage,
            _ => return Err(CoreError::StateCorruption),
        })
    }
}

/// One trusted device: its exact certificate, why it is trusted, and (for
/// lineage) which account's chain proved it.
#[derive(Clone, PartialEq, Eq)]
pub struct TrustedDevice {
    pub certificate: Vec<u8>,
    pub person_key: PersonKey,
    pub source: TrustSource,
    pub account: Option<String>,
}

impl core::fmt::Debug for TrustedDevice {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "TrustedDevice({:?}, <redacted>)", self.source)
    }
}

/// A credential that passed every check.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ValidatedDevice {
    pub person_key: PersonKey,
    pub device_id: DeviceId,
}

#[derive(Clone, Default, PartialEq, Eq)]
pub struct TrustPolicy {
    pub(crate) anchors: BTreeSet<PersonKey>,
    pub(crate) devices: BTreeMap<DeviceId, TrustedDevice>,
    pub(crate) pinned: BTreeMap<PersonKey, DeviceId>,
    pub(crate) revoked_devices: BTreeSet<DeviceId>,
    pub(crate) revoked_people: BTreeSet<PersonKey>,
    pub(crate) lineage_epochs: BTreeMap<String, u64>,
}

impl TrustPolicy {
    /// Records an out-of-band verified person key as a lineage root. A
    /// revoked key can never become an anchor again.
    pub(crate) fn anchor(&mut self, key: PersonKey) -> CoreResult<()> {
        if self.revoked_people.contains(&key) {
            return Err(CoreError::UnauthorizedDevice);
        }
        self.anchors.insert(key);
        Ok(())
    }

    /// Trusts one exact certificate. Refuses revoked devices or keys, a key
    /// already pinned to another device, and a device ID already bound to
    /// different certificate bytes.
    pub(crate) fn trust_certificate(
        &mut self,
        crypto: &impl OpenMlsCrypto,
        certificate: &[u8],
        source: TrustSource,
        account: Option<&str>,
    ) -> CoreResult<DeviceId> {
        let cert = DeviceCertificate::decode(certificate)?;
        cert.verify_signature(crypto)?;
        self.admit(certificate, &cert, source, account)?;
        Ok(cert.device_id)
    }

    fn admit(
        &mut self,
        bytes: &[u8],
        cert: &DeviceCertificate,
        source: TrustSource,
        account: Option<&str>,
    ) -> CoreResult<()> {
        if self.revoked_devices.contains(&cert.device_id)
            || self.revoked_people.contains(&cert.person_key)
        {
            return Err(CoreError::UnauthorizedDevice);
        }
        if let Some(pinned) = self.pinned.get(&cert.person_key) {
            if *pinned != cert.device_id {
                return Err(CoreError::UnauthorizedDevice);
            }
        }
        match self.devices.get_mut(&cert.device_id) {
            Some(existing) if existing.certificate != bytes => {
                return Err(CoreError::UnauthorizedDevice)
            }
            Some(existing) => {
                // Already trusted: keep the stronger local source, but record
                // the account a lineage proved it for.
                if existing.account.is_none() {
                    existing.account = account.map(str::to_owned);
                }
            }
            None => {
                self.devices.insert(
                    cert.device_id,
                    TrustedDevice {
                        certificate: bytes.to_vec(),
                        person_key: cert.person_key.clone(),
                        source,
                        account: account.map(str::to_owned),
                    },
                );
            }
        }
        self.pinned.insert(cert.person_key.clone(), cert.device_id);
        Ok(())
    }

    /// Revokes a device and, when known, its person key. Permanent.
    pub(crate) fn revoke(&mut self, device: DeviceId, key: Option<PersonKey>) {
        self.revoked_devices.insert(device);
        let known = self
            .devices
            .remove(&device)
            .map(|d| d.person_key)
            .or_else(|| {
                self.pinned
                    .iter()
                    .find(|(_, d)| **d == device)
                    .map(|(k, _)| k.clone())
            });
        for k in known.into_iter().chain(key) {
            self.revoked_people.insert(k);
        }
    }

    /// Validates an MLS credential and leaf signature key (D-057, D-085):
    /// basic credential → strict decode → certificate signature → device and
    /// person key not revoked → exact certificate trusted (or the pinned
    /// device of an anchor) → leaf key is the certified key.
    ///
    /// Takes `&mut self` because an anchor's first device is pinned here.
    /// Callers run inside `transact`, so a rejected operation rolls the pin
    /// back.
    pub fn validate(
        &mut self,
        crypto: &impl OpenMlsCrypto,
        credential: &Credential,
        leaf_signature_key: &[u8],
    ) -> CoreResult<ValidatedDevice> {
        let cert = Self::decode_credential(crypto, credential)?;
        let bytes = credential.serialized_content();
        if self.revoked_devices.contains(&cert.device_id)
            || self.revoked_people.contains(&cert.person_key)
        {
            return Err(CoreError::UnauthorizedDevice);
        }
        match self.devices.get(&cert.device_id) {
            Some(d) if d.certificate == bytes => {}
            Some(_) => return Err(CoreError::UnauthorizedDevice),
            None if self.anchors.contains(&cert.person_key) => {
                self.admit(bytes, &cert, TrustSource::Anchor, None)?
            }
            None => return Err(CoreError::UnauthorizedDevice),
        }
        if cert.device_signature_key != leaf_signature_key {
            return Err(CoreError::InvalidCredential);
        }
        Ok(ValidatedDevice {
            person_key: cert.person_key,
            device_id: cert.device_id,
        })
    }

    /// The non-mutating check senders run over the whole roster before
    /// encrypting: every member must still be trusted *now* (no anchor
    /// admission here; members were admitted when they were added).
    pub(crate) fn check_member(
        &self,
        crypto: &impl OpenMlsCrypto,
        credential: &Credential,
        leaf_signature_key: &[u8],
    ) -> CoreResult<DeviceId> {
        let cert = Self::decode_credential(crypto, credential)?;
        let trusted = self
            .devices
            .get(&cert.device_id)
            .is_some_and(|d| d.certificate == credential.serialized_content());
        if !trusted
            || self.revoked_devices.contains(&cert.device_id)
            || self.revoked_people.contains(&cert.person_key)
            || cert.device_signature_key != leaf_signature_key
        {
            return Err(CoreError::UnauthorizedDevice);
        }
        Ok(cert.device_id)
    }

    /// The account a lineage assigned to `device`, if any.
    pub(crate) fn account_of(&self, device: &DeviceId) -> Option<&str> {
        self.devices.get(device).and_then(|d| d.account.as_deref())
    }

    fn decode_credential(
        crypto: &impl OpenMlsCrypto,
        credential: &Credential,
    ) -> CoreResult<DeviceCertificate> {
        if credential.credential_type() != CredentialType::Basic {
            return Err(CoreError::InvalidCredential);
        }
        let cert = DeviceCertificate::decode(credential.serialized_content())?;
        cert.verify_signature(crypto)?;
        Ok(cert)
    }

    /// Applies a verified lineage (D-085). The root's person key must be an
    /// anchor; an older trust epoch than one already applied for this
    /// account is refused (`TrustStateStale`). Revocations are applied
    /// first and are permanent. This account's previously lineage-trusted
    /// devices that the new lineage no longer proves are dropped (server
    /// omission can only remove trust). A conflict with a pin or with
    /// different certificate bytes for a known device fails the whole call.
    pub(crate) fn apply_lineage(&mut self, outcome: &LineageOutcome, epoch: u64) -> CoreResult<()> {
        let account = outcome.account.as_str().to_owned();
        if let Some(seen) = self.lineage_epochs.get(&account) {
            if epoch < *seen {
                return Err(CoreError::TrustStateStale);
            }
        }
        if !self.anchors.contains(&outcome.root.person_key) {
            return Err(CoreError::UnauthorizedDevice);
        }
        if let Some(pinned) = self.pinned.get(&outcome.root.person_key) {
            if *pinned != outcome.root.device_id {
                return Err(CoreError::TrustChainInvalid);
            }
        }
        for (device, key) in &outcome.revoked {
            self.revoke(*device, key.clone());
        }
        self.devices.retain(|_, d| {
            !(d.source == TrustSource::Lineage && d.account.as_deref() == Some(account.as_str()))
        });
        for (bytes, cert) in &outcome.trusted {
            if self.revoked_devices.contains(&cert.device_id)
                || self.revoked_people.contains(&cert.person_key)
            {
                continue;
            }
            self.admit(bytes, cert, TrustSource::Lineage, Some(&account))
                .map_err(|_| CoreError::TrustChainInvalid)?;
        }
        self.lineage_epochs.insert(account, epoch);
        Ok(())
    }

    // ------------------------------------------------------- persistence

    /// Serialized form inside the sealed MLS state record (state version 2).
    pub(crate) fn encode(&self, out: &mut Vec<u8>) {
        out.extend_from_slice(&(self.anchors.len() as u32).to_be_bytes());
        for k in &self.anchors {
            put(out, &k.0);
        }
        out.extend_from_slice(&(self.devices.len() as u32).to_be_bytes());
        for d in self.devices.values() {
            out.push(d.source as u8);
            put(out, &d.certificate);
            put(out, d.account.as_deref().unwrap_or("").as_bytes());
        }
        out.extend_from_slice(&(self.pinned.len() as u32).to_be_bytes());
        for (k, d) in &self.pinned {
            put(out, &k.0);
            out.extend_from_slice(&d.0);
        }
        out.extend_from_slice(&(self.revoked_devices.len() as u32).to_be_bytes());
        for d in &self.revoked_devices {
            out.extend_from_slice(&d.0);
        }
        out.extend_from_slice(&(self.revoked_people.len() as u32).to_be_bytes());
        for k in &self.revoked_people {
            put(out, &k.0);
        }
        out.extend_from_slice(&(self.lineage_epochs.len() as u32).to_be_bytes());
        for (a, e) in &self.lineage_epochs {
            put(out, a.as_bytes());
            out.extend_from_slice(&e.to_be_bytes());
        }
    }

    pub(crate) fn decode(r: &mut Reader<'_>) -> CoreResult<Self> {
        let c = |_| CoreError::StateCorruption;
        let count = |r: &mut Reader<'_>| -> CoreResult<u32> {
            Ok(u32::from_be_bytes(r.fixed::<4>().map_err(c)?))
        };
        let key = |r: &mut Reader<'_>| PersonKey::from_slice(r.var().map_err(c)?).map_err(c);
        let id = |r: &mut Reader<'_>| -> CoreResult<DeviceId> {
            Ok(DeviceId(r.fixed::<16>().map_err(c)?))
        };
        let mut t = TrustPolicy::default();
        for _ in 0..count(r)? {
            t.anchors.insert(key(r)?);
        }
        for _ in 0..count(r)? {
            let source = TrustSource::from_u8(r.u8().map_err(c)?)?;
            let bytes = r.var().map_err(c)?.to_vec();
            let account = std::str::from_utf8(r.var().map_err(c)?)
                .map_err(|_| CoreError::StateCorruption)?
                .to_owned();
            let cert = DeviceCertificate::decode(&bytes).map_err(c)?;
            t.devices.insert(
                cert.device_id,
                TrustedDevice {
                    certificate: bytes,
                    person_key: cert.person_key,
                    source,
                    account: (!account.is_empty()).then_some(account),
                },
            );
        }
        for _ in 0..count(r)? {
            let k = key(r)?;
            t.pinned.insert(k, id(r)?);
        }
        for _ in 0..count(r)? {
            t.revoked_devices.insert(id(r)?);
        }
        for _ in 0..count(r)? {
            t.revoked_people.insert(key(r)?);
        }
        for _ in 0..count(r)? {
            let a = std::str::from_utf8(r.var().map_err(c)?)
                .map_err(|_| CoreError::StateCorruption)?
                .to_owned();
            t.lineage_epochs
                .insert(a, u64::from_be_bytes(r.fixed::<8>().map_err(c)?));
        }
        Ok(t)
    }
}
