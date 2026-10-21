import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirf_hum/features/moments/data/picker_cache_sweeper.dart';

// P2-3 / E81 (Prompt 18, D-141): leftover image_picker_android copies are
// removed at start-up; nothing else in the cache is touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('sh_cache_'));
  tearDown(() {
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  Directory dir(String name, {List<String> files = const ['IMG_1.jpg']}) {
    final d = Directory('${cache.path}/$name')..createSync();
    for (final f in files) {
      File('${d.path}/$f').writeAsBytesSync([0xff, 0xd8, 0xff]);
    }
    return d;
  }

  const uuid = '3f2c8a1e-9b4d-4c7a-8e21-5d6f7a8b9c0d';
  const uuid2 = 'a1b2c3d4-e5f6-4a7b-9c8d-0e1f2a3b4c5d';

  test('removes picker-shaped directories and their plaintext copies', () {
    final a = dir(uuid);
    final b = dir(uuid2, files: ['image_picker.png', 'second.heic']);
    final empty = dir('0f2c8a1e-9b4d-4c7a-bfff-5d6f7a8b9c0d', files: []);

    expect(PickerCacheSweeper.sweepDirectory(cache), 3);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
    expect(empty.existsSync(), isFalse);
  });

  test('leaves everything that is not exactly the picker layout', () {
    final keep = [
      dir('flutter_engine'),
      dir(uuid.toUpperCase()), // Java's UUID.toString() is lowercase
      dir('3f2c8a1e-9b4d-1c7a-8e21-5d6f7a8b9c0d'), // not version 4
      dir('3f2c8a1e-9b4d-4c7a-7e21-5d6f7a8b9c0d'), // wrong variant
      dir('${uuid}x'),
      dir('3f2c8a1e9b4d4c7a8e215d6f7a8b9c0d'),
    ];
    // A UUID directory holding a directory is not the picker's.
    final nested = dir(uuid);
    Directory('${nested.path}/inner').createSync();
    // Loose files at the top of the cache are never touched.
    final loose = File('${cache.path}/image_picker123.jpg')
      ..writeAsBytesSync([1]);

    expect(PickerCacheSweeper.sweepDirectory(cache), 0);
    for (final d in [...keep, nested]) {
      expect(d.existsSync(), isTrue, reason: d.path);
    }
    expect(File('${nested.path}/IMG_1.jpg').existsSync(), isTrue);
    expect(loose.existsSync(), isTrue);
  });

  test('never follows a link out of the cache', () {
    final outside = Directory.systemTemp.createTempSync('sh_outside_');
    addTearDown(() => outside.deleteSync(recursive: true));
    final precious = File('${outside.path}/precious.jpg')
      ..writeAsBytesSync([1]);
    try {
      Link('${cache.path}/$uuid').createSync(outside.path);
    } on FileSystemException {
      markTestSkipped('symbolic links need extra privileges on this host');
      return;
    }
    expect(PickerCacheSweeper.sweepDirectory(cache), 0);
    expect(precious.existsSync(), isTrue);
  });

  test('a missing cache directory is not an error', () {
    cache.deleteSync(recursive: true);
    expect(PickerCacheSweeper.sweepDirectory(cache), 0);
  });

  group('sweepAtStartup', () {
    const channel = MethodChannel(PickerCacheSweeper.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sweeps the directory the platform reports', () async {
      dir(uuid);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'cacheDirectory');
        return cache.path;
      });
      expect(
        await const PickerCacheSweeper(supported: true).sweepAtStartup(),
        1,
      );
    });

    test('a platform failure never stops start-up', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'boom'),
      );
      expect(
        await const PickerCacheSweeper(supported: true).sweepAtStartup(),
        0,
      );
    });

    test('unsupported platforms (web, non-Android) never ask', () async {
      var asked = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        asked = true;
        return cache.path;
      });
      dir(uuid);
      expect(
        await const PickerCacheSweeper(supported: false).sweepAtStartup(),
        0,
      );
      expect(asked, isFalse);
      expect(Directory('${cache.path}/$uuid').existsSync(), isTrue);
    });
  });
}
