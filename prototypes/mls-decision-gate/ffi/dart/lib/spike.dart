// EXPERIMENTAL — NOT FOR PRODUCTION. Not part of the Sirf Hum app.
//
// Thin dart:ffi binding over the Rust C ABI in ../src/lib.rs. It exists only
// to prove the Dart ↔ Rust boundary works; no key material crosses it.
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class ShBuf extends Struct {
  external Pointer<Uint8> ptr;
  @Size()
  external int len;
}

final class ShIdentity extends Opaque {}

final class ShGroup extends Opaque {}

class MlsRejected implements Exception {
  const MlsRejected(this.code);
  final int code;
  @override
  String toString() => 'MlsRejected($code)';
}

class Spike {
  Spike(String libraryPath) : _lib = DynamicLibrary.open(libraryPath);

  final DynamicLibrary _lib;

  late final _backendName = _lib
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'sh_experimental_backend_name',
      );
  late final _createIdentity = _lib
      .lookupFunction<
        Pointer<ShIdentity> Function(Pointer<Utf8>),
        Pointer<ShIdentity> Function(Pointer<Utf8>)
      >('sh_experimental_create_test_identity');
  late final _keyPackage = _lib
      .lookupFunction<
        Int32 Function(Pointer<ShIdentity>, Pointer<ShBuf>),
        int Function(Pointer<ShIdentity>, Pointer<ShBuf>)
      >('sh_experimental_key_package');
  late final _createGroup = _lib
      .lookupFunction<
        Pointer<ShGroup> Function(Pointer<ShIdentity>),
        Pointer<ShGroup> Function(Pointer<ShIdentity>)
      >('sh_experimental_create_test_group');
  late final _add = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Uint8>,
          Size,
          Pointer<ShBuf>,
          Pointer<ShBuf>,
        ),
        int Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Uint8>,
          int,
          Pointer<ShBuf>,
          Pointer<ShBuf>,
        )
      >('sh_experimental_add_test_member');
  late final _join = _lib
      .lookupFunction<
        Pointer<ShGroup> Function(Pointer<ShIdentity>, Pointer<Uint8>, Size),
        Pointer<ShGroup> Function(Pointer<ShIdentity>, Pointer<Uint8>, int)
      >('sh_experimental_join_test_group');
  late final _remove = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Utf8>,
          Pointer<ShBuf>,
        ),
        int Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Utf8>,
          Pointer<ShBuf>,
        )
      >('sh_experimental_remove_test_member');
  late final _processCommit = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Uint8>,
          Size,
        ),
        int Function(Pointer<ShIdentity>, Pointer<ShGroup>, Pointer<Uint8>, int)
      >('sh_experimental_process_test_commit');
  late final _encrypt = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Uint8>,
          Size,
          Pointer<ShBuf>,
        ),
        int Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Uint8>,
          int,
          Pointer<ShBuf>,
        )
      >('sh_experimental_encrypt_test_message');
  late final _decrypt = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Uint8>,
          Size,
          Pointer<ShBuf>,
        ),
        int Function(
          Pointer<ShIdentity>,
          Pointer<ShGroup>,
          Pointer<Uint8>,
          int,
          Pointer<ShBuf>,
        )
      >('sh_experimental_decrypt_test_message');
  late final _bufFree = _lib
      .lookupFunction<Void Function(ShBuf), void Function(ShBuf)>(
        'sh_experimental_buf_free',
      );

  String get backendName => _backendName().toDartString();

  Pointer<ShIdentity> createTestIdentity(String label) {
    final native = label.toNativeUtf8();
    try {
      final id = _createIdentity(native);
      if (id == nullptr) throw StateError('identity creation failed');
      return id;
    } finally {
      calloc.free(native);
    }
  }

  Uint8List keyPackage(Pointer<ShIdentity> id) =>
      _out((out) => _keyPackage(id, out));

  Pointer<ShGroup> createTestGroup(Pointer<ShIdentity> id) {
    final g = _createGroup(id);
    if (g == nullptr) throw StateError('group creation failed');
    return g;
  }

  ({Uint8List commit, Uint8List welcome}) addTestMember(
    Pointer<ShIdentity> id,
    Pointer<ShGroup> g,
    Uint8List keyPackage,
  ) {
    final commit = calloc<ShBuf>();
    final welcome = calloc<ShBuf>();
    try {
      final rc = _withBytes(
        keyPackage,
        (p, n) => _add(id, g, p, n, commit, welcome),
      );
      _check(rc);
      return (commit: _take(commit.ref), welcome: _take(welcome.ref));
    } finally {
      calloc
        ..free(commit)
        ..free(welcome);
    }
  }

  Pointer<ShGroup> joinTestGroup(Pointer<ShIdentity> id, Uint8List welcome) {
    final g = _withBytes(welcome, (p, n) => _join(id, p, n));
    if (g == nullptr) throw StateError('join failed');
    return g;
  }

  Uint8List removeTestMember(
    Pointer<ShIdentity> id,
    Pointer<ShGroup> g,
    String label,
  ) {
    final native = label.toNativeUtf8();
    try {
      return _out((out) => _remove(id, g, native, out));
    } finally {
      calloc.free(native);
    }
  }

  void processTestCommit(
    Pointer<ShIdentity> id,
    Pointer<ShGroup> g,
    Uint8List commit,
  ) => _check(_withBytes(commit, (p, n) => _processCommit(id, g, p, n)));

  Uint8List encryptTestMessage(
    Pointer<ShIdentity> id,
    Pointer<ShGroup> g,
    Uint8List plaintext,
  ) => _out(
    (out) => _withBytes(plaintext, (p, n) => _encrypt(id, g, p, n, out)),
  );

  Uint8List decryptTestMessage(
    Pointer<ShIdentity> id,
    Pointer<ShGroup> g,
    Uint8List ciphertext,
  ) => _out(
    (out) => _withBytes(ciphertext, (p, n) => _decrypt(id, g, p, n, out)),
  );

  T _withBytes<T>(Uint8List data, T Function(Pointer<Uint8>, int) f) {
    final p = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      p.asTypedList(data.length).setAll(0, data);
      return f(p, data.length);
    } finally {
      calloc.free(p);
    }
  }

  Uint8List _out(int Function(Pointer<ShBuf>) f) {
    final out = calloc<ShBuf>();
    try {
      _check(f(out));
      return _take(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  Uint8List _take(ShBuf buf) {
    final copy = Uint8List.fromList(buf.ptr.asTypedList(buf.len));
    _bufFree(buf);
    return copy;
  }

  void _check(int rc) {
    if (rc != 0) throw MlsRejected(rc);
  }
}
