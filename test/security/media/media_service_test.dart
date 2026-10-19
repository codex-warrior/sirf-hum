// Media through MessagingService (Prompt 11, D-093–D-096): real native
// cores and enrollment flows, the in-memory Firestore stand-in, and a
// rules-faithful in-memory object store with network faults.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/core/logging/app_logger.dart';
import 'package:sirf_hum/platform/io_media_files.dart';
import 'package:sirf_hum/security/device/device_registration.dart';
import 'package:sirf_hum/security/device/device_status.dart';
import 'package:sirf_hum/security/media/media_storage.dart';
import 'package:sirf_hum/security/messaging/messaging_service.dart';
import 'package:sirf_hum_crypto/sirf_hum_crypto.dart';

import '../device/device_test_support.dart';
import '../device/fake_registry.dart';
import '../messaging/fake_transport.dart';
import 'fake_media_storage.dart';

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
      throw UnimplementedError('not used by messaging');
}

class _Sink implements LogSink {
  final lines = <String>[];

  @override
  void write(LogRecord record) => lines.add(record.message);
}

Matcher media(MediaFailure f) =>
    throwsA(isA<MediaException>().having((e) => e.failure, 'failure', f));

Matcher messaging(MessagingFailure f) =>
    throwsA(isA<MessagingException>().having((e) => e.failure, 'failure', f));

/// Distinctive plaintext so any copy on disk or on the "server" is found.
const _marker = 'SIRF-HUM-PRIVATE-PHOTO/';

Uint8List _photo(int length) => Uint8List.fromList([
  for (var i = 0; i < length; i++) _marker.codeUnitAt(i % _marker.length),
]);

