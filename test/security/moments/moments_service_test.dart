// Moments over the real crypto core (Prompt 15, D-113–D-116): real native
// cores and enrollment, the in-memory Firestore stand-in and the
// rules-faithful object store with network faults. Runs in CI (Linux) with
// SIRF_HUM_REQUIRE_NATIVE_CRYPTO=1; skipped on hosts without the core.
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
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../device/device_test_support.dart';
import '../device/fake_registry.dart';
import '../media/fake_media_storage.dart';
import '../messaging/fake_transport.dart';

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

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) =>
      lines.add('${record.message} ${record.fields}');
}

Matcher fails(MomentFailure f) =>
    throwsA(isA<MomentException>().having((e) => e.failure, 'failure', f));

/// Distinctive plaintext so any copy on disk or on the "server" is found.
const _marker = 'SIRF-HUM-PRIVATE-MOMENT/';
const _caption = 'CAPTION-SECRET our first evening by the sea';

Uint8List _photo(int length, [int salt = 0]) => Uint8List.fromList([
  for (var i = 0; i < length; i++)
    (_marker.codeUnitAt(i % _marker.length) + salt) & 0xff,
]);

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
  final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x5d)));
  final markerBytes = _marker.codeUnits;
  final captionBytes = 'CAPTION-SECRET'.codeUnits;

  group('native', () {
    late Directory root;
    late Map<String, FakeRegistry> registries;
    late FakeTransport server;
    late FakeMediaStorage storage;
    final cores = <String, CryptoCore>{};
    final messaging = <String, MessagingService>{};
    final moments = <String, MomentsService>{};
    final mediaDirs = <String, String>{};
    var clock = 1000;
    var picked = 0;

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

    MomentsService serviceFor(String name, AccountId account) {
      final m = messaging[name] = MessagingService(
        core: cores[name]!,
        account: account,
        conversation: cid,
        transport: server,
        registry: _Registries(registries),
        media: MediaSupport(
          storage: storage,
          files: const IoMediaFiles(),
          directory: mediaDirs[name]!,
        ),
        clock: () => ++clock,
      );
      return moments[name] = MomentsService(
        messaging: m,
        now: () => DateTime(2026, 10, 20, 12),
      );
    }

    MomentInput input(Uint8List bytes) {
      final f = File('${root.path}/picked_${++picked}.jpg')
        ..writeAsBytesSync(bytes);
      return MomentInput(path: f.path, sizeBytes: bytes.length);
    }

    MomentDraft draft(List<Uint8List> photos, {String? caption = _caption}) =>
        MomentDraft(
          photos: [for (final p in photos) input(p)],
          caption: caption,
          memoryDate: MomentDate(2026, 10, 18),
        );

    List<Moment> shown(String name) =>
        moments[name]!.moments().whereType<Moment>().toList();

    List<LocalMessage> history(String name) => cores[name]!.history(cid);

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_moments_svc_');
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
      moments.clear();
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

    test('create → partner sees it → photos open; the server holds only '
        'ciphertext and the caption never leaves MLS', () async {
      final p1 = _photo(150000, 1);
      final p2 = _photo(4000, 2);
      expect(
        await moments['a1']!.create(draft([p1, p2])),
        MomentSaveOutcome.saved,
      );
      final mine = shown('a1').single;
      expect(mine.status, MomentStatus.saved);
      expect(mine.addedByYou, isTrue);
      expect(mine.photoCount, 2);

      // Server: two opaque objects, three messages, no plaintext anywhere.
      expect(storage.objects, hasLength(2));
      expect(server.messageDocs, hasLength(3));
      for (final o in storage.objects.values) {
        expect(_contains(o.bytes, markerBytes), isFalse);
        expect(_contains(o.bytes, captionBytes), isFalse);
      }
      for (final d in server.messageDocs.values) {
        expect(_contains(d.ciphertext, markerBytes), isFalse);
        expect(_contains(d.ciphertext, captionBytes), isFalse);
        expect(d.toFields().keys, isNot(contains('coupleId')));
      }

      await moments['b1']!.refresh();
      final theirs = shown('b1').single;
      expect(theirs.status, MomentStatus.received);
      expect(theirs.addedByYou, isFalse);
      expect(theirs.caption, _caption);
      expect(theirs.memoryDate, MomentDate(2026, 10, 18));
      expect(theirs.problem, MomentProblem.none);
      expect(await moments['b1']!.openPhoto(theirs.photos[0]), p1);
      expect(await moments['b1']!.openPhoto(theirs.photos[1]), p2);
      expect(await moments['a1']!.openPhoto(mine.photos[0]), p1);

      // No plaintext at rest in either slot (the picked files are the
      // caller's, outside the slots).
      for (final name in ['a1', 'b1']) {
        for (final f in Directory(
          '${root.path}/$name',
        ).listSync(recursive: true).whereType<File>()) {
          final b = f.readAsBytesSync();
          expect(_contains(b, markerBytes), isFalse, reason: f.path);
          expect(_contains(b, captionBytes), isFalse, reason: f.path);
        }
      }
    });

    test('offline: sealed on the phone, nothing leaves, then finishes '
        'exactly once', () async {
      storage.offline = true;
      server.offline = true;
      expect(
        await moments['a1']!.create(draft([_photo(9000), _photo(9000, 3)])),
        MomentSaveOutcome.savedOnPhone,
      );
      expect(shown('a1').single.status, MomentStatus.saving);
      expect(storage.objects, isEmpty);
      expect(server.messageDocs, isEmpty);

      storage.offline = false;
      server.offline = false;
      await moments['a1']!.retryPending();
      expect(shown('a1').single.status, MomentStatus.saved);
      await moments['a1']!.retryPending(); // nothing left: no duplicates
      expect(storage.objects, hasLength(2));
      expect(storage.uploads, 2);
      expect(server.messageDocs, hasLength(3));

      await moments['b1']!.refresh();
      expect(shown('b1'), hasLength(1));
    });

    test('photos always reach the server before the moment that lists '
        'them, even when the upload is interrupted', () async {
      storage.interruptNextUpload = true;
      expect(
        await moments['a1']!.create(draft([_photo(5000), _photo(5000, 4)])),
        MomentSaveOutcome.savedOnPhone,
      );
      expect(server.messageDocs, isEmpty, reason: 'nothing before its object');
      await moments['a1']!.retryPending();
      expect(shown('a1').single.status, MomentStatus.saved);
      expect(storage.uploads, 2);
    });

    test('a lost acknowledgement is recognised: no duplicate objects or '
        'moments', () async {
      storage.loseNextUploadAck = true;
      server.loseNextAck = true;
      await moments['a1']!.create(draft([_photo(3000)]));
      await moments['a1']!.retryPending();
      await moments['a1']!.retryPending();
      expect(storage.uploads, 1);
      expect(server.messageDocs, hasLength(2));
      await moments['b1']!.refresh();
      expect(shown('b1'), hasLength(1));
    });

    test('a failed photo leaves nothing behind: no queued message, no '
        'object, nothing sent', () async {
      final good = input(_photo(2000));
      final missing = MomentInput(
        path: '${root.path}/vanished.jpg',
        sizeBytes: 2000,
      );
      await expectLater(
        moments['a1']!.create(MomentDraft(photos: [good, missing])),
        fails(MomentFailure.photoUnreadable),
      );
      expect(history('a1'), isEmpty);
      expect(Directory(mediaDirs['a1']!).listSync(), isEmpty);
      expect(storage.objects, isEmpty);
      expect(server.messageDocs, isEmpty);
    });

    test('invalid drafts are refused before anything is encrypted', () async {
      final p = _photo(100);
      await expectLater(
        moments['a1']!.create(const MomentDraft(photos: [])),
        fails(MomentFailure.noPhotos),
      );
      await expectLater(
        moments['a1']!.create(draft(List.filled(9, p))),
        fails(MomentFailure.tooManyPhotos),
      );
      await expectLater(
        moments['a1']!.create(
          MomentDraft(
            photos: [
              MomentInput(
                path: input(p).path,
                sizeBytes: MediaLimits.maxPlaintextBytes + 1,
              ),
            ],
          ),
        ),
        fails(MomentFailure.photoTooLarge),
      );
      await expectLater(
        moments['a1']!.create(
          MomentDraft(photos: [input(p)], memoryDate: MomentDate(2026, 10, 21)),
        ),
        fails(MomentFailure.invalidDate),
      );
      await expectLater(
        moments['a1']!.create(draft([p], caption: 'x' * 2001)),
        fails(MomentFailure.captionTooLong),
      );
      expect(history('a1'), isEmpty);
      expect(Directory(mediaDirs['a1']!).listSync(), isEmpty);
    });

    test(
      'a file larger than it claimed is still refused by the core',
      () async {
        final big = File('${root.path}/big.jpg')..createSync();
        big.openSync(mode: FileMode.write)
          ..truncateSync(MediaLimits.maxPlaintextBytes + 1)
          ..closeSync();
        await expectLater(
          moments['a1']!.create(
            MomentDraft(photos: [MomentInput(path: big.path, sizeBytes: 1)]),
          ),
          fails(MomentFailure.photoTooLarge),
        );
        expect(history('a1'), isEmpty);
      },
    );

    test('a revoked or stale device creates, fetches and downloads '
        'nothing', () async {
      await moments['a1']!.create(draft([_photo(2000)]));
      for (final status in [
        DeviceStatus.revoked,
        DeviceStatus.pending,
        DeviceStatus.unknown,
      ]) {
        registries[accountB.value]!.statuses[hex('b1')] = status;
        await expectLater(
          moments['b1']!.create(draft([_photo(100)])),
          fails(MomentFailure.deviceNotTrusted),
          reason: status.name,
        );
        await expectLater(
          moments['b1']!.refresh(),
          fails(MomentFailure.deviceNotTrusted),
          reason: status.name,
        );
      }
      expect(history('b1'), isEmpty, reason: 'nothing fetched or sealed');

      // Received while active, but not cached: no download once revoked.
      registries[accountB.value]!.statuses[hex('b1')] = DeviceStatus.active;
      await moments['b1']!.refresh();
      final photo = shown('b1').single.photos.single;
      registries[accountB.value]!.statuses[hex('b1')] = DeviceStatus.revoked;
      final before = storage.downloads;
      await expectLater(
        moments['b1']!.openPhoto(photo),
        fails(MomentFailure.deviceNotTrusted),
      );
      expect(storage.downloads, before);
    });

    test('no new moment is encrypted to a revoked partner device; after '
        'its removal moments flow again, and it fetches nothing', () async {
      // b2 joins Ravi's account (approved by b1), then signs b1's
      // revocation (D-081).
      await enroll('b2', accountB, approver: 'b1');
      for (final r in ['a1', 'b1']) {
        cores['b2']!.trustVerifiedPersonKey(
          cores[r]!.publicIdentity().personKey,
        );
      }
      serviceFor('b2', accountB);
      await messaging['b2']!.refreshTrust();
      await messaging['b2']!.publishKeyPackage();
      await moments['a1']!.refresh();
      await messaging['a1']!.reconcileMembership();
      expect((await messaging['b2']!.sync()).joined, isTrue);

      await DeviceTrustService(registries[accountB.value]!).revoke(
        core: cores['b2']!,
        account: accountB,
        deviceIdHex: hex('b1'),
        reason: RevocationReason.lost,
      );
      await moments['a1']!.refresh(); // learns it through lineage
      final before = server.messageDocs.length;
      await expectLater(
        moments['a1']!.create(draft([_photo(100)])),
        fails(MomentFailure.notReady),
      );
      expect(server.messageDocs.length, before);
      expect(
        history('a1').where((m) => m.state == MessageState.queued),
        isEmpty,
      );

      await messaging['a1']!.reconcileMembership(); // removes b1 from MLS
      expect(
        await moments['a1']!.create(draft([_photo(100)], caption: 'after')),
        MomentSaveOutcome.saved,
      );
      await moments['b2']!.refresh();
      expect(shown('b2').single.caption, 'after');
      await expectLater(
        moments['b1']!.refresh(),
        fails(MomentFailure.deviceNotTrusted),
      );
      expect(shown('b1'), isEmpty);
    });

    test('an account outside the couple gets nothing', () async {
      server.members.remove(accountB.value);
      await expectLater(
        moments['b1']!.refresh(),
        fails(MomentFailure.notPaired),
      );
      await expectLater(
        moments['b1']!.create(draft([_photo(100)])),
        fails(MomentFailure.notPaired),
      );
      // Never "saved on this phone" when it can never be delivered.
      expect(
        history('b1').where((m) => m.state == MessageState.queued),
        isEmpty,
      );
      expect(Directory(mediaDirs['b1']!).listSync(), isEmpty);
      expect(moments['b1']!.moments(), isEmpty);
    });

    test('another conversation (another couple) shares nothing', () async {
      await moments['a1']!.create(draft([_photo(100)]));
      final other = MomentsService(
        messaging: MessagingService(
          core: cores['a1']!,
          account: accountA,
          conversation: ConversationId(Uint8List.fromList(List.filled(16, 1))),
          transport: server,
          registry: _Registries(registries),
          media: MediaSupport(
            storage: storage,
            files: const IoMediaFiles(),
            directory: mediaDirs['a1']!,
          ),
        ),
      );
      expect(other.moments(), isEmpty);
      await expectLater(
        other.openPhoto(shown('a1').single.photos.single),
        fails(MomentFailure.notFound),
      );
    });

    test('a core of another account is refused, never read', () async {
      final wrong = MomentsService(
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

    test("a forged moment listing the partner's photos is unreadable on "
        'both phones', () async {
      await moments['a1']!.create(draft([_photo(100)], caption: null));
      await moments['b1']!.refresh();
      final aPhoto = shown('b1').single.photos.single;
      // b1 crafts a manifest (through the normal API) claiming a1's photo.
      final forged = MomentPayload(
        photoMessageIds: [aPhoto.value],
        clientTimeMs: 1,
        caption: 'mine now',
      ).encode();
      await messaging['b1']!.queuePayload(forged);
      await messaging['b1']!.flushOutbox();
      await moments['a1']!.refresh();
      for (final n in ['a1', 'b1']) {
        final entries = moments[n]!.moments();
        expect(entries.whereType<UnreadableMoment>(), hasLength(1));
        expect(
          entries.whereType<Moment>().map((m) => m.caption),
          isNot(contains('mine now')),
        );
      }
    });

    test('corrupted ciphertext never opens; a missing object is '
        'unavailable', () async {
      await moments['a1']!.create(draft([_photo(70000)]));
      await moments['b1']!.refresh();
      final photo = shown('b1').single.photos.single;
      final key = storage.objects.keys.single;
      final original = Uint8List.fromList(storage.objects[key]!.bytes);
      storage.objects[key]!.bytes = Uint8List.fromList(original)..[60] ^= 1;
      await expectLater(
        moments['b1']!.openPhoto(photo),
        fails(MomentFailure.corrupted),
      );
      storage.objects.remove(key);
      await expectLater(
        moments['b1']!.openPhoto(photo),
        fails(MomentFailure.unavailable),
      );
      storage.objects[key] = StoredObject(original, hex('a1'));
      expect(await moments['b1']!.openPhoto(photo), _photo(70000));
    });

    test('only photos of a moment open here', () async {
      await messaging['a1']!.sendMedia(
        inputPath: input(_photo(100)).path,
        mediaClass: MediaClass.image,
      );
      final chatPhoto = MomentPhoto(
        messaging['a1']!.messages().single.messageIdHex,
      );
      expect(moments['a1']!.moments(), isEmpty);
      await expectLater(
        moments['a1']!.openPhoto(chatPhoto),
        fails(MomentFailure.notFound),
      );
      await expectLater(
        moments['a1']!.openPhoto(const MomentPhoto('zz')),
        fails(MomentFailure.notFound),
      );
    });

    test(
      'concurrent saves are serialized: two moments, no duplicates',
      () async {
        final results = await Future.wait([
          moments['a1']!.create(draft([_photo(500, 1)], caption: 'one')),
          moments['a1']!.create(draft([_photo(500, 2)], caption: 'two')),
        ]);
        expect(results, everyElement(MomentSaveOutcome.saved));
        expect(
          shown('a1').map((m) => m.caption),
          unorderedEquals(['one', 'two']),
        );
        expect(storage.uploads, 2);
        expect(server.messageDocs, hasLength(4));
      },
    );

    test('logs carry categories and counts only', () async {
      final sink = _Sink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
      addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
      storage.offline = true;
      await moments['a1']!.create(draft([_photo(100)]));
      storage.offline = false;
      await moments['a1']!.retryPending();
      await moments['b1']!.refresh();
      await moments['b1']!.openPhoto(shown('b1').single.photos.single);
      await expectLater(
        moments['a1']!.create(const MomentDraft(photos: [])),
        fails(MomentFailure.noPhotos),
      );
      final all = sink.lines.join('\n');
      for (final e in [
        'moment_upload_started',
        'moment_upload_completed',
        'moment_upload_failed',
        'moments_refreshed',
      ]) {
        expect(all, contains(e));
      }
      expect(all, isNot(contains('CAPTION-SECRET')));
      expect(all, isNot(contains(_marker)));
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
