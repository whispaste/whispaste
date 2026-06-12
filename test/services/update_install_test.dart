@TestOn('mac-os')
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/update/mac_update_installer.dart';
import 'package:whispaste/services/update_service.dart';

/// Update notifier whose initial state is pinned for installUpdate() tests
/// (the production state is only reachable via a real network download).
class _ReadyUpdateNotifier extends UpdateNotifier {
  _ReadyUpdateNotifier(this._initial);
  final UpdateState _initial;

  @override
  UpdateState build() {
    super.build(); // wires _dio + onDispose
    return _initial;
  }
}

/// Records swap() calls instead of mounting/spawning.
class _RecordingInstaller implements MacUpdateInstaller {
  _RecordingInstaller({this.throwOnSwap = false});
  final bool throwOnSwap;
  int calls = 0;
  String? dmgPath;
  String? targetBundlePath;

  @override
  Future<void> swap({
    required String dmgPath,
    required String targetBundlePath,
  }) async {
    calls++;
    this.dmgPath = dmgPath;
    this.targetBundlePath = targetBundlePath;
    if (throwOnSwap) throw Exception('swap boom');
  }
}

void main() {
  group('buildMacUpdateHelperScript', () {
    final script = buildMacUpdateHelperScript(
      parentPid: 4242,
      dmgPath: '/tmp/WhisPaste.dmg',
      targetBundlePath: '/Applications/WhisPaste.app',
      logPath: '/tmp/wp.log',
    );

    test('embeds the resolved pid, dmg, target and log', () {
      expect(script, contains('PARENT_PID=4242'));
      expect(script, contains("DMG='/tmp/WhisPaste.dmg'"));
      expect(script, contains("TARGET='/Applications/WhisPaste.app'"));
      expect(script, contains("LOG='/tmp/wp.log'"));
    });

    test('waits for the pid, mounts read-only and guards the bundle', () {
      expect(script, contains('kill -0 "\$PARENT_PID"'));
      expect(script, contains('hdiutil attach -nobrowse -readonly'));
      expect(script, contains('Contents/Info.plist'));
    });

    test('swaps atomically and escalates for non-writable targets', () {
      // Stage + atomic rename (never an in-place overwrite).
      expect(script, contains('ditto'));
      expect(script, contains(r'mv "$TARGET" "$BACKUP"'));
      expect(script, contains(r'mv "$STAGE" "$TARGET"'));
      // Writability branch + admin escalation + relaunch.
      expect(script, contains(r'[ -w "$PARENT_DIR" ]'));
      expect(script, contains('with administrator privileges'));
      expect(script, contains('xattr -dr com.apple.quarantine'));
      expect(script, contains(r'open "$TARGET"'));
    });

    test('single-quotes paths safely against injection', () {
      final evil = buildMacUpdateHelperScript(
        parentPid: 1,
        dmgPath: "/tmp/a'b.dmg",
        targetBundlePath: '/Applications/WhisPaste.app',
        logPath: '/tmp/x.log',
      );
      expect(evil, contains(r"DMG='/tmp/a'\''b.dmg'"));
    });
  });

  group('installUpdate (macOS)', () {
    late File dmgFile;
    final exitCalls = <int>[];

    setUp(() {
      UpdateNotifier.dioOverrideForTesting = Dio();
      UpdateNotifier.exitOverrideForTesting = exitCalls.add;
      UpdateNotifier.macBundlePathOverrideForTesting = () =>
          '/Applications/WhisPaste.app';
      dmgFile = File(
        '${Directory.systemTemp.path}/wp-test-${DateTime.now().microsecondsSinceEpoch}.dmg',
      )..writeAsBytesSync([0, 1, 2]);
    });

    tearDown(() {
      UpdateNotifier.dioOverrideForTesting = null;
      UpdateNotifier.exitOverrideForTesting = null;
      UpdateNotifier.macBundlePathOverrideForTesting = null;
      UpdateNotifier.macInstallerOverrideForTesting = null;
      UpdateNotifier.macOpenDmgOverrideForTesting = null;
      exitCalls.clear();
      if (dmgFile.existsSync()) dmgFile.deleteSync();
    });

    ProviderContainer containerWith(UpdateState initial) {
      final c = ProviderContainer(
        overrides: [
          updateProvider.overrideWith(() => _ReadyUpdateNotifier(initial)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    UpdateState ready() => UpdateState(
      phase: UpdatePhase.readyToInstall,
      downloadedPath: dmgFile.path,
    );

    test('swaps with the resolved target + dmg, then exits', () async {
      final installer = _RecordingInstaller();
      UpdateNotifier.macInstallerOverrideForTesting = installer;
      final c = containerWith(ready());

      await c.read(updateProvider.notifier).installUpdate();

      expect(installer.calls, 1);
      expect(installer.dmgPath, dmgFile.path);
      expect(installer.targetBundlePath, '/Applications/WhisPaste.app');
      expect(exitCalls, [0]);
    });

    test(
      'no resolvable bundle → manual-install fallback, no swap/exit',
      () async {
        UpdateNotifier.macBundlePathOverrideForTesting = () => null;
        final installer = _RecordingInstaller();
        UpdateNotifier.macInstallerOverrideForTesting = installer;
        final opened = <String>[];
        UpdateNotifier.macOpenDmgOverrideForTesting = (p) async =>
            opened.add(p);
        final c = containerWith(ready());

        await c.read(updateProvider.notifier).installUpdate();

        expect(installer.calls, 0);
        expect(opened, [dmgFile.path]);
        expect(exitCalls, isEmpty);
        expect(c.read(updateProvider).phase, UpdatePhase.idle);
      },
    );

    test('swap failure → error phase, no exit', () async {
      UpdateNotifier.macInstallerOverrideForTesting = _RecordingInstaller(
        throwOnSwap: true,
      );
      final c = containerWith(ready());

      await c.read(updateProvider.notifier).installUpdate();

      expect(exitCalls, isEmpty);
      expect(c.read(updateProvider).phase, UpdatePhase.error);
      expect(c.read(updateProvider).errorMessage, isNotNull);
    });

    test('missing dmg file → error phase, no swap', () async {
      final installer = _RecordingInstaller();
      UpdateNotifier.macInstallerOverrideForTesting = installer;
      dmgFile.deleteSync();
      final c = containerWith(ready());

      await c.read(updateProvider.notifier).installUpdate();

      expect(installer.calls, 0);
      expect(c.read(updateProvider).phase, UpdatePhase.error);
    });

    test('refuses while a recording is in progress', () async {
      final installer = _RecordingInstaller();
      UpdateNotifier.macInstallerOverrideForTesting = installer;
      final c = containerWith(ready());
      c.read(recordingProvider.notifier).startRecording(); // → recording

      await c.read(updateProvider.notifier).installUpdate();

      expect(installer.calls, 0);
      expect(exitCalls, isEmpty);
      // State untouched — user can retry after the recording settles.
      expect(c.read(updateProvider).phase, UpdatePhase.readyToInstall);
    });
  });
}
