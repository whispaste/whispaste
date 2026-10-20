import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/services/audio/capture/capture_dir.dart';

/// Fake process runner that records calls and answers `id -u`, `stat` and
/// `chmod` without touching the real file system.
class _FakeProcess {
  _FakeProcess({this.uid = '1000', this.ownerUid, this.chmodExit = 0});

  final String uid;
  final String? ownerUid;
  final int chmodExit;
  final calls = <String>[];

  Future<ProcessResult> call(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    return switch (exe) {
      'id' => ProcessResult(1, 0, '$uid\n', ''),
      'stat' => ProcessResult(1, 0, '${ownerUid ?? uid}\n', ''),
      'chmod' => ProcessResult(1, chmodExit, '', ''),
      _ => ProcessResult(1, 1, '', 'unexpected $exe'),
    };
  }
}

CaptureSystem _linux(Map<String, String> env, {String home = '/home/u'}) =>
    CaptureSystem(
      platform: CapturePlatform.linux,
      environment: {'HOME': home, ...env},
      appDataDir: '/home/u/.config/whispaste',
    );

final _posixSkip = Platform.isWindows ? 'POSIX permissions only' : null;

void main() {
  group('captureDirCandidates', () {
    test('linux prefers XDG_RUNTIME_DIR, falls back to the cache dir', () {
      final candidates = captureDirCandidates(
        _linux({'XDG_RUNTIME_DIR': '/run/user/1000'}),
      );
      expect(candidates, [
        p.posix.join('/run/user/1000', 'whispaste'),
        p.posix.join('/home/u/.cache', 'whispaste'),
      ]);
    });

    test('linux without a runtime dir uses XDG_CACHE_HOME when set', () {
      final candidates = captureDirCandidates(
        _linux({'XDG_CACHE_HOME': '/data/cache'}),
      );
      expect(candidates, [p.posix.join('/data/cache', 'whispaste')]);
    });

    test('an empty or relative XDG_RUNTIME_DIR counts as missing', () {
      for (final bad in ['', 'run/user/1000']) {
        final candidates = captureDirCandidates(
          _linux({'XDG_RUNTIME_DIR': bad}),
        );
        expect(candidates, [
          p.posix.join('/home/u/.cache', 'whispaste'),
        ], reason: 'XDG_RUNTIME_DIR="$bad"');
      }
    });

    test('macOS uses the app support folder, never the temp folder', () {
      final candidates = captureDirCandidates(
        const CaptureSystem(
          platform: CapturePlatform.macos,
          environment: {'TMPDIR': '/var/folders/x/T/'},
          appDataDir: '/Users/u/Library/Application Support/WhisPaste',
        ),
      );
      expect(candidates, [
        p.posix.join(
          '/Users/u/Library/Application Support/WhisPaste',
          'capture',
        ),
      ]);
    });

    test('macOS without an app support folder yields no candidate, never a '
        'relative path (fail closed)', () {
      final candidates = captureDirCandidates(
        const CaptureSystem(
          platform: CapturePlatform.macos,
          environment: {},
          appDataDir: '',
        ),
      );
      expect(candidates, isEmpty);
    });

    test('windows uses LOCALAPPDATA only (roaming APPDATA would sync)', () {
      final local = p.posix.join('C:', 'Users', 'u', 'AppData', 'Local');
      final candidates = captureDirCandidates(
        CaptureSystem(
          platform: CapturePlatform.windows,
          environment: {'LOCALAPPDATA': local, 'APPDATA': 'C:/roaming'},
          appDataDir: 'C:/roaming/WhisPaste',
        ),
      );
      expect(candidates, [p.windows.join(local, 'WhisPaste', 'capture')]);
    });

    test('windows without LOCALAPPDATA yields no candidate (fail closed)', () {
      final candidates = captureDirCandidates(
        const CaptureSystem(
          platform: CapturePlatform.windows,
          environment: {'APPDATA': 'C:/roaming'},
          appDataDir: 'C:/roaming/WhisPaste',
        ),
      );
      expect(candidates, isEmpty);
    });

    test('windows ignores a relative LOCALAPPDATA (PAR-023, fail closed)', () {
      final candidates = captureDirCandidates(
        const CaptureSystem(
          platform: CapturePlatform.windows,
          environment: {'LOCALAPPDATA': r'relative\Local'},
          appDataDir: 'C:/roaming/WhisPaste',
        ),
      );
      expect(candidates, isEmpty);
    });
  });

  group('captureWavFileName', () {
    test('keeps the whispaste_*.wav sweep pattern and adds randomness', () {
      final a = captureWavFileName(1700000000000, Random(1));
      final b = captureWavFileName(1700000000000, Random(2));

      expect(a, startsWith('whispaste_1700000000000_'));
      expect(a, endsWith('.wav'));
      expect(a, isNot(equals(b)), reason: 'name must not be predictable');
      // Same seed, same name: the randomness comes from the injected source.
      expect(
        captureWavFileName(1, Random(7)),
        captureWavFileName(1, Random(7)),
      );
    });
  });

  group('ensurePrivateDir', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('wp_capture_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('creates a missing folder with mode 0700', () async {
      final dir = p.join(root.path, 'whispaste');
      final ok = await ensurePrivateDir(dir, _linux({}));

      expect(ok, isTrue);
      expect(FileStat.statSync(dir).mode & 0x1FF, 0x1C0);
    }, skip: _posixSkip);

    test(
      'tightens an existing folder with looser permissions to 0700',
      () async {
        final dir = Directory(p.join(root.path, 'whispaste'))..createSync();
        await Process.run('chmod', ['755', dir.path]);

        final ok = await ensurePrivateDir(dir.path, _linux({}));

        expect(ok, isTrue);
        expect(FileStat.statSync(dir.path).mode & 0x1FF, 0x1C0);
      },
      skip: _posixSkip,
    );

    test('refuses a symlink and leaves its target untouched', () async {
      final target = Directory(p.join(root.path, 'target'))..createSync();
      await Process.run('chmod', ['755', target.path]);
      final link = p.join(root.path, 'whispaste');
      Link(link).createSync(target.path);

      final ok = await ensurePrivateDir(link, _linux({}));

      expect(ok, isFalse);
      expect(FileStat.statSync(target.path).mode & 0x1FF, 0x1ED);
    }, skip: _posixSkip);

    test('refuses a regular file sitting at the folder path', () async {
      final path = p.join(root.path, 'whispaste');
      File(path).writeAsStringSync('x');

      expect(await ensurePrivateDir(path, _linux({})), isFalse);
    }, skip: _posixSkip);

    test(
      'refuses a folder owned by another user and does not chmod it',
      () async {
        final dir = p.join(root.path, 'whispaste');
        Directory(dir).createSync();
        final fake = _FakeProcess(uid: '1000', ownerUid: '4242');

        final ok = await ensurePrivateDir(
          dir,
          CaptureSystem(
            platform: CapturePlatform.linux,
            environment: const {'HOME': '/home/u'},
            appDataDir: '/x',
            runProcess: fake.call,
          ),
        );

        expect(ok, isFalse);
        expect(fake.calls.where((c) => c.startsWith('chmod')), isEmpty);
      },
      skip: _posixSkip,
    );

    test('refuses when chmod fails', () async {
      final fake = _FakeProcess(chmodExit: 1);
      final ok = await ensurePrivateDir(
        p.join(root.path, 'whispaste'),
        CaptureSystem(
          platform: CapturePlatform.linux,
          environment: const {'HOME': '/home/u'},
          appDataDir: '/x',
          runProcess: fake.call,
        ),
      );
      expect(ok, isFalse);
    }, skip: _posixSkip);
  });

  group('resolveCaptureDir', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('wp_resolve_'));
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'falls back to the cache folder when XDG_RUNTIME_DIR is unusable',
      () async {
        // A regular file where the runtime folder should be: unusable.
        final runtime = p.join(root.path, 'run-is-a-file');
        File(runtime).writeAsStringSync('x');
        final cache = p.join(root.path, 'cache');

        final dir = await resolveCaptureDir(
          _linux({'XDG_RUNTIME_DIR': runtime, 'XDG_CACHE_HOME': cache}),
        );

        expect(dir, p.join(cache, 'whispaste'));
        expect(Directory(dir).existsSync(), isTrue);
      },
      skip: _posixSkip,
    );

    test('throws when no candidate can be made private', () async {
      await expectLater(
        resolveCaptureDir(
          const CaptureSystem(
            platform: CapturePlatform.windows,
            environment: {},
            appDataDir: 'C:/x',
          ),
        ),
        throwsA(isA<CaptureDirUnavailableException>()),
      );
    });

    test(
      'a tool that never returns fails the candidate instead of hanging',
      () async {
        // A hung fork()+exec() must not block the recording start: the call
        // times out and the recording fails closed, never /tmp.
        final system = CaptureSystem(
          platform: CapturePlatform.linux,
          environment: {'XDG_RUNTIME_DIR': root.path, 'HOME': root.path},
          appDataDir: '',
          processTimeout: const Duration(milliseconds: 50),
          runProcess: (exe, args) => Completer<ProcessResult>().future,
        );

        await expectLater(
          resolveCaptureDir(system),
          throwsA(isA<CaptureDirUnavailableException>()),
        );
      },
      skip: _posixSkip,
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });

  group('sweepLegacyTempWavs', () {
    late Directory tempDir;
    final launchedAt = DateTime(2026, 10, 19, 9);

    setUp(() => tempDir = Directory.systemTemp.createTempSync('wp_legacy_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    File file(String name, DateTime modified) =>
        File(p.join(tempDir.path, name))
          ..writeAsBytesSync([0])
          ..setLastModifiedSync(modified);

    test('removes own old whispaste_*.wav and nothing else', () async {
      final old = launchedAt.subtract(const Duration(days: 2));
      final stale = file('whispaste_1700000000000.wav', old);
      final fresh = file('whispaste_1700000000001.wav', launchedAt);
      final other = file('other.wav', old);
      final model = file('whispaste_model.bin', old);

      final fake = _FakeProcess(uid: '1000');
      final deleted = await sweepLegacyTempWavs(
        tempDir: tempDir,
        modifiedBefore: launchedAt,
        system: CaptureSystem(
          platform: CapturePlatform.linux,
          environment: const {},
          appDataDir: '/x',
          runProcess: fake.call,
        ),
      );

      expect(deleted, 1);
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
      expect(model.existsSync(), isTrue);
    }, skip: _posixSkip);

    test('does not follow a symlink named like a WAV', () async {
      final target = file(
        'victim.dat',
        launchedAt.subtract(const Duration(days: 1)),
      );
      Link(p.join(tempDir.path, 'whispaste_9.wav')).createSync(target.path);

      await sweepLegacyTempWavs(
        tempDir: tempDir,
        modifiedBefore: launchedAt,
        system: const CaptureSystem(
          platform: CapturePlatform.linux,
          environment: {},
          appDataDir: '/x',
        ),
      );

      expect(target.existsSync(), isTrue);
    }, skip: _posixSkip);

    test('skips WAVs owned by another user', () async {
      final wav = file(
        'whispaste_5.wav',
        launchedAt.subtract(const Duration(days: 1)),
      );
      final fake = _FakeProcess(uid: '1000', ownerUid: '4242');

      final deleted = await sweepLegacyTempWavs(
        tempDir: tempDir,
        modifiedBefore: launchedAt,
        system: CaptureSystem(
          platform: CapturePlatform.linux,
          environment: const {},
          appDataDir: '/x',
          runProcess: fake.call,
        ),
      );

      expect(deleted, 0);
      expect(wav.existsSync(), isTrue);
    }, skip: _posixSkip);

    test('runs only once: the second call is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final old = launchedAt.subtract(const Duration(days: 1));

      file('whispaste_1.wav', old);
      await sweepLegacyTempWavsOnce(
        tempDir: tempDir,
        modifiedBefore: launchedAt,
        system: const CaptureSystem(
          platform: CapturePlatform.windows,
          environment: {},
          appDataDir: 'C:/x',
        ),
        prefs: prefs,
      );
      expect(
        File(p.join(tempDir.path, 'whispaste_1.wav')).existsSync(),
        isFalse,
      );

      final again = file('whispaste_2.wav', old);
      await sweepLegacyTempWavsOnce(
        tempDir: tempDir,
        modifiedBefore: launchedAt,
        system: const CaptureSystem(
          platform: CapturePlatform.windows,
          environment: {},
          appDataDir: 'C:/x',
        ),
        prefs: prefs,
      );
      expect(again.existsSync(), isTrue);
    });
  });
}
