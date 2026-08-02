import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/single_instance_service.dart';

/// Resolves a `dart` executable usable to spawn `test/fixtures/single_instance_probe.dart`.
///
/// Under `flutter test`, [Platform.resolvedExecutable] points at the
/// `flutter_tester` binary, not `dart` — so fall back to the SDK bundled
/// alongside the Flutter checkout via `FLUTTER_ROOT`. Returns `null` (rather
/// than throwing) if neither resolves, so the one test that needs a real
/// second OS process can skip cleanly instead of failing the whole suite
/// over test-runner plumbing unrelated to the code under test.
String? _resolveDartExecutable() {
  final resolved = Platform.resolvedExecutable;
  if (p.basenameWithoutExtension(resolved).toLowerCase() == 'dart') {
    return resolved;
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final candidate = p.join(
      flutterRoot,
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      Platform.isWindows ? 'dart.exe' : 'dart',
    );
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

final _probePath = p.join(
  Directory.current.path,
  'test',
  'fixtures',
  'single_instance_probe.dart',
);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('whispaste_single_instance_');
    SingleInstanceService.lockDirOverride = tmp.path;
  });

  tearDown(() async {
    await SingleInstanceService.release();
    SingleInstanceService.onSecondInstanceLaunched = null;
    SingleInstanceService.lockDirOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('acquires the lock and creates instance.lock', () async {
    final primary = await SingleInstanceService.ensureSingleInstance();
    expect(primary, isTrue);
    expect(File(p.join(tmp.path, 'instance.lock')).existsSync(), isTrue);
  });

  test('re-entrant call in the same process returns true, not false', () async {
    // On POSIX, closing ANY file descriptor for a file drops every
    // advisory lock this process holds on it — so a second open/close
    // here would silently release the lock this process still needs.
    // Returning true without touching the file system a second time is
    // the only safe answer once _lock != null.
    final first = await SingleInstanceService.ensureSingleInstance();
    final second = await SingleInstanceService.ensureSingleInstance();
    expect(first, isTrue);
    expect(second, isTrue);
  });

  test(
    'release() then ensureSingleInstance() again reacquires the lock',
    () async {
      final first = await SingleInstanceService.ensureSingleInstance();
      expect(first, isTrue, reason: 'first caller should claim the lock');

      await SingleInstanceService.release();

      final second = await SingleInstanceService.ensureSingleInstance();
      expect(
        second,
        isTrue,
        reason:
            'after release(), the lock must be truly free — this is the '
            'exact guarantee a self-relaunch depends on: the freshly-spawned '
            'replacement process must be able to claim the lock immediately, '
            'or it treats itself as a duplicate launch and exits, leaving '
            'nothing running (observed live: native restart alert fired, app '
            'just closed instead of relaunching).',
      );
    },
  );

  test('release() is a no-op when the lock was never acquired', () async {
    await SingleInstanceService.release();
  });

  test('fails open when the lock directory cannot be created', () async {
    // Point the override at a path that is itself a regular file, so
    // Directory(...).create() fails on every platform — must not be
    // mistaken for "another instance is running".
    final blocker = File(p.join(tmp.path, 'blocker'))..createSync();
    SingleInstanceService.lockDirOverride = p.join(
      blocker.path,
      'single_instance',
    );

    final result = await SingleInstanceService.ensureSingleInstance();
    expect(result, isTrue);
  });

  test('fails open when the lock file itself cannot be opened', () async {
    // The lock directory creates fine, but the lock file path is itself a
    // directory — File.open() fails while Directory.create() already
    // succeeded, exercising the separate try/catch around open().
    final dir = p.join(tmp.path, 'single_instance');
    Directory(p.join(dir, 'instance.lock')).createSync(recursive: true);
    SingleInstanceService.lockDirOverride = dir;

    final result = await SingleInstanceService.ensureSingleInstance();
    expect(result, isTrue);
  });

  test(
    'a focus signal file fires the callback exactly once (debounced)',
    () async {
      final primary = await SingleInstanceService.ensureSingleInstance();
      expect(primary, isTrue);

      var callCount = 0;
      final completer = Completer<void>();
      SingleInstanceService.onSecondInstanceLaunched = () {
        callCount++;
        if (!completer.isCompleted) completer.complete();
      };

      final signal = File(p.join(tmp.path, 'focus.signal'));
      await signal.writeAsString('first', flush: true);
      await completer.future.timeout(const Duration(seconds: 5));

      // A second write inside the debounce window must not double-fire.
      await signal.writeAsString('second', flush: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(callCount, 1);
    },
  );

  group('cross-process', () {
    test(
      'a second real OS process is refused the lock and signals this one',
      () async {
        final dart = _resolveDartExecutable();
        if (dart == null) {
          markTestSkipped(
            'no dart executable resolvable from this test runner',
          );
          return;
        }

        final primary = await SingleInstanceService.ensureSingleInstance();
        expect(primary, isTrue);

        final completer = Completer<void>();
        SingleInstanceService.onSecondInstanceLaunched = completer.complete;

        final result = await Process.run(dart, ['run', _probePath, tmp.path]);
        expect(
          result.stdout.toString(),
          contains('SECONDARY'),
          reason: 'stderr: ${result.stderr}',
        );

        await completer.future.timeout(const Duration(seconds: 10));
      },
      tags: ['process'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a real OS process becomes primary when no lock is held',
      () async {
        final dart = _resolveDartExecutable();
        if (dart == null) {
          markTestSkipped(
            'no dart executable resolvable from this test runner',
          );
          return;
        }

        final result = await Process.run(dart, ['run', _probePath, tmp.path]);
        expect(
          result.stdout.toString(),
          contains('PRIMARY'),
          reason: 'stderr: ${result.stderr}',
        );
      },
      tags: ['process'],
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
