import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/app/product_area.dart';
import 'package:sirf_hum/features/notebook/application/notebook_controller.dart';
import 'package:sirf_hum/platform/secure_key_store.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../test/security/device/fake_registry.dart';
import '../test/security/messaging/fake_transport.dart';
import '../test/support/notebook_fakes.dart';
import '../test/support/session_fakes.dart';

class _Registries implements DeviceRegistry {
  _Registries(this.byAccount);

  final Map<String, FakeRegistry> byAccount;

  FakeRegistry _r(AccountId a) => byAccount[a.value]!;

  @override
  Future<DeviceStatus> status(AccountId a, String d) => _r(a).status(a, d);

  @override
  Future<AccountTrustState> trustState(AccountId a) => _r(a).trustState(a);

  @override
  Future<LineageRequest?> lineage(AccountId a) => _r(a).lineage(a);

  @override
  Future<List<DeviceRecord>> listDevices(AccountId a) => _r(a).listDevices(a);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used by the notebook');
}

/// Future and Us on a real device (Prompt 16). The UI runs over the
/// test-only fake backend (no production backend exists yet, D-121); the
/// second test runs the real NotebookService over the REAL platform key
/// store, with the in-memory server stand-in. Throwaway accounts; slots
/// removed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('Future and Us: honest without a backend; add with one', (
    tester,
  ) async {
    await pumpSirfHum(tester, initialLocation: ProductArea.future.path);
    expect(find.text('There’s a lot ahead of you.'), findsOneWidget);
    expect(find.text('+ Add'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final backend = FakeNotebookBackend();
    await pumpSirfHum(
      tester,
      initialLocation: ProductArea.future.path,
      extra: [notebookBackendProvider.overrideWithValue(backend)],
    );
    // "+ Add" beside Our Dreams, near the top on any phone.
    await tester.tap(find.widgetWithText(TextButton, '+ Add').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'On the device');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved. It’s here for both of you.'), findsOneWidget);
    expect(find.text('On the device'), findsOneWidget);

    await tester.tap(find.byIcon(ProductArea.us.icon));
    await tester.pumpAndSettle();
    expect(find.text('About Us'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoSecretsOnScreen(tester);
  });

  group('real core + platform key store', () {
    const keyStore = PlatformSecureKeyStore();
    final service = LocalDeviceIdentityService(keyStore: keyStore);
    final accountA = AccountId('itNotebookA');
    final accountB = AccountId('itNotebookB');
    final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x4f)));

    Future<void> clean() async {
      await service.removeAccount(accountA);
      await service.removeAccount(accountB);
    }

    setUp(clean);
    tearDown(clean);

    test('a plan is sealed, sent as ciphertext, completed by the partner; '
        'no plaintext in either slot', () async {
      final registries = {
        accountA.value: FakeRegistry(),
        accountB.value: FakeRegistry(),
      };
      final server = FakeTransport(
        members: [accountA.value, accountB.value],
        statusOf: (account, device) =>
            registries[account]?.statuses[device] ?? DeviceStatus.unknown,
      );

      final cores = <CryptoCore>[];
      final slots = <String>[];
      final notebooks = <NotebookService>[];
      for (final account in [accountA, accountB]) {
        final result = await service.open(account);
        expect(result, isA<LocalIdentityReady>(), reason: '$result');
        final core = (result as LocalIdentityReady).core;
        slots.add(
          await keyStore.slotDirectory(
            LocalDeviceIdentityService.slotFor(account),
          ),
        );
        expect(
          await DeviceRegistrationFlow(registries[account.value]!).enroll(
            core: core,
            account: account,
            platform: DevicePlatform.android,
          ),
          isA<EnrollmentActive>(),
        );
        cores.add(core);
      }
      final messaging = <MessagingService>[];
      for (final (i, account) in [accountA, accountB].indexed) {
        for (final c in cores) {
          cores[i].trustVerifiedPersonKey(c.publicIdentity().personKey);
        }
        final m = MessagingService(
          core: cores[i],
          account: account,
          conversation: cid,
          transport: server,
          registry: _Registries(registries),
        );
        messaging.add(m);
        notebooks.add(NotebookService(messaging: m));
        await m.refreshTrust();
        await m.publishKeyPackage();
      }
      await messaging[0].sync();
      await messaging[1].sync();

      const secret = 'DEVICE-NOTEBOOK-SECRET';
      expect(
        await notebooks[0].create(plan(secret, note: secret)),
        NotebookSaveOutcome.saved,
      );
      await notebooks[1].refresh();
      final received = notebooks[1].notebook().entries.single;
      expect(received.title, secret);
      await notebooks[1].update(received.handle, plan(secret, done: true));
      await notebooks[0].refresh();
      expect(notebooks[0].notebook().entries.single.done, isTrue);
      expect(
        notebooks[0].notebook().entries.single.section,
        NotebookSection.future,
      );

      bool holds(List<int> hay, List<int> needle) {
        outer:
        for (var i = 0; i + needle.length <= hay.length; i++) {
          for (var j = 0; j < needle.length; j++) {
            if (hay[i + j] != needle[j]) continue outer;
          }
          return true;
        }
        return false;
      }

      for (final d in server.messageDocs.values) {
        expect(holds(d.ciphertext, secret.codeUnits), isFalse);
      }
      for (final slot in slots) {
        for (final f in Directory(
          slot,
        ).listSync(recursive: true).whereType<File>()) {
          expect(
            holds(f.readAsBytesSync(), secret.codeUnits),
            isFalse,
            reason: f.path,
          );
        }
      }
      for (final c in cores) {
        c.close();
      }
    });
  });
}
