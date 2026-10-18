import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Firestore + Cloud Functions implementation of [DeviceRegistry]
/// (D-069, D-075, D-076).
///
/// - Reads: the owner's `users/{uid}/devices` records (rules: owner read).
/// - Revocation: the owner's one-way `revoked` update (rules).
/// - Everything that creates trust is a callable Function
///   (functions/src/index.ts). They need the Blaze plan to be deployed
///   (D-025); until then those calls fail as `unavailable`.
///
/// Only public material crosses this boundary: certificates, challenges,
/// signatures, the recovery key's PUBLIC half. Never private keys.
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

  CollectionReference<Map<String, dynamic>> _devices(AccountId account) =>
      _firestore.collection('users/${account.value}/devices');

  /// The `registerDevice` payload (tested against the server's inputs).
  static Map<String, Object> registrationPayload(PendingDeviceRegistration r) =>
      {
        'deviceId': r.deviceIdHex,
        'platform': r.platform.name,
        'certificate': base64Encode(r.certificate),
      };

  @override
  Future<DeviceStatus> status(AccountId account, String deviceIdHex) =>
      _guard(() async {
        final snap = await _devices(account).doc(deviceIdHex).get();
        if (!snap.exists) return DeviceStatus.unknown;
        return _statusOf(snap.data()?['status']);
      });

  @override
  Future<List<DeviceRecord>> listDevices(AccountId account) => _guard(() async {
    final snap = await _devices(account).get();
    return [
      for (final doc in snap.docs)
        DeviceRecord(
          deviceIdHex: doc.id,
          status: _statusOf(doc.data()['status']),
          platform: '${doc.data()['platform']}',
          activationMethod: doc.data()['activationMethod'] as String?,
          approvedByDeviceIdHex: doc.data()['approvedBy'] as String?,
        ),
    ];
  });

  @override
  Future<void> register(PendingDeviceRegistration r) =>
      _call('registerDevice', registrationPayload(r));

  @override
  Future<ActivationChallenge> requestChallenge(
    AccountId account,
    String deviceIdHex,
    ChallengePurpose purpose,
  ) => _guard(() async {
    final data = await _call('issueDeviceChallenge', {
      'deviceId': deviceIdHex,
      'purpose': switch (purpose) {
        ChallengePurpose.activation => 'activation',
        ChallengePurpose.recoveryRegistration => 'recovery_registration',
      },
    });
    return ActivationChallenge(
      challengeId: _string(data, 'challengeId'),
      challenge: base64Decode(_string(data, 'challenge')),
      expiresAtUnix: _int(data, 'expiresAtUnix'),
    );
  });

  @override
  Future<void> activate(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List proof,
  ) => _call('activateDevice', {
    'deviceId': deviceIdHex,
    'challengeId': challengeId,
    'proof': base64Encode(proof),
  });

  @override
  Future<ApprovalRequest> requestApproval(
    AccountId account,
    String deviceIdHex,
  ) => _guard(() async {
    final data = await _call('requestDeviceApproval', {
      'deviceId': deviceIdHex,
    });
    return ApprovalRequest(
      requestId: _string(data, 'requestId'),
      challenge: base64Decode(_string(data, 'challenge')),
      expiresAtUnix: _int(data, 'expiresAtUnix'),
    );
  });

  @override
  Future<void> proveEnrollment(
    AccountId account,
    String requestId,
    Uint8List proof,
  ) => _call('proveDeviceEnrollment', {
    'requestId': requestId,
    'proof': base64Encode(proof),
  });

  @override
  Future<List<PendingApproval>> pendingApprovals(AccountId account) =>
      _guard(() async {
        final result = await _functions
            .httpsCallable('listDeviceApprovalRequests')
            .call<List<Object?>>();
        return [
          for (final item in result.data.whereType<Map<Object?, Object?>>())
            PendingApproval(
              requestId: _string(item, 'requestId'),
              challenge: base64Decode(_string(item, 'challenge')),
              expiresAtUnix: _int(item, 'expiresAtUnix'),
              deviceIdHex: _string(item, 'deviceId'),
              platform: _string(item, 'platform'),
              certificate: base64Decode(_string(item, 'certificate')),
            ),
        ];
      });

  @override
  Future<void> approve(
    AccountId account,
    String requestId,
    String approverDeviceIdHex,
    Uint8List signature,
  ) => _call('approveDevice', {
    'requestId': requestId,
    'approverDeviceId': approverDeviceIdHex,
    'signature': base64Encode(signature),
  });

  @override
  Future<void> reject(AccountId account, String requestId) =>
      _call('rejectDeviceApproval', {'requestId': requestId});

  @override
  Future<void> revoke(AccountId account, String deviceIdHex) =>
      _guard(() async {
        await _devices(account).doc(deviceIdHex).update(revocationFields());
      });

  /// The owner's one-way revocation (exactly what the rules accept).
  static Map<String, Object> revocationFields() => {
    'status': 'revoked',
    'revokedAt': FieldValue.serverTimestamp(),
    'revokedReason': 'user_removed',
  };

  @override
  Future<void> registerRecoveryKey(
    AccountId account,
    String registrarDeviceIdHex,
    String challengeId,
    Uint8List recoveryPublicKey,
    Uint8List signature,
  ) => _call('registerRecoveryKey', {
    'deviceId': registrarDeviceIdHex,
    'challengeId': challengeId,
    'recoveryPublicKey': base64Encode(recoveryPublicKey),
    'signature': base64Encode(signature),
  });

  @override
  Future<void> recover(
    AccountId account,
    String requestId,
    Uint8List signature,
  ) => _call('recoverDevice', {
    'requestId': requestId,
    'signature': base64Encode(signature),
  });

  static DeviceStatus _statusOf(Object? value) =>
      DeviceStatus.fromServer(value) ??
      (throw const DeviceRegistryException(
        DeviceRegistryFailure.unexpectedState,
      ));

  Future<Map<Object?, Object?>> _call(String name, Map<String, Object> data) =>
      _guard(() async {
        final result = await _functions.httpsCallable(name).call<Object?>(data);
        final value = result.data;
        return value is Map<Object?, Object?> ? value : const {};
      });

  static String _string(Map<Object?, Object?> data, String key) {
    final value = data[key];
    if (value is! String) {
      throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
    }
    return value;
  }

  static int _int(Map<Object?, Object?> data, String key) {
    final value = data[key];
    if (value is! int) {
      throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
    }
    return value;
  }

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
