//! EXPERIMENTAL — NOT FOR PRODUCTION.
//!
//! Proves a Rust MLS core can sit behind a *narrow* C ABI that Dart (FFI on
//! Android/iOS/desktop) can call. Deliberately limited to the six test
//! operations from Prompt 05 §13. There is no API that returns private keys or
//! group secrets; callers only ever see opaque handles and wire-format bytes.
//!
//! Every entry point catches panics so a Rust panic never unwinds into Dart
//! (undefined behaviour). Return codes: 0 ok, -1 invalid argument,
//! -2 rejected by MLS (e.g. undecryptable), -3 internal panic.

use std::ffi::{c_char, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

use harness::Backend;

#[cfg(all(feature = "openmls", not(feature = "mlsrs")))]
type B = backend_openmls::OpenMls;
#[cfg(feature = "mlsrs")]
type B = backend_mlsrs::MlsRs;

pub const SH_OK: i32 = 0;
pub const SH_ERR_INVALID: i32 = -1;
pub const SH_ERR_REJECTED: i32 = -2;
pub const SH_ERR_PANIC: i32 = -3;

/// Opaque: a test device identity (never exposed as bytes).
pub struct ShIdentity(<B as Backend>::Device);
/// Opaque: one device's view of one group.
pub struct ShGroup(<B as Backend>::Group);

/// Bytes owned by Rust; release with `sh_experimental_buf_free`.
#[repr(C)]
pub struct ShBuf {
    pub ptr: *mut u8,
    pub len: usize,
}

impl ShBuf {
    fn from_vec(v: Vec<u8>) -> Self {
        let mut boxed = v.into_boxed_slice();
        let buf = ShBuf { ptr: boxed.as_mut_ptr(), len: boxed.len() };
        std::mem::forget(boxed);
        buf
    }
}

fn guard(f: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(SH_ERR_PANIC)
}

unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if ptr.is_null() {
        None
    } else {
        Some(std::slice::from_raw_parts(ptr, len))
    }
}

unsafe fn write_out(out: *mut ShBuf, v: Vec<u8>) -> i32 {
    if out.is_null() {
        return SH_ERR_INVALID;
    }
    *out = ShBuf::from_vec(v);
    SH_OK
}

/// Name and version of the MLS implementation behind this build.
#[no_mangle]
pub extern "C" fn sh_experimental_backend_name() -> *const c_char {
    #[cfg(feature = "mlsrs")]
    return c"mls-rs-0.56.0 (EXPERIMENTAL)".as_ptr();
    #[cfg(not(feature = "mlsrs"))]
    return c"openmls-0.9.1 (EXPERIMENTAL)".as_ptr();
}

/// # Safety
/// `label` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_create_test_identity(label: *const c_char) -> *mut ShIdentity {
    if label.is_null() {
        return ptr::null_mut();
    }
    catch_unwind(AssertUnwindSafe(|| {
        let label = CStr::from_ptr(label).to_str().ok()?;
        Some(Box::into_raw(Box::new(ShIdentity(B::new_device(label)))))
    }))
    .ok()
    .flatten()
    .unwrap_or(ptr::null_mut())
}

/// # Safety
/// `id` must come from `sh_experimental_create_test_identity` and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_free_identity(id: *mut ShIdentity) {
    if !id.is_null() {
        drop(Box::from_raw(id));
    }
}

/// A fresh KeyPackage (MLSMessage wire bytes) another member can add.
/// # Safety
/// Valid handle and output pointer.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_key_package(id: *const ShIdentity, out: *mut ShBuf) -> i32 {
    let Some(id) = id.as_ref() else { return SH_ERR_INVALID };
    guard(|| write_out(out, B::key_package(&id.0)))
}

/// # Safety
/// Valid identity handle.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_create_test_group(id: *const ShIdentity) -> *mut ShGroup {
    let Some(id) = id.as_ref() else { return ptr::null_mut() };
    catch_unwind(AssertUnwindSafe(|| Box::into_raw(Box::new(ShGroup(B::create_group(&id.0))))))
        .unwrap_or(ptr::null_mut())
}

/// # Safety
/// `g` must come from this library and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_free_group(g: *mut ShGroup) {
    if !g.is_null() {
        drop(Box::from_raw(g));
    }
}

