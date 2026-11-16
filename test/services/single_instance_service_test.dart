import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/instance_write_gate.dart';
import 'package:whispaste/services/single_instance_service.dart';

import '../test_helpers/dart_sdk.dart';

/// On Windows `dart run` starts the probe as a child of the dartdev process
/// it returns, so killing the handle can leave the probe holding the lock
/// file until its own hold time runs out (errno 32 on deletion, CI run on
/// c777f2fe). Retry until the probe is gone instead of failing teardown.
Future<void> _deleteWhenUnlocked(Directory dir) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
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
    SingleInstanceService.clock = DateTime.now;
    SingleInstanceService.onSecondInstanceLaunched = null;
    SingleInstanceService.onRemoteCommand = null;
    SingleInstanceService.lockDirOverride = null;
    SingleInstanceService.fallbackLockDirOverride = null;
    SingleInstanceService.debugResetClaim();
    await _deleteWhenUnlocked(tmp);
  });

  /// A lock folder that can never be created: its parent is a plain file.
  String unavailableDir(String name) {
    final blocker = File(p.join(tmp.path, '$name-blocker'))..createSync();
    return p.join(blocker.path, 'single_instance');
  }

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

  test('an uncreatable lock directory starts unverified, not as a second '
      'instance, and keeps the history closed', () async {
    // Point the override at a path that is itself a regular file, so
    // Directory(...).create() fails on every platform — must not be
    // mistaken for "another instance is running".
    SingleInstanceService.lockDirOverride = unavailableDir('primary');

    final result = await SingleInstanceService.ensureSingleInstance();
    expect(result, isTrue);
    expect(SingleInstanceService.claim, InstanceClaim.unverified);
    expect(InstanceWriteGate.closed, isTrue);
    expect(
      InstanceWriteGate.ensureOpen,
      throwsA(isA<InstanceCheckUnavailableException>()),
    );
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
    expect(SingleInstanceService.claim, InstanceClaim.unverified);
  });

  group('second lock in the temporary folder (#1647)', () {
    test('InstanceClaim.from: held anywhere wins, then acquired', () {
      const a = LockSiteResult.acquired;
      const h = LockSiteResult.held;
      const u = LockSiteResult.unavailable;
      expect(InstanceClaim.from([a, a]), InstanceClaim.primary);
      expect(InstanceClaim.from([u, a]), InstanceClaim.primary);
      expect(InstanceClaim.from([a, u]), InstanceClaim.primary);
      expect(InstanceClaim.from([a, h]), InstanceClaim.secondary);
      expect(InstanceClaim.from([u, h]), InstanceClaim.secondary);
      expect(InstanceClaim.from([h, u]), InstanceClaim.secondary);
      expect(InstanceClaim.from([u, u]), InstanceClaim.unverified);
    });

    test('tests without a second override use no second lock', () {
      expect(SingleInstanceService.fallbackLockDir(), isNull);
    });

    test('a primary holds both locks', () async {
      final fallback = p.join(tmp.path, 'fallback');
      SingleInstanceService.fallbackLockDirOverride = fallback;

      expect(await SingleInstanceService.ensureSingleInstance(), isTrue);
      expect(SingleInstanceService.claim, InstanceClaim.primary);
      expect(File(p.join(tmp.path, 'instance.lock')).existsSync(), isTrue);
      expect(File(p.join(fallback, 'instance.lock')).existsSync(), isTrue);
      expect(InstanceWriteGate.closed, isFalse);
    });

    test('an unwritable app-data folder still starts normally through the '
        'second lock', () async {
      SingleInstanceService.lockDirOverride = unavailableDir('primary');
      final fallback = p.join(tmp.path, 'fallback');
      SingleInstanceService.fallbackLockDirOverride = fallback;

      expect(await SingleInstanceService.ensureSingleInstance(), isTrue);
      expect(SingleInstanceService.claim, InstanceClaim.primary);
      expect(InstanceWriteGate.closed, isFalse);
      expect(File(p.join(fallback, 'instance.lock')).existsSync(), isTrue);
    });

    test('both locks unavailable: unverified with the gate closed', () async {
      SingleInstanceService.lockDirOverride = unavailableDir('primary');
      SingleInstanceService.fallbackLockDirOverride = unavailableDir('second');

      expect(await SingleInstanceService.ensureSingleInstance(), isTrue);
      expect(SingleInstanceService.claim, InstanceClaim.unverified);
      expect(InstanceWriteGate.closed, isTrue);
    });

    test('a toggle in an unverified start is queued once, also after the '
        'confirmation', () async {
      SingleInstanceService.lockDirOverride = unavailableDir('primary');
      final commands = <InstanceCommand>[];

      await SingleInstanceService.ensureSingleInstance(
        command: InstanceCommand.toggle,
      );
      SingleInstanceService.lockDirOverride = p.join(tmp.path, 'healed');
      expect(await SingleInstanceService.confirmUnverifiedStart(), isTrue);
      SingleInstanceService.onRemoteCommand = commands.add;

      expect(commands, [InstanceCommand.toggle]);
    });

    test('confirming an unverified start opens the gate, and takes the lock '
        'when it has become available', () async {
      SingleInstanceService.lockDirOverride = unavailableDir('primary');
      await SingleInstanceService.ensureSingleInstance();
      expect(InstanceWriteGate.closed, isTrue);

      // Still unavailable: the user's answer alone opens the gate.
      expect(await SingleInstanceService.confirmUnverifiedStart(), isTrue);
      expect(InstanceWriteGate.closed, isFalse);
      expect(SingleInstanceService.claim, InstanceClaim.unverified);

      // The folder works again: the next confirmation takes the lock.
      final healed = p.join(tmp.path, 'healed');
      SingleInstanceService.lockDirOverride = healed;
      expect(await SingleInstanceService.confirmUnverifiedStart(), isTrue);
      expect(SingleInstanceService.claim, InstanceClaim.primary);
      expect(File(p.join(healed, 'instance.lock')).existsSync(), isTrue);
    });

    test(
      'a running instance found only through the second lock makes this '
      'launch secondary and receives the signal there',
      () async {
        final dart = resolveDartExecutable();
        final fallback = p.join(tmp.path, 'fallback');
        final holder = await Process.start(dart, [
          'run',
          _probePath,
          fallback,
          '20000',
        ]);
        addTearDown(() async {
          holder.kill();
          await holder.exitCode;
        });
        final firstLine = await holder.stdout
            .transform(const SystemEncoding().decoder)
            .first
            .timeout(const Duration(minutes: 1));
        expect(firstLine, contains('PRIMARY'));

        // The app-data lock is free (the running instance could not reach
        // it), the second one is held.
        SingleInstanceService.fallbackLockDirOverride = fallback;
        final mayStart = await SingleInstanceService.ensureSingleInstance(
          command: InstanceCommand.toggle,
        );

        expect(mayStart, isFalse);
        expect(SingleInstanceService.claim, InstanceClaim.secondary);
        final signal = await File(
          p.join(fallback, 'focus.signal'),
        ).readAsString();
        expect(signal.trim(), endsWith(' toggle'));
      },
      tags: ['process'],
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  test(
    'a focus signal file fires the callback exactly once (debounced)',
    () async {
      // Frozen clock: every signal lands inside the debounce window no
      // matter how slowly the host delivers it.
      final now = DateTime(2026, 9, 30, 15);
      SingleInstanceService.clock = () => now;
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

      // A second instance inside the debounce window must not double-fire.
      // Reading the signal directly runs the watcher's handler on the new
      // content and returns once it is handled, whichever of the two gets
      // there first; no fixed wait for the watcher event.
      await signal.writeAsString('second', flush: true);
      await SingleInstanceService.debugReadSignal(tmp.path);

      expect(callCount, 1);
    },
  );

  test('a new signal after the debounce window fires again', () async {
    var now = DateTime(2026, 9, 30, 15);
    SingleInstanceService.clock = () => now;
    final primary = await SingleInstanceService.ensureSingleInstance();
    expect(primary, isTrue);

    var callCount = 0;
    var fired = Completer<void>();
    SingleInstanceService.onSecondInstanceLaunched = () {
      callCount++;
      if (!fired.isCompleted) fired.complete();
    };

    final signal = File(p.join(tmp.path, 'focus.signal'));
    await signal.writeAsString('first', flush: true);
    await fired.future.timeout(const Duration(seconds: 5));

    now = now.add(const Duration(seconds: 1));
    fired = Completer<void>();
    await signal.writeAsString('second', flush: true);
    await fired.future.timeout(const Duration(seconds: 5));

    expect(callCount, 2);
  });

  test('one signal fires once even when its events arrive far apart', () async {
    // Windows can surface a single signal write as several directory
    // events; on a loaded host they arrived further apart than the
    // debounce window and focused the window twice (runs 36727893561,
    // 36730929605). Rewriting the same content well past the window
    // reproduces that deterministically on every platform. The pinned clock
    // stands in for the time between the events.
    var now = DateTime(2026, 9, 30, 15);
    SingleInstanceService.clock = () => now;
    final primary = await SingleInstanceService.ensureSingleInstance();
    expect(primary, isTrue);

    var callCount = 0;
    final completer = Completer<void>();
    SingleInstanceService.onSecondInstanceLaunched = () {
      callCount++;
      if (!completer.isCompleted) completer.complete();
    };

    final signal = File(p.join(tmp.path, 'focus.signal'));
    await signal.writeAsString('2026-09-30T15:00:00.000', flush: true);
    await completer.future.timeout(const Duration(seconds: 5));

    // Well past the 400 ms debounce window.
    now = now.add(const Duration(milliseconds: 600));
    await signal.writeAsString('2026-09-30T15:00:00.000', flush: true);
    // Handles the rewritten content like a late watcher event would.
    await SingleInstanceService.debugReadSignal(tmp.path);

    expect(callCount, 1);
  });

  group('InstanceCommand.fromArgs', () {
    test('no remote-control flag means a plain focus request', () {
      expect(InstanceCommand.fromArgs(const []), InstanceCommand.focus);
      expect(
        InstanceCommand.fromArgs(const ['--autostart']),
        InstanceCommand.focus,
      );
    });

    test('--toggle and --cancel map to their commands', () {
      expect(
        InstanceCommand.fromArgs(const ['--toggle']),
        InstanceCommand.toggle,
      );
      expect(
        InstanceCommand.fromArgs(const ['--cancel']),
        InstanceCommand.cancel,
      );
    });

    test('flags are found among unrelated arguments', () {
      expect(
        InstanceCommand.fromArgs(const [
          '-NSDocumentRevisionsDebugMode',
          'YES',
          '--toggle',
        ]),
        InstanceCommand.toggle,
      );
    });

    test('the first remote-control flag wins when both are given', () {
      expect(
        InstanceCommand.fromArgs(const ['--cancel', '--toggle']),
        InstanceCommand.cancel,
      );
      expect(
        InstanceCommand.fromArgs(const ['--toggle', '--cancel']),
        InstanceCommand.toggle,
      );
    });

    test('bare words without the double dash are ignored', () {
      expect(
        InstanceCommand.fromArgs(const ['toggle', 'cancel']),
        InstanceCommand.focus,
      );
    });

    test('the newsletter link asks for the newsletter status', () {
      expect(
        InstanceCommand.fromArgs(const ['whispaste://newsletter/confirmed']),
        InstanceCommand.newsletterConfirmed,
      );
    });

    test('any other app link only focuses the window', () {
      expect(
        InstanceCommand.fromArgs(const [
          'whispaste://newsletter/confirmed?x=1',
        ]),
        InstanceCommand.focus,
      );
      expect(
        InstanceCommand.fromArgs(const ['whispaste://settings']),
        InstanceCommand.focus,
      );
    });
  });

  group('opened URLs (macOS)', () {
    tearDown(() {
      SingleInstanceService.onRemoteCommand = null;
      SingleInstanceService.onSecondInstanceLaunched = null;
    });

    test('a link opened before the app is ready waits for the handler', () {
      SingleInstanceService.openUrls(['whispaste://newsletter/confirmed']);
      final received = <InstanceCommand>[];
      SingleInstanceService.onRemoteCommand = received.add;
      expect(received, [InstanceCommand.newsletterConfirmed]);
    });

    test('an unknown link only focuses, a foreign URL too', () {
      var focusCalls = 0;
      final received = <InstanceCommand>[];
      SingleInstanceService.onRemoteCommand = received.add;
      SingleInstanceService.onSecondInstanceLaunched = () => focusCalls++;
      SingleInstanceService.openUrls([
        'whispaste://evil/run?cmd=x',
        'https://example.org',
      ]);
      expect(received, isEmpty);
      expect(focusCalls, 2);
    });
  });

  group('remote commands (--toggle / --cancel)', () {
    Future<InstanceCommand> nextCommand() {
      final completer = Completer<InstanceCommand>();
      SingleInstanceService.onRemoteCommand = (command) {
        if (!completer.isCompleted) completer.complete(command);
      };
      return completer.future.timeout(const Duration(seconds: 5));
    }

    test('a toggle signal is routed to onRemoteCommand, not focus', () async {
      final primary = await SingleInstanceService.ensureSingleInstance();
      expect(primary, isTrue);
      var focusCalls = 0;
      SingleInstanceService.onSecondInstanceLaunched = () => focusCalls++;

      final received = nextCommand();
      await File(
        p.join(tmp.path, 'focus.signal'),
      ).writeAsString('2026-10-07T10:00:00.000 toggle', flush: true);

      expect(await received, InstanceCommand.toggle);
      expect(focusCalls, 0);
      // A further event for the same write (Windows reports one write as
      // several) is handled like this direct read, and still never focuses.
      await SingleInstanceService.debugReadSignal(tmp.path);
      expect(focusCalls, 0);
    });

    test('a newsletter signal from a second start is routed', () async {
      final primary = await SingleInstanceService.ensureSingleInstance();
      expect(primary, isTrue);

      final received = nextCommand();
      await File(p.join(tmp.path, 'focus.signal')).writeAsString(
        '2026-10-07T10:00:00.000 newsletterConfirmed',
        flush: true,
      );

      expect(await received, InstanceCommand.newsletterConfirmed);
    });

    test('a cancel signal is routed to onRemoteCommand', () async {
      final primary = await SingleInstanceService.ensureSingleInstance();
      expect(primary, isTrue);

      final received = nextCommand();
      await File(
        p.join(tmp.path, 'focus.signal'),
      ).writeAsString('2026-10-07T10:00:00.000 cancel', flush: true);

      expect(await received, InstanceCommand.cancel);
    });

    test(
      'a signal still being read when the lock is released is dropped',
      () async {
        // One write can surface as several watcher events; a read started by
        // the last of them may finish after release(). It must not reach the
        // handler registered afterwards (CI run on 88d77dab delivered a stale
        // cancel into the next test's toggle handler).
        final primary = await SingleInstanceService.ensureSingleInstance();
        expect(primary, isTrue);
        await File(
          p.join(tmp.path, 'focus.signal'),
        ).writeAsString('2026-10-07T10:00:00.000 cancel', flush: true);

        final pendingRead = SingleInstanceService.debugReadSignal(tmp.path);
        await SingleInstanceService.release();
        final delivered = <InstanceCommand>[];
        SingleInstanceService.onRemoteCommand = delivered.add;
        await pendingRead;

        expect(delivered, isEmpty);
      },
    );

    test(
      'a focus request right before a toggle does not swallow the toggle',
      () async {
        // Debounce is per command: a focus followed by a toggle inside the
        // same window are two different requests, not a double-click.
        final now = DateTime(2026, 9, 30, 15);
        SingleInstanceService.clock = () => now;
        final primary = await SingleInstanceService.ensureSingleInstance();
        expect(primary, isTrue);
        final focused = Completer<void>();
        SingleInstanceService.onSecondInstanceLaunched = () {
          if (!focused.isCompleted) focused.complete();
        };

        final signal = File(p.join(tmp.path, 'focus.signal'));
        await signal.writeAsString('2026-10-07T10:00:00.000', flush: true);
        await focused.future.timeout(const Duration(seconds: 5));

        final received = nextCommand();
        await signal.writeAsString(
          '2026-10-07T10:00:00.100 toggle',
          flush: true,
        );
        expect(await received, InstanceCommand.toggle);
      },
    );

    test('a command that arrives before a handler is registered is delivered '
        'once one is', () async {
      // Written just before the lock is taken, so the startup catch-up (not
      // the FS watcher, whose latency varies per OS) picks it up —
      // deterministically before any handler exists. The mtime is pinned
      // ahead so whole-second mtime truncation can never push it outside
      // the catch-up window.
      final signal = File(p.join(tmp.path, 'focus.signal'));
      await signal.writeAsString('2026-10-07T10:00:00.000 toggle', flush: true);
      signal.setLastModifiedSync(
        DateTime.now().add(const Duration(seconds: 5)),
      );
      final primary = await SingleInstanceService.ensureSingleInstance();
      expect(primary, isTrue);

      final delivered = <InstanceCommand>[];
      SingleInstanceService.onRemoteCommand = delivered.add;
      expect(delivered, [InstanceCommand.toggle]);
    });

    test('the primary launched with --toggle queues its own toggle for the '
        'handler (no running instance: start the app, then record)', () async {
      final primary = await SingleInstanceService.ensureSingleInstance(
        command: InstanceCommand.toggle,
      );
      expect(primary, isTrue);

      final delivered = <InstanceCommand>[];
      SingleInstanceService.onRemoteCommand = delivered.add;
      expect(delivered, [InstanceCommand.toggle]);
    });

    test('a plain primary launch queues nothing', () async {
      final primary = await SingleInstanceService.ensureSingleInstance();
      expect(primary, isTrue);

      final delivered = <InstanceCommand>[];
      SingleInstanceService.onRemoteCommand = delivered.add;
      expect(delivered, isEmpty);
    });

    test('SIGUSR2 toggles the primary instance (Unix only)', () async {
      final primary = await SingleInstanceService.ensureSingleInstance();
      expect(primary, isTrue);

      final received = nextCommand();
      Process.killPid(pid, ProcessSignal.sigusr2);

      expect(await received, InstanceCommand.toggle);
    }, skip: Platform.isWindows ? 'SIGUSR2 does not exist on Windows' : false);

    test('release() drops commands nobody picked up', () async {
      await SingleInstanceService.ensureSingleInstance(
        command: InstanceCommand.toggle,
      );
      await SingleInstanceService.release();

      final delivered = <InstanceCommand>[];
      SingleInstanceService.onRemoteCommand = delivered.add;
      expect(delivered, isEmpty);
    });
  });

  group('cross-process', () {
    test(
      'a second real OS process is refused the lock and signals this one',
      () async {
        final dart = resolveDartExecutable();

        final primary = await SingleInstanceService.ensureSingleInstance();
        expect(primary, isTrue);

        // Idempotent: one signal write can surface as several directory
        // events on Windows, and on a loaded host they may land further
        // apart than the 400ms debounce. The exactly-once contract is the
        // debounce test's job, not this one's (run 36727893561).
        final completer = Completer<void>();
        SingleInstanceService.onSecondInstanceLaunched = () {
          if (!completer.isCompleted) completer.complete();
        };

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
      'a secondary launched with --toggle forwards the command to the '
      'process holding the lock',
      () async {
        final dart = resolveDartExecutable();

        // A real second OS process holds the lock as primary ...
        final holder = await Process.start(dart, [
          'run',
          _probePath,
          tmp.path,
          '20000',
        ]);
        // Kill AND await exit before the shared tearDown deletes the temp
        // dir: on Windows a still-dying holder keeps the lock file open and
        // the deletion fails with errno 32.
        addTearDown(() async {
          holder.kill();
          await holder.exitCode;
        });
        final firstLine = await holder.stdout
            .transform(const SystemEncoding().decoder)
            .first
            .timeout(const Duration(minutes: 1));
        expect(firstLine, contains('PRIMARY'));

        // ... so this process is the secondary `whispaste --toggle`.
        final isPrimary = await SingleInstanceService.ensureSingleInstance(
          command: InstanceCommand.toggle,
        );
        expect(isPrimary, isFalse);

        final signal = await File(
          p.join(tmp.path, 'focus.signal'),
        ).readAsString();
        expect(signal.trim(), endsWith(' toggle'));
      },
      tags: ['process'],
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a real OS process becomes primary when no lock is held',
      () async {
        final dart = resolveDartExecutable();

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
