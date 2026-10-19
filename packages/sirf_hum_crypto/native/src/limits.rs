//! Input size limits (Prompt 06 Part 6, D-059). Enforced at the API boundary
//! *before* any parsing or allocation proportional to attacker input.
//!
//! These bound MLS protocol payloads only. Media never goes through MLS
//! (encrypted-object architecture, E2EE-ARCHITECTURE §7).

/// Largest plaintext accepted by `encrypt` (text-sized application data).
pub const MAX_PLAINTEXT_BYTES: usize = 64 * 1024;

/// Largest MLS message accepted by `process_incoming` (application messages
/// at the plaintext limit plus framing, and commits for small groups).
pub const MAX_INCOMING_MESSAGE_BYTES: usize = 128 * 1024;

/// Largest KeyPackage message accepted by `add_member`.
pub const MAX_KEY_PACKAGE_BYTES: usize = 16 * 1024;

/// Largest Welcome message accepted by `join`.
pub const MAX_WELCOME_BYTES: usize = 128 * 1024;

/// Largest account identifier (UTF-8 bytes). Opaque server ID, never a key.
pub const MAX_ACCOUNT_ID_BYTES: usize = 128;

/// Largest encoded device certificate.
pub const MAX_CERTIFICATE_BYTES: usize = 512;

/// Largest sealed record read from local storage.
pub const MAX_RECORD_BYTES: usize = 8 * 1024 * 1024;

/// Members per group. A couple with a few devices each is far below this;
/// the cap bounds work done per commit.
pub const MAX_GROUP_MEMBERS: usize = 16;

/// Peer-side lineage blob (D-084): an account's whole trust chain. About
/// 0.5–1 KiB per link, so this fits far more devices than a couple needs.
pub const MAX_LINEAGE_BYTES: usize = 128 * 1024;

/// Most links, revocations or revoked IDs one lineage may carry.
pub const MAX_LINEAGE_ITEMS: usize = 64;

pub(crate) fn check(len: usize, max: usize) -> crate::CoreResult<()> {
    if len > max {
        Err(crate::CoreError::InputTooLarge)
    } else {
        Ok(())
    }
}