bool _contains(Uint8List hay, Uint8List needle) {
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
  final cid = ConversationId(Uint8List.fromList(List.filled(16, 0x6b)));
  final markerBytes = Uint8List.fromList(_marker.codeUnits);

  group('native', () {
    late Directory root;
    late Map<String, FakeRegistry> registries;
    late FakeTransport server;
    late FakeMediaStorage storage;
    final cores = <String, CryptoCore>{};
    final services = <String, MessagingService>{};
    final mediaDirs = <String, String>{};
    var clock = 1000;

    String hex(String name) =>
        PendingDeviceRegistration.hexOf(cores[name]!.publicIdentity().deviceId);

    DeviceStatus statusOf(String account, String device) =>
        registries[account]?.statuses[device] ?? DeviceStatus.unknown;

    Future<void> enroll(String name, AccountId account) async {
      final dir = Directory('${root.path}/$name')..createSync(recursive: true);
      final core = cores[name] = CryptoCore.initializeWithPlatformKey(
        directory: dir.path,
        storeKey: Uint8List.fromList(List.filled(32, name.codeUnits.first)),
      )..createIdentity(account);
      final state = await DeviceRegistrationFlow(
        registries[account.value]!,
      ).enroll(core: core, account: account, platform: DevicePlatform.android);
      expect(state, isA<EnrollmentActive>());
      mediaDirs[name] = IoMediaFiles.mediaDirectoryOf(dir.path);
    }

    MessagingService serviceFor(String name, AccountId account) =>
        services[name] = MessagingService(
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

    File input(Uint8List bytes) =>
        File('${root.path}/picked_${++clock}.jpg')..writeAsBytesSync(bytes);

    setUp(() async {
      root = Directory.systemTemp.createTempSync('sh_media_svc_');
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
      services.clear();
      await enroll('a1', accountA);
      await enroll('b1', accountB);
      for (final (n, a) in [('a1', accountA), ('b1', accountB)]) {
        for (final r in ['a1', 'b1']) {
          cores[n]!.trustVerifiedPersonKey(
            cores[r]!.publicIdentity().personKey,
          );
        }
        final s = serviceFor(n, a);
        await s.refreshTrust();
        await s.publishKeyPackage();
      }
      expect((await services['a1']!.sync()).epoch, 1);
      expect((await services['b1']!.sync()).joined, isTrue);
    });

    tearDown(() {
      for (final c in cores.values) {
        c.close();
      }
      root.deleteSync(recursive: true);
    });

    ChatMessage only(String name) => services[name]!.messages().single;

    test('send → object then message → receive → open; server sees '
        'ciphertext only', () async {
      final photo = _photo(150000);
      final picked = input(photo);
      expect(
        await services['a1']!.sendMedia(
          inputPath: picked.path,
          mediaClass: MediaClass.image,
        ),
        SendOutcome.sent,
      );
      // The app never copied the plaintext: the picked file is the caller's.
      expect(storage.objects, hasLength(1));
      final stored = storage.objects.values.single;
      expect(stored.senderDeviceIdHex, hex('a1'));
      expect(_contains(stored.bytes, markerBytes), isFalse);
      for (final doc in server.messageDocs.values) {
        expect(_contains(doc.ciphertext, markerBytes), isFalse);
        expect(doc.ciphertext.length, lessThan(1024), reason: 'a reference');
      }

      final r = await services['b1']!.sync();
      expect(r.received, 1);
      final m = only('b1');
      expect(m.text, isNull);
      expect(m.media!.mediaClass, MediaClass.image);
      expect(m.media!.plaintextLength, photo.length);
      expect(await services['b1']!.openMedia(m.messageIdHex), photo);
      expect(storage.downloads, 1);
      // Second open: from the ciphertext cache, no download.
      expect(await services['b1']!.openMedia(m.messageIdHex), photo);
      expect(storage.downloads, 1);
      // The sender opens its own media from its cache.
      expect(await services['a1']!.openMedia(only('a1').messageIdHex), photo);
      // Nothing under either account's directory holds plaintext.
      for (final name in ['a1', 'b1']) {
        for (final f in Directory(
          '${root.path}/$name',
        ).listSync(recursive: true).whereType<File>()) {
          expect(
            _contains(f.readAsBytesSync(), markerBytes),
            isFalse,
            reason: f.path,
          );
        }
      }
    });

    test(
      'offline / interrupted upload: queued, then object before message',
      () async {
        storage.interruptNextUpload = true;
        final photo = _photo(5000);
        expect(
          await services['a1']!.sendMedia(
            inputPath: input(photo).path,
            mediaClass: MediaClass.image,
          ),
          SendOutcome.queued,
        );
        expect(storage.objects, isEmpty);
        expect(
          server.messageDocs,
          isEmpty,
          reason: 'no reference without object',
        );
        expect(only('a1').state, MessageState.queued);

        storage.offline = true;
        expect(await services['a1']!.flushOutbox(), 0);
        expect(server.messageDocs, isEmpty);

        storage.offline = false;
        expect(await services['a1']!.flushOutbox(), 1);
        expect(storage.objects, hasLength(1));
        expect(only('a1').state, MessageState.sent);
        await services['b1']!.sync();
        expect(await services['b1']!.openMedia(only('b1').messageIdHex), photo);
      },
    );

    test('lost upload acknowledgement: the retry is refused, recognised as '
        'ours, uploaded exactly once', () async {
      storage.loseNextUploadAck = true;
      expect(
        await services['a1']!.sendMedia(
          inputPath: input(_photo(3000)).path,
          mediaClass: MediaClass.file,
        ),
        SendOutcome.queued,
      );
      expect(storage.objects, hasLength(1), reason: 'it did land');
      expect(await services['a1']!.flushOutbox(), 1);
      expect(storage.uploads, 1);
      expect(server.messageDocs, hasLength(1));
    });

    test(
      'a foreign object squatting at our path is not mistaken for ours',
      () async {
        storage.interruptNextUpload = true;
        await services['a1']!.sendMedia(
          inputPath: input(_photo(3000)).path,
          mediaClass: MediaClass.file,
        );
        final view = only('a1').media!;
        storage.objects[FakeMediaStorage.key(
          PendingDeviceRegistration.hexOf(DeviceId(cid.bytes)),
          PendingDeviceRegistration.hexOf(DeviceId(view.mediaId.bytes)),
        )] = StoredObject(
          Uint8List(view.objectLength),
          hex('b1'),
        );
        await expectLater(
          services['a1']!.flushOutbox(),
          messaging(MessagingFailure.rejected),
        );
        expect(server.messageDocs, isEmpty);
      },
    );

    test('malicious server: substituted, modified or truncated objects never '
        'open; the cache is purged and re-fetched once', () async {
      final first = _photo(70000);
      await services['a1']!.sendMedia(
        inputPath: input(first).path,
        mediaClass: MediaClass.video,
      );
      await services['a1']!.sendMedia(
        inputPath: input(_photo(70000)).path,
        mediaClass: MediaClass.video,
      );
      await services['b1']!.sync();
      final msgs = services['b1']!.messages();
      final keys = storage.objects.keys.toList();
      final original = Uint8List.fromList(storage.objects[keys[0]]!.bytes);
      String idFor(String key) => msgs
          .firstWhere(
            (m) => key.endsWith(
              PendingDeviceRegistration.hexOf(DeviceId(m.media!.mediaId.bytes)),
            ),
          )
          .messageIdHex;
      final target = idFor(keys[0]);

      // Substitution: object 2's bytes served for object 1 (same size).
      storage.objects[keys[0]]!.bytes = storage.objects[keys[1]]!.bytes;
      await expectLater(
        services['b1']!.openMedia(target),
        media(MediaFailure.corrupted),
      );
      // Modified byte.
      storage.objects[keys[0]]!.bytes = Uint8List.fromList(original)..[40] ^= 1;
      await expectLater(
        services['b1']!.openMedia(target),
        media(MediaFailure.corrupted),
      );
      // Truncated: refused on size before anything is written.
      storage.objects[keys[0]]!.bytes = original.sublist(
        0,
        original.length - 1,
      );
      await expectLater(
        services['b1']!.openMedia(target),
        media(MediaFailure.corrupted),
      );
      expect(Directory(mediaDirs['b1']!).listSync(), isEmpty);

      // The honest object opens; then the local cache is corrupted and
      // recovered by one fresh download.
      storage.objects[keys[0]]!.bytes = original;
      expect(await services['b1']!.openMedia(target), first);
      final cached = Directory(mediaDirs['b1']!).listSync().single as File;
      final bytes = cached.readAsBytesSync()..[100] ^= 1;
      cached.writeAsBytesSync(bytes);
      final before = storage.downloads;
      expect(await services['b1']!.openMedia(target), first);
      expect(storage.downloads, before + 1);
    });

    test('interrupted download leaves nothing; missing object is '
        'unavailable, never faked', () async {
      final photo = _photo(9000);
      await services['a1']!.sendMedia(
        inputPath: input(photo).path,
        mediaClass: MediaClass.image,
      );
      await services['b1']!.sync();
      final id = only('b1').messageIdHex;
      storage.interruptNextDownload = true;
      await expectLater(
        services['b1']!.openMedia(id),
        media(MediaFailure.unavailable),
      );
      expect(Directory(mediaDirs['b1']!).listSync(), isEmpty);
      storage.offline = true;
      await expectLater(
        services['b1']!.openMedia(id),
        media(MediaFailure.unavailable),
      );
      storage.offline = false;
      final saved = Map.of(storage.objects);
      storage.objects.clear(); // deleted / expired on the server
      await expectLater(
        services['b1']!.openMedia(id),
        media(MediaFailure.unavailable),
      );
      storage.objects.addAll(saved);
      expect(await services['b1']!.openMedia(id), photo);
    });

    test('text, unknown and other-account messages are not media', () async {
      await services['a1']!.sendText('hello');
      await services['b1']!.sync();
      await expectLater(
        services['b1']!.openMedia(only('b1').messageIdHex),
        media(MediaFailure.notMedia),
      );
      await services['a1']!.sendMedia(
        inputPath: input(_photo(100)).path,
        mediaClass: MediaClass.audio,
      );
      // Not synced yet on b1: a stale or unknown reference.
      final unknown = services['a1']!.messages().last.messageIdHex;
      await expectLater(
        services['b1']!.openMedia(unknown),
        media(MediaFailure.notMedia),
      );
    });

    test('input limits and lost outbox objects', () async {
      await expectLater(
        services['a1']!.sendMedia(
          inputPath: '${root.path}/missing.jpg',
          mediaClass: MediaClass.image,
        ),
        media(MediaFailure.invalidInput),
      );
      final big = File('${root.path}/big.bin')..createSync();
      big.openSync(mode: FileMode.write)
        ..truncateSync(MediaLimits.maxPlaintextBytes + 1)
        ..closeSync();
      await expectLater(
        services['a1']!.sendMedia(
          inputPath: big.path,
          mediaClass: MediaClass.video,
        ),
        media(MediaFailure.tooLarge),
      );
      expect(services['a1']!.messages(), isEmpty);

      // Queued, then its local object disappears before it was uploaded.
      storage.offline = true;
      await services['a1']!.sendMedia(
        inputPath: input(_photo(100)).path,
        mediaClass: MediaClass.image,
      );
      for (final f in Directory(mediaDirs['a1']!).listSync()) {
        f.deleteSync();
      }
      storage.offline = false;
      expect(await services['a1']!.flushOutbox(), 0);
      expect(services['a1']!.messages(), isEmpty, reason: 'abandoned');
      expect(server.messageDocs, isEmpty);
    });

    test('delete for me removes the record and the cached object', () async {
      await services['a1']!.sendMedia(
        inputPath: input(_photo(100)).path,
        mediaClass: MediaClass.image,
      );
      final id = only('a1').messageIdHex;
      expect(Directory(mediaDirs['a1']!).listSync(), hasLength(1));
      services['a1']!.deleteForMe(id);
      expect(services['a1']!.messages(), isEmpty);
      expect(Directory(mediaDirs['a1']!).listSync(), isEmpty);
      expect(storage.objects, hasLength(1), reason: 'never server deletion');
    });

    test('revoked device: no sending, no new downloads; its cache stays '
        '(documented)', () async {
      final photo = _photo(800);
      await services['a1']!.sendMedia(
        inputPath: input(photo).path,
        mediaClass: MediaClass.image,
      );
      await services['a1']!.sendMedia(
        inputPath: input(photo).path,
        mediaClass: MediaClass.image,
      );
      await services['b1']!.sync();
      final [opened, notYet] = services['b1']!.messages();
      expect(await services['b1']!.openMedia(opened.messageIdHex), photo);
      registries[accountB.value]!.statuses[hex('b1')] = DeviceStatus.revoked;
      await expectLater(
        services['b1']!.sendMedia(
          inputPath: input(photo).path,
          mediaClass: MediaClass.image,
        ),
        messaging(MessagingFailure.deviceNotTrusted),
      );
      await expectLater(
        services['b1']!.openMedia(notYet.messageIdHex),
        messaging(MessagingFailure.deviceNotTrusted),
      );
      // Revocation cannot reach into what the device already holds.
      expect(await services['b1']!.openMedia(opened.messageIdHex), photo);
      // A revoked sender's uploads are refused by the server too.
      expect(
        await storage.upload(
          conversationIdHex: 'c',
          mediaIdHex: 'm',
          senderDeviceIdHex: hex('b1'),
          filePath: input(photo).path,
        ),
        MediaUploadOutcome.refused,
      );
    });

    test('without media support every media call fails closed', () async {
      final plain = MessagingService(
        core: cores['a1']!,
        account: accountA,
        conversation: cid,
        transport: server,
        registry: _Registries(registries),
      );
      await expectLater(
        plain.sendMedia(
          inputPath: input(_photo(10)).path,
          mediaClass: MediaClass.image,
        ),
        media(MediaFailure.unsupported),
      );
      await expectLater(
        plain.openMedia('00' * 16),
        media(MediaFailure.unsupported),
      );
    });

    test('logs carry categories only', () async {
      final sink = _Sink();
      AppLogger.configure(sinks: [sink], minimumLevel: LogLevel.debug);
      addTearDown(() => AppLogger.configure(sinks: const [DeveloperLogSink()]));
      await services['a1']!.sendMedia(
        inputPath: input(_photo(100)).path,
        mediaClass: MediaClass.image,
      );
      await services['b1']!.sync();
      await services['b1']!.openMedia(only('b1').messageIdHex);
      final all = sink.lines.join('\n');
      expect(all, contains('media_sent'));
      expect(all, contains('media_opened'));
      expect(all, isNot(contains(_marker)));
      for (final n in ['a1', 'b1']) {
        expect(all, isNot(contains(hex(n))));
      }
      for (final k in storage.objects.keys) {
        expect(all, isNot(contains(k.split('/').last)));
      }
      expect(all, isNot(contains(root.path)));
    });
  }, skip: nativeSkip);
}
