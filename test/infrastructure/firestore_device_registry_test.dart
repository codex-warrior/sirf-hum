import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_device_registry.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

void main() {
  final registration = PendingDeviceRegistration(
    accountId: AccountId('accountA'),
    deviceId: DeviceId(Uint8List(16)),
    platform: DevicePlatform.ios,
    certificate: Uint8List.fromList(List.filled(185, 1)),
  );

  test('registration sends exactly what registerDevice reads', () {
    // Prompt 08: the server writes the pending record itself; the client
    // sends only these three inputs (functions/src/device/registration.ts).
    final payload = FirestoreDeviceRegistry.registrationPayload(registration);
    expect(payload.keys.toSet(), {'deviceId', 'platform', 'certificate'});
    final server = File(
      'functions/src/device/registration.ts',
    ).readAsStringSync();
    for (final key in payload.keys) {
      expect(server, contains('args.$key'), reason: 'server reads $key');
    }
    expect(payload['deviceId'], registration.deviceIdHex);
    expect(payload['platform'], 'ios');
    expect(
      base64Decode(payload['certificate']! as String),
      registration.certificate,
    );
  });

  test('revocation writes exactly the fields the rules allow', () {
    final rules = File('firebase/firestore.rules').readAsStringSync();
    final allowed = RegExp(
      r'affectedKeys\(\)\.hasOnly\(\[([^\]]*)\]\)',
    ).firstMatch(rules)!.group(1)!;
    final ruleFields = RegExp(r"'(\w+)'").allMatches(allowed).map((m) => m[1]);
    final fields = FirestoreDeviceRegistry.revocationFields();
    expect(fields.keys.toSet(), ruleFields.toSet());
    expect(fields['status'], 'revoked');
    expect(fields['revokedReason'], 'user_removed');
    expect(fields['revokedAt'], isA<FieldValue>());
  });

  test('implementation string matches the crypto core', () {
    expect(PendingDeviceRegistration.implementation, 'openmls/0.9.1');
  });
}
