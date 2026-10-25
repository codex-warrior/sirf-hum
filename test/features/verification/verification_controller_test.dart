// Partner verification controller and screen (Prompt 17B, D-128) over a
// fake backend: gating, the explicit-confirmation-only trust rule, wrong
// codes, stale answers across sign-out and account switches, and logs.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/features/verification/application/verification_controller.dart';
import 'package:sirf_hum/features/verification/domain/verification_state.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';
import 'package:sirf_hum/security/verification/safety_number.dart';
import 'package:sirf_hum/session/session_controller.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../../support/session_fakes.dart';

SafetyNumber _number(int partnerKey) => SafetyNumber.of(
  ownAccount: 'alice',
  ownRoot: PersonKey(Uint8List.fromList(List.filled(32, 1))),
  partnerAccount: 'bob',
  partnerRoot: PersonKey(Uint8List.fromList(List.filled(32, partnerKey))),
);

/// Mirrors PartnerVerificationService's trust rule: only a confirmation
/// (or a matching scan) of the number it showed verifies.
class FakeVerificationBackend implements PartnerVerificationBackend {
  FakeVerificationBackend({this.partnerKey = 2});

  int partnerKey;
  bool verified = false;
  int confirmations = 0;
  VerificationFailure? failNextConfirm;
  Completer<void>? gate;

  PartnerVerification _now() => PartnerVerification.forTesting(
    status: verified
        ? VerificationStatus.verified
        : VerificationStatus.notVerified,
    number: _number(partnerKey),
    partnerDeviceCount: verified ? 2 : 0,
  );

  @override
  Future<PartnerVerification> load() async {
    await gate?.future;
    return _now();
  }

  @override
  Future<PartnerVerification> confirmCompared(PartnerVerification shown) async {
    confirmations++;
    await gate?.future;
    final fail = failNextConfirm;
    failNextConfirm = null;
    if (fail != null) throw VerificationException(fail);
    if (shown.number != _number(partnerKey)) {
      throw const VerificationException(VerificationFailure.changedWhileShown);
    }
    verified = true;
    return _now();
  }

  @override
  Future<PartnerVerification> confirmScanned(
    PartnerVerification shown,
    Uint8List scanned,
  ) async {
    if (!shown.number.matchesScanned(scanned)) {
      throw const VerificationException(VerificationFailure.mismatch);
    }
    return confirmCompared(shown);
  }
}

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) => lines.add('${record.event} ${record.fields}');
}

