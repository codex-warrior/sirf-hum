//! Sirf Hum crypto core. **NOT production E2EE: unaudited.**
//!
//! Architecture and rules: `docs/security/CRYPTO-CORE-ARCHITECTURE.md`.
//!
//! Policy enforced by CI (`tool/check_crypto_core.sh`):
//! - no logging, printing or debug-print macros anywhere in `src/`, and no
//!   logging crates (checked by a source-scan test);
//! - exact dependency pins, OpenMLS `=0.9.1`;
//! - OpenMLS secret-logging features (`crypto-debug`, `content-debug`) off.

#![deny(clippy::print_stdout, clippy::print_stderr, clippy::dbg_macro)]

mod engine;
mod error;
pub mod ffi;
pub mod identity;
pub mod keystore;
pub mod limits;
pub mod lineage;
pub mod record;
pub mod recovery;
pub mod store;
pub mod trust;

pub use crate::engine::{
    media_ciphertext_len, media_object_file_name, AddResult, CryptoCore, Incoming, LocalMessage,
    MediaClass, MessageDirection, MessageState, PublicIdentity, Received, RecoveryApproval,
    RecoveryKeyBundle, RosterEntry, Sent, SentMedia, StagedCommit, CIPHERSUITE, IMPLEMENTATION,
    MEDIA_CHUNK_BYTES, MEDIA_HEADER_LEN, MEDIA_ID_LEN, MEDIA_REF_LEN, MEDIA_VIEW_LEN,
};
pub use crate::error::{CoreError, CoreResult};
