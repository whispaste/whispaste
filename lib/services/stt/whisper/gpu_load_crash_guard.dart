/// Crash-loop breaker for the in-process whisper.cpp GPU model load.
///
/// The Issue 03 cutover from a `whisper-server` subprocess to an in-process
/// FFI engine (`whisper_ffi_engine.dart`) traded subprocess crash isolation
/// away: a genuine native fault (segfault/access violation in
/// `whisper.dll`/`ggml-vulkan.dll`, e.g. on a GPU whose Vulkan compute
/// support is too old/buggy for the bundled backend) kills the whole app
/// process before any Dart `catch` runs — see `whisper_engine.dart`'s
/// [WhisperFailureKind.gpuCrash] doc comment. `SttServerStateNotifier`'s
/// existing CPU-fallback retry (`_start`) can only react to *catchable*
/// failures, so a hard crash repeats identically on every relaunch: the
/// pre-warm fires within a microtask of `runApp()` (no debounce on first
/// load), so the user never has a realistic window to reach
/// Einstellungen → Spracherkennung → GPU-Beschleunigung → "Deaktiviert"
/// before the app dies again.
///
/// This guard closes that gap without any GPU/VRAM heuristic: a marker file
/// is written synchronously to disk immediately before the native load call,
/// and removed only once the process has provably survived both the load
/// *and* the warmup inference that follows it (on old/weak GPUs the first
/// compute dispatch, not the weight load, is the more likely crash point —
/// see `stt_server_state_notifier.dart`'s `_start()`) — or once the GPU path
/// has been abandoned for a catchable failure. If the marker is still
/// present at the next launch, the previous attempt never returned, so
/// [crashedLastAttempt] is true and [recoverFromGpuLoadCrash] permanently
/// switches the persisted GPU-acceleration setting to CPU-only before
/// `runApp()`.
library;

import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/settings_enums.dart' show GpuAcceleration;
import '../../../core/config/settings_provider.dart';
import '../../../core/logging/crash_fingerprints.dart';
import '../../../core/logging/crash_reporter.dart';
import '../../path_service.dart';

/// Reads/writes the on-disk marker used to detect a GPU-load crash-loop.
///
/// Pure I/O, no Flutter/Riverpod dependency, so it is directly constructible
/// in unit tests with an injected [dataDir] — no fake filesystem needed.
class GpuLoadCrashGuard {
  GpuLoadCrashGuard({String? dataDir}) : _dataDir = dataDir ?? appDataDir();

  final String _dataDir;

  static const _markerFileName = '.gpu_load_attempt';

  File get _markerFile => File(p.join(_dataDir, _markerFileName));

  /// True if a previous session marked a GPU load attempt and never cleared
  /// it — i.e. the process died before the load call returned.
  bool get crashedLastAttempt => _markerFile.existsSync();

  /// Call immediately before a GPU-backed `WhisperEngine.load()`.
  void markAttempt() {
    try {
      _markerFile.parent.createSync(recursive: true);
      _markerFile.writeAsStringSync(DateTime.now().toIso8601String());
    } catch (e) {
      // Best-effort: if the marker can't be written, this launch simply
      // loses crash-loop protection — never let this block the real load.
      dev.log(
        'Failed to write GPU-load crash marker: $e',
        name: 'GpuLoadCrashGuard',
      );
    }
  }

  /// Call right after a GPU-backed load call returns, whether it succeeded
  /// or failed with a catchable exception — both prove the process is alive.
  void clearAttempt() {
    try {
      if (_markerFile.existsSync()) _markerFile.deleteSync();
    } catch (e) {
      // Best-effort, see markAttempt.
      dev.log(
        'Failed to clear GPU-load crash marker: $e',
        name: 'GpuLoadCrashGuard',
      );
    }
  }
}

final gpuLoadCrashGuardProvider = Provider<GpuLoadCrashGuard>(
  (ref) => GpuLoadCrashGuard(),
);

/// Startup recovery: if [GpuLoadCrashGuard.crashedLastAttempt] is true,
/// permanently forces `behavior.gpuAcceleration` to `disabled` — reusing
/// [whisperEngineProvider]'s existing "disabled" gate rather than a
/// session-only override, so the change is visible (and reversible) in the
/// settings screen the next time the user gets there. Must be awaited
/// before `runApp()` in `main.dart`, for the same cache-race reason the GPU
/// hardware probe is awaited there: the STT prewarm reads
/// `settingsProvider`'s cached value synchronously at construction.
///
/// Never throws: `main.dart` awaits this before `runApp()`, so a persistence
/// failure here (locked secure storage, disk full, DB locked) must not turn
/// into a silent, windowless dead boot — worse than the GPU crash this code
/// exists to fix. On such a failure the override simply doesn't stick this
/// launch (GPU is attempted again, self-limiting rather than permanently
/// stuck) and the failure is reported instead of thrown.
Future<void> recoverFromGpuLoadCrash(ProviderContainer container) async {
  final guard = container.read(gpuLoadCrashGuardProvider);
  if (!guard.crashedLastAttempt) return;

  CrashReporter.instance?.captureError(
    message:
        'STT GPU model load crashed the previous session — '
        'forcing CPU-only STT for all future launches',
    severity: 'warning',
    fingerprint: const [sttGpuLoadCrashRecovered],
  );

  try {
    await container
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            behavior: s.behavior.copyWith(
              gpuAcceleration: GpuAcceleration.disabled.value,
            ),
          ),
        );
  } catch (e, st) {
    CrashReporter.instance?.captureError(
      message:
          'Failed to persist the CPU-only override after a GPU load '
          'crash — GPU will be attempted again this launch: $e',
      severity: 'error',
      fingerprint: const [sttGpuLoadCrashRecovered],
      error: e,
      stackTrace: st,
    );
  } finally {
    // Always clear, even on a persistence failure above: leaving the marker
    // set would misreport an unrelated future crash as "already recovered
    // from", and the settings write failing here has nothing to do with
    // whether the next GPU load attempt itself will crash.
    guard.clearAttempt();
  }
}
