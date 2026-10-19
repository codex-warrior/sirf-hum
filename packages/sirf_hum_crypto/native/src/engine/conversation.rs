//! ABI v5 messaging core (Prompt 10; D-087, D-089, D-090, D-091).
//! Docs: `docs/security/E2EE-MESSAGING-DESIGN.md`.
//!
//! Thin policy on top of OpenMLS, like the rest of the core:
//! - **staged commits:** membership changes are generated without advancing
//!   the active epoch, then confirmed or discarded after the server
//!   arbitrates (first commit wins per epoch);
//! - **authenticated routing:** the message AAD is built here, never by the
//!   caller, and compared on receipt with the envelope fields;
//! - **local history:** every sent and received message is a sealed record
//!   written inside the same checkpoint as the MLS state change.
//!
//! A conversation's MLS group ID is its 16-byte conversation ID.

use super::*;

/// Firestore message schema version bound into the AAD (D-089).
pub const MESSAGE_SCHEMA_VERSION: u16 = 1;
/// Sirf Hum message protocol version bound into the AAD (D-089).
pub const MESSAGE_PROTOCOL_VERSION: u16 = 1;
pub const CONVERSATION_ID_LEN: usize = 16;
pub const MESSAGE_ID_LEN: usize = 16;

const AAD_CONTEXT: &[u8] = b"SirfHum-MessageAAD";
const AAD_VERSION: u8 = 1;
const HISTORY_VERSION: u8 = 1;
const HISTORY_PREFIX: &str = "msg_";

/// A commit generated but not yet applied (D-087). `from_epoch` is the
/// active epoch it was made from: the epoch the server arbitrates.
pub struct StagedCommit {
    pub from_epoch: u64,
    pub commit: Vec<u8>,
    /// For adds: the Welcome for the new devices.
    pub welcome: Option<Vec<u8>>,
}

impl core::fmt::Debug for StagedCommit {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(
            f,
            "StagedCommit(from_epoch: {}, <redacted>)",
            self.from_epoch
        )
    }
}

/// An encrypted outgoing message, ready for the envelope.
pub struct Sent {
    pub message_id: [u8; MESSAGE_ID_LEN],
    pub epoch: u64,
    pub ciphertext: Vec<u8>,
}

impl core::fmt::Debug for Sent {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "Sent(epoch: {}, <redacted>)", self.epoch)
    }
}

/// The outcome of receiving one message.
pub struct Received {
    /// Decrypted payload (empty for a duplicate). Wiped on drop.
    pub payload: Zeroizing<Vec<u8>>,
    /// The message ID was already in local history; nothing was processed.
    pub duplicate: bool,
}

impl core::fmt::Debug for Received {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(f, "Received(duplicate: {}, <redacted>)", self.duplicate)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageDirection {
    Outgoing = 1,
    Incoming = 2,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageState {
    /// Encrypted locally, not yet accepted by the server (the outbox).
    Queued = 1,
    /// Accepted by the server.
    Sent = 2,
    /// Received and decrypted.
    Received = 3,
}

/// One message of local history, as sealed on disk.
pub struct LocalMessage {
    pub message_id: [u8; MESSAGE_ID_LEN],
    pub sender_device_id: DeviceId,
    pub direction: MessageDirection,
    pub state: MessageState,
    pub epoch: u64,
    pub created_at_ms: u64,
    pub server_time_ms: u64,
    /// The application payload (private content). Wiped on drop.
    pub payload: Zeroizing<Vec<u8>>,
    /// Only while `Queued`: the ciphertext to upload.
    pub ciphertext: Option<Vec<u8>>,
}

impl core::fmt::Debug for LocalMessage {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        write!(
            f,
            "LocalMessage({:?}, {:?}, <redacted>)",
            self.direction, self.state
        )
    }
}

impl LocalMessage {
    /// `version | conversation[16] | message[16] | sender[16] | direction |
    /// state | epoch u64 | created u64 | server u64 | len|payload | has_ct u8
    /// [| len|ciphertext]`. Also the FFI form of one history entry.
    pub(crate) fn encode(&self, conversation: &[u8]) -> Zeroizing<Vec<u8>> {
        let mut out = Zeroizing::new(Vec::with_capacity(128 + self.payload.len()));
        out.push(HISTORY_VERSION);
        out.extend_from_slice(conversation);
        out.extend_from_slice(&self.message_id);
        out.extend_from_slice(&self.sender_device_id.0);
        out.push(self.direction as u8);
        out.push(self.state as u8);
        out.extend_from_slice(&self.epoch.to_be_bytes());
        out.extend_from_slice(&self.created_at_ms.to_be_bytes());
        out.extend_from_slice(&self.server_time_ms.to_be_bytes());
        put(&mut out, &self.payload);
        match &self.ciphertext {
            Some(ct) => {
                out.push(1);
                put(&mut out, ct);
            }
            None => out.push(0),
        }
        out
    }

