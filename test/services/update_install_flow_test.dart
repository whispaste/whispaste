import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/update_service.dart';

/// Recording notifier whose phase a test can move on demand.
class _SettableRecordingNotifier extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState(phase: RecordingPhase.idle);

  void setPhase(RecordingPhase phase) {
    state = RecordingState(phase: phase);
  }
}

ProviderContainer _container({required List<Object> exitCalls}) {
  final container = ProviderContainer(
    overrides: [recordingProvider.overrideWith(_SettableRecordingNotifier.new)],
  );
  addTearDown(container.dispose);
  UpdateNotifier.exitOverrideForTesting = (code) => exitCalls.add(code);
  addTearDown(() => UpdateNotifier.exitOverrideForTesting = null);
  return container;
}

/// A file that is not executable, so launching it fails on Linux and the
/// failure path of [UpdateNotifier.installUpdate] runs for real.
File _notExecutableInstaller() {
  final dir = Directory.systemTemp.createTempSync('uia-w2-install');
  addTearDown(() => dir.deleteSync(recursive: true));
  return File('${dir.path}/WhisPaste-Setup.exe')
    ..writeAsStringSync('not an installer');
}

void main() {
  final onLinux = Platform.isLinux;

  test(
    'a missing installer file is an install failure with a retry check',
    () async {
      final exitCalls = <Object>[];
      final container = _container(exitCalls: exitCalls);
      final notifier = container.read(updateProvider.notifier);
      notifier.debugSetStateForTesting(
        const UpdateState(
          phase: UpdatePhase.readyToInstall,
          downloadedPath: '/nonexistent/WhisPaste-Setup.exe',
        ),
      );

      await notifier.installUpdate();

      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.error);
      expect(state.installFailure, InstallFailure.installerMissing);
      expect(state.downloadedPath, isNull);
      expect(exitCalls, isEmpty);
    },
    skip: !onLinux ? 'exercises the Linux/Windows launch branch' : null,
  );

  test(
    'a failed launch keeps the installer so the user can install again',
    () async {
      final exitCalls = <Object>[];
      final container = _container(exitCalls: exitCalls);
      final installer = _notExecutableInstaller();
      final notifier = container.read(updateProvider.notifier);
      notifier.debugSetStateForTesting(
        UpdateState(
          phase: UpdatePhase.readyToInstall,
          downloadedPath: installer.path,
        ),
      );

      await notifier.installUpdate();

      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.error);
      expect(state.installFailure, InstallFailure.launchFailed);
      expect(state.downloadedPath, installer.path);
      expect(state.errorMessage, isNotNull);
      expect(exitCalls, isEmpty);
    },
    skip: !onLinux ? 'exercises the Linux/Windows launch branch' : null,
  );

  test(
    'an install requested during a recording is deferred, not started',
    () async {
      final exitCalls = <Object>[];
      final container = _container(exitCalls: exitCalls);
      final installer = _notExecutableInstaller();
      (container.read(recordingProvider.notifier) as _SettableRecordingNotifier)
          .setPhase(RecordingPhase.recording);
      final notifier = container.read(updateProvider.notifier);
      notifier.debugSetStateForTesting(
        UpdateState(
          phase: UpdatePhase.readyToInstall,
          downloadedPath: installer.path,
        ),
      );

      await notifier.installUpdate();

      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.readyToInstall);
      expect(state.installDeferred, isTrue);
      expect(state.installFailure, isNull);
      expect(exitCalls, isEmpty);
    },
    skip: !onLinux ? 'exercises the Linux/Windows launch branch' : null,
  );

  test(
    'a deferred install runs once the recording has ended',
    () async {
      final exitCalls = <Object>[];
      final container = _container(exitCalls: exitCalls);
      final installer = _notExecutableInstaller();
      final recording =
          container.read(recordingProvider.notifier)
              as _SettableRecordingNotifier;
      final notifier = container.read(updateProvider.notifier);
      notifier.debugSetStateForTesting(
        UpdateState(
          phase: UpdatePhase.readyToInstall,
          downloadedPath: installer.path,
        ),
      );
      recording.setPhase(RecordingPhase.transcribing);
      await notifier.installUpdate();
      expect(container.read(updateProvider).installDeferred, isTrue);

      recording.setPhase(RecordingPhase.done);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = container.read(updateProvider);
      expect(state.installDeferred, isFalse);
      expect(state.installFailure, InstallFailure.launchFailed);
    },
    skip: !onLinux ? 'exercises the Linux/Windows launch branch' : null,
  );
}
