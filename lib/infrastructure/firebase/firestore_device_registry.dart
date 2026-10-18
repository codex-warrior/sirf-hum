import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Firestore + Cloud Functions implementation of [DeviceRegistry] (D-069).
///
/// - `users/{uid}/devices/{deviceId}` holds the public registration record;
///   firebase/firestore.rules lets the owner create it as `pending` only.
/// - `issueDeviceChallenge` / `activateDevice` (functions/src/index.ts) run
///   proof of possession and set `active`; they need the Blaze plan to be
///   deployed (D-025), so until then activation fails as `unavailable`.
///
/// Only public material crosses this boundary: the certificate, the
/// challenge, and the proof signature. Never private keys.
class FirestoreDeviceRegistry implements DeviceRegistry {
  FirestoreDeviceRegistry({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: functionsRegion);

  /// Matches functions/src/config/environment.ts (D-016).
  static const functionsRegion = 'asia-south1';

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _record(
    AccountId account,
    String deviceIdHex,
  ) => _firestore.doc('users/${account.value}/devices/$deviceIdHex');

  @override
  Future<DeviceStatus> status(AccountId account, String deviceIdHex) =>
      _guard(() async {
        final snap = await _record(account, deviceIdHex).get();
        if (!snap.exists) return DeviceStatus.unknown;
        final status = DeviceStatus.fromServer(snap.data()?['status']);
        if (status == null) {
          throw const DeviceRegistryException(
            DeviceRegistryFailure.unexpectedState,
          );
        }
        return status;
      });

  @override
  Future<void> createPending(PendingDeviceRegistration r) =>
      _guard(() => _record(r.accountId, r.deviceIdHex).set(pendingFields(r)));

  /// The exact pending record (tested against the rules' field list).
  static Map<String, Object> pendingFields(PendingDeviceRegistration r) => {
    'schemaVersion': PendingDeviceRegistration.schemaVersion,
    'status': 'pending',
    'platform': r.platform.name,
    'certificate': Blob(r.certificate),
    'ciphersuite': PendingDeviceRegistration.ciphersuite,
    'implementation': PendingDeviceRegistration.implementation,
    'createdAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<ActivationChallenge> requestActivationChallenge(
    AccountId account,
    String deviceIdHex,
  ) => _guard(() async {
    final result = await _functions
        .httpsCallable('issueDeviceChallenge')
        .call<Map<Object?, Object?>>({'deviceId': deviceIdHex});
    final data = result.data;
    final id = data['challengeId'];
    final challenge = data['challenge'];
    if (id is! String || challenge is! String) {
      throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
    }
    return ActivationChallenge(
      challengeId: id,
      challenge: base64Decode(challenge),
    );
  });

  @override
  Future<void> activate(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List proof,
  ) => _guard(
    () => _functions.httpsCallable('activateDevice').call<Object?>({
      'deviceId': deviceIdHex,
      'challengeId': challengeId,
      'proof': base64Encode(proof),
    }),
  );

  /// Translates SDK errors into categories; SDK messages never propagate.
  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DeviceRegistryException {
      rethrow;
    } on FirebaseFunctionsException catch (e) {
      // Our callables put only the category in the message.
      throw DeviceRegistryException(
        DeviceRegistryFailure.fromServer(e.message),
      );
    } on FirebaseException catch (e) {
      throw DeviceRegistryException(
        e.code == 'permission-denied'
            ? DeviceRegistryFailure.invalidRecord
            : DeviceRegistryFailure.unavailable,
      );
    } on FormatException {
      throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
    }
  }
}