void main() {
  late FakeAccountSession session;
  late void Function(AccountId?) switchTo;
  final bob = AccountId('uidBob0123456789abcdefXYZ');

  ProviderContainer container({
    PartnerVerificationBackend? backend,
    bool noBackend = false,
    bool privateContent = true,
    Map<String, PartnerVerificationBackend>? perAccount,
  }) {
    session = FakeAccountSession(alice);
    var current = alice.value;
    final c = ProviderContainer(
      overrides: sessionOverrides(
        session: session,
        backend: FakePairingBackend.returning(paired),
        profiles: FakeCoupleProfiles(names),
        privateContent: privateContent,
        extra: [
          if (perAccount != null)
            partnerVerificationBackendProvider.overrideWith((ref) {
              ref.watch(sessionProvider);
              return perAccount[current];
            })
          else
            partnerVerificationBackendProvider.overrideWithValue(
              noBackend ? null : backend ?? FakeVerificationBackend(),
            ),
        ],
      ),
    );
    // As production: one backend per account, rebuilt on a session change.
    switchTo = (a) {
      current = a?.value ?? '';
      session.emit(a);
    };
    addTearDown(c.dispose);
    return c;
  }

  Future<VerificationViewState> settle(ProviderContainer c) async {
    c.listen(partnerVerificationProvider, (_, _) {}, fireImmediately: true);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(partnerVerificationProvider);
  }

  group('gating', () {
    test('production today: no backend → not yet available', () async {
      expect(
        await settle(container(noBackend: true)),
        isA<VerificationUnavailable>().having(
          (s) => s.reason,
          'reason',
          VerificationUnavailableReason.notYetAvailable,
        ),
      );
    });

    test('web: needs the phone, the backend is never asked', () async {
      final backend = FakeVerificationBackend();
      expect(
        await settle(container(backend: backend, privateContent: false)),
        isA<VerificationUnavailable>().having(
          (s) => s.reason,
          'reason',
          VerificationUnavailableReason.needsPhone,
        ),
      );
      expect(backend.confirmations, 0);
    });
  });

  group('trust only by explicit confirmation', () {
    test('loads Not verified with 12 groups and a scannable code', () async {
      final s = await settle(container()) as VerificationReady;
      expect(s.status, VerificationStatus.notVerified);
      expect(s.groups, hasLength(12));
      expect(SafetyNumber.payloadFromQrText(s.qrText), isNotNull);
    });

    test('"The numbers match" verifies', () async {
      final backend = FakeVerificationBackend();
      final c = container(backend: backend);
      await settle(c);
      await c.read(partnerVerificationProvider.notifier).confirmCompared();
      final s = c.read(partnerVerificationProvider) as VerificationReady;
      expect(s.verified, isTrue);
      expect(s.notice, VerificationNotice.verified);
      expect(backend.verified, isTrue);
    });

    test('a wrong QR trusts nothing; the right one verifies', () async {
      final backend = FakeVerificationBackend();
      final c = container(backend: backend);
      final ready = await settle(c) as VerificationReady;
      final controller = c.read(partnerVerificationProvider.notifier);
      for (final wrong in [
        'hello',
        _number(9).qrText,
        '${ready.qrText.substring(0, 20)}0${ready.qrText.substring(21)}',
      ]) {
        await controller.confirmScanned(wrong);
        final s = c.read(partnerVerificationProvider) as VerificationReady;
        expect(s.notice, VerificationNotice.scanMismatch);
        expect(s.verified, isFalse);
      }
      expect(backend.verified, isFalse);
      await controller.confirmScanned(ready.qrText);
      expect(
        (c.read(partnerVerificationProvider) as VerificationReady).verified,
        isTrue,
      );
    });

    test('"They don\'t match" trusts nothing and says so', () async {
      final backend = FakeVerificationBackend();
      final c = container(backend: backend);
      await settle(c);
      c.read(partnerVerificationProvider.notifier).reportMismatch();
      final s = c.read(partnerVerificationProvider) as VerificationReady;
      expect(s.notice, VerificationNotice.reportedMismatch);
      expect(s.verified, isFalse);
      expect(backend.confirmations, 0);
    });

    test('a number that changed while shown is never trusted', () async {
      final backend = FakeVerificationBackend();
      final c = container(backend: backend);
      await settle(c);
      backend.partnerKey = 3; // the server now shows another identity
      await c.read(partnerVerificationProvider.notifier).confirmCompared();
      final s = await settle(c) as VerificationReady;
      expect(backend.verified, isFalse);
      expect(s.verified, isFalse);
      expect(s.groups, _number(3).groups, reason: 'the new number is shown');
    });

    test('a revoked identity is reported, not verified', () async {
      final backend = FakeVerificationBackend()
        ..failNextConfirm = VerificationFailure.revoked;
      final c = container(backend: backend);
      await settle(c);
      await c.read(partnerVerificationProvider.notifier).confirmCompared();
      final s = c.read(partnerVerificationProvider) as VerificationReady;
      expect(s.notice, VerificationNotice.revoked);
      expect(s.verified, isFalse);
    });

    test('one confirmation at a time', () async {
      final backend = FakeVerificationBackend();
      final c = container(backend: backend);
      await settle(c);
      backend.gate = Completer<void>();
      final controller = c.read(partnerVerificationProvider.notifier);
      final first = controller.confirmCompared();
      await Future<void>.delayed(Duration.zero);
      expect(
        (c.read(partnerVerificationProvider) as VerificationReady).busy,
        isTrue,
      );
      await controller.confirmCompared();
      backend.gate!.complete();
      await first;
      expect(backend.confirmations, 1);
    });
  });

  group('stale answers', () {
    test('signed out while loading: the late answer never shows', () async {
      final backend = FakeVerificationBackend()..gate = Completer<void>();
      final c = container(backend: backend);
      c.listen(partnerVerificationProvider, (_, _) {}, fireImmediately: true);
      await Future<void>.delayed(Duration.zero);
      session.emit(null);
      backend.gate!.complete();
      final s = await settle(c);
      expect(s, isA<VerificationUnavailable>());
    });

    test('a confirmation that finishes after an account switch never marks '
        'the new account verified', () async {
      final aliceBackend = FakeVerificationBackend();
      final bobBackend = FakeVerificationBackend(partnerKey: 7);
      final c = container(
        perAccount: {alice.value: aliceBackend, bob.value: bobBackend},
      );
      await settle(c);
      aliceBackend.gate = Completer<void>();
      final pending = c
          .read(partnerVerificationProvider.notifier)
          .confirmCompared();
      await Future<void>.delayed(Duration.zero);
      switchTo(bob);
      aliceBackend.gate!.complete();
      await pending;
      final s = await settle(c) as VerificationReady;
      expect(s.verified, isFalse);
      expect(s.groups, _number(7).groups);
      expect(bobBackend.verified, isFalse);
    });
  });

  test('logs carry states only, never the number', () async {
    final sink = _Sink();
    AppLogger.configure(sinks: [sink]);
    addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
    final c = container();
    final s = await settle(c) as VerificationReady;
    await c.read(partnerVerificationProvider.notifier).confirmCompared();
    final all = sink.lines.join('\n');
    expect(all, contains('partner_verification_state'));
    for (final g in s.groups) {
      expect(all, isNot(contains(g)));
    }
    expect(all, isNot(contains(s.qrText.substring(6, 30))));
  });

  testWidgets('Us → Safety number: compare, confirm, Verified', (tester) async {
    setPhoneWindow(tester);
    final backend = FakeVerificationBackend();
    await pumpSirfHum(
      tester,
      initialLocation: '/us',
      extra: [partnerVerificationBackendProvider.overrideWithValue(backend)],
    );
    await tester.scrollUntilVisible(find.text('Privacy & Safety'), 200);
    expect(find.text('Encrypted · verify (optional)'), findsOneWidget);
    await tester.tap(find.text('Privacy & Safety'));
    await tester.pumpAndSettle();
    expect(find.text('Verify Ravi'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text(_number(2).groups.first), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('code Ravi can scan')), findsOneWidget);
    Future<void> tapVisible(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tapVisible("They don't match");
    expect(backend.verified, isFalse);
    await tapVisible('The numbers match');
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(backend.verified, isFalse, reason: 'backing out trusts nothing');
    await tapVisible('The numbers match');
    await tester.tap(find.text('They match'));
    await tester.pumpAndSettle();
    expect(backend.verified, isTrue);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('The numbers match'), findsNothing);
  });
}
