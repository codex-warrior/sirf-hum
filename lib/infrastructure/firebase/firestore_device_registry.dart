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
/// - Reads: the owner's `users/{uid}/devices` records and `accountTrust/{uid}`
///   (rules: owner read; every client write is denied).
/// - Everything that changes trust, revocation included (D-081), is a
///   callable Function
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
          certificate: _optionalBytes(doc.data()['certificate']),
          activatedEpoch: doc.data()['activatedEpoch'] as int?,
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
        ChallengePurpose.revocation => 'revocation',
        ChallengePurpose.resetCancel => 'reset_cancel',
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
  Future<void> revoke(
    AccountId account, {
    required String revokerDeviceIdHex,
    required String deviceIdHex,
    required RevocationReason reason,
    required String challengeId,
    required Uint8List signature,
  }) => _call(
    'revokeDevice',
    revocationPayload(
      revokerDeviceIdHex: revokerDeviceIdHex,
      deviceIdHex: deviceIdHex,
      reason: reason,
      challengeId: challengeId,
      signature: signature,
    ),
  );

  /// The `revokeDevice` payload (tested against the server's inputs).
  static Map<String, Object> revocationPayload({
    required String revokerDeviceIdHex,
    required String deviceIdHex,
    required RevocationReason reason,
    required String challengeId,
    required Uint8List signature,
  }) => {
    'revokerDeviceId': revokerDeviceIdHex,
    'deviceId': deviceIdHex,
    'reason': reason.wireValue,
    'challengeId': challengeId,
    'signature': base64Encode(signature),
  };

  DocumentReference<Map<String, dynamic>> _trust(AccountId account) =>
      _firestore.doc('accountTrust/${account.value}');

  @override
  Future<AccountTrustState> trustState(AccountId account) => _guard(() async {
    final snap = await _trust(account).get();
    return trustStateFrom(snap.data());
  });

  /// Parses `accountTrust/{uid}` (functions/src/device/epoch.ts, reset.ts).
  static AccountTrustState trustStateFrom(Map<String, Object?>? data) {
    if (data == null) return AccountTrustState.none;
    final epoch = data['trustEpoch'];
    if (epoch is! int || epoch < 0) _malformed();
    final reset = data['reset'];
    final effectiveAt = reset is Map && reset['status'] == 'pending'
        ? reset['effectiveAtMillis']
        : null;
    return AccountTrustState(
      trustEpoch: epoch,
      identityEpoch: data['identityEpoch'] as int? ?? 0,
      bootstrapOpen: data['bootstrapOpen'] == true,
      resetEffectiveAt: effectiveAt is int
          ? DateTime.fromMillisecondsSinceEpoch(effectiveAt, isUtc: true)
          : null,
    );
  }

  @override
  Future<LineageRequest?> lineage(AccountId account) => _guard(() async {
    final trust = await _trust(account).get();
    final devices = await _devices(account).get();
    return lineageFrom(
      account: account,
      trust: trust.data(),
      records: {for (final d in devices.docs) d.id: d.data()},
    );
  });

  /// Builds the lineage request from the stored public evidence (D-084;
  /// functions/src/device/trust.ts and revocation.ts write it). The root is
  /// the current identity's first device; earlier identities (before a
  /// reset) are excluded by activation epoch. Missing or malformed evidence
  /// is [DeviceRegistryFailure.unexpectedState], never a shorter chain.
  static LineageRequest? lineageFrom({
    required AccountId account,
    required Map<String, Object?>? trust,
    required Map<String, Map<String, Object?>> records,
  }) {
    final rootId = trust?['firstDeviceId'];
    if (trust == null || trust['bootstrapOpen'] == true || rootId is! String) {
      return null;
    }
    final root = records[rootId] ?? _malformed();
    final rootEpoch = _epoch(root, 'activatedEpoch') ?? _malformed();
    final current =
        [
          for (final e in records.entries)
            if ((_epoch(e.value, 'activatedEpoch') ?? -1) > rootEpoch) e,
        ]..sort(
          (a, b) => _epoch(
            a.value,
            'activatedEpoch',
          )!.compareTo(_epoch(b.value, 'activatedEpoch')!),
        );
    final links = <LineageLink>[
      for (final e in current)
        switch (e.value['activationMethod']) {
          'approval' => _approvalLink(e.value),
          'recovery' => _recoveryLink(e.value),
          _ => _malformed(),
        },
    ];
    final revocations = <SignedRevocation>[];
    final revokedIds = <Uint8List>[];
    for (final e in records.entries) {
      if (e.value['status'] != 'revoked') continue;
      final revokedEpoch = _epoch(e.value, 'revokedEpoch');
      // Revoked before this identity's root existed: not part of the chain.
      if (revokedEpoch == null || revokedEpoch <= rootEpoch) continue;
      final revocation = e.value['revocation'];
      if (revocation is Map && revocation['authority'] == 'device') {
        revocations.add(
          SignedRevocation(
            protocolVersion: _intOf(revocation['protocolVersion']),
            revokerCertificate: _bytes(revocation['revokerCertificate']),
            revokedCertificate: _bytes(e.value['certificate']),
            reason: _intOf(revocation['reason']),
            challenge: _bytes(revocation['challenge']),
            expiresAtUnix: _intOf(revocation['expiresAtUnix']),
            signature: _bytes(revocation['signature']),
          ),
        );
      } else {
        // Server-asserted (identity reset): honoured, never a reason to trust.
        revokedIds.add(_hexBytes(e.key));
      }
    }
    return LineageRequest(
      accountId: account.value,
      rootCertificate: _bytes(root['certificate']),
      links: links,
      revocations: revocations,
      revokedDeviceIds: revokedIds,
    );
  }

  static ApprovalLink _approvalLink(Map<String, Object?> record) {
    final e = _map(record['approval']);
    return ApprovalLink(
      protocolVersion: _intOf(e['protocolVersion']),
      approverCertificate: _bytes(e['approverCertificate']),
      newCertificate: _bytes(record['certificate']),
      challenge: _bytes(e['challenge']),
      expiresAtUnix: _intOf(e['expiresAtUnix']),
      signature: _bytes(e['signature']),
    );
  }

  static RecoveryLink _recoveryLink(Map<String, Object?> record) {
    final e = _map(record['recovery']);
    final reg = _map(e['registration']);
    return RecoveryLink(
      protocolVersion: _intOf(e['protocolVersion']),
      registrarCertificate: _bytes(reg['registrarCertificate']),
      recoveryPublicKey: _bytes(e['recoveryPublicKey']),
      registrationChallenge: _bytes(reg['challenge']),
      registrationExpiresAtUnix: _intOf(reg['expiresAtUnix']),
      registrationSignature: _bytes(reg['signature']),
      newCertificate: _bytes(record['certificate']),
      challenge: _bytes(e['challenge']),
      expiresAtUnix: _intOf(e['expiresAtUnix']),
      signature: _bytes(e['signature']),
    );
  }

  static Never _malformed() => throw const DeviceRegistryException(
    DeviceRegistryFailure.unexpectedState,
  );

  static int? _epoch(Map<String, Object?> record, String key) {
    final v = record[key];
    return v is int ? v : null;
  }

  static int _intOf(Object? v) => v is int ? v : _malformed();

  static Map<Object?, Object?> _map(Object? v) =>
      v is Map<Object?, Object?> ? v : _malformed();

  static Uint8List? _optionalBytes(Object? v) => switch (v) {
    Blob() => v.bytes,
    Uint8List() => v,
    _ => null,
  };

  static Uint8List _bytes(Object? v) => _optionalBytes(v) ?? _malformed();

  static final _deviceIdHex = RegExp(r'^[0-9a-f]{32}$');

  static Uint8List _hexBytes(String hex) {
    if (!_deviceIdHex.hasMatch(hex)) _malformed();
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  @override
  Future<DateTime> requestIdentityReset(AccountId account) => _guard(() async {
    final data = await _call('requestIdentityReset', const {});
    return DateTime.fromMillisecondsSinceEpoch(
      _int(data, 'effectiveAtMillis'),
      isUtc: true,
    );
  });

  @override
  Future<void> cancelIdentityReset(
    AccountId account,
    String deviceIdHex,
    String challengeId,
    Uint8List signature,
  ) => _call('cancelIdentityReset', {
    'deviceId': deviceIdHex,
    'challengeId': challengeId,
    'signature': base64Encode(signature),
  });

  @override
  Future<void> completeIdentityReset(AccountId account) =>
      _call('completeIdentityReset', const {});

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
