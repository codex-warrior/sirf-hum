//! C ABI for Dart (D-063: hand-written ABI + Flutter native assets).
//!
//! Ownership and lifecycle rules, every function:
//! - **Handles:** `sh_crypto_open` returns an opaque `ShCore*` owned by the
//!   caller until `sh_crypto_close`. The core is behind a mutex; calls on one
//!   handle are serialized. A handle must not be used after close.
//! - **Inputs:** `(ptr, len)` pairs are borrowed for the call only; Rust copies
//!   what it keeps. A null `ptr` with `len == 0` is an empty slice.
//! - **Outputs:** `ShBuf` values are allocated by Rust and owned by the caller,
//!   who must release each exactly once with `sh_crypto_buf_free` (which also
//!   wipes the bytes). Outputs are written only when the call returns 0.
//! - **Errors:** the return value is 0 or a negative `CoreError` code. No
//!   strings, no debug output, no secrets cross this boundary.
//! - **Panics:** caught at every entry point (`SH_INTERNAL`); never unwind
//!   into Dart.
//! - **Secrets:** no function returns device/person private keys, epoch
//!   secrets or serialized state. Two things leave on purpose, for display
//!   only: decrypted application messages (`sh_crypto_process`,
//!   `sh_crypto_receive_message`, `sh_crypto_history`) and a newly
//!   created recovery key's text (`sh_crypto_create_recovery_key`, once, by
//!   explicit user action, D-076). A recovery key typed by the user comes in
//!   through `sh_crypto_recovery_approval` and is wiped after signing.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;
use std::sync::Mutex;

use zeroize::Zeroize;

use crate::identity::{AccountId, DeviceId, PersonKey, ProofPurpose, RevocationReason};
use crate::keystore::{
    EphemeralTestKeyStore, InsecureFileTestKeyStore, KeyEncryptionKeyProvider, PlatformProvidedKey,
};
use crate::store::FileStore;
use crate::{CoreError, CryptoCore, Incoming};

/// Bumped on any incompatible ABI change; Dart refuses mismatches.
/// v2 (Prompt 07): platform store key, account check, device proof.
/// v3 (Prompt 08): device approval, approval code, recovery key.
/// v4 (Prompt 09): signed revocation, reset cancellation, trust epoch,
/// peer-side lineage verification.
/// v5 (Prompt 10): device-pinned lineage trust, staged commits, messages with
/// authenticated routing, sealed local history. v4 functions are unchanged.
pub const ABI_VERSION: u32 = 5;

pub const KEYSTORE_EPHEMERAL_TEST: u32 = 1;
pub const KEYSTORE_INSECURE_FILE_TEST: u32 = 2;
/// The platform keystore adapter: the key arrives through
/// `sh_crypto_open_with_platform_key`, never through `sh_crypto_open`
/// (which returns Unsupported for this value).
pub const KEYSTORE_PLATFORM: u32 = 100;

pub const INCOMING_APPLICATION: u32 = 1;
pub const INCOMING_COMMIT: u32 = 2;
pub const INCOMING_REMOVED: u32 = 3;

pub struct ShCore(Mutex<CryptoCore>);

#[repr(C)]
pub struct ShBuf {
    pub ptr: *mut u8,
    pub len: usize,
}

impl ShBuf {
    fn from_vec(v: Vec<u8>) -> Self {
        let mut boxed = v.into_boxed_slice();
        let buf = ShBuf {
            ptr: boxed.as_mut_ptr(),
            len: boxed.len(),
        };
        std::mem::forget(boxed);
        buf
    }
}

fn code(r: Result<(), CoreError>) -> i32 {
    match r {
        Ok(()) => 0,
        Err(e) => e.code(),
    }
}

fn guarded(f: impl FnOnce() -> Result<(), CoreError>) -> i32 {
    catch_unwind(AssertUnwindSafe(|| code(f()))).unwrap_or(CoreError::Internal.code())
}

unsafe fn slice<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], CoreError> {
    if ptr.is_null() {
        if len == 0 {
            Ok(&[])
        } else {
            Err(CoreError::InvalidInput)
        }
    } else {
        Ok(std::slice::from_raw_parts(ptr, len))
    }
}

