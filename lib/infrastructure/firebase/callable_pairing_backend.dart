import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sirf_hum/infrastructure/firebase/firestore_device_registry.dart';
import 'package:sirf_hum/security/couple/pairing.dart';

/// The signed pairing callables (functions/src/couple/pairing.ts, Prompt 12).
/// Only the step, its subject (token or pairing ID), the challenge and the
/// 64-byte proof cross this boundary. Account IDs, statuses and timestamps
/// are never sent: the server derives them.
class CallablePairingBackend implements PairingBackend {
  CallablePairingBackend({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(
            region: FirestoreDeviceRegistry.functionsRegion,
          );

  final FirebaseFunctions _functions;

  @override
  Future<PairingChallenge> requestChallenge({
    required String deviceIdHex,
    required PairingStep step,
    String? token,
    String? pairingId,
  }) async {
    final data = await _call('requestPairingChallenge', {
      'deviceId': deviceIdHex,
      'action': step.name,
      'token': ?token,
      'pairingId': ?pairingId,
    });
    final id = data['challengeId'];
    final challenge = data['challenge'];
    if (id is! String || challenge is! String) throw _unavailable;
    return PairingChallenge(
      challengeId: id,
      challenge: base64Decode(challenge),
    );
  }

  @override
  Future<PairingInvitation> create(SignedPairingStep step) async {
    final data = await _call('createPairingInvitation', _signed(step));
    final (id, token, expires) = (
      data['pairingId'],
      data['token'],
      data['expiresAtMillis'],
    );
    if (id is! String || token is! String || expires is! int) {
      throw _unavailable;
    }
    if (!PairingInvitation.tokenPattern.hasMatch(token)) throw _unavailable;
    return PairingInvitation(
      pairingId: id,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true),
    );
  }

  @override
  Future<PairingAcceptance> accept(SignedPairingStep step, String token) async {
    final data = await _call('acceptPairingInvitation', {
      ..._signed(step),
      'token': token,
    });
    final (id, code, name, by) = (
      data['pairingId'],
      data['confirmationCode'],
      data['partnerDisplayName'],
      data['confirmExpiresAtMillis'],
    );
    if (id is! String || code is! String || by is! int) throw _unavailable;
    if (name != null && name is! String) throw _unavailable;
    return PairingAcceptance(
      pairingId: id,
      code: code,
      partnerDisplayName: name as String?,
      confirmBy: DateTime.fromMillisecondsSinceEpoch(by, isUtc: true),
    );
  }

  @override
  Future<CoupleMembership> confirm(
    SignedPairingStep step,
    String pairingId,
    String code,
  ) async {
    final data = await _call('confirmPairing', {
      ..._signed(step),
      'pairingId': pairingId,
      'confirmationCode': code,
    });
    final (couple, conversation) = (data['coupleId'], data['conversationId']);
    if (couple is! String || conversation is! String) throw _unavailable;
    return CoupleMembership(coupleId: couple, conversationId: conversation);
  }

  @override
  Future<void> reject(SignedPairingStep step, String pairingId) =>
      _call('rejectPairing', {..._signed(step), 'pairingId': pairingId});

  @override
  Future<void> cancel(SignedPairingStep step, String pairingId) =>
      _call('cancelPairing', {..._signed(step), 'pairingId': pairingId});

  @override
  Future<PairingState> state() async =>
      PairingState.parse(await _call('getPairingState', const {}));

  static const _unavailable = PairingException(PairingFailure.unavailable);

  static Map<String, Object?> _signed(SignedPairingStep step) => {
    'deviceId': step.deviceIdHex,
    'challengeId': step.challengeId,
    'proof': base64Encode(step.proof),
  };

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
      throw PairingException(PairingFailure.fromServer(e.message));
    } on FirebaseException {
      throw _unavailable;
    } on FormatException {
      throw _unavailable;
    }
  }
}