    fn decode(bytes: &[u8], conversation: &[u8], message: &[u8]) -> CoreResult<Self> {
        let c = |_| CoreError::StateCorruption;
        let mut r = Reader(bytes);
        if r.u8().map_err(c)? != HISTORY_VERSION
            || r.fixed::<CONVERSATION_ID_LEN>().map_err(c)? != conversation
        {
            return Err(CoreError::StateCorruption);
        }
        let message_id = r.fixed::<MESSAGE_ID_LEN>().map_err(c)?;
        if message_id != message {
            return Err(CoreError::StateCorruption);
        }
        let sender_device_id = DeviceId(r.fixed::<DEVICE_ID_LEN>().map_err(c)?);
        let direction = match r.u8().map_err(c)? {
            1 => MessageDirection::Outgoing,
            2 => MessageDirection::Incoming,
            _ => return Err(CoreError::StateCorruption),
        };
        let state = match r.u8().map_err(c)? {
            1 => MessageState::Queued,
            2 => MessageState::Sent,
            3 => MessageState::Received,
            _ => return Err(CoreError::StateCorruption),
        };
        let u64_be = |r: &mut Reader<'_>| -> CoreResult<u64> {
            Ok(u64::from_be_bytes(r.fixed::<8>().map_err(c)?))
        };
        let epoch = u64_be(&mut r)?;
        let created_at_ms = u64_be(&mut r)?;
        let server_time_ms = u64_be(&mut r)?;
        let payload = Zeroizing::new(r.var().map_err(c)?.to_vec());
        let ciphertext = match r.u8().map_err(c)? {
            0 => None,
            1 => Some(r.var().map_err(c)?.to_vec()),
            _ => return Err(CoreError::StateCorruption),
        };
        if !r.0.is_empty() || (state == MessageState::Queued) != ciphertext.is_some() {
            return Err(CoreError::StateCorruption);
        }
        Ok(Self {
            message_id,
            sender_device_id,
            direction,
            state,
            epoch,
            created_at_ms,
            server_time_ms,
            payload,
            ciphertext,
        })
    }
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push(DIGITS[(b >> 4) as usize] as char);
        s.push(DIGITS[(b & 0x0f) as usize] as char);
    }
    s
}

fn history_name(conversation: &[u8], message: &[u8]) -> String {
    format!("{HISTORY_PREFIX}{}_{}", hex(conversation), hex(message))
}

pub(super) fn conversation_id(bytes: &[u8]) -> CoreResult<&[u8]> {
    if bytes.len() != CONVERSATION_ID_LEN {
        return Err(CoreError::InvalidInput);
    }
    Ok(bytes)
}

pub(super) fn message_id(bytes: &[u8]) -> CoreResult<[u8; MESSAGE_ID_LEN]> {
    bytes.try_into().map_err(|_| CoreError::InvalidInput)
}

