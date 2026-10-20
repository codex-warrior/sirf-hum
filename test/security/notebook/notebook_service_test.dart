// The couple's notebook over the real crypto core (Prompt 16, D-118–D-121):
// real native cores and enrollment, the in-memory Firestore stand-in and
// network faults. Runs in CI (Linux) with SIRF_HUM_REQUIRE_NATIVE_CRYPTO=1;
// skipped on hosts without the core.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/platform/io_media_files.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/device/device_trust_service.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum/security/moments/moment.dart';
import 'package:sirf_hum/security/moments/moment_payload.dart';
import 'package:sirf_hum/security/moments/moments_service.dart';
import 'package:sirf_hum/security/notebook/notebook.dart';
import 'package:sirf_hum/security/notebook/notebook_payload.dart';
import 'package:sirf_hum/security/notebook/notebook_service.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../device/device_test_support.dart';
import '../device/fake_registry.dart';
import '../media/fake_media_storage.dart';
import '../messaging/fake_transport.dart';

class _Registries implements DeviceRegistry {
  _Registries(this.byAccount);

  final Map<String, FakeRegistry> byAccount;

  /// Status answers left before the registry goes "offline". Null: up.
  int? statusBudget;

  FakeRegistry _r(AccountId a) => byAccount[a.value]!;

  @override
  Future<DeviceStatus> status(AccountId a, String d) {
    final budget = statusBudget;
    if (budget != null) {
      if (budget <= 0) {
        throw const DeviceRegistryException(DeviceRegistryFailure.unavailable);
      }
      statusBudget = budget - 1;
    }
    return _r(a).status(a, d);
  }

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

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) =>
      lines.add('${record.message} ${record.fields}');
}

Matcher fails(NotebookFailure f) =>
    throwsA(isA<NotebookException>().having((e) => e.failure, 'failure', f));

/// Distinctive plaintext so any copy on disk or on the "server" is found.
const _secret = 'NOTEBOOK-SECRET';

NotebookFields _plan(
  String title, {
  FutureStatus status = FutureStatus.planned,
  String? note,
  MomentDate? date,
}) => NotebookFields(
  section: NotebookSection.future,
  category: FutureCategory.plan.wireValue,
  status: status.wireValue,
  title: title,
  note: note,
  date: date,
);