unsafe fn write(out: *mut ShBuf, v: Vec<u8>) -> Result<(), CoreError> {
    if out.is_null() {
        return Err(CoreError::InvalidInput);
    }
    *out = ShBuf::from_vec(v);
    Ok(())
}

unsafe fn with_core<T>(
    h: *const ShCore,
    f: impl FnOnce(&mut CryptoCore) -> Result<T, CoreError>,
) -> Result<T, CoreError> {
    let h = h.as_ref().ok_or(CoreError::InvalidInput)?;
    let mut core = h.0.lock().map_err(|_| CoreError::Internal)?;
    f(&mut core)
}

#[no_mangle]
pub extern "C" fn sh_crypto_abi_version() -> u32 {
    ABI_VERSION
}

/// # Safety
/// `dir[..dir_len]` must be readable (or null with `dir_len == 0`).
unsafe fn open_dir(dir: *const u8, dir_len: usize) -> Result<PathBuf, CoreError> {
    let dir = std::str::from_utf8(slice(dir, dir_len)?).map_err(|_| CoreError::InvalidInput)?;
    if dir.is_empty() {
        return Err(CoreError::InvalidInput);
    }
    Ok(PathBuf::from(dir))
}

/// # Safety
/// `out` must be writable.
unsafe fn open_into(
    dir: &std::path::Path,
    keys: &dyn KeyEncryptionKeyProvider,
    out: *mut *mut ShCore,
) -> Result<(), CoreError> {
    let core = CryptoCore::open(Box::new(FileStore::open(dir)?), keys)?;
    *out = Box::into_raw(Box::new(ShCore(Mutex::new(core))));
    Ok(())
}

/// Opens or restores the core for one device from `dir` (app-private) with a
/// TEST key store (`KEYSTORE_EPHEMERAL_TEST` / `KEYSTORE_INSECURE_FILE_TEST`).
///
/// # Safety
/// `dir[..dir_len]` must be valid UTF-8 bytes; `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_open(
    dir: *const u8,
    dir_len: usize,
    keystore: u32,
    out: *mut *mut ShCore,
) -> i32 {
    guarded(|| {
        if out.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let dir = open_dir(dir, dir_len)?;
        let keys: Box<dyn KeyEncryptionKeyProvider> = match keystore {
            KEYSTORE_EPHEMERAL_TEST => Box::new(EphemeralTestKeyStore::new()),
            KEYSTORE_INSECURE_FILE_TEST => {
                Box::new(InsecureFileTestKeyStore::open_or_create(&dir)?)
            }
            _ => return Err(CoreError::Unsupported),
        };
        open_into(&dir, keys.as_ref(), out)
    })
}

/// Opens or restores the core with the 32-byte store key obtained from the
/// platform keystore adapter (D-066). The key is copied into zeroizing memory;
/// the caller wipes its own copy after the call.
///
/// # Safety
/// `dir[..dir_len]` valid UTF-8; `key[..key_len]` readable; `out` writable.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_open_with_platform_key(
    dir: *const u8,
    dir_len: usize,
    key: *const u8,
    key_len: usize,
    out: *mut *mut ShCore,
) -> i32 {
    guarded(|| {
        if out.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let dir = open_dir(dir, dir_len)?;
        let keys = PlatformProvidedKey::from_slice(slice(key, key_len)?)?;
        open_into(&dir, &keys, out)
    })
}

/// # Safety
/// `h` from `sh_crypto_open`, not used afterwards. Null is ignored.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_close(h: *mut ShCore) {
    if !h.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(h))));
    }
}

/// Encoded public identity: `device_id[16] | u32 len | person_key | u32 len | certificate`.
fn encode_public(p: &crate::PublicIdentity) -> Vec<u8> {
    let mut out = p.device_id.0.to_vec();
    crate::identity::put(&mut out, &p.person_key.0);
    crate::identity::put(&mut out, &p.certificate);
    out
}