/// The exact AAD of a message (D-089).
pub(crate) fn message_aad(
    schema_version: u16,
    protocol_version: u16,
    conversation: &[u8],
    message: &[u8],
    sender: &DeviceId,
) -> Vec<u8> {
    let mut out = Vec::with_capacity(AAD_CONTEXT.len() + 5 + 48);
    out.extend_from_slice(AAD_CONTEXT);
    out.push(AAD_VERSION);
    out.extend_from_slice(&schema_version.to_be_bytes());
    out.extend_from_slice(&protocol_version.to_be_bytes());
    out.extend_from_slice(conversation);
    out.extend_from_slice(message);
    out.extend_from_slice(&sender.0);
    out
}

pub(super) fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn parse_key_packages(key_packages: &[Vec<u8>]) -> CoreResult<Vec<KeyPackageIn>> {
    if key_packages.is_empty() || key_packages.len() > MAX_KEY_PACKAGES_PER_COMMIT {
        return Err(CoreError::InvalidInput);
    }
    key_packages
        .iter()
        .map(|kp| {
            limits::check(kp.len(), MAX_KEY_PACKAGE_BYTES)?;
            match parse(kp)?.extract() {
                MlsMessageBodyIn::KeyPackage(k) => Ok(k),
                _ => Err(CoreError::MalformedMessage),
            }
        })
        .collect()
}

impl CryptoCore {
    // ------------------------------------------------------ staged commits

    /// Creates the conversation's MLS group (group ID = conversation ID) and
    /// stages the commit adding `key_packages`. Nothing is active until
    /// [`Self::confirm_commit`]`(0)`; [`Self::discard_commit`] deletes the
    /// group again.
    pub fn create_conversation_group(
        &mut self,
        conversation: &[u8],
        key_packages: &[Vec<u8>],
    ) -> CoreResult<StagedCommit> {
        self.guard()?;
        self.identity()?;
        let cid = conversation_id(conversation)?.to_vec();
        if self.state.groups.contains_key(&cid) {
            return Err(CoreError::InvalidInput);
        }
        let kps = parse_key_packages(key_packages)?;
        self.transact(|core| {
            let id = core.identity()?;
            let group = MlsGroup::new_with_group_id(
                &core.state.provider,
                &id.signer(),
                &create_config(),
                GroupId::from_slice(&cid),
                id.credential_with_key(),
            )
            .map_err(|_| CoreError::InternalCryptoFailure)?;
            core.state.groups.insert(cid.clone(), group);
            core.stage_adds(&cid, kps)
        })
    }

    /// Stages a commit adding devices (validated against the trust policy
    /// before anything is generated).
    pub fn stage_add_members(
        &mut self,
        group_id: &[u8],
        key_packages: &[Vec<u8>],
    ) -> CoreResult<StagedCommit> {
        self.guard()?;
        self.identity()?;
        let kps = parse_key_packages(key_packages)?;
        self.transact(|core| core.stage_adds(group_id, kps))
    }

    fn stage_adds(&mut self, group_id: &[u8], kps: Vec<KeyPackageIn>) -> CoreResult<StagedCommit> {
        let signer = self.identity()?.signer();
        let State {
            provider,
            groups,
            trust,
            ..
        } = &mut self.state;
        let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
        if group.pending_commit().is_some() {
            return Err(CoreError::CommitPending);
        }
        let mut valid = Vec::with_capacity(kps.len());
        let mut adding = std::collections::BTreeSet::new();
        for kp_in in kps {
            let kp = kp_in
                .validate(provider.crypto(), ProtocolVersion::Mls10)
                .map_err(|_| CoreError::InvalidCredential)?;
            let leaf = kp.leaf_node();
            let device = trust.validate(
                provider.crypto(),
                leaf.credential(),
                leaf.signature_key().as_slice(),
            )?;
            let already = group
                .members()
                .any(|m| crate::identity::device_id_of(&m.credential) == Some(device.device_id));
            if already || !adding.insert(device.device_id) {
                return Err(CoreError::InvalidInput);
            }
            valid.push(kp);
        }
        if group.members().count() + valid.len() > MAX_GROUP_MEMBERS {
            return Err(CoreError::Unsupported);
        }
        let from_epoch = group.epoch().as_u64();
        let (commit, welcome, _info) = group
            .add_members(provider, &signer, &valid)
            .map_err(|_| CoreError::ProtocolViolation)?;
        Ok(StagedCommit {
            from_epoch,
            commit: ser(&commit)?,
            welcome: Some(ser(&welcome)?),
        })
    }

