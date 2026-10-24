// The pairing screens (D-101–D-104, D-131) over a fake trusted phone. The
// signed steps themselves are tested in pairing_service_test.dart and on the
// server in functions/test/emulator/pairing.test.mjs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/features/pairing/application/invite_message.dart';
import 'package:sirf_hum/features/pairing/application/pairing_controller.dart';
import 'package:sirf_hum/features/pairing/application/pairing_device.dart';
import 'package:sirf_hum/platform/text_share.dart';
import 'package:sirf_hum/security/couple/pairing.dart';

import '../support/session_fakes.dart';

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) =>
      lines.add('${record.message} ${record.fields}');
}

class _Share implements TextShare {
  final shared = <String>[];

  @override
  Future<void> share(String text) async => shared.add(text);
}

const _token = FakePairingSession.token;

void main() {
  late _Sink sink;
  late PairingState server;
  late FakePairingBackend backend;
  late FakePairingSession phone;
  late _Share share;

  setUp(() {
    sink = _Sink();
    AppLogger.configure(sinks: [sink]);
    addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
    server = const PairingNone();
    backend = FakePairingBackend(() async => server);
    phone = FakePairingSession(backend);
    share = _Share();
  });

  tearDown(() {
    // The invitation token is a bearer secret and the code a comparison
    // secret: neither is ever logged.
    for (final line in sink.lines) {
      expect(line, isNot(contains(_token)));
      expect(line, isNot(contains('482913')));
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    PairingDeviceSetup? setup,
    FakeAccountSession? session,
  }) async {
    setPhoneWindow(tester);
    reduceMotion(tester);
    await pumpSirfHum(
      tester,
      session: session,
      backend: backend,
      profiles: FakeCoupleProfiles(names),
      deviceSetup:
          setup ?? FakePairingDeviceSetup(() async => DeviceSetupReady(phone)),
      extra: [
        textShareProvider.overrideWithValue(share),
        pairingPollIntervalProvider.overrideWithValue(
          const Duration(seconds: 1),
        ),
      ],
    );
  }

  Future<void> poll(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('inviter: invite, share, type the code, paired', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Invite your person'));
    await tester.pumpAndSettle();
    expect(phone.calls, ['create']);
    expect(find.text('Your invite is ready.'), findsOneWidget);

    await tester.tap(find.text('Share invite'));
    await tester.pumpAndSettle();
    expect(share.shared, [inviteMessage(_token)]);

    // The other person accepts on their phone.
    server = awaiting(isInviter: true);
    await poll(tester);
    expect(find.text('Ravi joined.'), findsOneWidget);
    expectNoSecretsOnScreen(tester);

    // A wrong code is refused by the server and can be retyped.
    phone.fail = PairingFailure.confirmationCodeInvalid;
    await tester.enterText(find.byType(TextField), '111111');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('doesn’t match'), findsOneWidget);

    phone.fail = null;
    server = paired;
    await tester.enterText(find.byType(TextField), '482913');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(phone.calls.last, 'confirm:482913');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Asha & Ravi.'), findsOneWidget);
    expect(phone.closed, isTrue, reason: 'keys released once paired');
  });

  testWidgets('the code field takes digits only, six at most', (tester) async {
    server = awaiting(isInviter: true);
    await pump(tester);
    await tester.enterText(find.byType(TextField), '48a29-13999');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '482913');
  });

  testWidgets('invitee: paste the message, read the code, paired', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('I have an invite'));
    await tester.pumpAndSettle();
    expect(find.text('Join your person.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), inviteMessage(_token));
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(phone.calls, ['accept:$_token']);
    expect(find.text('Read this code to Ravi.'), findsOneWidget);
    expect(find.text('482 913'), findsOneWidget);

    // The inviter confirms on their phone.
    server = paired;
    await poll(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('an unusable invite is refused before any server step', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('I have an invite'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello there');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(phone.calls, isEmpty);
    expect(find.textContaining('can’t be used'), findsOneWidget);

    // Back to the choice.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Bring your person in.'), findsOneWidget);
  });

  testWidgets('the server refusing an invite says so, human copy', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('I have an invite'));
    await tester.pumpAndSettle();
    phone.fail = PairingFailure.invitationInvalid;
    await tester.enterText(find.byType(TextField), _token);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.textContaining('can’t be used'), findsOneWidget);
    expectNoSecretsOnScreen(tester);
  });

  testWidgets('the inviter can refuse whoever accepted', (tester) async {
    server = awaiting(isInviter: true);
    await pump(tester);
    server = const PairingNone();
    await tester.tap(find.text('That’s not my person'));
    await tester.pumpAndSettle();
    expect(phone.calls, ['reject']);
    expect(find.text('Bring your person in.'), findsOneWidget);
  });

  testWidgets('an open invite can be cancelled', (tester) async {
    server = invited;
    await pump(tester);
    server = const PairingNone();
    await tester.tap(find.text('Cancel invite'));
    await tester.pumpAndSettle();
    expect(phone.calls, ['cancel']);
    expect(find.text('Bring your person in.'), findsOneWidget);
  });

  testWidgets('a failed setup can be retried', (tester) async {
    var fail = true;
    final setup = FakePairingDeviceSetup(
      () async => fail
          ? throw const PairingException(PairingFailure.unavailable)
          : DeviceSetupReady(phone),
    );
    await pump(tester, setup: setup);
    expect(find.text('We couldn’t set up this phone.'), findsOneWidget);
    expectNoSecretsOnScreen(tester);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Bring your person in.'), findsOneWidget);
    expect(setup.accounts, [alice, alice]);
  });

  testWidgets('a second phone waits for approval and shows its code', (
    tester,
  ) async {
    await pump(
      tester,
      setup: FakePairingDeviceSetup(
        () async => const DeviceSetupAwaitingApproval(42),
      ),
    );
    expect(
      find.text('This account is set up on another phone.'),
      findsOneWidget,
    );
    expect(find.text('000 042'), findsOneWidget);
    expect(find.text('Invite your person'), findsNothing);
  });

  testWidgets('a removed phone cannot pair', (tester) async {
    await pump(
      tester,
      setup: FakePairingDeviceSetup(
        () async => const DeviceSetupUnavailable(DeviceSetupProblem.removed),
      ),
    );
    expect(
      find.text('This phone was removed from your account.'),
      findsOneWidget,
    );
    expect(find.text('Invite your person'), findsNothing);
  });

  testWidgets('signing out releases this phone’s keys', (tester) async {
    final session = FakeAccountSession(alice);
    await pump(tester, session: session);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(phone.closed, isTrue);
    expect(find.text('Your private space for two.'), findsOneWidget);
  });

  testWidgets('an invite already open elsewhere shows that invite', (
    tester,
  ) async {
    await pump(tester);
    phone.fail = PairingFailure.pairingInProgress;
    server = invited;
    await tester.tap(find.text('Invite your person'));
    await tester.pumpAndSettle();
    expect(find.text('Your invite is out.'), findsOneWidget);
  });

  group('inviteTokenIn', () {
    test('finds the token in the shared message', () {
      expect(inviteTokenIn(inviteMessage(_token)), _token);
    });

    test('accepts the bare code, with spacing around it', () {
      expect(inviteTokenIn('  $_token \n'), _token);
    });

    test('refuses text without a whole 22-character code', () {
      expect(inviteTokenIn('hello'), isNull);
      expect(inviteTokenIn('${_token}X'), isNull);
      expect(inviteTokenIn('Invite code: short'), isNull);
    });
  });
}