/// # Safety
/// Valid handle; readable account bytes (UTF-8); writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_create_identity(
    h: *const ShCore,
    account: *const u8,
    len: usize,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let account =
            std::str::from_utf8(slice(account, len)?).map_err(|_| CoreError::InvalidInput)?;
        let public = with_core(h, |c| c.create_identity(AccountId::new(account)?))?;
        write(out, encode_public(&public))
    })
}

/// # Safety
/// Valid handle; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_public_identity(h: *const ShCore, out: *mut ShBuf) -> i32 {
    guarded(|| {
        let public = with_core(h, |c| c.public_identity())?;
        write(out, encode_public(&public))
    })
}

/// Returns 0 if the local identity belongs to `account`, `AccountMismatch`
/// if it belongs to another account, `IdentityState` if there is none.
///
/// # Safety
/// Valid handle; readable account bytes (UTF-8).
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_check_account(
    h: *const ShCore,
    account: *const u8,
    len: usize,
) -> i32 {
    guarded(|| {
        let account =
            std::str::from_utf8(slice(account, len)?).map_err(|_| CoreError::InvalidInput)?;
        let account = AccountId::new(account)?;
        with_core(h, |c| c.check_account(&account))
    })
}

/// Signs a 32-byte server challenge for `purpose` (1 = activation) with the
/// device signature key; `out` receives the 64-byte Ed25519 signature. The
/// signed payload is built inside Rust (identity::device_proof_payload).
///
/// # Safety
/// Valid handle; readable challenge; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_device_proof(
    h: *const ShCore,
    purpose: u32,
    challenge: *const u8,
    challenge_len: usize,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let purpose = ProofPurpose::from_u32(purpose)?;
        let challenge = slice(challenge, challenge_len)?;
        let proof = with_core(h, |c| c.device_proof(purpose, challenge))?;
        write(out, proof)
    })
}

/// Approves another device of this account (D-075): `out` receives the
/// approver PIK's 64-byte signature over the approval statement.
///
/// # Safety
/// Valid handle; readable inputs; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_approve_device(
    h: *const ShCore,
    new_certificate: *const u8,
    certificate_len: usize,
    challenge: *const u8,
    challenge_len: usize,
    expires_at_unix: u64,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let cert = slice(new_certificate, certificate_len)?;
        let challenge = slice(challenge, challenge_len)?;
        let signature = with_core(h, |c| c.approve_device(cert, challenge, expires_at_unix))?;
        write(out, signature)
    })
}

/// The six-digit comparison code for a pending device (no handle needed).
///
/// # Safety
/// Readable inputs; writable `out_code`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_approval_code(
    new_certificate: *const u8,
    certificate_len: usize,
    challenge: *const u8,
    challenge_len: usize,
    out_code: *mut u32,
) -> i32 {
    guarded(|| {
        if out_code.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let provider = openmls_rust_crypto::OpenMlsRustCrypto::default();
        *out_code = crate::identity::approval_code(
            openmls_traits::OpenMlsProvider::crypto(&provider),
            slice(new_certificate, certificate_len)?,
            slice(challenge, challenge_len)?,
        )?;
        Ok(())
    })
}

/// Creates a recovery key (D-076). `out_secret` receives the UTF-8 text to
/// show the user once; `out_public` the 32-byte public key; `out_signature`
/// this device's PIK signature registering it.
///
/// # Safety
/// Valid handle; readable challenge; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_create_recovery_key(
    h: *const ShCore,
    challenge: *const u8,
    challenge_len: usize,
    expires_at_unix: u64,
    out_secret: *mut ShBuf,
    out_public: *mut ShBuf,
    out_signature: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_secret.is_null() || out_public.is_null() || out_signature.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let challenge = slice(challenge, challenge_len)?;
        let bundle = with_core(h, |c| c.create_recovery_key(challenge, expires_at_unix))?;
        write(out_secret, bundle.secret.as_bytes().to_vec())?;
        write(out_public, bundle.public_key.to_vec())?;
        write(out_signature, bundle.registration_signature.clone())
    })
}

