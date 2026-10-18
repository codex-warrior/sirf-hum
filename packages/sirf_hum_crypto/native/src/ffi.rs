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
//! - **Secrets:** no function returns private keys, epoch secrets or
//!   serialized state. Plaintext leaves only via `sh_crypto_process` (the
//!   decrypted application message, for display).

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;
use std::sync::Mutex;

use zeroize::Zeroize;

use crate::identity::{AccountId, DeviceId, PersonKey};
use crate::keystore::{EphemeralTestKeyStore, InsecureFileTestKeyStore, KeyEncryptionKeyProvider};
use crate::store::FileStore;
use crate::{CoreError, CryptoCore, Incoming};

/// Bumped on any incompatible ABI change; Dart refuses mismatches.
pub const ABI_VERSION: u32 = 1;

pub const KEYSTORE_EPHEMERAL_TEST: u32 = 1;
pub const KEYSTORE_INSECURE_FILE_TEST: u32 = 2;
/// Reserved for the platform keystore adapter (not implemented: Unsupported).
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

/// Opens or restores the core for one device from `dir` (app-private).
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
        let dir = std::str::from_utf8(slice(dir, dir_len)?).map_err(|_| CoreError::InvalidInput)?;
        if dir.is_empty() {
            return Err(CoreError::InvalidInput);
        }
        let dir = PathBuf::from(dir);
        let keys: Box<dyn KeyEncryptionKeyProvider> = match keystore {
            KEYSTORE_EPHEMERAL_TEST => Box::new(EphemeralTestKeyStore::new()),
            KEYSTORE_INSECURE_FILE_TEST => {
                Box::new(InsecureFileTestKeyStore::open_or_create(&dir)?)
            }
            _ => return Err(CoreError::Unsupported),
        };
        let core = CryptoCore::open(Box::new(FileStore::open(&dir)?), keys.as_ref())?;
        *out = Box::into_raw(Box::new(ShCore(Mutex::new(core))));
        Ok(())
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
