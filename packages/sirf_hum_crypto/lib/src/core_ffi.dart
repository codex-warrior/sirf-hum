// Native implementation of the crypto-core API (Android, iOS, test hosts).
//
// Boundary rules (native/src/ffi.rs): inputs are borrowed for one call;
// every output buffer is copied into Dart and released exactly once with
// sh_crypto_buf_free, which wipes it. Input buffers holding plaintext are
// zeroed before release. Dart heap copies cannot be reliably wiped (GC), which
// is a documented limitation (docs/security/CRYPTO-CORE-ARCHITECTURE.md).
@DefaultAsset('package:sirf_hum_crypto/sirf_hum_crypto')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:sirf_hum_crypto/src/lineage.dart';
import 'package:sirf_hum_crypto/src/types.dart';

/// ABI version this Dart code was written against (native ABI_VERSION).
const int expectedAbiVersion = 5;

// True in release (product) builds, where test key stores are refused.
const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');

const int _incomingApplication = 1;
const int _incomingCommit = 2;
const int _incomingRemoved = 3;

final class _ShCore extends Opaque {}

final class _ShBuf extends Struct {
  external Pointer<Uint8> ptr;
  @Size()
  external int len;
}

@Native<Uint32 Function()>(symbol: 'sh_crypto_abi_version')
external int _abiVersion();

@Native<
  Int32 Function(Pointer<Uint8>, Size, Uint32, Pointer<Pointer<_ShCore>>)
>(symbol: 'sh_crypto_open')
external int _open(
  Pointer<Uint8> dir,
  int len,
  int keystore,
  Pointer<Pointer<_ShCore>> out,
);

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Pointer<_ShCore>>,
  )
>(symbol: 'sh_crypto_open_with_platform_key')
external int _openWithPlatformKey(
  Pointer<Uint8> dir,
  int dirLen,
  Pointer<Uint8> key,
  int keyLen,
  Pointer<Pointer<_ShCore>> out,
);

@Native<Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size)>(
  symbol: 'sh_crypto_check_account',
)
external int _checkAccount(Pointer<_ShCore> h, Pointer<Uint8> a, int len);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Uint32,
    Pointer<Uint8>,
    Size,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_device_proof')