    /// Stages a commit removing devices (e.g. revoked ones). Removing this
    /// device itself is refused.
    pub fn stage_remove_members(
        &mut self,
        group_id: &[u8],
        devices: &[DeviceId],
    ) -> CoreResult<StagedCommit> {
        self.guard()?;
        let own = self.identity()?.certificate.device_id;
        if devices.is_empty() || devices.contains(&own) {
            return Err(CoreError::InvalidInput);
        }
        self.transact(|core| {
            let signer = core.identity()?.signer();
            let State {
                provider, groups, ..
            } = &mut core.state;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            if group.pending_commit().is_some() {
                return Err(CoreError::CommitPending);
            }
            let mut leaves = Vec::with_capacity(devices.len());
            for device in devices {
                let leaf = group
                    .members()
                    .find(|m| crate::identity::device_id_of(&m.credential) == Some(*device))
                    .ok_or(CoreError::InvalidInput)?
                    .index;
                if leaves.contains(&leaf) {
                    return Err(CoreError::InvalidInput);
                }
                leaves.push(leaf);
            }
            let from_epoch = group.epoch().as_u64();
            let (commit, _w, _i) = group
                .remove_members(provider, &signer, &leaves)
                .map_err(|_| CoreError::ProtocolViolation)?;
            Ok(StagedCommit {
                from_epoch,
                commit: ser(&commit)?,
                welcome: None,
            })
        })
    }

    /// Stages a self update (fresh leaf keys: post-compromise healing).
    pub fn stage_self_update(&mut self, group_id: &[u8]) -> CoreResult<StagedCommit> {
        self.guard()?;
        self.identity()?;
        self.transact(|core| {
            let signer = core.identity()?.signer();
            let State {
                provider, groups, ..
            } = &mut core.state;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            if group.pending_commit().is_some() {
                return Err(CoreError::CommitPending);
            }
            let from_epoch = group.epoch().as_u64();
            let bundle = group
                .self_update(provider, &signer, LeafNodeParameters::default())
                .map_err(|_| CoreError::ProtocolViolation)?;
            let (commit, _w, _i) = bundle.into_messages();
            Ok(StagedCommit {
                from_epoch,
                commit: ser(&commit)?,
                welcome: None,
            })
        })
    }

    /// The epoch a staged commit was made from, if one is staged (e.g. after
    /// a restart, to resolve it against the server).
    pub fn staged_commit_epoch(&self, group_id: &[u8]) -> CoreResult<Option<u64>> {
        self.guard()?;
        let group = self
            .state
            .groups
            .get(group_id)
            .ok_or(CoreError::UnknownGroup)?;
        Ok(group
            .pending_commit()
            .is_some()
            .then(|| group.epoch().as_u64()))
    }

    /// Applies the staged commit the server accepted for `from_epoch`, once.
    /// A repeated confirm of the same epoch returns the current epoch;
    /// anything else is `NoStagedCommit` and changes nothing.
    pub fn confirm_commit(&mut self, group_id: &[u8], from_epoch: u64) -> CoreResult<u64> {
        self.guard()?;
        self.identity()?;
        self.transact(|core| {
            let State {
                provider,
                groups,
                confirmed,
                ..
            } = &mut core.state;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            let epoch = group.epoch().as_u64();
            if group.pending_commit().is_none() {
                return if confirmed.get(group_id) == Some(&from_epoch) && epoch == from_epoch + 1 {
                    Ok(epoch)
                } else {
                    Err(CoreError::NoStagedCommit)
                };
            }
            if epoch != from_epoch {
                return Err(CoreError::NoStagedCommit);
            }
            group
                .merge_pending_commit(provider)
                .map_err(|_| CoreError::PersistenceFailure)?;
            confirmed.insert(group_id.to_vec(), from_epoch);
            Ok(group.epoch().as_u64())
        })
    }

