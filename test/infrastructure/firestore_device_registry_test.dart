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

  test('the pending record has exactly the fields the rules accept', () {
    final rules = File('firebase/firestore.rules').readAsStringSync();
    final listed = RegExp(
      r'let fields = \[([^\]]*)\]',
      multiLine: true,
    ).firstMatch(rules)!.group(1)!;
    final ruleFields = RegExp(r"'(\w+)'").allMatches(listed).map((m) => m[1]);
    expect(
      FirestoreDeviceRegistry.pendingFields(registration).keys.toSet(),
      ruleFields.toSet(),
    );
  });

  test('values match the rules: pending, v1, ciphersuite 1, bytes', () {
    final f = FirestoreDeviceRegistry.pendingFields(registration);
    expect(f['status'], 'pending');
    expect(f['schemaVersion'], 1);
    expect(f['ciphersuite'], 1);
    expect(f['implementation'], 'openmls/0.9.1');
    expect(f['platform'], 'ios');
    expect(f['certificate'], isA<Blob>());
    expect(f['createdAt'], isA<FieldValue>());
  });

  test('implementation string matches the crypto core', () {
    expect(PendingDeviceRegistration.implementation, 'openmls/0.9.1');
  });
}
