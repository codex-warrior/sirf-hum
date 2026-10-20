import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sirf_hum/features/moments/application/moment_photo_picker.dart';
import 'package:sirf_hum/features/moments/application/moments_controller.dart';
import 'package:sirf_hum/platform/io_media_files.dart';
import 'package:sirf_hum/platform/secure_key_store.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/device/local_device_identity.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../test/security/device/fake_registry.dart';
import '../test/security/media/fake_media_storage.dart';
import '../test/security/messaging/fake_transport.dart';
import '../test/support/moments_fakes.dart';
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
      throw UnimplementedError('not used by moments');
}

/// Moments on a real device (Prompt 15). The UI runs over the test-only
/// fake backend (no production backend exists yet, D-116); the second test
/// runs the real MomentsService over the REAL platform key store, with the
/// in-memory server stand-ins. Throwaway accounts; slots removed.
/// Home's Moments entry sits below the fold on small screens.
Future<void> openMoments(WidgetTester tester) async {
  final go = find.widgetWithText(TextButton, 'Go to Moments');
  await tester.ensureVisible(go);
  await tester.pumpAndSettle();
  await tester.tap(go);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // A tap that misses its target must fail here, not warn.
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('Moments: honest without a backend; add and open with one', (
    tester,
  ) async {
    await pumpSirfHum(tester);
    await openMoments(tester);
    expect(find.text('Your first memory is waiting.'), findsOneWidget);
    expect(find.text('Add a memory'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final picker = FakePhotoPicker();
    final backend = FakeMomentsBackend()
      ..onCreated = (d) => fakeMoment(1, caption: d.caption?.trim());
    await pumpSirfHum(
      tester,
      extra: [
        momentsBackendProvider.overrideWithValue(backend),
        momentPhotoPickerProvider.overrideWithValue(picker),
      ],
    );
    await openMoments(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add a memory'));
    await tester.pumpAndSettle();
    picker.next = [picker.photo()];
    final choose = find.widgetWithText(FilledButton, 'Choose photos');
    await tester.ensureVisible(choose);
    await tester.pumpAndSettle();
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'On the device');
    final save = find.widgetWithText(FilledButton, 'Save memory');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Saved. It’s here for both of you.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expectNoSecretsOnScreen(tester);
  });

  group('real core + platform key store', () {
    const keyStore = PlatformSecureKeyStore();
    final service = LocalDeviceIdentityService(keyStore: keyStore);
    final accountA = AccountId('itMomentsA');
    final accountB = AccountId('itMomentsB');
    final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x4e)));

    Future<void> clean() async {
      await service.removeAccount(accountA);
      await service.removeAccount(accountB);
    }

    setUp(clean);
    tearDown(clean);

    test('a moment is sealed, sent as ciphertext and opened by the '
        'partner; no plaintext in either slot', () async {
      final registries = {
        accountA.value: FakeRegistry(),
        accountB.value: FakeRegistry(),
      };
      DeviceStatus statusOf(String account, String device) =>
          registries[account]?.statuses[device] ?? DeviceStatus.unknown;
      final server = FakeTransport(
        members: [accountA.value, accountB.value],
        statusOf: statusOf,
      );
      final storage = FakeMediaStorage(
        uploaderStatus: (d) =>
            [for (final a in registries.keys) statusOf(a, d)].firstWhere(
              (s) => s != DeviceStatus.unknown,
              orElse: () => DeviceStatus.unknown,
            ),
      );

      final cores = <CryptoCore>[];
      final slots = <String>[];
      final moments = <MomentsService>[];
      final messaging = <MessagingService>[];
      for (final account in [accountA, accountB]) {
        final result = await service.open(account);
        expect(result, isA<LocalIdentityReady>(), reason: '$result');
        final core = (result as LocalIdentityReady).core;
        final slot = await keyStore.slotDirectory(
          LocalDeviceIdentityService.slotFor(account),
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
        slots.add(slot);
      }
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
          media: MediaSupport(
            storage: storage,
            files: const IoMediaFiles(),
            directory: IoMediaFiles.mediaDirectoryOf(slots[i]),
          ),
        );
        messaging.add(m);
        moments.add(MomentsService(messaging: m));
        await m.refreshTrust();
        await m.publishKeyPackage();
      }
      await messaging[0].sync();
      await messaging[1].sync();

      final marker = 'SIRF-HUM-DEVICE-MOMENT/'.codeUnits;
      final photo = Uint8List.fromList([
        for (var i = 0; i < 200000; i++) marker[i % marker.length],
      ]);
      final inputs = Directory.systemTemp.createTempSync('it_moments_in_');
      addTearDown(() => inputs.deleteSync(recursive: true));
      final picked = File('${inputs.path}/p.jpg')..writeAsBytesSync(photo);

      expect(
        await moments[0].create(
          MomentDraft(
            photos: [MomentInput(path: picked.path, sizeBytes: photo.length)],
            caption: 'DEVICE-CAPTION',
          ),
        ),
        MomentSaveOutcome.saved,
      );
      await moments[1].refresh();
      final received = moments[1].moments().whereType<Moment>().single;
      expect(received.caption, 'DEVICE-CAPTION');
      expect(await moments[1].openPhoto(received.photos.single), photo);

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

      for (final o in storage.objects.values) {
        expect(holds(o.bytes, marker), isFalse);
      }
      for (final slot in slots) {
        for (final f in Directory(
          slot,
        ).listSync(recursive: true).whereType<File>()) {
          final b = f.readAsBytesSync();
          expect(holds(b, marker), isFalse, reason: f.path);
          expect(holds(b, 'DEVICE-CAPTION'.codeUnits), isFalse, reason: f.path);
        }
      }
      for (final c in cores) {
        c.close();
      }
    });
  });
}
