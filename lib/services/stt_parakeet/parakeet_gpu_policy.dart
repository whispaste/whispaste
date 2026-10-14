/// Backend choice for the Parakeet engine: GPU (libparakeet on the ggml
/// backends — Metal/Vulkan/CUDA) when available, sherpa-onnx CPU otherwise.
///
/// Everything here is pure decision logic plus a small on-disk crash marker,
/// so the selection table and the crash-loop breaker are unit-testable
/// without a native library. The FFI side lives in `parakeet_gpu_engine.dart`.
///
/// For the user this stays one engine, "Parakeet". No new settings switch:
/// the existing GPU-acceleration setting (`GpuAcceleration.disabled`) is the
/// only user-facing input and is honoured here.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../stt/whisper/whisper_ffi_engine.dart' show defaultWhisperLibraryPath;

/// Platform release gate for the GPU Parakeet engine.
///
/// macOS (Metal) is on by default. Windows and Linux follow
/// [parakeetGpuWindowsLinuxEnabled] — flip that single constant to switch
/// them off again without touching the rest of the engine.
const bool parakeetGpuWindowsLinuxEnabled = true;

/// Whether the GPU Parakeet engine may be used on the current platform.
bool parakeetGpuPlatformEnabled() {
  if (Platform.isMacOS) return true;
  if (Platform.isWindows || Platform.isLinux) {
    return parakeetGpuWindowsLinuxEnabled;
  }
  return false;
}

/// Consecutive GPU-load crashes after which GPU Parakeet stays off (see
/// [ParakeetGpuCrashMarker]) until the strikes expire.
const int parakeetGpuCrashStrikeThreshold = 2;

/// How long recorded crash strikes keep GPU Parakeet off. Without an expiry
/// the strikes could never reset: a healthy GPU run resets them, but no GPU
/// run is attempted while they are exhausted. After this period one more
/// attempt runs, still guarded by the crash marker.
const Duration parakeetGpuCrashStrikeExpiry = Duration(days: 14);

enum ParakeetBackend {
  /// libparakeet on a ggml GPU backend (Metal, Vulkan or CUDA).
  gpu,

  /// sherpa-onnx on the CPU (the historical engine, always available).
  sherpaCpu,
}

/// Why the GPU path was not chosen. Logged, and surfaced as a reason in
/// tests; never shown as an error because sherpa-onnx covers the request.
enum ParakeetBackendReason {
  gpuSelected,
  platformDisabled,
  gpuAccelerationDisabled,
  libraryMissing,
  crashedLastLaunch,
  crashStrikesExhausted,
}

/// Pure selection table. The first failing condition wins, in the order below.
/// [gpuAccelerationAllowed] is `behavior.gpuAcceleration != 'disabled'`.
ParakeetBackendReason parakeetBackendReason({
  required bool platformEnabled,
  required bool gpuAccelerationAllowed,
  required bool libraryPresent,
  required bool crashedLastLaunch,
  required int crashStrikes,
}) {
  if (!platformEnabled) return ParakeetBackendReason.platformDisabled;
  if (!gpuAccelerationAllowed) {
    return ParakeetBackendReason.gpuAccelerationDisabled;
  }
  if (!libraryPresent) return ParakeetBackendReason.libraryMissing;
  if (crashedLastLaunch) return ParakeetBackendReason.crashedLastLaunch;
  if (crashStrikes >= parakeetGpuCrashStrikeThreshold) {
    return ParakeetBackendReason.crashStrikesExhausted;
  }
  return ParakeetBackendReason.gpuSelected;
}

/// Maps a [ParakeetBackendReason] to the backend that runs.
ParakeetBackend parakeetBackendFor(ParakeetBackendReason reason) =>
    reason == ParakeetBackendReason.gpuSelected
    ? ParakeetBackend.gpu
    : ParakeetBackend.sherpaCpu;

/// Detects a GPU load that killed the process before it could finish.
///
/// A marker file is written synchronously immediately before the native load
/// and removed once the load and one warm-up transcription have returned. A
/// marker still present at the next launch means that attempt never returned:
/// the launch skips GPU (see [parakeetBackendReason]) and the strike count
/// grows. A confirmed-healthy GPU run resets the strikes, and so does
/// [parakeetGpuCrashStrikeExpiry] passing since the last strike.
///
/// Pure file I/O on an injected [dir] and clock, so tests run on a temp
/// directory.
class ParakeetGpuCrashMarker {
  ParakeetGpuCrashMarker({required this.dir, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final String dir;
  final DateTime Function() _now;

  static const _attemptFile = '.parakeet_gpu_attempt';
  static const _strikesFile = '.parakeet_gpu_strikes';

  File get _attempt => File(p.join(dir, _attemptFile));
  File get _strikes => File(p.join(dir, _strikesFile));

  /// Call once per launch, before any GPU decision. Returns true when the
  /// previous launch died during a GPU load; in that case the marker is
  /// consumed and one strike is recorded.
  bool recoverFromPreviousLaunch() {
    if (!_attempt.existsSync()) return false;
    _attempt.deleteSync();
    _writeStrikes(readStrikes() + 1);
    return true;
  }

  /// Writes the marker right before the native load.
  void markAttempt() {
    Directory(dir).createSync(recursive: true);
    _attempt.writeAsStringSync('gpu', flush: true);
  }

  /// Removes the marker after a healthy GPU run and resets the strikes.
  void confirmHealthy() {
    if (_attempt.existsSync()) _attempt.deleteSync();
    if (_strikes.existsSync()) _strikes.deleteSync();
  }

  /// Removes the marker after a load that failed with a catchable error. The
  /// process survived, so this is not a crash and records no strike.
  void abandonAttempt() {
    if (_attempt.existsSync()) _attempt.deleteSync();
  }

  /// Strikes recorded within [parakeetGpuCrashStrikeExpiry]; older strikes
  /// are dropped. The file holds `<count> <last strike, ms since epoch>`.
  int readStrikes() {
    if (!_strikes.existsSync()) return 0;
    final parts = _strikes.readAsStringSync().trim().split(' ');
    final count = int.tryParse(parts.first) ?? 0;
    final at = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (at == null) return count;
    final age = _now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    if (age >= parakeetGpuCrashStrikeExpiry) {
      _strikes.deleteSync();
      return 0;
    }
    return count;
  }

  void _writeStrikes(int n) {
    Directory(dir).createSync(recursive: true);
    _strikes.writeAsStringSync(
      '$n ${_now().millisecondsSinceEpoch}',
      flush: true,
    );
  }
}

/// Absolute path of libparakeet, resolved like the libwhisper library (same
/// bundle directory: `Frameworks/` on macOS, next to the exe on Windows, the
/// `lib/` folder on Linux).
String parakeetGpuLibraryPath() {
  final name = Platform.isWindows
      ? 'parakeet.dll'
      : Platform.isMacOS
      ? 'libparakeet.dylib'
      : 'libparakeet.so';
  return p.join(p.dirname(defaultWhisperLibraryPath()), name);
}

/// Whether the GPU engine should be provisioned (its GGUF downloaded) on this
/// machine. Excludes the crash-marker state on purpose: a download is wanted
/// even while a crash strike currently disables GPU for one launch.
bool parakeetGpuWanted({required bool gpuAccelerationAllowed}) =>
    parakeetGpuPlatformEnabled() &&
    gpuAccelerationAllowed &&
    File(parakeetGpuLibraryPath()).existsSync();