    /// Drops the staged commit for `from_epoch` (the server refused it or
    /// another commit won). Discarding the first commit of a group this
    /// device created also deletes the group. Nothing staged: no-op.
    pub fn discard_commit(&mut self, group_id: &[u8], from_epoch: u64) -> CoreResult<()> {
        self.guard()?;
        self.identity()?;
        self.transact(|core| {
            let State {
                provider, groups, ..
            } = &mut core.state;
            let group = groups.get_mut(group_id).ok_or(CoreError::UnknownGroup)?;
            if group.pending_commit().is_none() {
                return Ok(());
            }
            let epoch = group.epoch().as_u64();
            if epoch != from_epoch {
                return Err(CoreError::NoStagedCommit);
            }
            if epoch == 0 {
                // Only a locally created group sits at epoch 0 (joined groups
                // start later): without its first commit it means nothing.
                group
                    .delete(provider.storage())
                    .map_err(|_| CoreError::PersistenceFailure)?;
                groups.remove(group_id);
            } else {
                group
                    .clear_pending_commit(provider.storage())
                    .map_err(|_| CoreError::PersistenceFailure)?;
            }
            Ok(())
        })
    }

    /// Processes another member's commit that the server accepted for
    /// `epoch`, sent by `sender` (D-088). Refused while a commit of ours is
    /// staged (`CommitPending`): discard first.
    pub fn process_commit(
        &mut self,
        group_id: &[u8],
        epoch: u64,
        sender: DeviceId,
        commit: &[u8],
    ) -> CoreResult<Incoming> {
        self.guard()?;
        self.identity()?;
        limits::check(commit.len(), MAX_INCOMING_MESSAGE_BYTES)?;
        if self.staged_commit_epoch(group_id)?.is_some() {
            return Err(CoreError::CommitPending);
        }
        let routing = Routing {
            group_id: group_id.to_vec(),
            epoch,
            sender,
            expected_aad: None,
        };
        self.process_inner(commit, Some(&routing), |_, _| Ok(()))
    }

    /// Joins the conversation from a Welcome; refuses a Welcome for any other
    /// group. Returns the epoch joined.
    pub fn join_conversation(&mut self, conversation: &[u8], welcome: &[u8]) -> CoreResult<u64> {
        let cid = conversation_id(conversation)?.to_vec();
        self.join_with(welcome, Some(&cid))?;
        self.epoch(&cid)
    }

    // ------------------------------------------------------------ messages

    /// Encrypts one message payload for the conversation (D-089). The message
    /// ID is random (OS CSPRNG), generated here. Refused while a commit is
    /// staged, and while the roster holds any device this device no longer
    /// trusts (e.g. revoked): remove it first, so no new content is
    /// encrypted to it. The payload and queued ciphertext are sealed into
    /// local history in the same transaction.
    pub fn send_message(&mut self, conversation: &[u8], payload: &[u8]) -> CoreResult<Sent> {
        self.guard()?;
        self.identity()?;
        let cid = conversation_id(conversation)?.to_vec();
        // Media references (kind 2) carry keys and are built only by
        // `send_media` (D-094): a caller-supplied one is refused.
        if payload.is_empty() || super::media::claims_media(payload) {
            return Err(CoreError::InvalidInput);
        }
        limits::check(payload.len(), MAX_MESSAGE_PAYLOAD_BYTES)?;
        let mut mid = [0u8; MESSAGE_ID_LEN];
        OsRng.fill_bytes(&mut mid);
        let payload = Zeroizing::new(payload.to_vec());
        self.transact(|core| core.encrypt_into_history(&cid, mid, payload, now_ms()))
    }

