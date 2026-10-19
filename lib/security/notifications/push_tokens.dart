import 'dart:async';
import 'dart:typed_data';

import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// The device's FCM token (implemented by
/// `lib/infrastructure/firebase/firebase_push.dart`). A token is a delivery
/// address only; it never identifies or authorizes the device (D-098).
abstract interface class PushTokenSource {
  /// Null when push is unavailable (no Play services, permission, Web).
  Future<String?> token();

  /// New tokens after rotation.
  Stream<String> get onTokenRefresh;

  /// Invalidates the token at FCM (logout).
  Future<void> deleteToken();
}

/// A single-use challenge bound by the server to one token (or to
/// clearing). Public values only.
class PushTokenChallenge {
  const PushTokenChallenge({
    required this.challengeId,
    required this.challenge,
  });

  final String challengeId;
  final Uint8List challenge;

  @override
  String toString() => 'PushTokenChallenge(<redacted>)';
}

/// Port to the `requestPushTokenChallenge` / `registerPushToken` callables.
/// Failures are [DeviceRegistryException] categories.
abstract interface class PushTokenRegistry {
  Future<PushTokenChallenge> requestChallenge({
    required String deviceIdHex,
    required String? token,
  });

  Future<void> register({
    required String deviceIdHex,
    required String challengeId,
    required String? token,
    required Uint8List proof,
  });
}

/// Registers this device's push token with proof of possession (D-098): the
/// device key signs a challenge bound to the exact token, so a Firebase
/// session alone can never redirect or silence this device's wake-ups.
///
/// Call [register] when the device is active (app start, after approval)
/// and [watchRotation] to follow token refreshes; [unregister] on logout
/// (signed clear, then the token is deleted at FCM, which also covers an
/// offline logout). The server sends wake-ups only to devices that are
/// active at send time; this class never decides trust.
class PushTokenRegistrar {
  PushTokenRegistrar({
    required this.core,
    required PushTokenSource source,
    required PushTokenRegistry registry,
  }) : _source = source,
       _registry = registry;

  final CryptoCore core;
  final PushTokenSource _source;
  final PushTokenRegistry _registry;

  String get _deviceHex =>
      PendingDeviceRegistration.hexOf(core.publicIdentity().deviceId);

  /// Registers the current token. Returns false when there is none.
  Future<bool> register() async {
    final token = await _source.token();
    if (token == null) {
      _log('push_token_registered', 'no_token');
      return false;
    }
    await _signed(token);
    _log('push_token_registered', 'ok');
    return true;
  }

  /// Re-registers on every rotation until the subscription is cancelled.
  /// Failures are logged as categories and retried on the next rotation
  /// or [register].
  StreamSubscription<String> watchRotation() =>
      _source.onTokenRefresh.listen((token) async {
        try {
          await _signed(token);
          _log('push_token_rotated', 'ok');
        } on DeviceRegistryException catch (e) {
          _log('push_token_rotated', e.failure.name);
        }
      });

  /// Logout: clears the server record (signed), then deletes the token at
  /// FCM. If the clear cannot reach the server, the deleted token makes FCM
  /// refuse it and the server removes it on the next send.
  Future<void> unregister() async {
    try {
      await _signed(null);
      _log('push_token_cleared', 'ok');
    } on DeviceRegistryException catch (e) {
      _log('push_token_cleared', e.failure.name);
    } finally {
      await _source.deleteToken();
    }
  }

  Future<void> _signed(String? token) async {
    final device = _deviceHex;
    final c = await _registry.requestChallenge(
      deviceIdHex: device,
      token: token,
    );
    final proof = core.deviceProof(DeviceProofPurpose.pushToken, c.challenge);
    await _registry.register(
      deviceIdHex: device,
      challengeId: c.challengeId,
      token: token,
      proof: proof,
    );
  }

  static void _log(String event, String outcome) =>
      AppLogger.info(event, fields: {'outcome': SafeLogString(outcome)});
}

/// What a push asks the device to do (D-097). It carries nothing else:
/// whatever is new is fetched and decrypted on the device.
enum PushSignal {
  /// Something new from the partner (shown as the generic notification).
  message,

  /// Silent: sync (own device sent, a commit, a revocation).
  sync,

  /// Not a Sirf Hum wake-up, or a version this build does not know:
  /// ignored (never interpreted).
  unknown;

  /// Strict parse of the FCM data payload `{v: '1', k: 'm' | 's'}`.
  static PushSignal parse(Map<String, Object?> data) {
    if (data.length != 2 || data['v'] != '1') return unknown;
    return switch (data['k']) {
      'm' => message,
      's' => sync,
      _ => unknown,
    };
  }
}
