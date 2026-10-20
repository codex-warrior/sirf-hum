// Partner identity verification (Prompt 17B, D-128) with real native cores,
// real enrollment/approval flows and one FakeRegistry per account. Persons
// A (a1 root, a2) and B (b1 root, b2). The server's view of B can be
// swapped to model substitution.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/device/device_trust_service.dart';
import 'package:sirf_hum/security/verification/partner_verification.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../device/device_test_support.dart';
import '../device/fake_registry.dart';

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
      throw UnimplementedError('not used by verification');
}

Matcher fails(VerificationFailure f) => throwsA(
  isA<VerificationException>().having((e) => e.failure, 'failure', f),
);

void main() {
  final accountA = AccountId('accountA');
  final accountB = AccountId('accountB');

  group('native', () {
    late Directory root;
    late Map<String, FakeRegistry> registries;
    final cores = <String, CryptoCore>{};

    CryptoCore open(String name) => CryptoCore.initializeWithPlatformKey(
      directory: (Directory(
        '${root.path}/$name',
      )..createSync(recursive: true)).path,
      storeKey: Uint8List.fromList(List.filled(32, name.codeUnits.last)),
    );

    String hex(String name) =>
        PendingDeviceRegistration.hexOf(cores[name]!.publicIdentity().deviceId);

    Future<void> enroll(
      String name,
      AccountId account, {
      String? approver,
      FakeRegistry? into,
    }) async {
      final core = cores[name] = open(name)..createIdentity(account);
      final reg = into ?? registries[account.value]!;
      final state = await DeviceRegistrationFlow(
        reg,
      ).enroll(core: core, account: account, platform: DevicePlatform.android);
      if (approver != null) {
        expect(state, isA<EnrollmentAwaitingApproval>());
        final trust = DeviceTrustService(reg);
        final candidate = (await trust.pendingApprovals(
          core: cores[approver]!,
          account: account,
        )).single;
        await trust.approve(
          core: cores[approver]!,
          account: account,
          candidate: candidate,
        );
      } else {
        expect(state, isA<EnrollmentActive>());
      }
    }

    /// The service on [name]'s phone; [view] overrides what the server
    /// shows for each account (substitution).
    PartnerVerificationService on(
      String name, {
      Map<String, FakeRegistry>? view,
    }) {
      final mine = name.startsWith('a') ? accountA : accountB;
      return PartnerVerificationService(
        core: cores[name]!,
        account: mine,
        partner: mine == accountA ? accountB : accountA,
        registry: _Registries(view ?? registries),
      );
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_verify_');
      registries = {
        accountA.value: FakeRegistry(),
        accountB.value: FakeRegistry(),
      };
      cores.clear();
      await enroll('a1', accountA);
      await enroll('b1', accountB);
      await enroll('a2', accountA, approver: 'a1');
      await enroll('b2', accountB, approver: 'b1');
    });

    tearDown(() {
      for (final c in cores.values) {
        c.close();
      }
      root.deleteSync(recursive: true);
    });

    test('not verified until compared; all four phones show the same number; '
        'confirming verifies only that phone', () async {
      final views = [
        for (final n in ['a1', 'a2', 'b1', 'b2']) await on(n).load(),
      ];
      for (final v in views) {
        expect(v.status, VerificationStatus.notVerified);
        expect(v.number, views.first.number);
        expect(v.number.groups, hasLength(12));
      }
      final verified = await on('a1').confirmCompared(views.first);
      expect(verified.status, VerificationStatus.verified);
      expect(verified.partnerDeviceCount, 2);
      expect((await on('a2').load()).status, VerificationStatus.notVerified);
      expect((await on('b1').load()).status, VerificationStatus.notVerified);
      // A verified partner's devices are trusted through the lineage.
      expect(
        cores['a1']!.deviceAccount(cores['b2']!.publicIdentity().deviceId),
        accountB.value,
      );
    });

    test('scanning the right QR verifies; a wrong QR trusts nothing', () async {
      final shown = await on('a1').load();
      final partnerScreen = await on('b1').load();
      await expectLater(
        on('a1').confirmScanned(shown, Uint8List(69)),
        fails(VerificationFailure.mismatch),
      );
      final tampered = partnerScreen.number.qrPayload..[40] ^= 1;
      await expectLater(
        on('a1').confirmScanned(shown, tampered),
        fails(VerificationFailure.mismatch),
      );
      expect((await on('a1').load()).status, VerificationStatus.notVerified);
      final ok = await on(
        'a1',
      ).confirmScanned(shown, (await on('b1').load()).number.qrPayload);
      expect(ok.status, VerificationStatus.verified);
    });

    test('verification survives a restart (sealed in the core)', () async {
      await on('a1').confirmCompared(await on('a1').load());
      cores['a1']!.close();
      cores['a1'] = open('a1');
      expect((await on('a1').load()).status, VerificationStatus.verified);
    });

    test('server substitution: another root for B changes the number and is '
        'never verified by a stale confirmation', () async {
      final genuine = await on('a1').load();
      await on('a1').confirmCompared(genuine);
      // The server now presents an attacker's identity as account B.
      final evil = FakeRegistry();
      await enroll('x1', accountB, into: evil);
      // A competent attacker also moves the trust epoch forward (an older
      // one would be refused as stale before anything else).
      evil.trustEpoch = registries[accountB.value]!.trustEpoch + 1;
      final swapped = {
        accountA.value: registries[accountA.value]!,
        accountB.value: evil,
      };
      final seen = await on('a1', view: swapped).load();
      expect(seen.number, isNot(genuine.number));
      expect(seen.status, VerificationStatus.notVerified);
      // B's real phone still shows the genuine number: the people notice.
      expect((await on('b1').load()).number, genuine.number);
      // Confirming the number shown BEFORE the swap anchors nothing new.
      await expectLater(
        on('a1', view: swapped).confirmCompared(genuine),
        fails(VerificationFailure.changedWhileShown),
      );
      // Scanning B's genuine code against the substituted view fails.
      await expectLater(
        on('a1', view: swapped).confirmScanned(seen, genuine.number.qrPayload),
        fails(VerificationFailure.mismatch),
      );
      expect(
        cores['a1']!.deviceAccount(cores['x1']!.publicIdentity().deviceId),
        isNull,
      );
    });

    test(
      'a new partner device stays verified through the signed lineage',
      () async {
        await on('a1').confirmCompared(await on('a1').load());
        await enroll('b3', accountB, approver: 'b1');
        final v = await on('a1').load();
        expect(v.status, VerificationStatus.verified);
        expect(v.partnerDeviceCount, 3);
        expect(
          cores['a1']!.deviceAccount(cores['b3']!.publicIdentity().deviceId),
          accountB.value,
        );
      },
    );

    test('a changed partner identity (reset) needs a new comparison, and the '
        "old identity's devices stop being trusted at once", () async {
      final before = await on('a1').load();
      await on('a1').confirmCompared(before);
      final reg = registries[accountB.value]!;
      await reg.requestIdentityReset(accountB);
      await reg.completeIdentityReset(accountB);
      await enroll('b4', accountB);
      final after = await on('a1').load();
      expect(after.status, VerificationStatus.notVerified);
      expect(after.partnerResetCount, 1);
      expect(after.number, isNot(before.number));
      for (final old in ['b1', 'b2']) {
        expect(
          cores['a1']!.deviceAccount(cores[old]!.publicIdentity().deviceId),
          isNull,
          reason: old,
        );
      }
      // Comparing the NEW number verifies the new identity.
      final again = await on('a1').confirmCompared(after);
      expect(again.status, VerificationStatus.verified);
    });

    test('a revoked root can never be verified again, even if the server '
        'shows the old identity once more', () async {
      await on('a1').confirmCompared(await on('a1').load());
      final reg = registries[accountB.value]!;
      // Keep the old evidence, then reset B.
      final oldRoot = reg.firstDeviceId;
      final oldCert = Map.of(reg.certificates);
      final oldLinks = Map.of(reg.links);
      await reg.requestIdentityReset(accountB);
      await reg.completeIdentityReset(accountB);
      await enroll('b4', accountB);
      expect((await on('a1').load()).status, VerificationStatus.notVerified);
      // A malicious server re-presents the old identity as current.
      final replay = FakeRegistry()
        ..firstDeviceId = oldRoot
        ..trustEpoch = reg.trustEpoch
        ..certificates.addAll(oldCert)
        ..links.addAll(oldLinks)
        ..statuses.addAll(reg.statuses);
      final old = {
        accountA.value: registries[accountA.value]!,
        accountB.value: replay,
      };
      final shown = await on('a1', view: old).load();
      expect(shown.status, VerificationStatus.notVerified);
      await expectLater(
        on('a1', view: old).confirmCompared(shown),
        fails(VerificationFailure.revoked),
      );
    });

    test(
      'account switch: a service never runs on another account\'s core',
      () async {
        final wrong = PartnerVerificationService(
          core: cores['b1']!,
          account: accountA,
          partner: accountB,
          registry: _Registries(registries),
        );
        await expectLater(
          wrong.load(),
          throwsA(
            isA<CryptoException>().having(
              (e) => e.code,
              'code',
              CryptoErrorCode.accountMismatch,
            ),
          ),
        );
      },
    );

    test('a revoked, pending or unknown own device cannot verify', () async {
      registries[accountA.value]!.statuses[hex('a2')] = DeviceStatus.revoked;
      await expectLater(
        on('a2').load(),
        fails(VerificationFailure.ownIdentityUnproven),
      );
      expect(
        cores['a2']!.deviceAccount(cores['b1']!.publicIdentity().deviceId),
        isNull,
      );
    });

    test('a partner without a trusted device yet is unavailable, not '
        'verified', () async {
      final reg = registries[accountB.value]!;
      await reg.requestIdentityReset(accountB);
      await reg.completeIdentityReset(accountB);
      await expectLater(
        on('a1').load(),
        fails(VerificationFailure.partnerUnavailable),
      );
    });
  }, skip: nativeSkip);
}