    /// Re-encrypts a queued message under the current epoch after the server
    /// refused it as stale (D-091). Same message ID; the refused ciphertext
    /// was never accepted.
    pub fn reencrypt_message(&mut self, conversation: &[u8], message: &[u8]) -> CoreResult<Sent> {
        self.guard()?;
        self.identity()?;
        let cid = conversation_id(conversation)?.to_vec();
        let mid = message_id(message)?;
        let record = self
            .load_history(&cid, &mid)?
            .ok_or(CoreError::InvalidInput)?;
        if record.direction != MessageDirection::Outgoing || record.state != MessageState::Queued {
            return Err(CoreError::InvalidInput);
        }
        let created = record.created_at_ms;
        self.transact(|core| core.encrypt_into_history(&cid, mid, record.payload, created))
    }

    pub(super) fn encrypt_into_history(
        &mut self,
        cid: &[u8],
        mid: [u8; MESSAGE_ID_LEN],
        payload: Zeroizing<Vec<u8>>,
        created_at_ms: u64,
    ) -> CoreResult<Sent> {
        let (signer, own) = {
            let id = self.identity()?;
            (id.signer(), id.certificate.device_id)
        };
        let (ciphertext, epoch) = {
            let State {
                provider,
                groups,
                trust,
                ..
            } = &mut self.state;
            let group = groups.get_mut(cid).ok_or(CoreError::UnknownGroup)?;
            if group.pending_commit().is_some() {
                return Err(CoreError::CommitPending);
            }
            for m in group.members() {
                trust.check_member(provider.crypto(), &m.credential, m.signature_key.as_slice())?;
            }
            group.set_aad(message_aad(
                MESSAGE_SCHEMA_VERSION,
                MESSAGE_PROTOCOL_VERSION,
                cid,
                &mid,
                &own,
            ));
            let out = group
                .create_message(provider, &signer, &payload)
                .map_err(|_| CoreError::ProtocolViolation)?;
            (ser(&out)?, group.epoch().as_u64())
        };
        let record = LocalMessage {
            message_id: mid,
            sender_device_id: own,
            direction: MessageDirection::Outgoing,
            state: MessageState::Queued,
            epoch,
            created_at_ms,
            server_time_ms: 0,
            payload,
            ciphertext: Some(ciphertext.clone()),
        };
        self.put_history(cid, &record)?;
        Ok(Sent {
            message_id: mid,
            epoch,
            ciphertext,
        })
    }

    /// Marks a queued message as accepted by the server and drops its
    /// ciphertext. Idempotent.
    pub fn mark_message_sent(
        &mut self,
        conversation: &[u8],
        message: &[u8],
        server_time_ms: u64,
    ) -> CoreResult<()> {
        self.guard()?;
        self.identity()?;
        let cid = conversation_id(conversation)?.to_vec();
        let mid = message_id(message)?;
        let mut record = self
            .load_history(&cid, &mid)?
            .ok_or(CoreError::InvalidInput)?;
        match (record.direction, record.state) {
            (MessageDirection::Outgoing, MessageState::Sent) => Ok(()),
            (MessageDirection::Outgoing, MessageState::Queued) => {
                record.state = MessageState::Sent;
                record.ciphertext = None;
                record.server_time_ms = server_time_ms;
                self.put_history(&cid, &record)
            }
            _ => Err(CoreError::InvalidInput),
        }
    }

