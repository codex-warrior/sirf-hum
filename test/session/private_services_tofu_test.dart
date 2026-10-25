// WhatsApp-style trust (D-160) with real native cores: two phones that never
// compared safety numbers still form the couple's encrypted group, and the
// safety-number page shows the partner as "not compared" (optional) until
// the person compares.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum/security/verification/partner_code_memory.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';
import 'package:sirf_hum/session/private_services.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../security/device/device_test_support.dart';
import '../security/device/fake_registry.dart';
import '../security/messaging/fake_transport.dart';

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
      throw UnimplementedError('not used here');
}

void main() {
  final accountA = AccountId('accountA');
  final accountB = AccountId('accountB');
  final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x6c)));

  group('native', () {
    late Directory root;
    late Map<String, FakeRegistry> registries;
    late FakeTransport server;
    final cores = <String, CryptoCore>{};

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_tofu_');
      registries = {
        accountA.value: FakeRegistry(),
        accountB.value: FakeRegistry(),
      };
      server = FakeTransport(
        members: [accountA.value, accountB.value],
        statusOf: (account, device) =>
            registries[account]?.statuses[device] ?? DeviceStatus.unknown,
      )..trustEpochOf = ((a) => registries[a]!.trustEpoch);
      cores.clear();
      for (final (name, account) in [('a1', accountA), ('b1', accountB)]) {
        final core = cores[name] = CryptoCore.initializeWithPlatformKey(
          directory: (Directory(
            '${root.path}/$name',
          )..createSync(recursive: true)).path,
          storeKey: Uint8List.fromList(List.filled(32, name.codeUnits.first)),
        )..createIdentity(account);
        expect(
          await DeviceRegistrationFlow(registries[account.value]!).enroll(
            core: core,
            account: account,
            platform: DevicePlatform.android,
          ),
          isA<EnrollmentActive>(),
        );
      }
    });

    tearDown(() {
      for (final c in cores.values) {
        c.close();
      }
      root.deleteSync(recursive: true);
    });

    PrivateServices services(
      String name,
      AccountId account,
      AccountId partner,
      PartnerCodeMemory codes,
    ) => PrivateServices(
      core: cores[name]!,
      messaging: MessagingService(
        core: cores[name]!,
        account: account,
        conversation: cid,
        transport: server,
        registry: _Registries(registries),
      ),
      partner: partner,
      registry: _Registries(registries),
      codes: codes,
    );

    test('never compared, still connected; comparing stays optional', () async {
      final codesA = InMemoryPartnerCodeMemory();
      final codesB = InMemoryPartnerCodeMemory();
      final a = services('a1', accountA, accountB, codesA);
      final b = services('b1', accountB, accountA, codesB);
      var changes = 0;
      a.onPartnerCodeChanged = () => changes++;

      // Each phone publishes, then the first to see the other creates the
      // group and the other joins: no comparison anywhere.
      await a.connect();
      await b.connect();
      await a.connect();
      await b.connect();

      expect(a.messaging.core.epoch(GroupId(cid.bytes)), greaterThan(0));
      expect(b.messaging.core.epoch(GroupId(cid.bytes)), greaterThan(0));
      expect(await codesA.lastTrusted(), isNotNull);
      expect(changes, 0, reason: 'a first trust is not a change');

      // The page shows "not compared" until the person compares.
      final shown = await a.verification.load();
      expect(shown.status, VerificationStatus.notVerified);
      final compared = await a.verification.confirmCompared(shown);
      expect(compared.status, VerificationStatus.verified);
      expect(await codesA.compared(), shown.code);

      // A message gets through without anyone having compared on B.
      expect(await a.messaging.sendText('hello'), SendOutcome.sent);
      await b.messaging.sync();
      expect(b.messaging.messages().map((m) => m.text), contains('hello'));
    });

    test('a different code than the one trusted before is announced', () async {
      final codes = InMemoryPartnerCodeMemory();
      await codes.setLastTrusted('an-older-code');
      final a = services('a1', accountA, accountB, codes);
      var changes = 0;
      a.onPartnerCodeChanged = () => changes++;
      await a.connect();
      expect(changes, 1);
      await a.connect();
      expect(changes, 1, reason: 'announced once per change');
    });
  }, skip: nativeSkip);
}