bool _contains(Uint8List hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  final accountA = AccountId('accountA');
  final accountB = AccountId('accountB');
  final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x6e)));
  final secretBytes = _secret.codeUnits;

  group('native', () {
    late Directory root;
    late Map<String, FakeRegistry> registries;
    late FakeTransport server;
    late FakeMediaStorage storage;
    final cores = <String, CryptoCore>{};
    final messaging = <String, MessagingService>{};
    final notebooks = <String, NotebookService>{};
    final mediaDirs = <String, String>{};
    final registryOf = <String, _Registries>{};
    var clock = 1000;

    String hex(String name) =>
        PendingDeviceRegistration.hexOf(cores[name]!.publicIdentity().deviceId);

    DeviceStatus statusOf(String account, String device) =>
        registries[account]?.statuses[device] ?? DeviceStatus.unknown;

    Future<void> enroll(
      String name,
      AccountId account, {
      String? approver,
    }) async {
      final dir = Directory('${root.path}/$name')..createSync(recursive: true);
      final core = cores[name] = CryptoCore.initializeWithPlatformKey(
        directory: dir.path,
        storeKey: Uint8List.fromList(
          List.filled(32, name.codeUnits.first ^ name.codeUnits.last),
        ),
      )..createIdentity(account);
      final reg = registries[account.value]!;
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
      mediaDirs[name] = IoMediaFiles.mediaDirectoryOf(dir.path);
    }

    NotebookService serviceFor(String name, AccountId account) {
      final m = messaging[name] = MessagingService(
        core: cores[name]!,
        account: account,
        conversation: cid,
        transport: server,
        registry: registryOf[name] = _Registries(registries),
        media: MediaSupport(
          storage: storage,
          files: const IoMediaFiles(),
          directory: mediaDirs[name]!,
        ),
        clock: () => ++clock,
      );
      return notebooks[name] = NotebookService(
        messaging: m,
        now: () => DateTime(2026, 10, 20, 12),
      );
    }

    List<NotebookEntry> shown(String name) =>
        notebooks[name]!.notebook().entries;

    List<LocalMessage> history(String name) => cores[name]!.history(cid);

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_notebook_svc_');
      registries = {
        accountA.value: FakeRegistry(),
        accountB.value: FakeRegistry(),
      };
      server = FakeTransport(
        members: [accountA.value, accountB.value],
        statusOf: statusOf,
      );
      storage = FakeMediaStorage(
        uploaderStatus: (device) {
          for (final account in registries.keys) {
            final s = statusOf(account, device);
            if (s != DeviceStatus.unknown) return s;
          }
          return DeviceStatus.unknown;
        },
      );
      cores.clear();
      messaging.clear();
      notebooks.clear();
      await enroll('a1', accountA);
      await enroll('b1', accountB);
      for (final (n, a) in [('a1', accountA), ('b1', accountB)]) {
        for (final r in ['a1', 'b1']) {
          cores[n]!.trustVerifiedPersonKey(
            cores[r]!.publicIdentity().personKey,
          );
        }
        serviceFor(n, a);
        await messaging[n]!.refreshTrust();
        await messaging[n]!.publishKeyPackage();
      }
      expect((await messaging['a1']!.sync()).epoch, 1);
      expect((await messaging['b1']!.sync()).joined, isTrue);
    });

    tearDown(() {
      for (final c in cores.values) {
        c.close();
      }
      root.deleteSync(recursive: true);
    });

    test('create → partner sees it, completes it → both phones agree; the '
        'server and both slots hold no plaintext', () async {
      expect(
        await notebooks['a1']!.create(
          _plan(
            '$_secret Udaipur',
            note: '$_secret lake',
            date: MomentDate(2026, 12, 28),
          ),
        ),
        NotebookSaveOutcome.saved,
      );
      final mine = shown('a1').single;
      expect(mine.addedByYou, isTrue);
      expect(mine.saving, isFalse);

      await notebooks['b1']!.refresh();
      final theirs = shown('b1').single;
      expect(theirs.title, '$_secret Udaipur');
      expect(theirs.note, '$_secret lake');
      expect(theirs.date, MomentDate(2026, 12, 28));
      expect(theirs.addedByYou, isFalse);

      expect(
        await notebooks['b1']!.update(
          theirs.handle,
          _plan('$_secret Udaipur', status: FutureStatus.done),
        ),
        NotebookSaveOutcome.saved,
      );
      await notebooks['a1']!.refresh();
      for (final n in ['a1', 'b1']) {
        expect(shown(n).single.done, isTrue, reason: n);
        expect(shown(n).single.note, isEmpty, reason: 'full replacement');
      }
      expect(shown('a1').single.changedByYou, isFalse);

      expect(server.messageDocs, hasLength(2));
      for (final d in server.messageDocs.values) {
        expect(_contains(d.ciphertext, secretBytes), isFalse);
        final fields = d.toFields().keys;
        expect(fields, isNot(contains('coupleId')));
        expect(fields, isNot(contains('title')));
      }
      for (final name in ['a1', 'b1']) {
        for (final f in Directory(
          '${root.path}/$name',
        ).listSync(recursive: true).whereType<File>()) {
          expect(
            _contains(f.readAsBytesSync(), secretBytes),
            isFalse,
            reason: f.path,
          );
        }
      }
    });

    test('remove reaches both phones; a late edit of a removed record does '
        'nothing', () async {
      await notebooks['a1']!.create(_plan('Goa'));
      await notebooks['b1']!.refresh();
      final handle = shown('b1').single.handle;

      await notebooks['a1']!.remove(shown('a1').single.handle);
      expect(shown('a1'), isEmpty);
      // b1 has not heard yet and edits; the server orders it after.
      await notebooks['b1']!.update(handle, _plan('Goa in March'));
      await notebooks['a1']!.refresh();
      await notebooks['b1']!.refresh();
      expect(shown('a1'), isEmpty);
      expect(shown('b1'), isEmpty);
      await expectLater(
        notebooks['b1']!.update(handle, _plan('again')),
        fails(NotebookFailure.notFound),
      );
      await expectLater(
        notebooks['b1']!.remove(handle),
        fails(NotebookFailure.notFound),
      );
    });

    test('offline: sealed on the phone, nothing leaves, then finishes '
        'exactly once', () async {
      server.offline = true;
      expect(
        await notebooks['a1']!.create(_plan('Manali')),
        NotebookSaveOutcome.savedOnPhone,
      );
      expect(shown('a1').single.saving, isTrue);
      expect(server.messageDocs, isEmpty);

      server.offline = false;
      await notebooks['a1']!.retryPending();
      expect(shown('a1').single.saving, isFalse);
      await notebooks['a1']!.retryPending();
      expect(server.messageDocs, hasLength(1));
      await notebooks['b1']!.refresh();
      expect(shown('b1'), hasLength(1));
    });

    test('device registry offline BEFORE sealing: unavailable, nothing kept; '
        'AFTER sealing: saved on the phone, exactly once', () async {
      registryOf['a1']!.statusBudget = 0;
      await expectLater(
        notebooks['a1']!.create(_plan('x')),
        fails(NotebookFailure.unavailable),
      );
      expect(history('a1'), isEmpty);

      registryOf['a1']!.statusBudget = 1; // queuePayload's check only
      expect(
        await notebooks['a1']!.create(_plan('y')),
        NotebookSaveOutcome.savedOnPhone,
      );
      expect(server.messageDocs, isEmpty);
      registryOf['a1']!.statusBudget = null;
      await notebooks['a1']!.refresh();
      expect(server.messageDocs, hasLength(1));
      await notebooks['b1']!.refresh();
      expect(shown('b1').single.title, 'y');
    });

    test('a lost acknowledgement is recognised: no duplicate', () async {
      server.loseNextAck = true;
      await notebooks['a1']!.create(_plan('Pondicherry'));
      await notebooks['a1']!.retryPending();
      await notebooks['a1']!.retryPending();
      expect(server.messageDocs, hasLength(1));
      await notebooks['b1']!.refresh();
      expect(shown('b1'), hasLength(1));
    });

    test('invalid changes are refused before anything is sealed', () async {
      await expectLater(
        notebooks['a1']!.create(
          NotebookFields(
            section: NotebookSection.story,
            title: 'Tomorrow',
            date: MomentDate(2026, 10, 21),
          ),
        ),
        fails(NotebookFailure.invalidDate),
      );
      await expectLater(
        notebooks['a1']!.create(
          NotebookFields(
            section: NotebookSection.togetherSince,
            date: MomentDate(2027, 1, 1),
          ),
        ),
        fails(NotebookFailure.invalidDate),
      );
      // A plan's date may be in the past or the future: never "missed".
      await notebooks['a1']!.create(
        _plan('Anniversary dinner', date: MomentDate(2020, 1, 1)),
      );
      await notebooks['a1']!.create(
        _plan('Trip', date: MomentDate(2030, 1, 1)),
      );
      expect(history('a1'), hasLength(2));

      // The section cannot change through an update.
      await expectLater(
        notebooks['a1']!.update(
          shown('a1').first.handle,
          NotebookFields(section: NotebookSection.ritual, title: 'x'),
        ),
        fails(NotebookFailure.notFound),
      );
      await expectLater(
        notebooks['a1']!.update(const NotebookHandle('zz'), _plan('x')),
        fails(NotebookFailure.notFound),
      );
      expect(history('a1'), hasLength(2));
    });

    test('section limits hold', () async {
      for (
        var i = 0;
        i < NotebookService.limits[NotebookSection.ritual]!;
        i++
      ) {
        await notebooks['a1']!.create(
          NotebookFields(section: NotebookSection.ritual, title: 'r$i'),
        );
      }
      await expectLater(
        notebooks['a1']!.create(
          NotebookFields(section: NotebookSection.ritual, title: 'one more'),
        ),
        fails(NotebookFailure.limitReached),
      );
      await notebooks['a1']!.create(
        NotebookFields(
          section: NotebookSection.togetherSince,
          date: MomentDate(2021, 3, 12),
        ),
      );
      await expectLater(
        notebooks['a1']!.create(
          NotebookFields(
            section: NotebookSection.togetherSince,
            date: MomentDate(2021, 3, 13),
          ),
        ),
        fails(NotebookFailure.limitReached),
      );
    });

    test('a revoked or stale device writes and fetches nothing', () async {
      await notebooks['a1']!.create(_plan('Goa'));
      for (final status in [
        DeviceStatus.revoked,
        DeviceStatus.pending,
        DeviceStatus.unknown,
      ]) {
        registries[accountB.value]!.statuses[hex('b1')] = status;
        await expectLater(
          notebooks['b1']!.create(_plan('x')),
          fails(NotebookFailure.deviceNotTrusted),
          reason: status.name,
        );
        await expectLater(
          notebooks['b1']!.refresh(),
          fails(NotebookFailure.deviceNotTrusted),
          reason: status.name,
        );
      }
      expect(history('b1'), isEmpty, reason: 'nothing fetched or sealed');
    });

    test('a change sealed while trusted never leaves once the device is '
        'revoked, and is not reported saved', () async {
      server.offline = true;
      expect(
        await notebooks['b1']!.create(_plan('queued')),
        NotebookSaveOutcome.savedOnPhone,
      );
      server.offline = false;
      registries[accountB.value]!.statuses[hex('b1')] = DeviceStatus.revoked;
      await expectLater(
        notebooks['b1']!.retryPending(),
        fails(NotebookFailure.deviceNotTrusted),
      );
      expect(server.messageDocs, isEmpty);
    });

    test('a revoked partner device gets no new change; after its removal '
        'changes flow again', () async {
      await enroll('b2', accountB, approver: 'b1');
      for (final r in ['a1', 'b1']) {
        cores['b2']!.trustVerifiedPersonKey(
          cores[r]!.publicIdentity().personKey,
        );
      }
      serviceFor('b2', accountB);
      await messaging['b2']!.refreshTrust();
      await messaging['b2']!.publishKeyPackage();
      await notebooks['a1']!.refresh();
      await messaging['a1']!.reconcileMembership();
      expect((await messaging['b2']!.sync()).joined, isTrue);

      await DeviceTrustService(registries[accountB.value]!).revoke(
        core: cores['b2']!,
        account: accountB,
        deviceIdHex: hex('b1'),
        reason: RevocationReason.lost,
      );
      await notebooks['a1']!.refresh();
      final before = server.messageDocs.length;
      await expectLater(
        notebooks['a1']!.create(_plan('not for b1')),
        fails(NotebookFailure.notReady),
      );
      expect(server.messageDocs.length, before);

      await messaging['a1']!.reconcileMembership();
      expect(
        await notebooks['a1']!.create(_plan('after')),
        NotebookSaveOutcome.saved,
      );
      await notebooks['b2']!.refresh();
      expect(shown('b2').single.title, 'after');
      await expectLater(
        notebooks['b1']!.refresh(),
        fails(NotebookFailure.deviceNotTrusted),
      );
      expect(shown('b1'), isEmpty);
    });

    test('an account outside the couple gets nothing and keeps nothing '
        'queued', () async {
      server.members.remove(accountB.value);
      await expectLater(
        notebooks['b1']!.refresh(),
        fails(NotebookFailure.notPaired),
      );
      await expectLater(
        notebooks['b1']!.create(_plan('x')),
        fails(NotebookFailure.notPaired),
      );
      expect(
        history('b1').where((m) => m.state == MessageState.queued),
        isEmpty,
      );
      expect(shown('b1'), isEmpty);
    });

    test('another conversation (another couple) shares nothing; a core of '
        'another account is refused', () async {
      await notebooks['a1']!.create(_plan('ours'));
      final other = NotebookService(
        messaging: MessagingService(
          core: cores['a1']!,
          account: accountA,
          conversation: ConversationId(Uint8List.fromList(List.filled(16, 1))),
          transport: server,
          registry: _Registries(registries),
        ),
      );
      expect(other.notebook().entries, isEmpty);
      await expectLater(
        other.update(shown('a1').single.handle, _plan('theirs')),
        fails(NotebookFailure.notFound),
      );

      final wrong = NotebookService(
        messaging: MessagingService(
          core: cores['a1']!,
          account: accountB,
          conversation: cid,
          transport: server,
          registry: _Registries(registries),
        ),
      );
      await expectLater(
        wrong.refresh(),
        throwsA(
          isA<CryptoException>().having(
            (e) => e.code,
            'code',
            CryptoErrorCode.accountMismatch,
          ),
        ),
      );
    });

    test('a forged change from the partner that names the wrong section is '
        'unreadable on both phones and changes nothing', () async {
      await notebooks['a1']!.create(_plan('Goa'));
      await notebooks['b1']!.refresh();
      final forged = NotebookPayload.update(
        target: shown('b1').single.handle.value,
        fields: NotebookFields(section: NotebookSection.story, title: 'mine'),
        clientTimeMs: 1,
      ).encode();
      await messaging['b1']!.queuePayload(forged);
      await messaging['b1']!.flushOutbox();
      await notebooks['a1']!.refresh();
      for (final n in ['a1', 'b1']) {
        final snap = notebooks[n]!.notebook();
        expect(snap.entries.single.title, 'Goa', reason: n);
        expect(snap.unreadable, 1, reason: n);
      }
    });

    test('notebook and moments share one conversation lock: concurrent '
        'changes from both features all arrive, once each', () async {
      final moments = MomentsService(messaging: messaging['a1']!);
      final photo = File('${root.path}/p.jpg')
        ..writeAsBytesSync(List.filled(3000, 7));
      final results = await Future.wait<Object?>([
        notebooks['a1']!.create(_plan('one')),
        moments.create(
          MomentDraft(photos: [MomentInput(path: photo.path, sizeBytes: 3000)]),
        ),
        notebooks['a1']!.refresh().then((_) => null),
        notebooks['a1']!.create(_plan('two')),
      ]);
      expect(results[0], NotebookSaveOutcome.saved);
      expect(results[1], MomentSaveOutcome.saved);
      expect(results[3], NotebookSaveOutcome.saved);
      expect(server.messageDocs, hasLength(4));

      await notebooks['b1']!.refresh();
      expect(shown('b1').map((e) => e.title), ['one', 'two']);
      final theirMoments = MomentsService(messaging: messaging['b1']!);
      expect(theirMoments.moments().whereType<Moment>(), hasLength(1));
      // Moments ignore notebook records and vice versa.
      expect(theirMoments.moments(), hasLength(1));
    });

    test('logs carry categories only', () async {
      final sink = _Sink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
      addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
      // Sealed, then the registry goes offline before the upload: deferred.
      registryOf['a1']!.statusBudget = 1;
      await notebooks['a1']!.create(_plan(_secret, note: _secret));
      registryOf['a1']!.statusBudget = null;
      await notebooks['a1']!.retryPending();
      await notebooks['b1']!.refresh();
      await notebooks['b1']!.remove(shown('b1').single.handle);
      await expectLater(
        notebooks['a1']!.create(_plan('   ')),
        fails(NotebookFailure.missingTitle),
      );
      final all = sink.lines.join('\n');
      for (final e in [
        'notebook_write_started',
        'notebook_write_completed',
        'notebook_write_failed',
        'notebook_write_deferred',
        'notebook_refreshed',
      ]) {
        expect(all, contains(e));
      }
      expect(all, isNot(contains(_secret)));
      expect(all, isNot(contains(root.path)));
      for (final n in ['a1', 'b1']) {
        expect(all, isNot(contains(hex(n))));
      }
      for (final m in server.messageDocs.values) {
        expect(all, isNot(contains(m.messageIdHex)));
      }
      expect(all, isNot(contains(accountA.value)));
    });
  }, skip: nativeSkip);
}