/// Adds one member by KeyPackage; outputs the commit and the Welcome.
/// # Safety
/// Valid handles, readable `kp[..kp_len]`, writable outputs.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_add_test_member(
    id: *const ShIdentity,
    g: *mut ShGroup,
    kp: *const u8,
    kp_len: usize,
    out_commit: *mut ShBuf,
    out_welcome: *mut ShBuf,
) -> i32 {
    let (Some(id), Some(g), Some(kp)) = (id.as_ref(), g.as_mut(), bytes(kp, kp_len)) else {
        return SH_ERR_INVALID;
    };
    guard(|| {
        let (commit, welcome) = B::add(&id.0, &mut g.0, &[kp.to_vec()]);
        let rc = write_out(out_commit, commit);
        if rc != SH_OK {
            return rc;
        }
        write_out(out_welcome, welcome)
    })
}

/// # Safety
/// Valid identity handle and readable `welcome[..len]`.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_join_test_group(
    id: *const ShIdentity,
    welcome: *const u8,
    len: usize,
) -> *mut ShGroup {
    let (Some(id), Some(welcome)) = (id.as_ref(), bytes(welcome, len)) else {
        return ptr::null_mut();
    };
    catch_unwind(AssertUnwindSafe(|| Box::into_raw(Box::new(ShGroup(B::join(&id.0, welcome))))))
        .unwrap_or(ptr::null_mut())
}

/// # Safety
/// Valid handles, NUL-terminated `label`, writable output.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_remove_test_member(
    id: *const ShIdentity,
    g: *mut ShGroup,
    label: *const c_char,
    out_commit: *mut ShBuf,
) -> i32 {
    let (Some(id), Some(g)) = (id.as_ref(), g.as_mut()) else { return SH_ERR_INVALID };
    if label.is_null() {
        return SH_ERR_INVALID;
    }
    let Ok(label) = CStr::from_ptr(label).to_str() else { return SH_ERR_INVALID };
    guard(|| write_out(out_commit, B::remove(&id.0, &mut g.0, label)))
}

/// # Safety
/// Valid handles and readable `commit[..len]`.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_process_test_commit(
    id: *const ShIdentity,
    g: *mut ShGroup,
    commit: *const u8,
    len: usize,
) -> i32 {
    let (Some(id), Some(g), Some(commit)) = (id.as_ref(), g.as_mut(), bytes(commit, len)) else {
        return SH_ERR_INVALID;
    };
    guard(|| match B::process_commit(&id.0, &mut g.0, commit) {
        Ok(()) => SH_OK,
        Err(_) => SH_ERR_REJECTED,
    })
}

/// # Safety
/// Valid handles, readable `pt[..len]`, writable output.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_encrypt_test_message(
    id: *const ShIdentity,
    g: *mut ShGroup,
    pt: *const u8,
    len: usize,
    out: *mut ShBuf,
) -> i32 {
    let (Some(id), Some(g), Some(pt)) = (id.as_ref(), g.as_mut(), bytes(pt, len)) else {
        return SH_ERR_INVALID;
    };
    guard(|| write_out(out, B::encrypt(&id.0, &mut g.0, pt)))
}

/// Returns `SH_ERR_REJECTED` (never partial plaintext) when MLS rejects it.
/// # Safety
/// Valid handles, readable `ct[..len]`, writable output.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_decrypt_test_message(
    id: *const ShIdentity,
    g: *mut ShGroup,
    ct: *const u8,
    len: usize,
    out: *mut ShBuf,
) -> i32 {
    let (Some(id), Some(g), Some(ct)) = (id.as_ref(), g.as_mut(), bytes(ct, len)) else {
        return SH_ERR_INVALID;
    };
    guard(|| match B::decrypt(&id.0, &mut g.0, ct) {
        Ok(pt) => write_out(out, pt),
        Err(_) => SH_ERR_REJECTED,
    })
}

/// # Safety
/// `buf` must have been produced by this library and not freed before.
#[no_mangle]
pub unsafe extern "C" fn sh_experimental_buf_free(buf: ShBuf) {
    if !buf.ptr.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(buf.ptr, buf.len)));
    }
}
