import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/app.dart';
import 'package:sirf_hum/features/home/application/home_providers.dart';
import 'package:sirf_hum/features/pairing/application/pairing_controller.dart';
import 'package:sirf_hum/features/pairing/application/pairing_device.dart';
import 'package:sirf_hum/security/account/account_session.dart';
import 'package:sirf_hum/security/couple/couple_profiles.dart';
import 'package:sirf_hum/security/couple/pairing.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

/// Values that must never appear on screen or in logs.
const testUid = 'uidAlice0123456789abcdefXYZ';
const testCoupleId = '0123456789abcdef0123456789abcdef';
const testConversationId = 'fedcba9876543210fedcba9876543210';
const testPairingId = 'aaaaaaaabbbbbbbbccccccccdddddddd';
const secretValues = [
  testUid,
  testCoupleId,
  testConversationId,
  testPairingId,
  '482913', // confirmation code
];

final alice = AccountId(testUid);

/// An auth session the test drives. Emits [initial] to each new listener,
/// like Firebase's restored session.
class FakeAccountSession implements AccountSession {
  FakeAccountSession([this._current]);

  AccountId? _current;
  final _changes = StreamController<AccountId?>.broadcast();
  int signOuts = 0;

  void emit(AccountId? account) {
    _current = account;
    _changes.add(account);
  }

  @override
  Stream<AccountId?> get accountChanges async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    emit(null);
  }
}

/// `getPairingState` answers set by the test. Every signed step throws: the
/// shell and entry screens must never perform one.
class FakePairingBackend implements PairingBackend {
  FakePairingBackend(this.answer);

  /// Returns the next answer (or throws a [PairingException]).
  Future<PairingState> Function() answer;
  int stateCalls = 0;

  static FakePairingBackend returning(PairingState state) =>
      FakePairingBackend(() async => state);

  static FakePairingBackend failing(PairingFailure failure) =>
      FakePairingBackend(() async => throw PairingException(failure));

  @override
  Future<PairingState> state() {
    stateCalls++;
    return answer();
  }

  @override
  Future<PairingChallenge> requestChallenge({
    required String deviceIdHex,
    required PairingStep step,
    String? token,
    String? pairingId,
  }) => throw StateError('no signed pairing step from the UI');

  @override
  Future<PairingInvitation> create(SignedPairingStep step) =>
      throw StateError('no signed pairing step from the UI');

  @override
  Future<PairingAcceptance> accept(SignedPairingStep step, String token) =>
      throw StateError('no signed pairing step from the UI');

  @override
  Future<CoupleMembership> confirm(
    SignedPairingStep step,
    String id,
    String code,
  ) => throw StateError('no signed pairing step from the UI');

  @override
  Future<void> reject(SignedPairingStep step, String id) =>
      throw StateError('no signed pairing step from the UI');

  @override
  Future<void> cancel(SignedPairingStep step, String id) =>
      throw StateError('no signed pairing step from the UI');

  @override
  Future<PairingChallenge> requestUnpairChallenge({
    required String deviceIdHex,
    required String coupleId,
  }) => throw StateError('no signed pairing step from the UI');

  @override
  Future<void> unpair(SignedPairingStep step, String coupleId) =>
      throw StateError('no signed pairing step from the UI');
}

/// This phone's signed pairing steps, as the pairing screen drives them.
/// [state] asks [backend], so `stateCalls` counts every server read.
class FakePairingSession implements PairingSession {
  FakePairingSession(this.backend);

  final PairingBackend? backend;
  final calls = <String>[];
  PairingFailure? fail;
  bool closed = false;
  Completer<void>? gate;

  static const token = 'AbCdEfGhIjKlMnOpQrStUv';

  Future<void> _step(String name) async {
    calls.add(name);
    await gate?.future;
    if (fail case final f?) throw PairingException(f);
  }

  @override
  Future<PairingInvitation> createInvitation() async {
    await _step('create');
    return PairingInvitation(
      pairingId: testPairingId,
      token: token,
      expiresAt: DateTime.utc(2026, 10, 20),
    );
  }

  @override
  Future<PairingAcceptance> acceptInvitation(String token) async {
    await _step('accept:$token');
    return PairingAcceptance(
      pairingId: testPairingId,
      code: '482913',
      partnerDisplayName: 'Ravi',
      confirmBy: DateTime.utc(2026, 10, 20),
    );
  }

  @override
  Future<CoupleMembership> confirm(String pairingId, String code) async {
    await _step('confirm:$code');
    return const CoupleMembership(
      coupleId: testCoupleId,
      conversationId: testConversationId,
    );
  }

  @override
  Future<void> reject(String pairingId) => _step('reject');

  @override
  Future<void> cancel(String pairingId) => _step('cancel');