    /// Verifies, decrypts and stores one message (D-089). Every envelope
    /// field given here is checked against what MLS authenticated; any
    /// mismatch rolls back (the key is not consumed). A message ID already
    /// in history is reported as a duplicate without processing.
    #[allow(clippy::too_many_arguments)]
    pub fn receive_message(
        &mut self,
        conversation: &[u8],
        message: &[u8],
        sender: DeviceId,
        epoch: u64,
        schema_version: u16,
        protocol_version: u16,
        ciphertext: &[u8],
        server_time_ms: u64,
    ) -> CoreResult<Received> {
        self.guard()?;
        let own = self.identity()?.certificate.device_id;
        limits::check(ciphertext.len(), MAX_MESSAGE_CIPHERTEXT_BYTES)?;
        let cid = conversation_id(conversation)?.to_vec();
        let mid = message_id(message)?;
        if sender == own {
            // MLS senders cannot decrypt their own messages; ours are in
            // history already. A server claiming otherwise is refused.
            return Err(CoreError::EnvelopeMismatch);
        }
        if self.load_history(&cid, &mid)?.is_some() {
            return Ok(Received {
                payload: Zeroizing::new(Vec::new()),
                duplicate: true,
            });
        }
        let routing = Routing {
            group_id: cid.clone(),
            epoch,
            sender,
            expected_aad: Some(message_aad(
                schema_version,
                protocol_version,
                &cid,
                &mid,
                &sender,
            )),
        };
        let mut payload = Zeroizing::new(Vec::new());
        self.process_inner(ciphertext, Some(&routing), |core, incoming| {
            let Incoming::Application(pt) = incoming else {
                return Err(CoreError::ProtocolViolation);
            };
            // Authenticated, but a version this build does not speak: fail
            // closed ("update Sirf Hum"), never guess.
            if schema_version != MESSAGE_SCHEMA_VERSION
                || protocol_version != MESSAGE_PROTOCOL_VERSION
            {
                return Err(CoreError::Unsupported);
            }
            if pt.is_empty() || pt.len() > MAX_MESSAGE_PAYLOAD_BYTES {
                return Err(CoreError::ProtocolViolation);
            }
            // A media reference must decode strictly (D-094); Dart gets only
            // its key-free view, the full reference is sealed.
            if super::media::claims_media(pt) && super::media::MediaRef::decode(pt).is_err() {
                return Err(CoreError::ProtocolViolation);
            }
            payload = super::media::public_payload(Zeroizing::new(pt.to_vec()))?;
            core.put_history(
                &cid,
                &LocalMessage {
                    message_id: mid,
                    sender_device_id: sender,
                    direction: MessageDirection::Incoming,
                    state: MessageState::Received,
                    epoch,
                    created_at_ms: now_ms(),
                    server_time_ms,
                    payload: Zeroizing::new(pt.to_vec()),
                    ciphertext: None,
                },
            )
        })?;
        Ok(Received {
            payload,
            duplicate: false,
        })
    }

    /// The account a verified lineage assigned to `device` (D-085), so the
    /// envelope's `senderAccountId` can be checked.
    pub fn device_account(&self, device: &DeviceId) -> CoreResult<Option<String>> {
        self.guard()?;
        Ok(self.state.trust.account_of(device).map(str::to_owned))
    }

    // ------------------------------------------------------------- history

    /// All local messages of the conversation, in record-name order (the
    /// caller orders by time). Media references appear as their key-free
    /// view. Any unreadable record fails the whole call
    /// (`StateCorruption`): no partial or unauthenticated history.
    pub fn history(&self, conversation: &[u8]) -> CoreResult<Vec<LocalMessage>> {
        self.guard()?;
        self.identity()?;
        let cid = conversation_id(conversation)?;
        let prefix = format!("{HISTORY_PREFIX}{}_", hex(cid));
        let names = self.store.list(&prefix)?;
        if names.len() > MAX_HISTORY_RECORDS {
            return Err(CoreError::Unsupported);
        }
        names
            .iter()
            .map(|name| {
                let mid = decode_hex16(&name[prefix.len()..])?;
                let mut record = self
                    .load_history(cid, &mid)?
                    .ok_or(CoreError::StateCorruption)?;
                // Media keys never leave Rust (D-094).
                record.payload = super::media::public_payload(record.payload)?;
                Ok(record)
            })
            .collect()
    }

