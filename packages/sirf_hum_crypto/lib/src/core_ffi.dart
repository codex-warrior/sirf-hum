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
import 'package:sirf_hum_crypto/src/types.dart';

/// ABI version this Dart code was written against (native ABI_VERSION).
const int expectedAbiVersion = 1;

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

@Native<Int32 Function(Pointer<_ShCore>)>(symbol: 'sh_crypto_wipe')
external int _wipe(Pointer<_ShCore> h);

@Native<Void Function(_ShBuf)>(symbol: 'sh_crypto_buf_free')
external void _bufFree(_ShBuf buf);

final _finalizer = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<_ShCore>)>>(
    _close,
  ).cast(),
);

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
  static CryptoCore initialize({
    required String directory,
    required KeyStoreKind keyStore,
  }) {
    if (!isAvailable) throw const CryptoException(CryptoErrorCode.unsupported);
    final out = calloc<Pointer<_ShCore>>();
    try {
      _input(
        utf8.encode(directory),
        (p, n) => _check(_open(p, n, keyStore.wireValue, out)),
      );
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