/// Signs a recovery approval for this device with the user-typed recovery
/// key (UTF-8). `out_signature`: 64 bytes; `out_public`: the key's public
/// half (for a local match against the registered key).
///
/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_recovery_approval(
    h: *const ShCore,
    recovery_key: *const u8,
    recovery_key_len: usize,
    challenge: *const u8,
    challenge_len: usize,
    expires_at_unix: u64,
    out_signature: *mut ShBuf,
    out_public: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_signature.is_null() || out_public.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let key = std::str::from_utf8(slice(recovery_key, recovery_key_len)?)
            .map_err(|_| CoreError::RecoveryKeyInvalid)?;
        let challenge = slice(challenge, challenge_len)?;
        let approval = with_core(h, |c| c.recovery_approval(key, challenge, expires_at_unix))?;
        write(out_signature, approval.signature)?;
        write(out_public, approval.recovery_public_key.to_vec())
    })
}

/// Signs a revocation of `revoked_certificate` (reason: 1 removed, 2 lost,
/// 3 stolen, 4 compromised) with this device's PIK (D-081).
///
/// # Safety
/// Valid handle; readable inputs; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_sign_revocation(
    h: *const ShCore,
    revoked_certificate: *const u8,
    certificate_len: usize,
    reason: u32,
    challenge: *const u8,
    challenge_len: usize,
    expires_at_unix: u64,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let reason = u8::try_from(reason).map_err(|_| CoreError::InvalidInput)?;
        let reason = RevocationReason::from_u8(reason)?;
        let cert = slice(revoked_certificate, certificate_len)?;
        let challenge = slice(challenge, challenge_len)?;
        let signature = with_core(h, |c| {
            c.sign_revocation(cert, reason, challenge, expires_at_unix)
        })?;
        write(out, signature)
    })
}

/// Signs a cancellation of a pending identity reset (D-082).
///
/// # Safety
/// Valid handle; readable challenge; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_sign_reset_cancellation(
    h: *const ShCore,
    challenge: *const u8,
    challenge_len: usize,
    expires_at_unix: u64,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let challenge = slice(challenge, challenge_len)?;
        let signature = with_core(h, |c| c.sign_reset_cancellation(challenge, expires_at_unix))?;
        write(out, signature)
    })
}

/// Records the server trust epoch; `TrustStateStale` if it went backwards
/// (D-083). `out_previous` receives the previously seen epoch.
///
/// # Safety
/// Valid handle; writable `out_previous`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_observe_trust_epoch(
    h: *const ShCore,
    epoch: u64,
    out_previous: *mut u64,
) -> i32 {
    guarded(|| {
        if out_previous.is_null() {
            return Err(CoreError::InvalidInput);
        }
        *out_previous = with_core(h, |c| c.observe_trust_epoch(epoch))?;
        Ok(())
    })
}

/// Verifies an account's trust lineage (lineage.rs format, D-084) without a
/// handle; `out` receives `u32 count | count x device id[16]` of the devices
/// still trusted.
///
/// # Safety
/// Readable blob; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_verify_lineage(
    blob: *const u8,
    blob_len: usize,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let provider = openmls_rust_crypto::OpenMlsRustCrypto::default();
        let trusted = crate::lineage::verify_encoded(
            openmls_traits::OpenMlsProvider::crypto(&provider),
            slice(blob, blob_len)?,
        )?;
        write(out, trusted)
    })
}

/// # Safety
/// Valid handle; readable 32-byte key.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_trust_verified_person_key(
    h: *const ShCore,
    key: *const u8,
    len: usize,
) -> i32 {
    guarded(|| {
        let key = PersonKey::from_slice(slice(key, len)?)?;
        with_core(h, |c| c.trust_verified_person_key(key))
    })
}

/// # Safety
/// Valid handle; readable 16-byte device ID.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_revoke_device(
    h: *const ShCore,
    device: *const u8,
    len: usize,
) -> i32 {
    guarded(|| {
        let device = DeviceId::from_slice(slice(device, len)?)?;
        with_core(h, |c| c.revoke_device(device))
    })
}

/// # Safety
/// Valid handle; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_key_package(h: *const ShCore, out: *mut ShBuf) -> i32 {
    guarded(|| {
        let kp = with_core(h, |c| c.key_package())?;
        write(out, kp)
    })
}

