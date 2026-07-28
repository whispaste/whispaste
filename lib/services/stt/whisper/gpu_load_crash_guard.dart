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
/// [crashedLastAttempt] is true and [recoverFromGpuLoadCrash] records one
/// more entry in the *consecutive*-crash streak ([recordCrash]). Only once
/// that streak reaches [kGpuCrashStrikeThreshold] does recovery permanently
/// switch the persisted GPU-acceleration setting to CPU-only — a single
/// crash instead retries GPU silently on the very next launch, so a false
/// positive (the user killing the process mid-load, a forced OS-update
/// reboot) doesn't cost the user their GPU over one unlucky launch. The
/// streak resets to zero the moment a GPU-backed load is confirmed to
/// survive both the load and the warmup inference ([resetCrashStreak]) —
/// see `stt_server_state_notifier.dart`'s `_start()`.
///
/// Once the threshold is reached, [recoverFromGpuLoadCrash] also arms a
/// one-time UI notice ([markPendingUserNotice] / [consumePendingUserNotice])
/// so the user is told what happened and can re-enable GPU acceleration
/// themselves — see `RecoveryToastKind.gpuLoadCrashDisabled` in
/// `recording_behavior.dart`.
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
  static const _noticeFileName = '.gpu_load_crash_notice_pending';
  static const _strikesFileName = '.gpu_load_crash_strikes';

  File get _markerFile => File(p.join(_dataDir, _markerFileName));
  File get _noticeFile => File(p.join(_dataDir, _noticeFileName));
  File get _strikesFile => File(p.join(_dataDir, _strikesFileName));

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

  /// Call once [recoverFromGpuLoadCrash] has actually persisted the
  /// CPU-only override — records that the UI owes the user a one-time
  /// "we switched you to CPU" toast (see [consumePendingUserNotice]).
  void markPendingUserNotice() {
    try {
      _noticeFile.parent.createSync(recursive: true);
      _noticeFile.writeAsStringSync('');
    } catch (e) {
      dev.log(
        'Failed to write GPU-disabled notice marker: $e',
        name: 'GpuLoadCrashGuard',
      );
    }
  }

  /// One-shot read: true exactly once per recorded event — deletes the
  /// marker on the way out, so a later rebuild/relaunch never re-shows the
  /// same toast. Intended to be called from a post-frame callback once the
  /// UI's `ref.listen` on `recoveryToastNotifierProvider` is already
  /// attached (see `recording_behavior.dart`'s `initState`).
  bool consumePendingUserNotice() {
    try {
      if (!_noticeFile.existsSync()) return false;
      _noticeFile.deleteSync();
      return true;
    } catch (e) {
      dev.log(
        'Failed to consume GPU-disabled notice marker: $e',
        name: 'GpuLoadCrashGuard',
      );
      return false;
    }
  }

  /// Number of consecutive GPU-load crashes recorded so far — 0 if none, or
  /// after the streak was last reset by a confirmed successful GPU load.
  int get consecutiveCrashes {
    try {
      if (!_strikesFile.existsSync()) return 0;
      return int.tryParse(_strikesFile.readAsStringSync().trim()) ?? 0;
    } catch (e) {
      dev.log(
        'Failed to read GPU-load crash streak: $e',
        name: 'GpuLoadCrashGuard',
      );
      return 0;
    }
  }

  /// Records one more consecutive GPU-load crash and returns the new count.
  /// Called by [recoverFromGpuLoadCrash] once per detected crash.
  int recordCrash() {
    final next = consecutiveCrashes + 1;
    try {
      _strikesFile.parent.createSync(recursive: true);
      _strikesFile.writeAsStringSync('$next');
    } catch (e) {
      dev.log(
        'Failed to write GPU-load crash streak: $e',
        name: 'GpuLoadCrashGuard',
      );
    }
    return next;
  }

  /// Resets the crash streak to zero — call once a GPU-backed load has been
  /// confirmed to survive both the load and the warmup inference, since the
  /// GPU turned out fine after all.
  void resetCrashStreak() {
    try {
      if (_strikesFile.existsSync()) _strikesFile.deleteSync();
    } catch (e) {
      dev.log(
        'Failed to reset GPU-load crash streak: $e',
        name: 'GpuLoadCrashGuard',
      );
    }
  }
}

/// Consecutive GPU-load crashes required before [recoverFromGpuLoadCrash]
/// permanently disables GPU acceleration. Deliberately >1: a single crash
/// is cheap to retry silently on the next launch and absorbs a false
/// positive (Task-Manager kill mid-load, a forced OS-update reboot) without
/// costing the user their GPU over one unlucky launch; genuinely
/// incompatible hardware still recovers within [kGpuCrashStrikeThreshold]
/// launches.
const int kGpuCrashStrikeThreshold = 2;

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

  // Always clear the in-flight marker: reaching this point already proves
  // last session's crash has been accounted for (via recordCrash below),
  // independent of whether the streak has hit the threshold yet.
  final strikes = guard.recordCrash();
  guard.clearAttempt();

  if (strikes < kGpuCrashStrikeThreshold) {
    // Below threshold: retry GPU silently on this very launch. No settings
    // change, no user-facing notice — a single crash must not cost the
    // user their GPU over what may well be an unrelated fluke.
    CrashReporter.instance?.captureError(
      message:
          'STT GPU model load crashed ($strikes/$kGpuCrashStrikeThreshold) '
          '— retrying GPU once more before switching to CPU-only',
      severity: 'warning',
      fingerprint: const [sttGpuLoadCrashRecovered],
    );
    return;
  }

  CrashReporter.instance?.captureError(
    message:
        'STT GPU model load crashed $strikes times in a row — '
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
    // Only promise the user a notice — and only reset the streak — once the
    // override has actually stuck. On the catch path below, GPU stays
    // enabled and the streak is left at/above threshold on purpose, so the
    // very next crash retries this same escalation instead of demanding a
    // fresh two-strike run.
    guard.markPendingUserNotice();
    guard.resetCrashStreak();
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
  }
}
