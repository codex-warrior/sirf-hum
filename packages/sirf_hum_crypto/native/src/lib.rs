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
pub mod record;
pub mod recovery;
pub mod store;

pub use crate::engine::{
    AddResult, CryptoCore, Incoming, PublicIdentity, RecoveryApproval, RecoveryKeyBundle,
    RosterEntry, CIPHERSUITE, IMPLEMENTATION,
};
pub use crate::error::{CoreError, CoreResult};