/// # Safety
/// Valid handle; writable `out_group`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_create_group(h: *const ShCore, out_group: *mut ShBuf) -> i32 {
    guarded(|| {
        let gid = with_core(h, |c| c.create_group())?;
        write(out_group, gid)
    })
}

/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_add_member(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    key_package: *const u8,
    kp_len: usize,
    out_commit: *mut ShBuf,
    out_welcome: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_commit.is_null() || out_welcome.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let (g, kp) = (slice(group, group_len)?, slice(key_package, kp_len)?);
        let added = with_core(h, |c| c.add_member(g, kp))?;
        write(out_commit, added.commit)?;
        write(out_welcome, added.welcome)
    })
}

/// # Safety
/// Valid handle; readable inputs; writable `out_commit`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_remove_member(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    device: *const u8,
    device_len: usize,
    out_commit: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let device = DeviceId::from_slice(slice(device, device_len)?)?;
        let commit = with_core(h, |c| c.remove_member(g, device))?;
        write(out_commit, commit)
    })
}

/// # Safety
/// Valid handle; readable group ID; writable `out_commit`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_self_update(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    out_commit: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let commit = with_core(h, |c| c.self_update(g))?;
        write(out_commit, commit)
    })
}

/// # Safety
/// Valid handle; readable Welcome; writable `out_group`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_join(
    h: *const ShCore,
    welcome: *const u8,
    len: usize,
    out_group: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let w = slice(welcome, len)?;
        let gid = with_core(h, |c| c.join(w))?;
        write(out_group, gid)
    })
}

/// # Safety
/// Valid handle; readable inputs; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_encrypt(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    plaintext: *const u8,
    pt_len: usize,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let (g, pt) = (slice(group, group_len)?, slice(plaintext, pt_len)?);
        let ct = with_core(h, |c| c.encrypt(g, pt))?;
        write(out, ct)
    })
}

/// Processes one incoming MLS message. On success `*out_kind` is
/// INCOMING_APPLICATION (payload = plaintext), INCOMING_COMMIT (payload =
/// new epoch, u64 BE) or INCOMING_REMOVED (empty payload).
///
/// # Safety
/// Valid handle; readable message; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_process(
    h: *const ShCore,
    message: *const u8,
    len: usize,
    out_kind: *mut u32,
    out_payload: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_kind.is_null() || out_payload.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let m = slice(message, len)?;
        let incoming = with_core(h, |c| c.process_incoming(m))?;
        let (kind, payload) = match incoming {
            Incoming::Application(mut pt) => {
                // Hand ownership of a copy to Dart; wipe ours.
                let v = pt.to_vec();
                pt.zeroize();
                (INCOMING_APPLICATION, v)
            }
            Incoming::CommitApplied { epoch } => (INCOMING_COMMIT, epoch.to_be_bytes().to_vec()),
            Incoming::RemovedFromGroup => (INCOMING_REMOVED, Vec::new()),
        };
        *out_kind = kind;
        write(out_payload, payload)
    })
}

/// # Safety
/// Valid handle; readable group ID; writable `out_epoch`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_epoch(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    out_epoch: *mut u64,
) -> i32 {
    guarded(|| {
        if out_epoch.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let g = slice(group, group_len)?;
        *out_epoch = with_core(h, |c| c.epoch(g))?;
        Ok(())
    })
}

/// Encoded roster: `u32 count | count × (device_id[16] | person_key[32])`.
///
/// # Safety
/// Valid handle; readable group ID; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_roster(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let roster = with_core(h, |c| c.roster(g))?;
        let mut v = (roster.len() as u32).to_be_bytes().to_vec();
        for entry in roster {
            v.extend_from_slice(&entry.device_id.0);
            v.extend_from_slice(&entry.person_key.0);
        }
        write(out, v)
    })
}

/// Deletes all local records for this core and resets it to empty.
///
/// # Safety
/// Valid handle.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_wipe(h: *const ShCore) -> i32 {
    guarded(|| with_core(h, |c| c.wipe()))
}

