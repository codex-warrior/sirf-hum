import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_device_registry.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/notifications/push_tokens.dart';

/// FCM token source (Prompt 11, D-098). Android only: Web has no device
/// identity and therefore no registration (D-046), iOS is out of scope
/// (D-092). Incoming messages are parsed with [PushSignal.parse] and carry
/// nothing but a kind.
class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Future<String?> token() async {
    try {
      return await _messaging.getToken();
    } on FirebaseException {
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } on FirebaseException {
      // Offline: the server drops the token on its next failed send.
    }
  }
}

/// The signed push-token callables (functions/src/notification/tokens.ts).
/// Only the token, the challenge and the 64-byte proof cross this boundary.
class CallablePushTokenRegistry implements PushTokenRegistry {
  CallablePushTokenRegistry({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(
            region: FirestoreDeviceRegistry.functionsRegion,
          );

  final FirebaseFunctions _functions;

  @override
  Future<PushTokenChallenge> requestChallenge({
    required String deviceIdHex,
    required String? token,
  }) async {
    final data = await _call('requestPushTokenChallenge', {
      'deviceId': deviceIdHex,
      'token': token,
    });
    final id = data['challengeId'];
    final challenge = data['challenge'];
    if (id is! String || challenge is! String) {
      throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
    }
    return PushTokenChallenge(
      challengeId: id,
      challenge: base64Decode(challenge),
    );
  }

  @override
  Future<void> register({
    required String deviceIdHex,
    required String challengeId,
    required String? token,
    required Uint8List proof,
  }) => _call('registerPushToken', {
    'deviceId': deviceIdHex,
    'challengeId': challengeId,
    'token': token,
    'proof': base64Encode(proof),
  });

  Future<Map<Object?, Object?>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      final value = result.data;
      return value is Map<Object?, Object?> ? value : const {};
    } on FirebaseFunctionsException catch (e) {
      // Our callables put only the category in the message.
      throw DeviceRegistryException(
        DeviceRegistryFailure.fromServer(e.message),
      );
    } on FirebaseException {
      throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
    } on FormatException {
      throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
    }
  }
}
