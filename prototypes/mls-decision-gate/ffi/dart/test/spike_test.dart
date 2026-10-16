// EXPERIMENTAL — NOT FOR PRODUCTION.
// Run: SH_FFI_LIB=/path/to/libsh_crypto_ffi_spike.so dart test
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sh_crypto_ffi_spike/spike.dart';
import 'package:test/test.dart';

void main() {
  final path = Platform.environment['SH_FFI_LIB'];
  if (path == null) {
    throw StateError('Set SH_FFI_LIB to the built native library.');
  }
  final spike = Spike(path);
  Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

  test('reports which MLS backend it wraps', () {
    expect(spike.backendName, contains('EXPERIMENTAL'));
  });

  test('Dart drives create, add, encrypt, decrypt, remove through FFI', () {
    final alice = spike.createTestIdentity('a/1');
    final bob = spike.createTestIdentity('b/1');
    final aliceLaptop = spike.createTestIdentity('a/2');

    final ga = spike.createTestGroup(alice);
    final addBob = spike.addTestMember(alice, ga, spike.keyPackage(bob));
    final gb = spike.joinTestGroup(bob, addBob.welcome);

    final addLaptop = spike.addTestMember(
      alice,
      ga,
      spike.keyPackage(aliceLaptop),
    );
    spike.processTestCommit(bob, gb, addLaptop.commit);
    final gl = spike.joinTestGroup(aliceLaptop, addLaptop.welcome);

    final hello = spike.encryptTestMessage(bob, gb, utf8Bytes('hello'));
    expect(utf8.decode(spike.decryptTestMessage(alice, ga, hello)), 'hello');
    expect(
      utf8.decode(spike.decryptTestMessage(aliceLaptop, gl, hello)),
      'hello',
    );

    // Revoke the laptop; it must not read anything sent afterwards.
    final removal = spike.removeTestMember(alice, ga, 'a/2');
    spike.processTestCommit(bob, gb, removal);
    final after = spike.encryptTestMessage(bob, gb, utf8Bytes('after'));
    expect(utf8.decode(spike.decryptTestMessage(alice, ga, after)), 'after');
    expect(
      () => spike.decryptTestMessage(aliceLaptop, gl, after),
      throwsA(isA<MlsRejected>()),
    );
  });

  test('tampered and replayed ciphertexts are rejected through FFI', () {
    final alice = spike.createTestIdentity('a/1');
    final bob = spike.createTestIdentity('b/1');
    final ga = spike.createTestGroup(alice);
    final add = spike.addTestMember(alice, ga, spike.keyPackage(bob));
    final gb = spike.joinTestGroup(bob, add.welcome);

    final ct = spike.encryptTestMessage(alice, ga, utf8Bytes('once'));
    final forged = Uint8List.fromList(ct)..[ct.length - 1] ^= 1;
    expect(
      () => spike.decryptTestMessage(bob, gb, forged),
      throwsA(isA<MlsRejected>()),
    );
    expect(utf8.decode(spike.decryptTestMessage(bob, gb, ct)), 'once');
    expect(
      () => spike.decryptTestMessage(bob, gb, ct),
      throwsA(isA<MlsRejected>()),
    );
  });
}