/// Releases a buffer returned by this library, wiping its bytes first.
///
/// # Safety
/// `buf` must come from this library and be freed at most once.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_buf_free(buf: ShBuf) {
    if !buf.ptr.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| {
            let mut boxed = Box::from_raw(ptr::slice_from_raw_parts_mut(buf.ptr, buf.len));
            boxed.zeroize();
        }));
    }
}

// ------------------------------------------------------------------ ABI v5
//
// Prompt 10 messaging core (docs/security/E2EE-MESSAGING-DESIGN.md):
// device-pinned lineage trust (D-085), staged commits (D-087), messages with
// authenticated routing (D-089) and sealed local history (D-090). All v4
// functions above keep their meaning.

/// `u32 count | count × (u32 len | bytes)`, strictly (no trailing bytes).
fn decode_list(bytes: &[u8]) -> Result<Vec<Vec<u8>>, CoreError> {
    let mut r = crate::identity::Reader(bytes);
    let count = u32::from_be_bytes(r.fixed::<4>().map_err(|_| CoreError::InvalidInput)?) as usize;
    if count > crate::limits::MAX_GROUP_MEMBERS {
        return Err(CoreError::InvalidInput);
    }
    let mut out = Vec::with_capacity(count);
    for _ in 0..count {
        out.push(r.var().map_err(|_| CoreError::InvalidInput)?.to_vec());
    }
    if !r.0.is_empty() {
        return Err(CoreError::InvalidInput);
    }
    Ok(out)
}

/// # Safety
/// `out` must be writable when not null.
unsafe fn set<T>(out: *mut T, value: T) -> Result<(), CoreError> {
    if out.is_null() {
        return Err(CoreError::InvalidInput);
    }
    *out = value;
    Ok(())
}

/// # Safety
/// Writable outputs.
unsafe fn write_staged(
    staged: crate::StagedCommit,
    out_from_epoch: *mut u64,
    out_commit: *mut ShBuf,
    out_welcome: *mut ShBuf,
) -> Result<(), CoreError> {
    set(out_from_epoch, staged.from_epoch)?;
    write(out_commit, staged.commit)?;
    if !out_welcome.is_null() {
        write(out_welcome, staged.welcome.unwrap_or_default())?;
    }
    Ok(())
}

/// Verifies an account lineage (lineage.rs format) and applies it to the
/// trust policy (D-085). `trust_epoch` is the server's
/// `accountTrust.trustEpoch`; `out_count` receives the number of that
/// account's devices now trusted.
///
/// # Safety
/// Valid handle; readable blob; writable `out_count`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_trust_lineage(
    h: *const ShCore,
    blob: *const u8,
    blob_len: usize,
    trust_epoch: u64,
    out_count: *mut u32,
) -> i32 {
    guarded(|| {
        let blob = slice(blob, blob_len)?;
        let count = with_core(h, |c| c.trust_lineage(blob, trust_epoch))?;
        set(out_count, count)
    })
}

/// Creates the conversation group (group ID = 16-byte conversation ID) and
/// stages its first commit adding the key packages (`decode_list` form).
///
/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_create_conversation_group(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    key_packages: *const u8,
    key_packages_len: usize,
    out_from_epoch: *mut u64,
    out_commit: *mut ShBuf,
    out_welcome: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_commit.is_null() || out_welcome.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let cid = slice(conversation, conversation_len)?;
        let kps = decode_list(slice(key_packages, key_packages_len)?)?;
        let staged = with_core(h, |c| c.create_conversation_group(cid, &kps))?;
        write_staged(staged, out_from_epoch, out_commit, out_welcome)
    })
}

/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_stage_add_members(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    key_packages: *const u8,
    key_packages_len: usize,
    out_from_epoch: *mut u64,
    out_commit: *mut ShBuf,
    out_welcome: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_commit.is_null() || out_welcome.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let g = slice(group, group_len)?;
        let kps = decode_list(slice(key_packages, key_packages_len)?)?;
        let staged = with_core(h, |c| c.stage_add_members(g, &kps))?;
        write_staged(staged, out_from_epoch, out_commit, out_welcome)
    })
}