  @override
  Future<PairingState> state() =>
      backend?.state() ??
      Future.error(const PairingException(PairingFailure.unavailable));

  @override
  void close() => closed = true;
}

class FakePairingDeviceSetup implements PairingDeviceSetup {
  FakePairingDeviceSetup(this.result);

  /// Returns the next result (or throws).
  Future<DeviceSetupResult> Function() result;
  final accounts = <AccountId>[];

  @override
  Future<DeviceSetupResult> setUp(AccountId account) {
    accounts.add(account);
    return result();
  }
}

class FakeCoupleProfiles implements CoupleProfiles {
  FakeCoupleProfiles([this.value = CoupleNames.unknown]);

  CoupleNames value;
  final requested = <AccountId>[];

  @override
  Future<CoupleNames> names(AccountId account) async {
    requested.add(account);
    return value;
  }

  /// Set to make the next save fail.
  CoupleProfileException? saveError;
  final saved = <String>[];

  @override
  Future<void> setYourName(AccountId account, String name) async {
    final error = saveError;
    if (error != null) throw error;
    final value = acceptableName(name);
    if (value == null) {
      throw const CoupleProfileException(CoupleProfileFailure.invalidName);
    }
    saved.add(value);
    this.value = CoupleNames(yours: value, partner: this.value.partner);
  }
}

/// The server's answers used across tests.
const paired = PairingPaired(
  coupleId: testCoupleId,
  conversationId: testConversationId,
);
final invited = PairingInvited(
  pairingId: testPairingId,
  expiresAt: DateTime.utc(2026, 10, 20),
);
PairingAwaitingConfirmation awaiting({required bool isInviter}) =>
    PairingAwaitingConfirmation(
      isInviter: isInviter,
      pairingId: testPairingId,
      // D-131: the inviter's phone never receives the code.
      code: isInviter ? null : '482913',
      partnerDisplayName: 'Ravi',
      expiresAt: DateTime.utc(2026, 10, 20),
    );

const names = CoupleNames(yours: 'Asha', partner: 'Ravi');

List<Override> sessionOverrides({
  required AccountSession session,
  PairingBackend? backend,
  CoupleProfiles? profiles,
  bool privateContent = true,
  DateTime? now,
  PairingDeviceSetup? deviceSetup,
  List<Override> extra = const [],
}) => [
  accountSessionProvider.overrideWithValue(session),
  pairingBackendProvider.overrideWithValue(backend),
  coupleProfilesProvider.overrideWithValue(profiles ?? FakeCoupleProfiles()),
  privateContentAvailableProvider.overrideWithValue(privateContent),
  homeClockProvider.overrideWithValue(() => now ?? DateTime(2026, 10, 19, 19)),
  // A phone that is already trusted, reading the same server answers.
  pairingDeviceSetupProvider.overrideWithValue(
    deviceSetup ??
        FakePairingDeviceSetup(
          () async => DeviceSetupReady(FakePairingSession(backend)),
        ),
  ),
  ...extra,
];

void setPhoneWindow(WidgetTester tester, [Size size = const Size(390, 844)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Reduced motion: waiting indicators stand still, so screens settle.
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Pumps the real app (router, shell, screens) over fakes.
Future<void> pumpSirfHum(
  WidgetTester tester, {
  AccountSession? session,
  PairingBackend? backend,
  CoupleProfiles? profiles,
  bool privateContent = true,
  String? initialLocation,
  bool settle = true,
  PairingDeviceSetup? deviceSetup,
  List<Override> extra = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: sessionOverrides(
        session: session ?? FakeAccountSession(alice),
        backend: backend ?? FakePairingBackend.returning(paired),
        profiles: profiles ?? FakeCoupleProfiles(names),
        privateContent: privateContent,
        deviceSetup: deviceSetup,
        extra: extra,
      ),
      child: SirfHumApp(initialLocation: initialLocation),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

/// Every string on screen: text widgets and the semantics tree.
List<String> visibleStrings(WidgetTester tester) {
  final texts = [
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      ?(w.data ?? w.textSpan?.toPlainText()),
    for (final w in tester.widgetList<RichText>(find.byType(RichText)))
      w.text.toPlainText(),
  ];
  final root =
      tester.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
  final semantics = <String>[];
  void visit(SemanticsNode node) {
    semantics
      ..add(node.label)
      ..add(node.value)
      ..add(node.hint);
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  return [...texts, ...semantics];
}

void expectNoSecretsOnScreen(WidgetTester tester) {
  final strings = visibleStrings(tester).join('\n');
  for (final secret in secretValues) {
    expect(strings, isNot(contains(secret)), reason: 'leaked $secret');
  }
  for (final internal in [
    'Firebase',
    'Exception',
    'PairingFailure',
    'users/',
  ]) {
    expect(strings, isNot(contains(internal)), reason: 'leaked $internal');
  }
}
