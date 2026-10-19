import 'dart:typed_data';

import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/core/logging/log_value.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Platforms that can hold a device identity (Web cannot, D-046).
enum DevicePlatform { android, ios }

/// The public registration record a client creates (status `pending`).
/// Exactly the fields `firebase/firestore.rules` accepts; each is justified
/// in DEVICE-IDENTITY.md ("Server-visible fields").
class PendingDeviceRegistration {
  PendingDeviceRegistration({
    required this.accountId,
    required DeviceId deviceId,
    required this.platform,
    required Uint8List certificate,
  }) : deviceIdHex = hexOf(deviceId),
       certificate = Uint8List.fromList(certificate) {
    if (certificate.isEmpty || certificate.length > maxCertificateBytes) {
      throw const DeviceRegistryException(DeviceRegistryFailure.invalidRecord);
    }
  }

  static const int schemaVersion = 1;
  static const int maxCertificateBytes = 512;

  /// MLS ciphersuite 0x0001 and implementation (D-061 capabilities).
  static const int ciphersuite = 1;
  static const String implementation = 'openmls/0.9.1';

  final AccountId accountId;

  /// Lower-case hex of the 16-byte device ID; the record's document ID.
  final String deviceIdHex;
  final DevicePlatform platform;

  /// The PIK-signed device certificate (D-064). Public material.
  final Uint8List certificate;

  static String hexOf(DeviceId id) =>
      id.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  String toString() => 'PendingDeviceRegistration(<redacted>)';
}

/// A server-issued, single-use activation challenge (5-minute lifetime).
class ActivationChallenge {
  ActivationChallenge({required this.challengeId, required Uint8List challenge})
    : challenge = Uint8List.fromList(challenge) {
    if (challenge.length != 32) {
      throw const DeviceRegistryException(DeviceRegistryFailure.invalidRecord);
    }
  }

  final String challengeId;
  final Uint8List challenge;

  @override
  String toString() => 'ActivationChallenge(<redacted>)';
}

/// Stable failure categories, matching functions/src/device/registration.ts.
enum DeviceRegistryFailure {
  invalidRecord,
  unauthenticated,
  deviceNotFound,
  deviceNotPending,
  challengeInvalid,
  challengeExpired,
  proofInvalid,
  certificateInvalid,
  duplicateDevice,

  /// The server returned a status this client does not understand.
  unexpectedState,

  /// Network, App Check or backend unavailable; safe to retry later.
  unavailable;

  /// Maps the server's category string; anything unknown is [unavailable]
  /// (retryable), never success.
  static DeviceRegistryFailure fromServer(String? category) =>
      switch (category) {
        'invalid_argument' => invalidRecord,
        'unauthenticated' => unauthenticated,
        'device_not_found' => deviceNotFound,
        'device_not_pending' => deviceNotPending,
        'challenge_invalid' => challengeInvalid,
        'challenge_expired' => challengeExpired,
        'proof_invalid' => proofInvalid,
        'certificate_invalid' => certificateInvalid,
        'duplicate_device' => duplicateDevice,
        _ => unavailable,
      };
}

class DeviceRegistryException implements Exception {
  const DeviceRegistryException(this.failure);

  final DeviceRegistryFailure failure;

  @override
  String toString() => 'DeviceRegistryException(${failure.name})';
}

/// Port for the server-side device registry, implemented by
/// `lib/infrastructure/firebase/firestore_device_registry.dart`.
abstract interface class DeviceRegistry {
  /// The record's status, [DeviceStatus.unknown] when there is none.
  Future<DeviceStatus> status(AccountId account, String deviceIdHex);

  /// Creates the `pending` record (Security Rules validate it).
  Future<void> createPending(PendingDeviceRegistration registration);

  Future<ActivationChallenge> requestActivationChallenge(
    AccountId account,
    String deviceIdHex,
  );

  /// Submits the proof; the server verifies it and activates the device.
  Future<void> activate(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List proof,
  );
}

/// Drives one device from unknown to active (DEVICE-IDENTITY.md, lifecycle).
///
/// Idempotent: safe to rerun after any failure. It never retries a
/// challenge (each attempt asks for a new one) and never tries to revive a
/// revoked device.
class DeviceRegistrationFlow {
  const DeviceRegistrationFlow(this._registry);

  final DeviceRegistry _registry;

  /// Registers and activates the device behind [core] for [account].
  /// Returns the final status: [DeviceStatus.active], or
  /// [DeviceStatus.revoked] (terminal: the caller needs a new identity).
  Future<DeviceStatus> ensureActive({
    required CryptoCore core,
    required AccountId account,
    required DevicePlatform platform,
  }) async {
    // The core must hold this account's identity before anything is sent.
    core.checkAccount(account);
    final identity = core.publicIdentity();
    final deviceIdHex = PendingDeviceRegistration.hexOf(identity.deviceId);

    var status = await _registry.status(account, deviceIdHex);
    if (status == DeviceStatus.unknown) {
      await _registry.createPending(
        PendingDeviceRegistration(
          accountId: account,
          deviceId: identity.deviceId,
          platform: platform,
          certificate: identity.certificate,
        ),
      );
      status = DeviceStatus.pending;
    }
    if (status == DeviceStatus.pending) {
      final challenge = await _registry.requestActivationChallenge(
        account,
        deviceIdHex,
      );
      final proof = core.deviceProof(
        DeviceProofPurpose.activation,
        challenge.challenge,
      );
      await _registry.activate(
        account,
        deviceIdHex,
        challenge.challengeId,
        proof,
      );
      status = DeviceStatus.active;
    }
    AppLogger.info(
      'device_registration_status',
      fields: {'status': SafeLogString(status.name)},
    );
    return status;
  }
}