/// `devices` is `n × 16` bytes of device IDs.
///
/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_stage_remove_members(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    devices: *const u8,
    devices_len: usize,
    out_from_epoch: *mut u64,
    out_commit: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let raw = slice(devices, devices_len)?;
        if raw.is_empty() || raw.len() % 16 != 0 {
            return Err(CoreError::InvalidInput);
        }
        let ids = raw
            .chunks(16)
            .map(DeviceId::from_slice)
            .collect::<Result<Vec<_>, _>>()?;
        let staged = with_core(h, |c| c.stage_remove_members(g, &ids))?;
        write_staged(staged, out_from_epoch, out_commit, ptr::null_mut())
    })
}

/// # Safety
/// Valid handle; readable group; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_stage_self_update(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    out_from_epoch: *mut u64,
    out_commit: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let staged = with_core(h, |c| c.stage_self_update(g))?;
        write_staged(staged, out_from_epoch, out_commit, ptr::null_mut())
    })
}

/// `out_has` = 1 and `out_epoch` = the staged commit's epoch when one is
/// staged, else `out_has` = 0.
///
/// # Safety
/// Valid handle; readable group; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_staged_commit_epoch(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    out_has: *mut u32,
    out_epoch: *mut u64,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let staged = with_core(h, |c| c.staged_commit_epoch(g))?;
        set(out_has, u32::from(staged.is_some()))?;
        set(out_epoch, staged.unwrap_or(0))
    })
}

/// # Safety
/// Valid handle; readable group; writable `out_epoch`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_confirm_commit(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    from_epoch: u64,
    out_epoch: *mut u64,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let epoch = with_core(h, |c| c.confirm_commit(g, from_epoch))?;
        set(out_epoch, epoch)
    })
}

/// # Safety
/// Valid handle; readable group.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_discard_commit(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    from_epoch: u64,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        with_core(h, |c| c.discard_commit(g, from_epoch))
    })
}

/// Processes another member's accepted commit. `out_kind`:
/// INCOMING_COMMIT (`out_epoch` = new epoch) or INCOMING_REMOVED.
///
/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_process_commit(
    h: *const ShCore,
    group: *const u8,
    group_len: usize,
    epoch: u64,
    sender: *const u8,
    sender_len: usize,
    commit: *const u8,
    commit_len: usize,
    out_kind: *mut u32,
    out_epoch: *mut u64,
) -> i32 {
    guarded(|| {
        let g = slice(group, group_len)?;
        let sender = DeviceId::from_slice(slice(sender, sender_len)?)?;
        let commit = slice(commit, commit_len)?;
        let incoming = with_core(h, |c| c.process_commit(g, epoch, sender, commit))?;
        match incoming {
            Incoming::CommitApplied { epoch } => {
                set(out_kind, INCOMING_COMMIT)?;
                set(out_epoch, epoch)
            }
            Incoming::RemovedFromGroup => {
                set(out_kind, INCOMING_REMOVED)?;
                set(out_epoch, 0)
            }
            Incoming::Application(_) => Err(CoreError::ProtocolViolation),
        }
    })
}

/// # Safety
/// Valid handle; readable inputs; writable `out_epoch`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_join_conversation(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    welcome: *const u8,
    welcome_len: usize,
    out_epoch: *mut u64,
) -> i32 {
    guarded(|| {
        let cid = slice(conversation, conversation_len)?;
        let w = slice(welcome, welcome_len)?;
        let epoch = with_core(h, |c| c.join_conversation(cid, w))?;
        set(out_epoch, epoch)
    })
}

/// Encrypts one message payload; `out_message_id` receives the 16-byte
/// random message ID generated by the core.
///
/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_send_message(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    payload: *const u8,
    payload_len: usize,
    out_message_id: *mut ShBuf,
    out_epoch: *mut u64,
    out_ciphertext: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_message_id.is_null() || out_ciphertext.is_null() || out_epoch.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let cid = slice(conversation, conversation_len)?;
        let p = slice(payload, payload_len)?;
        let sent = with_core(h, |c| c.send_message(cid, p))?;
        set(out_epoch, sent.epoch)?;
        write(out_message_id, sent.message_id.to_vec())?;
        write(out_ciphertext, sent.ciphertext)
    })
}

