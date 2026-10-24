import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/features/phone_setup/application/phone_setup_controller.dart';
import 'package:sirf_hum/features/phone_setup/presentation/phone_setup_screen.dart';
import 'package:sirf_hum/session/phone_setup.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../../support/session_fakes.dart';

/// A phone whose private services say "set this phone up again".
class _NeedsSetupOpener implements PrivateServicesOpener {
  int opens = 0;
  bool active = false;

  /// While set, opening waits for it (to observe the reopen).
  Completer<PrivateServices>? hold;

  @override
  Future<PrivateServices> open(AccountId account) {
    opens++;
    if (active) return (hold = Completer()).future;
    return Future.error(
      const PrivateServicesException(PrivateServicesProblem.needsSetup),
    );
  }
}

/// A scripted [PhoneSetup]: each call returns the next answer.
class _FakeSetup implements PhoneSetup {
  _FakeSetup(this.answers);

  final List<Object> answers;
  final calls = <String>[];
  final keys = <String>[];
  bool closed = false;

  Future<PhoneSetupStep> _next(String call) async {
    calls.add(call);
    final answer = answers.removeAt(0);
    if (answer is PhoneSetupException) throw answer;
    return answer as PhoneSetupStep;
  }

  @override
  Future<PhoneSetupStep> check() => _next('check');

  @override
  Future<PhoneSetupStep> useRecoveryKey(String key) {
    keys.add(key);
    return _next('key');
  }

  @override
  Future<PhoneSetupStep> requestReset() => _next('reset');

  @override
  Future<PhoneSetupStep> finishReset() => _next('finish');

  @override
  void close() => closed = true;
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late _NeedsSetupOpener opener;

  Future<_FakeSetup> pump(
    WidgetTester tester,
    List<Object> answers, {
    String? location,
  }) async {
    final setup = _FakeSetup(answers);
    opener = _NeedsSetupOpener();
    setPhoneWindow(tester);
    await pumpSirfHum(
      tester,
      initialLocation: location,
      extra: [
        privateServicesOpenerProvider.overrideWithValue(opener),
        phoneSetupFactoryProvider.overrideWithValue((_) => setup),
      ],
    );
    return setup;
  }

  Finder text(String s) => find.text(s);

  testWidgets('Home says to set the phone up; never "no longer trusted"', (
    tester,
  ) async {
    await pump(tester, []);
    expect(text('Set up this phone'), findsOneWidget);
    expect(find.textContaining('no longer'), findsNothing);
  });

  testWidgets('Moments, Future and Us offer the setup, not a dead end', (
    tester,
  ) async {
    for (final area in [ProductArea.moments, ProductArea.future]) {
      await tester.pumpWidget(const SizedBox());
      await pump(tester, [], location: area.path);
      expect(
        find.widgetWithText(FilledButton, 'Set up this phone'),
        findsOneWidget,
        reason: area.name,
      );
      expect(find.textContaining('no longer'), findsNothing);
    }
  });

  testWidgets('start fresh: confirm, wait, finish, then compare again — and '
      'the private services reopen', (tester) async {
    final effectiveAt = DateTime.now().add(const Duration(hours: 1));
    final setup = await pump(tester, [
      const PhoneSetupNeedsApproval(code: 123456),
      PhoneSetupResetPending(effectiveAt),
      const PhoneSetupResetReady(),
      const PhoneSetupDone(newIdentity: true),
    ]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Set up'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSetupScreen), findsOneWidget);
    expect(text('No backup key?'), findsOneWidget);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Start fresh'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start fresh'));
    await tester.pumpAndSettle();
    expect(text('Start fresh on this phone?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Start fresh'));
    await tester.pumpAndSettle();
    expect(text('Almost there.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Check again'));
    await tester.pumpAndSettle();
    expect(text('Ready when you are.'), findsOneWidget);

    final opensBefore = opener.opens;
    opener.active = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Finish setting up'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(setup.calls, ['check', 'reset', 'check', 'finish']);
    expect(setup.closed, isTrue, reason: 'keys closed before reopening');
    expect(text('This phone is set up.'), findsOneWidget);
    expect(find.textContaining('compare your safety numbers'), findsOneWidget);
    // Back on Home (visible again), the private services open afresh.
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(opener.opens, greaterThan(opensBefore), reason: 'reopened');
  });

  testWidgets('backup key: a wrong key says so; the right one sets it up', (
    tester,
  ) async {
    final setup = await pump(tester, [
      const PhoneSetupNeedsApproval(code: 123456),
      const PhoneSetupException(PhoneSetupFailure.wrongKey),
      const PhoneSetupDone(newIdentity: false),
    ]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Set up'));
    await tester.pumpAndSettle();
    final use = find.widgetWithText(OutlinedButton, 'Use backup key');
    expect(tester.widget<OutlinedButton>(use).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ABCD-EFGH');
    await tester.pump();
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(
      text('That backup key didn’t work. Check it and try again.'),
      findsOneWidget,
    );
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(setup.keys, ['ABCD-EFGH', 'ABCD-EFGH']);
    expect(text('This phone is set up.'), findsOneWidget);
  });

  testWidgets('the setup screen meets guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, [const PhoneSetupNeedsApproval(code: 1)]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Set up'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
