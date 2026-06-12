import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/update/mac_update_installer.dart';
import 'package:whispaste/services/update_service.dart';

/// Records the resolved swap arguments instead of spawning the real detached
/// helper, so `installUpdate` can be observed without mounting or relaunching.
class _RecordingMacInstaller implements MacUpdateInstaller {
  int calls = 0;
  String? dmgPath;
  String? targetBundlePath;
  Object? throwOnSwap;

  @override
  Future<void> swap({
    required String dmgPath,
    required String targetBundlePath,
  }) async {
    calls++;
    this.dmgPath = dmgPath;
    this.targetBundlePath = targetBundlePath;
    if (throwOnSwap != null) throw throwOnSwap!;
  }
}

/// Drives [recordingProvider] into a fixed phase without touching audio/timers.
class _FakeRecordingNotifier extends RecordingNotifier {
  _FakeRecordingNotifier(this._phase);
  final RecordingPhase _phase;

  @override
  RecordingState build() => RecordingState(phase: _phase);
}

void main() {
  // ---------------------------------------------------------------------------
  // Slice 01/02 — the generated detached helper script (pure, platform-neutral).
  // ---------------------------------------------------------------------------
  group('buildMacUpdateHelperScript', () {
    String build({
      int pid = 4242,
      String dmg = '/tmp/WhisPaste.dmg',
      String target = '/Applications/WhisPaste.app',
      String log = '/tmp/wp-update.log',
    }) => buildMacUpdateHelperScript(
      parentPid: pid,
      dmgPath: dmg,
      targetBundlePath: target,
      logPath: log,
    );

    test('waits for the parent PID to exit before touching anything', () {
      final s = build(pid: 9931);
      expect(s, contains('PARENT_PID=9931'));
      expect(s, contains('kill -0 "\$PARENT_PID"'));
    });

    test('mounts the DMG read-only and nobrowse', () {
      expect(build(), contains('hdiutil attach -nobrowse -readonly'));
    });

    test('pre-flight guard refuses an invalid bundle in the DMG', () {
      final s = build();
      expect(s, contains('Contents/Info.plist'));
      expect(s, contains('abort, nothing touched'));
    });

    test('swaps atomically: stage, then rename old out and new in', () {
      final s = build();
      // ditto stages a copy, then two renames move it into place atomically.
      expect(s, contains('/usr/bin/ditto'));
      expect(s, contains('mv "\$TARGET" "\$BACKUP"'));
      expect(s, contains('mv "\$STAGE" "\$TARGET"'));
    });

    test('strips quarantine from the staged bundle', () {
      expect(build(), contains('/usr/bin/xattr -dr com.apple.quarantine'));
    });

    test('escalates once via osascript when the target is not writable', () {
      final s = build();
      expect(s, contains('-w "\$PARENT_DIR"'));
      expect(s, contains('with administrator privileges'));
      // Exactly one escalation path (single password prompt).
      expect('with administrator privileges'.allMatches(s).length, 1);
    });

    test('detaches with a forced retry and relaunches the new bundle', () {
      final s = build();
      expect(s, contains('hdiutil detach -force'));
      expect(s, contains('/usr/bin/open "\$TARGET"'));
    });

    test('shell-quotes paths to survive spaces and quotes', () {
      final s = build(
        dmg: "/tmp/My Drive/Whis'Paste.dmg",
        target: "/Applications/Odd '1'.app",
      );
      // Single quotes inside the path are escaped as the POSIX '\'' idiom.
      expect(s, contains(r"'\''"));
      // The raw unescaped path must never appear verbatim.
      expect(s, isNot(contains("Whis'Paste.dmg\n")));
    });
  });

  // ---------------------------------------------------------------------------
  // resolveMacAppBundlePath — the test runner never lives in an .app bundle.
  // ---------------------------------------------------------------------------
  test('resolveMacAppBundlePath returns null outside an .app bundle', () {
    // The dart/flutter test runner executable is not inside
    // `<bundle>.app/Contents/MacOS/`, so production resolution yields null and
    // the caller falls back to a manual install.
    expect(resolveMacAppBundlePath(), isNull);
  });

  // ---------------------------------------------------------------------------
  // installUpdate — recording guard (Slice 03), platform-neutral: the guard
  // returns before any platform branch, so it runs on every host.
  // ---------------------------------------------------------------------------
  group('installUpdate recording guard', () {
    late Directory tmp;
    late File dmg;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wp-update-test');
      dmg = File('${tmp.path}/WhisPaste.dmg')..writeAsStringSync('x');
    });

    tearDown(() {
      UpdateNotifier.macInstallerOverrideForTesting = null;
      UpdateNotifier.macBundlePathOverrideForTesting = null;
      UpdateNotifier.macOpenDmgOverrideForTesting = null;
      UpdateNotifier.exitOverrideForTesting = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<void> runGuarded(RecordingPhase phase) async {
      final installer = _RecordingMacInstaller();
      var exitCalls = 0;
      UpdateNotifier.macInstallerOverrideForTesting = installer;
      UpdateNotifier.macBundlePathOverrideForTesting = () =>
          '/Applications/WhisPaste.app';
      UpdateNotifier.exitOverrideForTesting = (_) => exitCalls++;

      final container = ProviderContainer(
        overrides: [
          recordingProvider.overrideWith(() => _FakeRecordingNotifier(phase)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(updateProvider.notifier);
      notifier.debugSetStateForTesting(
        UpdateState(
          phase: UpdatePhase.readyToInstall,
          downloadedPath: dmg.path,
        ),
      );

      await notifier.installUpdate();

      // Blocked: no swap, no exit, phase preserved for a later retry.
      expect(installer.calls, 0);
      expect(exitCalls, 0);
      expect(container.read(updateProvider).phase, UpdatePhase.readyToInstall);
    }

    test(
      'does nothing while recording',
      () => runGuarded(RecordingPhase.recording),
    );

    test(
      'does nothing while transcribing',
      () => runGuarded(RecordingPhase.transcribing),
    );
  });

  // ---------------------------------------------------------------------------
  // installUpdate — macOS swap routing (Slice 01/02). Skipped off macOS, where
  // installUpdate takes the Windows/else branch instead.
  // ---------------------------------------------------------------------------
  group(
    'installUpdate macOS routing',
    () {
      late Directory tmp;
      late File dmg;

      setUp(() {
        tmp = Directory.systemTemp.createTempSync('wp-update-test');
        dmg = File('${tmp.path}/WhisPaste.dmg')..writeAsStringSync('x');
      });

      tearDown(() {
        UpdateNotifier.macInstallerOverrideForTesting = null;
        UpdateNotifier.macBundlePathOverrideForTesting = null;
        UpdateNotifier.macOpenDmgOverrideForTesting = null;
        UpdateNotifier.exitOverrideForTesting = null;
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      ({ProviderContainer container, UpdateNotifier notifier}) makeReady() {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(updateProvider.notifier);
        notifier.debugSetStateForTesting(
          UpdateState(
            phase: UpdatePhase.readyToInstall,
            downloadedPath: dmg.path,
          ),
        );
        return (container: container, notifier: notifier);
      }

      test('resolved bundle → swap with (dmg, target) then exit(0)', () async {
        final installer = _RecordingMacInstaller();
        var exitCode = -1;
        UpdateNotifier.macInstallerOverrideForTesting = installer;
        UpdateNotifier.macBundlePathOverrideForTesting = () =>
            '/Applications/WhisPaste.app';
        UpdateNotifier.exitOverrideForTesting = (c) => exitCode = c;

        await makeReady().notifier.installUpdate();

        expect(installer.calls, 1);
        expect(installer.dmgPath, dmg.path);
        expect(installer.targetBundlePath, '/Applications/WhisPaste.app');
        expect(exitCode, 0);
      });

      test(
        'no resolvable bundle → manual DMG fallback, no swap, no exit',
        () async {
          final installer = _RecordingMacInstaller();
          String? opened;
          var exitCalls = 0;
          UpdateNotifier.macInstallerOverrideForTesting = installer;
          UpdateNotifier.macBundlePathOverrideForTesting = () => null;
          UpdateNotifier.macOpenDmgOverrideForTesting = (path) async {
            opened = path;
          };
          UpdateNotifier.exitOverrideForTesting = (_) => exitCalls++;

          final r = makeReady();
          await r.notifier.installUpdate();

          expect(installer.calls, 0);
          expect(opened, dmg.path);
          expect(exitCalls, 0);
          expect(r.container.read(updateProvider).phase, UpdatePhase.idle);
        },
      );

      test('swap throws → error phase with message, no exit', () async {
        final installer = _RecordingMacInstaller()
          ..throwOnSwap = StateError('boom');
        var exitCalls = 0;
        UpdateNotifier.macInstallerOverrideForTesting = installer;
        UpdateNotifier.macBundlePathOverrideForTesting = () =>
            '/Applications/WhisPaste.app';
        UpdateNotifier.exitOverrideForTesting = (_) => exitCalls++;

        final r = makeReady();
        await r.notifier.installUpdate();

        expect(exitCalls, 0);
        final state = r.container.read(updateProvider);
        expect(state.phase, UpdatePhase.error);
        expect(state.errorMessage, isNotNull);
      });
    },
    skip: !Platform.isMacOS ? 'macOS-only install branch' : false,
  );

  // ---------------------------------------------------------------------------
  // installUpdate — missing DMG guard fires on every platform (checked before
  // the platform branch).
  // ---------------------------------------------------------------------------
  test('installUpdate → error when the downloaded file is gone', () async {
    UpdateNotifier.exitOverrideForTesting = (_) {};
    addTearDown(() => UpdateNotifier.exitOverrideForTesting = null);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(updateProvider.notifier);
    notifier.debugSetStateForTesting(
      const UpdateState(
        phase: UpdatePhase.readyToInstall,
        downloadedPath: '/nonexistent/path/WhisPaste.dmg',
      ),
    );

    await notifier.installUpdate();

    final state = container.read(updateProvider);
    expect(state.phase, UpdatePhase.error);
    expect(state.errorMessage, contains('Installer file not found'));
  });
}
