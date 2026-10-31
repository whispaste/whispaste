import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/overview/storage_usage.dart';
import 'package:whispaste/services/storage_usage_service.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart' as diag;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('storage-usage-test-');
    diag.appDataDirOverride = root.path;
    diag.sttDirOverride = null;
    diag.retainedAudioDirOverride = null;
  });

  tearDown(() {
    diag.appDataDirOverride = null;
    diag.sttDirOverride = null;
    diag.retainedAudioDirOverride = null;
    root.deleteSync(recursive: true);
  });

  void writeBytes(String path, int count) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(count, 1));
  }

  group('directoryBytes', () {
    test('a missing folder counts as empty', () async {
      expect(await directoryBytes(p.join(root.path, 'nope')), 0);
    });

    test('sums the regular files below the folder', () async {
      writeBytes(p.join(root.path, 'a', 'x.bin'), 100);
      writeBytes(p.join(root.path, 'a', 'b', 'y.bin'), 250);
      expect(await directoryBytes(p.join(root.path, 'a')), 350);
    });

    test('does not follow symbolic links', () async {
      final outside = File(p.join(root.path, 'outside.bin'))
        ..writeAsBytesSync(List.filled(999, 1));
      final folder = Directory(p.join(root.path, 'folder'))..createSync();
      writeBytes(p.join(folder.path, 'own.bin'), 10);
      Link(p.join(folder.path, 'link.bin')).createSync(outside.path);
      expect(await directoryBytes(folder.path), 10);
    });

    test('an unreadable folder gives no number instead of a guess', () async {
      final locked = Directory(p.join(root.path, 'locked'))..createSync();
      writeBytes(p.join(locked.path, 'z.bin'), 5);
      Process.runSync('chmod', ['000', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['700', locked.path]));
      expect(await directoryBytes(locked.path), isNull);
    }, skip: Platform.isWindows ? 'chmod does not apply on Windows' : null);
  });

  test('measures models, recordings and cache separately', () async {
    diag.sttDirOverride = p.join(root.path, 'models');
    writeBytes(p.join(root.path, 'models', 'm.bin'), 1000);
    writeBytes(p.join(root.path, 'recordings', 'r.wav'), 200);
    writeBytes(p.join(root.path, 'gpu-probe', 'probe.wav'), 30);
    writeBytes(p.join(root.path, 'app_icons', 'i.png'), 4);

    final sizes = await measureStorage();
    expect(sizes.models, 1000);
    expect(sizes.recordings, 200);
    expect(sizes.cache, 34);
  });

  test('clearing empties only the cache folders', () async {
    diag.sttDirOverride = p.join(root.path, 'models');
    writeBytes(p.join(root.path, 'models', 'm.bin'), 10);
    writeBytes(p.join(root.path, 'gpu-probe', 'probe.wav'), 10);
    writeBytes(p.join(root.path, 'app_icons', 'i.png'), 10);

    await clearStorageCache();

    expect(Directory(p.join(root.path, 'gpu-probe')).existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'app_icons')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'models', 'm.bin')).existsSync(), isTrue);
    // Clearing again, with nothing there, is not an error.
    await clearStorageCache();
  });

  group('StorageUsageCache', () {
    StorageSizes sizes(int cache) =>
        StorageSizes(models: 1, recordings: 2, cache: cache);

    test(
      'keeps a fresh measurement and measures again after the ttl',
      () async {
        var now = DateTime(2026, 10, 31, 12);
        var walks = 0;
        final cache = StorageUsageCache(
          measure: () async => sizes(++walks),
          now: () => now,
          ttl: const Duration(minutes: 10),
        );

        expect((await cache.read()).cache, 1);
        now = now.add(const Duration(minutes: 9));
        expect((await cache.read()).cache, 1);
        expect(walks, 1);

        now = now.add(const Duration(minutes: 2));
        expect((await cache.read()).cache, 2);
        expect(walks, 2);
      },
    );

    test('concurrent reads share one walk', () async {
      var walks = 0;
      final gate = Completer<StorageSizes>();
      final cache = StorageUsageCache(
        measure: () {
          walks++;
          return gate.future;
        },
      );

      final first = cache.read();
      final second = cache.read();
      gate.complete(sizes(7));

      expect((await first).cache, 7);
      expect((await second).cache, 7);
      expect(walks, 1);
    });

    test('invalidate and force both measure again', () async {
      var walks = 0;
      final cache = StorageUsageCache(measure: () async => sizes(++walks));

      await cache.read();
      cache.invalidate();
      expect((await cache.read()).cache, 2);
      expect((await cache.read(force: true)).cache, 3);
    });

    test('a failed walk is not kept', () async {
      var calls = 0;
      final cache = StorageUsageCache(
        measure: () async {
          calls++;
          if (calls == 1) throw const FileSystemException('boom');
          return sizes(calls);
        },
      );

      await expectLater(cache.read(), throwsA(isA<FileSystemException>()));
      expect((await cache.read()).cache, 2);
    });
  });
}
