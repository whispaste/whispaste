/// Restarts WhisPaste cleanly on macOS, Windows and Linux (#825).
///
/// Behind the "Restart" button of the cards that name a restart as the way out
/// (the speech model cannot start, the hotkey stopped responding). One entry
/// point, three platform ways, so the button behaves the same everywhere:
///
/// - macOS: the native relaunch helper (`MacOSLifecycleChannel.restart`).
/// - Windows and Linux: start a fresh copy of this executable detached (on
///   Linux the AppImage file when run from one), then end this process.
///
/// Settings and history are persisted anyway, so the new process comes back
/// in the same state. A dictation is never cut off: while one is recording,
/// transcribing or refining the restart waits and runs when it is finished.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/platform/macos_lifecycle_channel.dart';
import '../core/recording/recording_state.dart';
import 'graceful_shutdown.dart';
import 'single_instance_service.dart';

final _log = AppLogger('AppRestart');

/// What [AppRestartService.requestRestart] did with the request.
enum AppRestartResult {
  /// The restart started; the process ends shortly.
  started,

  /// A dictation is running; the restart runs when it is finished.
  deferred,

  /// The new process could not be started; this one keeps running.
  failed,
}

/// How a fresh copy of the app is started on Windows and Linux.
typedef AppSpawn =
    Future<void> Function(String executable, List<String> arguments);

class AppRestartService {
  AppRestartService({
    required this.isDictationBusy,
    required this.shutdown,
    this.releaseInstanceLock = SingleInstanceService.release,
    this.macRelaunch = MacOSLifecycleChannel.restart,
    this.spawn = _spawnDetached,
    this.endProcess = _exitProcess,
    String? Function()? appImagePath,
    String? resolvedExecutable,
    bool? isMacOS,
  }) : _appImagePath = appImagePath ?? _envAppImage,
       _executable = resolvedExecutable ?? Platform.resolvedExecutable,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  /// Whether a dictation holds the transcriber right now.
  final bool Function() isDictationBusy;

  /// Frees the speech engines before the process ends.
  final Future<void> Function() shutdown;

  /// Frees the single-instance lock so the new process is not taken for a
  /// second instance.
  final Future<void> Function() releaseInstanceLock;

  /// The macOS relaunch helper.
  final Future<void> Function() macRelaunch;

  final AppSpawn spawn;
  final void Function() endProcess;

  final String? Function() _appImagePath;
  final String _executable;
  final bool _isMacOS;

  bool _pending = false;
  bool _running = false;

  /// Whether a restart waits for the end of a dictation.
  bool get isPending => _pending;

  /// Asks for a restart: runs now, or after the running dictation.
  Future<AppRestartResult> requestRestart() async {
    if (_running) return AppRestartResult.started;
    if (isDictationBusy()) {
      _pending = true;
      _log.info('Restart waits for the running dictation');
      return AppRestartResult.deferred;
    }
    return _run();
  }

  /// Call when a dictation has ended: runs a restart that was waiting.
  Future<void> dictationEnded() async {
    if (!_pending || isDictationBusy()) return;
    _pending = false;
    await _run();
  }

  /// The path to start again: the AppImage file when run from one (the mounted
  /// binary disappears with this process), else the running executable.
  String get relaunchExecutable {
    final image = _appImagePath();
    return image != null && image.isNotEmpty ? image : _executable;
  }

  Future<AppRestartResult> _run() async {
    _running = true;
    _pending = false;
    try {
      await shutdown().timeout(const Duration(seconds: 15));
    } catch (e) {
      _log.debug('Engine shutdown before restart failed (non-fatal): $e');
    }
    try {
      await releaseInstanceLock();
      if (_isMacOS) {
        await macRelaunch();
      } else {
        // No arguments: a one-shot command line (a toggle, a link) must not
        // run a second time in the new process.
        await spawn(relaunchExecutable, const []);
        endProcess();
      }
      return AppRestartResult.started;
    } catch (e, st) {
      _log.error('Restart failed, keeping this process', e, st);
      _running = false;
      return AppRestartResult.failed;
    }
  }

  static String? _envAppImage() {
    final path = Platform.environment['APPIMAGE'];
    return path != null && path.isNotEmpty && File(path).existsSync()
        ? path
        : null;
  }

  static Future<void> _spawnDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }

  static void _exitProcess() => exit(0);
}

final appRestartServiceProvider = Provider<AppRestartService>((ref) {
  final service = AppRestartService(
    isDictationBusy: () => isDictationBusy(ref.read(recordingProvider).phase),
    shutdown: () => runGracefulEngineShutdown(ref.container),
  );
  ref.listen(recordingProvider.select((s) => s.phase), (_, phase) {
    if (!isDictationBusy(phase)) unawaited(service.dictationEnded());
  });
  return service;
});