external int _deviceProof(
  Pointer<_ShCore> h,
  int purpose,
  Pointer<Uint8> challenge,
  int len,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_approve_device')
external int _approveDevice(
  Pointer<_ShCore> h,
  Pointer<Uint8> cert,
  int certLen,
  Pointer<Uint8> challenge,
  int challengeLen,
  int expiresAt,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint32>)
>(symbol: 'sh_crypto_approval_code')
external int _approvalCode(
  Pointer<Uint8> cert,
  int certLen,
  Pointer<Uint8> challenge,
  int challengeLen,
  Pointer<Uint32> out,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<_ShBuf>,
    Pointer<_ShBuf>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_create_recovery_key')
external int _createRecoveryKey(
  Pointer<_ShCore> h,
  Pointer<Uint8> challenge,
  int challengeLen,
  int expiresAt,
  Pointer<_ShBuf> secret,
  Pointer<_ShBuf> publicKey,
  Pointer<_ShBuf> signature,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<_ShBuf>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_recovery_approval')
external int _recoveryApproval(
  Pointer<_ShCore> h,
  Pointer<Uint8> key,
  int keyLen,
  Pointer<Uint8> challenge,
  int challengeLen,
  int expiresAt,
  Pointer<_ShBuf> signature,
  Pointer<_ShBuf> publicKey,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Uint32,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_sign_revocation')
external int _signRevocation(
  Pointer<_ShCore> h,
  Pointer<Uint8> cert,
  int certLen,
  int reason,
  Pointer<Uint8> challenge,
  int challengeLen,
  int expiresAt,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_sign_reset_cancellation')
external int _signResetCancellation(
  Pointer<_ShCore> h,
  Pointer<Uint8> challenge,
  int challengeLen,
  int expiresAt,
  Pointer<_ShBuf> out,
);

@Native<Int32 Function(Pointer<_ShCore>, Uint64, Pointer<Uint64>)>(
  symbol: 'sh_crypto_observe_trust_epoch',
)
external int _observeTrustEpoch(
  Pointer<_ShCore> h,
  int epoch,
  Pointer<Uint64> previous,
);

@Native<Int32 Function(Pointer<Uint8>, Size, Pointer<_ShBuf>)>(
  symbol: 'sh_crypto_verify_lineage',
)
external int _verifyLineage(Pointer<Uint8> blob, int len, Pointer<_ShBuf> out);

@Native<Void Function(Pointer<_ShCore>)>(symbol: 'sh_crypto_close')
external void _close(Pointer<_ShCore> h);

@Native<
  Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Pointer<_ShBuf>)
>(symbol: 'sh_crypto_create_identity')
external int _createIdentity(
  Pointer<_ShCore> h,
  Pointer<Uint8> a,
  int len,
  Pointer<_ShBuf> out,
);

@Native<Int32 Function(Pointer<_ShCore>, Pointer<_ShBuf>)>(
  symbol: 'sh_crypto_public_identity',
)
external int _publicIdentity(Pointer<_ShCore> h, Pointer<_ShBuf> out);

@Native<Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size)>(
  symbol: 'sh_crypto_trust_verified_person_key',
)
external int _trust(Pointer<_ShCore> h, Pointer<Uint8> key, int len);

@Native<Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size)>(
  symbol: 'sh_crypto_revoke_device',
)
external int _revoke(Pointer<_ShCore> h, Pointer<Uint8> device, int len);

@Native<Int32 Function(Pointer<_ShCore>, Pointer<_ShBuf>)>(
  symbol: 'sh_crypto_key_package',
)
external int _keyPackage(Pointer<_ShCore> h, Pointer<_ShBuf> out);

@Native<Int32 Function(Pointer<_ShCore>, Pointer<_ShBuf>)>(
  symbol: 'sh_crypto_create_group',
)
external int _createGroup(Pointer<_ShCore> h, Pointer<_ShBuf> out);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<_ShBuf>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_add_member')
external int _addMember(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint8> kp,
  int kpl,
  Pointer<_ShBuf> commit,
  Pointer<_ShBuf> welcome,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_remove_member')
external int _removeMember(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint8> d,
  int dl,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Pointer<_ShBuf>)
>(symbol: 'sh_crypto_self_update')
external int _selfUpdate(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Pointer<_ShBuf>)
>(symbol: 'sh_crypto_join')
external int _join(
  Pointer<_ShCore> h,
  Pointer<Uint8> w,
  int wl,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_encrypt')
external int _encrypt(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint8> pt,
  int ptl,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint32>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_process')
external int _process(
  Pointer<_ShCore> h,
  Pointer<Uint8> m,
  int ml,
  Pointer<Uint32> kind,
  Pointer<_ShBuf> payload,
);

@Native<
  Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Pointer<Uint64>)
>(symbol: 'sh_crypto_epoch')
external int _epoch(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint64> out,
);

@Native<
  Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Pointer<_ShBuf>)
>(symbol: 'sh_crypto_roster')
external int _roster(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<_ShBuf> out,
);

// ------------------------------------------------------------------ ABI v5

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Uint32>,
  )
>(symbol: 'sh_crypto_trust_lineage')
external int _trustLineage(
  Pointer<_ShCore> h,
  Pointer<Uint8> blob,
  int len,
  int epoch,
  Pointer<Uint32> count,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint64>,
    Pointer<_ShBuf>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_create_conversation_group')
external int _createConversationGroup(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<Uint8> kps,
  int kpsl,
  Pointer<Uint64> fromEpoch,
  Pointer<_ShBuf> commit,
  Pointer<_ShBuf> welcome,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint64>,
    Pointer<_ShBuf>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_stage_add_members')
external int _stageAddMembers(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint8> kps,
  int kpsl,
  Pointer<Uint64> fromEpoch,
  Pointer<_ShBuf> commit,
  Pointer<_ShBuf> welcome,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint64>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_stage_remove_members')
external int _stageRemoveMembers(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint8> devices,
  int dl,
  Pointer<Uint64> fromEpoch,
  Pointer<_ShBuf> commit,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint64>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_stage_self_update')
external int _stageSelfUpdate(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint64> fromEpoch,
  Pointer<_ShBuf> commit,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint32>,
    Pointer<Uint64>,
  )
>(symbol: 'sh_crypto_staged_commit_epoch')
external int _stagedCommitEpoch(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  Pointer<Uint32> has,
  Pointer<Uint64> epoch,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Uint64>,
  )
>(symbol: 'sh_crypto_confirm_commit')
external int _confirmCommit(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  int fromEpoch,
  Pointer<Uint64> epoch,
);

@Native<Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Uint64)>(
  symbol: 'sh_crypto_discard_commit',
)
external int _discardCommit(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  int fromEpoch,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint32>,
    Pointer<Uint64>,
  )
>(symbol: 'sh_crypto_process_commit')
external int _processCommit(
  Pointer<_ShCore> h,
  Pointer<Uint8> g,
  int gl,
  int epoch,
  Pointer<Uint8> sender,
  int sl,
  Pointer<Uint8> commit,
  int cl,
  Pointer<Uint32> kind,
  Pointer<Uint64> newEpoch,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint64>,
  )
>(symbol: 'sh_crypto_join_conversation')
external int _joinConversation(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<Uint8> w,
  int wl,
  Pointer<Uint64> epoch,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<_ShBuf>,
    Pointer<Uint64>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_send_message')
external int _sendMessage(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<Uint8> p,
  int pl,
  Pointer<_ShBuf> messageId,
  Pointer<Uint64> epoch,
  Pointer<_ShBuf> ciphertext,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint64>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_reencrypt_message')
external int _reencryptMessage(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<Uint8> m,
  int ml,
  Pointer<Uint64> epoch,
  Pointer<_ShBuf> ciphertext,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Uint64,
  )
>(symbol: 'sh_crypto_mark_message_sent')
external int _markMessageSent(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<Uint8> m,
  int ml,
  int serverTimeMs,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Uint64,
    Uint32,
    Uint32,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Uint32>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_receive_message')
external int _receiveMessage(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<Uint8> m,
  int ml,
  Pointer<Uint8> s,
  int sl,
  int epoch,
  int schema,
  int protocol,
  Pointer<Uint8> ct,
  int ctl,
  int serverTimeMs,
  Pointer<Uint32> duplicate,
  Pointer<_ShBuf> payload,
);

@Native<
  Int32 Function(
    Pointer<_ShCore>,
    Pointer<Uint8>,
    Size,
    Pointer<Uint32>,
    Pointer<_ShBuf>,
  )
>(symbol: 'sh_crypto_device_account')
external int _deviceAccount(
  Pointer<_ShCore> h,
  Pointer<Uint8> d,
  int dl,
  Pointer<Uint32> has,
  Pointer<_ShBuf> account,
);

@Native<
  Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Pointer<_ShBuf>)
>(symbol: 'sh_crypto_history')
external int _history(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<_ShBuf> out,
);

@Native<
  Int32 Function(Pointer<_ShCore>, Pointer<Uint8>, Size, Pointer<Uint8>, Size)
>(symbol: 'sh_crypto_delete_local_message')
external int _deleteLocalMessage(
  Pointer<_ShCore> h,
  Pointer<Uint8> c,
  int cl,
  Pointer<Uint8> m,
  int ml,
);

@Native<Int32 Function(Pointer<_ShCore>)>(symbol: 'sh_crypto_wipe')
external int _wipe(Pointer<_ShCore> h);

@Native<Void Function(_ShBuf)>(symbol: 'sh_crypto_buf_free')
external void _bufFree(_ShBuf buf);

final _finalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<_ShCore>)>>(
    _close,
  ).cast(),
);

/// Expiry values are whole seconds since the epoch, never negative.
int _u64(int value) {
  if (value < 0) throw const CryptoException(CryptoErrorCode.invalidInput);
  return value;
}

int _u32(int value) {
  if (value < 0 || value > 0xffffffff) {
    throw const CryptoException(CryptoErrorCode.invalidInput);
  }
  return value;
}

void _check(int rc) {
  if (rc != 0) throw CryptoException(CryptoErrorCode.fromCode(rc));
}

/// Copies [data] into native memory for one call, then zeroes and frees it.
T _input<T>(Uint8List data, T Function(Pointer<Uint8> ptr, int len) call) {
  final ptr = calloc<Uint8>(data.isEmpty ? 1 : data.length);
  final view = ptr.asTypedList(data.isEmpty ? 1 : data.length);
  view.setAll(0, data);
  try {
    return call(ptr, data.length);
  } finally {
    view.fillRange(0, view.length, 0);
    calloc.free(ptr);
  }
}

/// Runs [call] with one output buffer and returns a Dart copy of it. The
/// native buffer is released (and wiped) whether or not the call succeeded.
Uint8List _output(int Function(Pointer<_ShBuf> out) call) {
  final out = calloc<_ShBuf>();
  try {
    _check(call(out));
    return _copy(out.ref);
  } finally {
    _bufFree(out.ref);
    calloc.free(out);
  }
}

Uint8List _copy(_ShBuf buf) => buf.len == 0
    ? Uint8List(0)
    : Uint8List.fromList(buf.ptr.asTypedList(buf.len));

/// The device's crypto core: identity, MLS groups and encrypted local state.
///
/// **NOT production E2EE: unaudited.** Every mutating call persists the new
/// state atomically before it returns; a failed call leaves both memory and
/// disk at the previous state (checkpoint/rollback). Calls are synchronous.
final class CryptoCore implements Finalizable {
  CryptoCore._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  Pointer<_ShCore> _handle;

  /// Whether a native crypto core is bundled for this platform with a
  /// matching ABI. False on Web and on hosts without a native build.
  static bool get isAvailable {
    try {
      return _abiVersion() == expectedAbiVersion;
    } on ArgumentError {
      // Native asset not bundled for this target.
      return false;
    }
  }

  /// Opens the core for one device, restoring any state found in
  /// [directory] (which must be app-private storage). Fails closed with
  /// [CryptoErrorCode.stateCorruption] if stored state cannot be
  /// authenticated, rather than starting empty.
  ///
  /// Only for the insecure TEST key stores. They are refused in release
  /// builds, and [KeyStoreKind.platform] must use [initializeWithPlatformKey].
  static CryptoCore initialize({
    required String directory,
    required KeyStoreKind keyStore,
  }) {
    // Release builds refuse the insecure test key stores outright.
    if (!isAvailable || keyStore == KeyStoreKind.platform || _isReleaseBuild) {
      throw const CryptoException(CryptoErrorCode.unsupported);
    }
    return _openWith(
      (out) => _input(
        utf8.encode(directory),
        (p, n) => _open(p, n, keyStore.wireValue, out),
      ),
    );
  }

  /// Opens or restores the core with the 32-byte store key obtained from the
  /// platform key store (Android Keystore / iOS Keychain, D-066).
  ///
  /// [storeKey] is filled with zeros after the call so the caller's copy does
  /// not linger; the native copy lives only in zeroizing memory.
  static CryptoCore initializeWithPlatformKey({
    required String directory,
    required Uint8List storeKey,
  }) {
    try {
      if (!isAvailable) {
        throw const CryptoException(CryptoErrorCode.unsupported);
      }
      return _openWith(
        (out) => _input(
          utf8.encode(directory),
          (d, dl) => _input(
            storeKey,
            (k, kl) => _openWithPlatformKey(d, dl, k, kl, out),
          ),
        ),
      );
    } finally {
      wipeBytes(storeKey);
    }
  }

  static CryptoCore _openWith(int Function(Pointer<Pointer<_ShCore>>) open) {
    final out = calloc<Pointer<_ShCore>>();
    try {
      _check(open(out));
      return CryptoCore._(out.value);
    } finally {
      calloc.free(out);
    }
  }

  Pointer<_ShCore> get _h {
    if (_handle == nullptr) {
      throw const CryptoException(CryptoErrorCode.invalidInput);
    }
    return _handle;
  }

  /// Releases native state (secrets are wiped in memory; disk state stays).
  void close() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    _close(_handle);
    _handle = nullptr;
  }

  PublicIdentity createIdentity(AccountId account) => _parseIdentity(
    _input(
      utf8.encode(account.value),
      (p, n) => _output((o) => _createIdentity(_h, p, n, o)),
    ),
  );

  PublicIdentity publicIdentity() =>
      _parseIdentity(_output((o) => _publicIdentity(_h, o)));

  /// Throws [CryptoErrorCode.accountMismatch] unless this device's local
  /// identity belongs to [account] ([CryptoErrorCode.identityState] if there
  /// is none). Call on every open: one account's identity must never be
  /// used for another (DEVICE-IDENTITY.md).
  void checkAccount(AccountId account) => _input(
    utf8.encode(account.value),
    (p, n) => _check(_checkAccount(_h, p, n)),
  );

  /// Signs a 32-byte server challenge with the device key to prove possession
  /// (D-070). The signed payload is built inside the core from its own account
  /// and certificate; the result is a 64-byte Ed25519 signature (public).
  Uint8List deviceProof(DeviceProofPurpose purpose, Uint8List challenge) =>
      _input(
        challenge,
        (c, cl) =>
            _output((o) => _deviceProof(_h, purpose.wireValue, c, cl, o)),
      );

  /// Approves another device of this account (D-075): signs the approval
  /// statement with this device's PIK and trusts the new device's person key
  /// locally. Returns the 64-byte signature for the server, which decides
  /// whether it counts (approver still active, request live).
  Uint8List approveDevice({
    required Uint8List newCertificate,
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _input(
    newCertificate,
    (n, nl) => _input(
      challenge,
      (c, cl) => _output(
        (o) => _approveDevice(_h, n, nl, c, cl, _u64(expiresAtUnix), o),
      ),
    ),
  );

  /// The six-digit code both devices show, so the user approves the device
  /// in their hand (D-075). Not a secret.
  static int approvalCode({
    required Uint8List newCertificate,
    required Uint8List challenge,
  }) {
    if (!isAvailable) throw const CryptoException(CryptoErrorCode.unsupported);
    final out = calloc<Uint32>();
    try {
      _input(
        newCertificate,
        (n, nl) => _input(
          challenge,
          (c, cl) => _check(_approvalCode(n, nl, c, cl, out)),
        ),
      );
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Creates a recovery key (D-076) and signs its registration. The returned
  /// [RecoveryKeyBundle.secret] must be shown to the user once and never
  /// stored, sent or logged; Dart strings cannot be wiped.
  RecoveryKeyBundle createRecoveryKey({
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _input(challenge, (c, cl) {
    final secret = calloc<_ShBuf>();
    final publicKey = calloc<_ShBuf>();
    final signature = calloc<_ShBuf>();
    try {
      _check(
        _createRecoveryKey(
          _h,
          c,
          cl,
          _u64(expiresAtUnix),
          secret,
          publicKey,
          signature,
        ),
      );
      final text = _copy(secret.ref);
      try {
        return RecoveryKeyBundle(
          secret: utf8.decode(text),
          publicKey: _copy(publicKey.ref),
          registrationSignature: _copy(signature.ref),
        );
      } finally {
        wipeBytes(text);
      }
    } finally {
      for (final b in [secret, publicKey, signature]) {
        _bufFree(b.ref);
        calloc.free(b);
      }
    }
  });

  /// Signs a recovery approval for THIS device with the user-typed recovery
  /// key. The native copy of the key is wiped after signing.
  RecoveryApprovalResult recoveryApproval({
    required String recoveryKey,
    required Uint8List challenge,
    required int expiresAtUnix,
  }) {
    final keyBytes = Uint8List.fromList(utf8.encode(recoveryKey));
    try {
      return _input(
        keyBytes,
        (k, kl) => _input(challenge, (c, cl) {
          final signature = calloc<_ShBuf>();
          final publicKey = calloc<_ShBuf>();
          try {
            _check(
              _recoveryApproval(
                _h,
                k,
                kl,
                c,
                cl,
                _u64(expiresAtUnix),
                signature,
                publicKey,
              ),
            );
            return RecoveryApprovalResult(
              signature: _copy(signature.ref),
              recoveryPublicKey: _copy(publicKey.ref),
            );
          } finally {
            for (final b in [signature, publicKey]) {
              _bufFree(b.ref);
              calloc.free(b);
            }
          }
        }),
      );
    } finally {
      wipeBytes(keyBytes);
    }
  }

  /// Signs a revocation of [revokedCertificate] (another device of this
  /// account, or this device itself) with this device's PIK (D-081). The
  /// server decides whether it counts (this device must be active).
  Uint8List signRevocation({
    required Uint8List revokedCertificate,
    required RevocationReason reason,
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _input(
    revokedCertificate,
    (r, rl) => _input(
      challenge,
      (c, cl) => _output(
        (o) => _signRevocation(
          _h,
          r,
          rl,
          reason.wireValue,
          c,
          cl,
          _u64(expiresAtUnix),
          o,
        ),
      ),
    ),
  );

  /// Signs a cancellation of a pending identity reset (D-082).
  Uint8List signResetCancellation({
    required Uint8List challenge,
    required int expiresAtUnix,
  }) => _input(
    challenge,
    (c, cl) => _output(
      (o) => _signResetCancellation(_h, c, cl, _u64(expiresAtUnix), o),
    ),
  );

  /// Records the server's account trust epoch (D-083). Throws
  /// [CryptoErrorCode.trustStateStale] if it is older than one this device
  /// already saw (a stale or rolled-back server view). Returns the
  /// previously seen epoch.
  int observeTrustEpoch(int epoch) {
    final previous = calloc<Uint64>();
    try {
      _check(_observeTrustEpoch(_h, _u64(epoch), previous));
      return previous.value;
    } finally {
      calloc.free(previous);
    }
  }

  /// Verifies an account's trust lineage on this device (D-084) and returns
  /// the device IDs still trusted, in chain order. Throws
  /// [CryptoErrorCode.trustChainInvalid] for any broken link.
  static List<DeviceId> verifyLineage(LineageRequest request) {
    if (!isAvailable) throw const CryptoException(CryptoErrorCode.unsupported);
    final bytes = _input(
      request.encode(),
      (b, bl) => _output((o) => _verifyLineage(b, bl, o)),
    );
    final view = ByteData.sublistView(bytes);
    if (bytes.length < 4) throw const CryptoException(CryptoErrorCode.internal);
    final count = view.getUint32(0, Endian.big);
    if (bytes.length != 4 + count * 16) {
      throw const CryptoException(CryptoErrorCode.internal);
    }
    return [
      for (var i = 0; i < count; i++)
        DeviceId(bytes.sublist(4 + i * 16, 20 + i * 16)),
    ];
  }

  /// Trusts a person key the user has verified out of band (D-064). Devices
  /// certified by untrusted person keys are rejected at the boundary.
  void trustVerifiedPersonKey(PersonKey key) =>
      _input(key.bytes, (p, n) => _check(_trust(_h, p, n)));

  void revokeDevice(DeviceId device) =>
      _input(device.bytes, (p, n) => _check(_revoke(_h, p, n)));

  /// A fresh MLS KeyPackage for this device (public).
  Uint8List keyPackage() => _output((o) => _keyPackage(_h, o));

  GroupId createGroup() => GroupId(_output((o) => _createGroup(_h, o)));

  AddMemberResult addMember(GroupId group, Uint8List keyPackage) => _input(
    group.bytes,
    (g, gl) => _input(keyPackage, (k, kl) {
      final commit = calloc<_ShBuf>();
      final welcome = calloc<_ShBuf>();
      try {
        _check(_addMember(_h, g, gl, k, kl, commit, welcome));
        return AddMemberResult(
          commit: _copy(commit.ref),
          welcome: _copy(welcome.ref),
        );
      } finally {
        _bufFree(commit.ref);
        _bufFree(welcome.ref);
        calloc
          ..free(commit)
          ..free(welcome);
      }
    }),
  );

  Uint8List removeMember(GroupId group, DeviceId device) => _input(
    group.bytes,
    (g, gl) => _input(
      device.bytes,
      (d, dl) => _output((o) => _removeMember(_h, g, gl, d, dl, o)),
    ),
  );

  Uint8List selfUpdate(GroupId group) =>
      _input(group.bytes, (g, gl) => _output((o) => _selfUpdate(_h, g, gl, o)));

  GroupId join(Uint8List welcome) =>
      GroupId(_input(welcome, (w, wl) => _output((o) => _join(_h, w, wl, o))));

  /// Encrypts private content for [group]. [plaintext]'s native copy is
  /// wiped after the call.
  Uint8List encrypt(GroupId group, Uint8List plaintext) => _input(
    group.bytes,
    (g, gl) => _input(
      plaintext,
      (p, pl) => _output((o) => _encrypt(_h, g, gl, p, pl, o)),
    ),
  );

  /// Validates and applies one incoming MLS message. Oversized input is
  /// rejected before parsing; any rejection leaves state unchanged.
  IncomingResult processIncoming(Uint8List message) => _input(message, (m, ml) {
    final kind = calloc<Uint32>();
    try {
      final payload = _output((o) => _process(_h, m, ml, kind, o));
      return switch (kind.value) {
        _incomingApplication => IncomingApplication(payload),
        _incomingCommit when payload.length == 8 => IncomingCommit(
          ByteData.sublistView(payload).getUint64(0, Endian.big),
        ),
        _incomingRemoved => const IncomingRemoved(),
        _ => throw const CryptoException(CryptoErrorCode.internal),
      };
    } finally {
      calloc.free(kind);
    }
  });

  int epoch(GroupId group) => _input(group.bytes, (g, gl) {
    final out = calloc<Uint64>();
    try {
      _check(_epoch(_h, g, gl, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  });

  List<RosterEntry> roster(GroupId group) {
    final bytes = _input(
      group.bytes,
      (g, gl) => _output((o) => _roster(_h, g, gl, o)),
    );
    final view = ByteData.sublistView(bytes);
    if (bytes.length < 4) throw const CryptoException(CryptoErrorCode.internal);
    final count = view.getUint32(0, Endian.big);
    if (bytes.length != 4 + count * 48) {
      throw const CryptoException(CryptoErrorCode.internal);
    }
    return [
      for (var i = 0; i < count; i++)
        RosterEntry(
          deviceId: DeviceId(bytes.sublist(4 + i * 48, 20 + i * 48)),
          personKey: PersonKey(bytes.sublist(20 + i * 48, 52 + i * 48)),
        ),
    ];
  }

  // ---------------------------------------------------------------- ABI v5
  // Messaging core (docs/security/E2EE-MESSAGING-DESIGN.md).

  /// Verifies an account lineage (D-084) and applies it to this device's
  /// trust (D-085): the root's person key must be anchored with
  /// [trustVerifiedPersonKey]; [trustEpoch] is the server's
  /// `accountTrust.trustEpoch` and must not go backwards for that account
  /// ([CryptoErrorCode.trustStateStale]). Returns how many devices of that
  /// account are now trusted.
  int trustLineage(LineageRequest request, int trustEpoch) =>
      _input(request.encode(), (b, bl) {
        final count = calloc<Uint32>();
        try {
          _check(_trustLineage(_h, b, bl, _u64(trustEpoch), count));
          return count.value;
        } finally {
          calloc.free(count);
        }
      });

  /// Creates the conversation's MLS group (group ID = conversation ID) and
  /// stages its first commit adding [keyPackages]. Nothing is active until
  /// [confirmCommit] (epoch 0); [discardCommit] deletes the group again.
  StagedCommit createConversationGroup(
    ConversationId conversation,
    List<Uint8List> keyPackages,
  ) => _input(
    conversation.bytes,
    (c, cl) => _input(
      encodeByteList(keyPackages),
      (k, kl) => _staged(
        withWelcome: true,
        (e, commit, welcome) =>
            _createConversationGroup(_h, c, cl, k, kl, e, commit, welcome),
      ),
    ),
  );

  /// Stages a commit adding devices; each credential is validated first.
  StagedCommit stageAddMembers(
    ConversationId conversation,
    List<Uint8List> keyPackages,
  ) => _input(
    conversation.bytes,
    (c, cl) => _input(
      encodeByteList(keyPackages),
      (k, kl) => _staged(
        withWelcome: true,
        (e, commit, welcome) =>
            _stageAddMembers(_h, c, cl, k, kl, e, commit, welcome),
      ),
    ),
  );

  /// Stages a commit removing devices (e.g. revoked ones).
  StagedCommit stageRemoveMembers(
    ConversationId conversation,
    List<DeviceId> devices,
  ) => _input(
    conversation.bytes,
    (c, cl) => _input(
      Uint8List.fromList([for (final d in devices) ...d.bytes]),
      (d, dl) => _staged(
        withWelcome: false,
        (e, commit, _) => _stageRemoveMembers(_h, c, cl, d, dl, e, commit),
      ),
    ),
  );

  /// Stages a self update (fresh leaf keys).
  StagedCommit stageSelfUpdate(ConversationId conversation) => _input(
    conversation.bytes,
    (c, cl) => _staged(
      withWelcome: false,
      (e, commit, _) => _stageSelfUpdate(_h, c, cl, e, commit),
    ),
  );

  StagedCommit _staged(
    int Function(
      Pointer<Uint64> fromEpoch,
      Pointer<_ShBuf> commit,
      Pointer<_ShBuf> welcome,
    )
    call, {
    required bool withWelcome,
  }) {
    final epoch = calloc<Uint64>();
    final commit = calloc<_ShBuf>();
    final welcome = calloc<_ShBuf>();
    try {
      _check(call(epoch, commit, welcome));
      return StagedCommit(
        fromEpoch: epoch.value,
        commit: _copy(commit.ref),
        welcome: withWelcome ? _copy(welcome.ref) : null,
      );
    } finally {
      _bufFree(commit.ref);
      _bufFree(welcome.ref);
      calloc
        ..free(epoch)
        ..free(commit)
        ..free(welcome);
    }
  }

  /// The epoch of the staged commit, or null when none is staged.
  int? stagedCommitEpoch(ConversationId conversation) =>
      _input(conversation.bytes, (c, cl) {
        final has = calloc<Uint32>();
        final epoch = calloc<Uint64>();
        try {
          _check(_stagedCommitEpoch(_h, c, cl, has, epoch));
          return has.value == 1 ? epoch.value : null;
        } finally {
          calloc
            ..free(has)
            ..free(epoch);
        }
      });

  /// Applies the staged commit the server accepted for [fromEpoch]; returns
  /// the new epoch. Repeating it is idempotent; anything else throws
  /// [CryptoErrorCode.noStagedCommit].
  int confirmCommit(ConversationId conversation, int fromEpoch) =>
      _input(conversation.bytes, (c, cl) {
        final epoch = calloc<Uint64>();
        try {
          _check(_confirmCommit(_h, c, cl, _u64(fromEpoch), epoch));
          return epoch.value;
        } finally {
          calloc.free(epoch);
        }
      });

  /// Drops the staged commit for [fromEpoch] (refused, or another won).
  void discardCommit(ConversationId conversation, int fromEpoch) => _input(
    conversation.bytes,
    (c, cl) => _check(_discardCommit(_h, c, cl, _u64(fromEpoch))),
  );

  /// Processes another member's commit the server accepted for [epoch].
  IncomingResult processCommit(
    ConversationId conversation, {
    required int epoch,
    required DeviceId sender,
    required Uint8List commit,
  }) => _input(
    conversation.bytes,
    (c, cl) => _input(
      sender.bytes,
      (s, sl) => _input(commit, (m, ml) {
        final kind = calloc<Uint32>();
        final newEpoch = calloc<Uint64>();
        try {
          _check(
            _processCommit(
              _h,
              c,
              cl,
              _u64(epoch),
              s,
              sl,
              m,
              ml,
              kind,
              newEpoch,
            ),
          );
          return switch (kind.value) {
            _incomingCommit => IncomingCommit(newEpoch.value),
            _incomingRemoved => const IncomingRemoved(),
            _ => throw const CryptoException(CryptoErrorCode.internal),
          };
        } finally {
          calloc
            ..free(kind)
            ..free(newEpoch);
        }
      }),
    ),
  );

  /// Joins the conversation from a Welcome; returns the epoch joined.
  int joinConversation(ConversationId conversation, Uint8List welcome) =>
      _input(
        conversation.bytes,
        (c, cl) => _input(welcome, (w, wl) {
          final epoch = calloc<Uint64>();
          try {
            _check(_joinConversation(_h, c, cl, w, wl, epoch));
            return epoch.value;
          } finally {
            calloc.free(epoch);
          }
        }),
      );

  /// Encrypts one message payload (private content; its native copy is
  /// wiped). The core generates the message ID and seals the payload and
  /// queued ciphertext into local history.
  SentMessage sendMessage(ConversationId conversation, Uint8List payload) =>
      _input(
        conversation.bytes,
        (c, cl) => _input(payload, (p, pl) {
          final id = calloc<_ShBuf>();
          final epoch = calloc<Uint64>();
          final ct = calloc<_ShBuf>();
          try {
            _check(_sendMessage(_h, c, cl, p, pl, id, epoch, ct));
            return SentMessage(
              messageId: MessageId(_copy(id.ref)),
              epoch: epoch.value,
              ciphertext: _copy(ct.ref),
            );
          } finally {
            _bufFree(id.ref);
            _bufFree(ct.ref);
            calloc
              ..free(id)
              ..free(epoch)
              ..free(ct);
          }
        }),
      );

  /// Re-encrypts a queued message under the current epoch (same ID).
  SentMessage reencryptMessage(ConversationId conversation, MessageId id) =>
      _input(
        conversation.bytes,
        (c, cl) => _input(id.bytes, (m, ml) {
          final epoch = calloc<Uint64>();
          final ct = calloc<_ShBuf>();
          try {
            _check(_reencryptMessage(_h, c, cl, m, ml, epoch, ct));
            return SentMessage(
              messageId: id,
              epoch: epoch.value,
              ciphertext: _copy(ct.ref),
            );
          } finally {
            _bufFree(ct.ref);
            calloc
              ..free(epoch)
              ..free(ct);
          }
        }),
      );

  /// The server accepted a queued message: keep only its payload.
  void markMessageSent(
    ConversationId conversation,
    MessageId id, {
    required int serverTimeMs,
  }) => _input(
    conversation.bytes,
    (c, cl) => _input(
      id.bytes,
      (m, ml) => _check(_markMessageSent(_h, c, cl, m, ml, _u64(serverTimeMs))),
    ),
  );

  /// Verifies every envelope field against what MLS authenticated, then
  /// decrypts and seals the message into history. Throws on any mismatch
  /// (state unchanged, so the genuine message still decrypts later).
  ReceivedMessage receiveMessage(
    ConversationId conversation, {
    required MessageId messageId,
    required DeviceId sender,
    required int epoch,
    required int schemaVersion,
    required int protocolVersion,
    required Uint8List ciphertext,
    required int serverTimeMs,
  }) => _input(
    conversation.bytes,
    (c, cl) => _input(
      messageId.bytes,
      (m, ml) => _input(
        sender.bytes,
        (s, sl) => _input(ciphertext, (t, tl) {
          final duplicate = calloc<Uint32>();
          final payload = calloc<_ShBuf>();
          try {
            _check(
              _receiveMessage(
                _h,
                c,
                cl,
                m,
                ml,
                s,
                sl,
                _u64(epoch),
                _u32(schemaVersion),
                _u32(protocolVersion),
                t,
                tl,
                _u64(serverTimeMs),
                duplicate,
                payload,
              ),
            );
            return ReceivedMessage(
              payload: _copy(payload.ref),
              duplicate: duplicate.value == 1,
            );
          } finally {
            _bufFree(payload.ref);
            calloc
              ..free(duplicate)
              ..free(payload);
          }
        }),
      ),
    ),
  );

  /// The account a verified lineage assigned to [device], or null.
  String? deviceAccount(DeviceId device) => _input(device.bytes, (d, dl) {
    final has = calloc<Uint32>();
    final out = calloc<_ShBuf>();
    try {
      _check(_deviceAccount(_h, d, dl, has, out));
      return has.value == 1 ? utf8.decode(_copy(out.ref)) : null;
    } finally {
      _bufFree(out.ref);
      calloc
        ..free(has)
        ..free(out);
    }
  });

  /// The conversation's sealed local history (unordered; private content).
  List<LocalMessage> history(ConversationId conversation) => decodeHistory(
    _input(
      conversation.bytes,
      (c, cl) => _output((o) => _history(_h, c, cl, o)),
    ),
    conversation,
  );

  /// Deletes one message from this device only ("delete for me").
  void deleteLocalMessage(ConversationId conversation, MessageId id) => _input(
    conversation.bytes,
    (c, cl) => _input(
      id.bytes,
      (m, ml) => _check(_deleteLocalMessage(_h, c, cl, m, ml)),
    ),
  );

  /// Deletes all local crypto records for this device and resets the core.
  void wipe() => _check(_wipe(_h));
}

/// `device_id[16] | u32 len | person_key | u32 len | certificate`, strictly.
PublicIdentity _parseIdentity(Uint8List bytes) {
  const bad = CryptoException(CryptoErrorCode.internal);
  final view = ByteData.sublistView(bytes);
  var at = 16;
  Uint8List field() {
    if (bytes.length < at + 4) throw bad;
    final len = view.getUint32(at, Endian.big);
    at += 4;
    if (bytes.length < at + len) throw bad;
    final value = bytes.sublist(at, at + len);
    at += len;
    return value;
  }

  if (bytes.length < 16) throw bad;
  final identity = PublicIdentity(
    deviceId: DeviceId(bytes.sublist(0, 16)),
    personKey: PersonKey(field()),
    certificate: field(),
  );
  if (at != bytes.length) throw bad;
  return identity;
}