/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_reencrypt_message(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    message: *const u8,
    message_len: usize,
    out_epoch: *mut u64,
    out_ciphertext: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_ciphertext.is_null() || out_epoch.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let cid = slice(conversation, conversation_len)?;
        let mid = slice(message, message_len)?;
        let sent = with_core(h, |c| c.reencrypt_message(cid, mid))?;
        set(out_epoch, sent.epoch)?;
        write(out_ciphertext, sent.ciphertext)
    })
}

/// # Safety
/// Valid handle; readable inputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_mark_message_sent(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    message: *const u8,
    message_len: usize,
    server_time_ms: u64,
) -> i32 {
    guarded(|| {
        let cid = slice(conversation, conversation_len)?;
        let mid = slice(message, message_len)?;
        with_core(h, |c| c.mark_message_sent(cid, mid, server_time_ms))
    })
}

/// Verifies, decrypts and stores one message. `out_duplicate` = 1 means the
/// message ID was already in history (`out_payload` empty).
///
/// # Safety
/// Valid handle; readable inputs; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_receive_message(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    message: *const u8,
    message_len: usize,
    sender: *const u8,
    sender_len: usize,
    epoch: u64,
    schema_version: u32,
    protocol_version: u32,
    ciphertext: *const u8,
    ciphertext_len: usize,
    server_time_ms: u64,
    out_duplicate: *mut u32,
    out_payload: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_duplicate.is_null() || out_payload.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let cid = slice(conversation, conversation_len)?;
        let mid = slice(message, message_len)?;
        let sender = DeviceId::from_slice(slice(sender, sender_len)?)?;
        let schema = u16::try_from(schema_version).map_err(|_| CoreError::InvalidInput)?;
        let protocol = u16::try_from(protocol_version).map_err(|_| CoreError::InvalidInput)?;
        let ct = slice(ciphertext, ciphertext_len)?;
        let mut received = with_core(h, |c| {
            c.receive_message(
                cid,
                mid,
                sender,
                epoch,
                schema,
                protocol,
                ct,
                server_time_ms,
            )
        })?;
        set(out_duplicate, u32::from(received.duplicate))?;
        // Hand a copy to Dart; ours is wiped.
        let v = received.payload.to_vec();
        received.payload.zeroize();
        write(out_payload, v)
    })
}

/// The account a verified lineage assigned to a device (UTF-8), if any:
/// `out_has` = 0 means none.
///
/// # Safety
/// Valid handle; readable device ID; writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_device_account(
    h: *const ShCore,
    device: *const u8,
    device_len: usize,
    out_has: *mut u32,
    out_account: *mut ShBuf,
) -> i32 {
    guarded(|| {
        if out_account.is_null() {
            return Err(CoreError::InvalidInput);
        }
        let device = DeviceId::from_slice(slice(device, device_len)?)?;
        let account = with_core(h, |c| c.device_account(&device))?;
        set(out_has, u32::from(account.is_some()))?;
        write(out_account, account.unwrap_or_default().into_bytes())
    })
}

/// Local history of the conversation: `u32 count | count × (u32 len |
/// record)` with the record layout of `LocalMessage::encode`. Contains
/// private content (payloads): display only.
///
/// # Safety
/// Valid handle; readable conversation ID; writable `out`.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_history(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    out: *mut ShBuf,
) -> i32 {
    guarded(|| {
        let cid = slice(conversation, conversation_len)?;
        let records = with_core(h, |c| c.history(cid))?;
        let mut v = (records.len() as u32).to_be_bytes().to_vec();
        for r in &records {
            crate::identity::put(&mut v, &r.encode(cid));
        }
        write(out, v)
    })
}

/// # Safety
/// Valid handle; readable inputs.
#[no_mangle]
pub unsafe extern "C" fn sh_crypto_delete_local_message(
    h: *const ShCore,
    conversation: *const u8,
    conversation_len: usize,
    message: *const u8,
    message_len: usize,
) -> i32 {
    guarded(|| {
        let cid = slice(conversation, conversation_len)?;
        let mid = slice(message, message_len)?;
        with_core(h, |c| c.delete_local_message(cid, mid))
    })
}
