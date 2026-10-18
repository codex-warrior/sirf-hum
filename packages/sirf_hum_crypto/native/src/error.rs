//! Safe, stable error categories (Prompt 06 Part 7).
//!
//! Errors carry only a category. They never contain key material,
//! plaintext, ciphertext, serialized state, or OpenMLS debug output, so they
//! are safe to log and to return across the FFI boundary. The numeric codes
//! are part of the ABI: never renumber, only append.

use core::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum CoreError {
    /// Caller passed an argument the API does not accept.
    InvalidInput = -1,
    /// Input exceeded a size limit and was not parsed (limits.rs).
    InputTooLarge = -2,
    /// A credential/device certificate is malformed or its signature is bad.
    InvalidCredential = -3,
    /// The credential is valid but not authorized (untrusted person key,
    /// revoked device, or not a member).
    UnauthorizedDevice = -4,
    /// Bytes are not a well-formed MLS message of the expected type.
    MalformedMessage = -5,
    /// Integrity/authenticity check failed (AEAD tag, signature, MAC).
    AuthenticationFailure = -6,
    /// The message (or its key) was already used.
    Replay = -7,
    /// The message belongs to an epoch whose secrets are not available.
    StaleEpoch = -8,
    /// The message is for a group this device is not in.
    UnknownGroup = -9,
    /// Protocol rule violated (invalid commit, unexpected proposal).
    ProtocolViolation = -10,
    /// Local state failed integrity checks or has an unknown version.
    StateCorruption = -11,
    /// Writing local state failed; in-memory state was rolled back.
    PersistenceFailure = -12,
    /// Rolling back after a failure itself failed. The core must be reopened.
    RollbackFailure = -13,
    /// Operation not supported in this build or configuration.
    Unsupported = -14,
    /// Unexpected failure inside the cryptographic library.
    InternalCryptoFailure = -15,
    /// No identity exists yet, or an identity already exists.
    IdentityState = -16,
    /// A panic was caught at the FFI boundary.
    Internal = -17,
    /// The local identity belongs to a different account than the caller
    /// expects (account switching must never reuse another account's
    /// identity; DEVICE-IDENTITY.md).
    AccountMismatch = -18,
    /// A recovery key is malformed or mistyped (bad prefix, encoding,
    /// version or checksum). Says nothing about whether it is registered.
    RecoveryKeyInvalid = -19,
}

impl CoreError {
    pub const fn code(self) -> i32 {
        self as i32
    }

    pub const ALL: [CoreError; 19] = [
        CoreError::InvalidInput,
        CoreError::InputTooLarge,
        CoreError::InvalidCredential,
        CoreError::UnauthorizedDevice,
        CoreError::MalformedMessage,
        CoreError::AuthenticationFailure,
        CoreError::Replay,
        CoreError::StaleEpoch,
        CoreError::UnknownGroup,
        CoreError::ProtocolViolation,
        CoreError::StateCorruption,
        CoreError::PersistenceFailure,
        CoreError::RollbackFailure,
        CoreError::Unsupported,
        CoreError::InternalCryptoFailure,
        CoreError::IdentityState,
        CoreError::Internal,
        CoreError::AccountMismatch,
        CoreError::RecoveryKeyInvalid,
    ];

    /// Stable snake_case name, safe for logs.
    pub const fn name(self) -> &'static str {
        match self {
            CoreError::InvalidInput => "invalid_input",
            CoreError::InputTooLarge => "input_too_large",
            CoreError::InvalidCredential => "invalid_credential",
            CoreError::UnauthorizedDevice => "unauthorized_device",
            CoreError::MalformedMessage => "malformed_message",
            CoreError::AuthenticationFailure => "authentication_failure",
            CoreError::Replay => "replay",
            CoreError::StaleEpoch => "stale_epoch",
            CoreError::UnknownGroup => "unknown_group",
            CoreError::ProtocolViolation => "protocol_violation",
            CoreError::StateCorruption => "state_corruption",
            CoreError::PersistenceFailure => "persistence_failure",
            CoreError::RollbackFailure => "rollback_failure",
            CoreError::Unsupported => "unsupported",
            CoreError::InternalCryptoFailure => "internal_crypto_failure",
            CoreError::IdentityState => "identity_state",
            CoreError::Internal => "internal",
            CoreError::AccountMismatch => "account_mismatch",
            CoreError::RecoveryKeyInvalid => "recovery_key_invalid",
        }
    }
}

impl fmt::Display for CoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

impl std::error::Error for CoreError {}

pub type CoreResult<T> = Result<T, CoreError>;

/// Maps OpenMLS message-processing errors to safe categories. The original
/// error is dropped here on purpose: its Debug output can include internal
/// state and must never reach Dart or logs.
pub(crate) fn from_process_error<E>(e: openmls::prelude::ProcessMessageError<E>) -> CoreError {
    use openmls::framing::errors::{MessageDecryptionError, SecretTreeError};
    use openmls::prelude::{ProcessMessageError as P, ValidationError as V};

    match e {
        P::ValidationError(v) => match v {
            V::WrongGroupId => CoreError::UnknownGroup,
            V::WrongEpoch | V::NoPastEpochData => CoreError::StaleEpoch,
            V::UnknownMember | V::NonMemberApplicationMessage | V::UnauthorizedExternalSender => {
                CoreError::UnauthorizedDevice
            }
            V::InvalidSignature
            | V::InvalidMembershipTag
            | V::MissingMembershipTag
            | V::MissingConfirmationTag
            | V::InvalidLeafNodeSignature => CoreError::AuthenticationFailure,
            V::UnableToDecrypt(d) => match d {
                MessageDecryptionError::AeadError => CoreError::AuthenticationFailure,
                MessageDecryptionError::MalformedContent
                | MessageDecryptionError::WrongWireFormat => CoreError::MalformedMessage,
                MessageDecryptionError::GenerationOutOfBound => CoreError::StaleEpoch,
                MessageDecryptionError::SecretTreeError(s) => match s {
                    SecretTreeError::SecretReuseError => CoreError::Replay,
                    SecretTreeError::TooDistantInThePast => CoreError::StaleEpoch,
                    SecretTreeError::TooDistantInTheFuture
                    | SecretTreeError::RatchetTooLong
                    | SecretTreeError::IndexOutOfBounds => CoreError::ProtocolViolation,
                    _ => CoreError::InternalCryptoFailure,
                },
                _ => CoreError::InternalCryptoFailure,
            },
            V::LibraryError(_) => CoreError::InternalCryptoFailure,
            _ => CoreError::ProtocolViolation,
        },
        P::IncompatibleWireFormat => CoreError::MalformedMessage,
        P::InvalidCommit(_) | P::UnsupportedProposalType => CoreError::ProtocolViolation,
        P::UnauthorizedExternalApplicationMessage | P::UnauthorizedExternalCommitMessage => {
            CoreError::UnauthorizedDevice
        }
        P::GroupStateError(_) => CoreError::UnknownGroup,
        P::StorageError(_) => CoreError::PersistenceFailure,
        P::LibraryError(_) => CoreError::InternalCryptoFailure,
        #[allow(unreachable_patterns)]
        _ => CoreError::InternalCryptoFailure,
    }
}