    /// Deletes one message from this device's history ("delete for me").
    /// It does not delete it from the server or from other devices.
    pub fn delete_local_message(&mut self, conversation: &[u8], message: &[u8]) -> CoreResult<()> {
        self.guard()?;
        self.identity()?;
        let cid = conversation_id(conversation)?;
        let mid = message_id(message)?;
        self.store.delete(&history_name(cid, &mid))
    }

    fn put_history(&mut self, cid: &[u8], record: &LocalMessage) -> CoreResult<()> {
        let plain = record.encode(cid);
        limits::check(plain.len(), MAX_HISTORY_RECORD_BYTES)?;
        let name = history_name(cid, &record.message_id);
        let sealed = record::seal(&self.kek, RecordKind::LocalMessage, &name, &plain)?;
        self.store.put(&name, &sealed)
    }

    pub(super) fn load_history(&self, cid: &[u8], mid: &[u8]) -> CoreResult<Option<LocalMessage>> {
        let name = history_name(cid, mid);
        match self.store.get(&name)? {
            None => Ok(None),
            Some(raw) => {
                let plain = record::open(&self.kek, RecordKind::LocalMessage, &name, &raw)?;
                LocalMessage::decode(&plain, cid, mid).map(Some)
            }
        }
    }
}

fn decode_hex16(s: &str) -> CoreResult<[u8; 16]> {
    let bytes = s.as_bytes();
    if bytes.len() != 32 {
        return Err(CoreError::StateCorruption);
    }
    let nibble = |c: u8| -> CoreResult<u8> {
        match c {
            b'0'..=b'9' => Ok(c - b'0'),
            b'a'..=b'f' => Ok(c - b'a' + 10),
            _ => Err(CoreError::StateCorruption),
        }
    };
    let mut out = [0u8; 16];
    for (i, o) in out.iter_mut().enumerate() {
        *o = nibble(bytes[2 * i])? << 4 | nibble(bytes[2 * i + 1])?;
    }
    Ok(out)
}

#[cfg(test)]
mod golden {
    use super::*;

    /// Shared with `packages/sirf_hum_crypto/test/messaging_types_test.dart`.
    pub(crate) const HISTORY_RECORD_HEX: &str = concat!(
        "01",
        "11111111111111111111111111111111",
        "22222222222222222222222222222222",
        "33333333333333333333333333333333",
        "01",
        "01",
        "0000000000000005",
        "00000000000003e8",
        "0000000000000000",
        "00000002",
        "6869",
        "01",
        "00000002",
        "aabb",
    );

    /// D-089 AAD for conversation 0x11.., message 0x22.., sender 0x33...
    pub(crate) const AAD_HEX: &str = concat!(
        "5369726648756d2d4d65737361676541414401",
        "0001",
        "0001",
        "11111111111111111111111111111111",
        "22222222222222222222222222222222",
        "33333333333333333333333333333333",
    );

    #[test]
    fn history_record_and_aad_match_the_golden_vectors() {
        let record = LocalMessage {
            message_id: [0x22; 16],
            sender_device_id: DeviceId([0x33; 16]),
            direction: MessageDirection::Outgoing,
            state: MessageState::Queued,
            epoch: 5,
            created_at_ms: 1000,
            server_time_ms: 0,
            payload: Zeroizing::new(b"hi".to_vec()),
            ciphertext: Some(vec![0xaa, 0xbb]),
        };
        let encoded = record.encode(&[0x11; 16]);
        assert_eq!(hex(&encoded), HISTORY_RECORD_HEX);
        let back = LocalMessage::decode(&encoded, &[0x11; 16], &[0x22; 16]).unwrap();
        assert_eq!(back.payload.as_slice(), b"hi");
        assert_eq!(
            LocalMessage::decode(&encoded, &[0x12; 16], &[0x22; 16]).unwrap_err(),
            CoreError::StateCorruption,
            "a record for another conversation"
        );
        let aad = message_aad(1, 1, &[0x11; 16], &[0x22; 16], &DeviceId([0x33; 16]));
        assert_eq!(hex(&aad), AAD_HEX);
    }
}
