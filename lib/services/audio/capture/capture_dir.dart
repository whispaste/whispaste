/// Private, per-user folder for the volatile capture WAV.
///
/// A dictation is recorded to a WAV before it is transcribed and deleted
/// again. That file must not live in the shared system temp folder: there
/// the name is predictable and other local users can see or pre-create it.
///
/// Locations, most preferred first (no candidate ever falls back to the
/// shared temp folder):
/// - Linux: `$XDG_RUNTIME_DIR/whispaste`, then `$XDG_CACHE_HOME/whispaste`
///   (or `~/.cache/whispaste`).
/// - macOS: `<app support>/WhisPaste/capture` (sandbox-safe: `$HOME` is the
///   container).
/// - Windows: `%LOCALAPPDATA%\WhisPaste\capture`. LOCALAPPDATA is not
///   roaming and its ACL already grants only the owning user, SYSTEM and
///   Administrators. There is no chmod on Windows. The roaming `%APPDATA%`
///   is deliberately not a fallback because it would sync audio.
///
/// On POSIX a candidate is used only if it is a real directory (not a
/// symlink), owned by the current user, and can be set to mode 0700. A
/// candidate that fails any check is skipped.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/app_logger.dart';
import '../../path_service.dart' as paths;

final _log = AppLogger('CaptureDir');

/// Platform the capture folder is resolved for. Injected so tests can run
/// every branch on any host.
enum CapturePlatform { linux, macos, windows }

/// Runs an external tool and returns its result (defaults to [_runProcess]).
typedef CaptureProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Default runner: `Process.run` on its own isolate. A `fork()`+`exec()` that
/// deadlocks wedges the thread it runs on (see `_runProcessGuarded` in
/// `gpu_info.dart`). On a separate isolate the timeout in [_runOk] still fires,
/// and the recording start path stays responsive.
Future<ProcessResult> _runProcess(String executable, List<String> arguments) =>
    Isolate.run(() => Process.run(executable, arguments));

/// Everything the capture-folder logic reads from the host: platform,
/// environment, app-data folder and a process runner for `id`/`stat`/`chmod`.
class CaptureSystem {
  const CaptureSystem({
    required this.platform,
    required this.environment,
    required this.appDataDir,
    this.runProcess = _runProcess,
    this.processTimeout = const Duration(seconds: 5),
  });

  /// The running host.
  factory CaptureSystem.current() => CaptureSystem(
    platform: Platform.isWindows
        ? CapturePlatform.windows
        : Platform.isMacOS
        ? CapturePlatform.macos
        : CapturePlatform.linux,
    environment: Platform.environment,
    appDataDir: _appDataDirOrEmpty(),
  );

  final CapturePlatform platform;
  final Map<String, String> environment;
  final String appDataDir;
  final CaptureProcessRunner runProcess;

  /// Upper bound for one `id`/`stat`/`chmod` call. Past it the tool counts as
  /// failed, so a hung process cannot stall the recording start.
  final Duration processTimeout;

  // Windows has no appDataDir requirement, and a missing APPDATA must not
  // break the capture folder or the startup sweep.
  static String _appDataDirOrEmpty() {
    try {
      return paths.appDataDir();
    } on StateError {
      return '';
    }
  }
}

/// Thrown when no candidate folder can be made private.
class CaptureDirUnavailableException implements Exception {
  const CaptureDirUnavailableException(this.candidates);

  final List<String> candidates;

  @override
  String toString() =>
      'No private capture folder is usable (tried: ${candidates.join(', ')})';
}

/// Ordered candidate folders for [system], most preferred first. Pure: no
/// file-system access, so every platform branch is testable.
List<String> captureDirCandidates(CaptureSystem system) {
  final env = system.environment;
  // Paths follow the target platform's style, not the host's.
  final path = system.platform == CapturePlatform.windows ? p.windows : p.posix;
  String? absoluteEnv(String key) {
    final value = env[key];
    return value != null && path.isAbsolute(value) ? value : null;
  }

  switch (system.platform) {
    case CapturePlatform.linux:
      final runtime = absoluteEnv('XDG_RUNTIME_DIR');
      final cacheHome =
          absoluteEnv('XDG_CACHE_HOME') ??
          (absoluteEnv('HOME') == null
              ? null
              : path.join(env['HOME']!, '.cache'));
      return [
        if (runtime != null) path.join(runtime, 'whispaste'),
        if (cacheHome != null) path.join(cacheHome, 'whispaste'),
      ];
    case CapturePlatform.macos:
      // An empty app-data folder would make a relative path below the CWD.
      if (!path.isAbsolute(system.appDataDir)) return const [];
      return [path.join(system.appDataDir, 'capture')];
    case CapturePlatform.windows:
      // Relative LOCALAPPDATA would resolve below the CWD, as on POSIX.
      final local = absoluteEnv('LOCALAPPDATA');
      if (local == null) return const [];
      return [path.join(local, 'WhisPaste', 'capture')];
  }
}

/// Whether [name] is a WhisPaste capture WAV. The single pattern shared by
/// the startup sweeps and the file name generator.
bool isCaptureWavName(String name) =>
    name.startsWith('whispaste_') && name.endsWith('.wav');

/// Unpredictable file name for one capture WAV: `whispaste_<ms>_<16 hex>.wav`.
/// Keeps the `whispaste_*.wav` pattern the sweeps rely on.
String captureWavFileName(int timestampMs, Random random) {
  final suffix = List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'whispaste_${timestampMs}_$suffix.wav';
}

/// Runs [tool] and returns its result, or `null` when it cannot run, exits
/// with a non-zero code, or does not finish within `processTimeout`.
Future<ProcessResult?> _runOk(
  CaptureSystem system,
  String tool,
  List<String> arguments,
) async {
  try {
    final result = await system
        .runProcess(tool, arguments)
        .timeout(system.processTimeout);
    return result.exitCode == 0 ? result : null;
  } on TimeoutException {
    _log.warning('$tool did not finish within ${system.processTimeout}');
    return null;
  } on Exception {
    return null;
  }
}

/// Numeric uid of the current user, or `null` if unknown.
Future<int?> _currentUid(CaptureSystem system) async {
  final result = await _runOk(system, 'id', ['-u']);
  return int.tryParse(result?.stdout.toString().trim() ?? '');
}

/// Numeric uid owning [path], or `null` if unknown. `stat` syntax differs
/// between GNU (Linux) and BSD (macOS); it follows the host's own tool, not
/// the target platform of [system].
Future<int?> _ownerUid(CaptureSystem system, String path) async {
  final arguments = Platform.isMacOS ? ['-f', '%u', path] : ['-c', '%u', path];
  final result = await _runOk(system, 'stat', arguments);
  return int.tryParse(result?.stdout.toString().trim() ?? '');
}

/// Makes [path] a private folder for the current user, creating it if needed.
///
/// Returns `false` (and the caller must try another candidate) when [path] is
/// a symlink, is not a directory, is owned by someone else, or cannot be set
/// to 0700. The candidates live under the user's own runtime, cache or
/// LOCALAPPDATA folder, so no other local user can plant a link there. The
/// check-then-chmod gap is therefore not an attack surface.
Future<bool> ensurePrivateDir(String path, CaptureSystem system) async {
  switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    case FileSystemEntityType.link:
    case FileSystemEntityType.file:
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.unixDomainSock:
      return false;
    case FileSystemEntityType.directory:
    case FileSystemEntityType.notFound:
      break;
  }
  try {
    Directory(path).createSync(recursive: true);
  } on FileSystemException {
    return false;
  }

  if (system.platform == CapturePlatform.windows) return true;

  final me = await _currentUid(system);
  final owner = await _ownerUid(system, path);
  if (me == null || owner == null || owner != me) return false;
  if (await _runOk(system, 'chmod', ['700', path]) == null) return false;
  return (FileStat.statSync(path).mode & 0x1FF) == 0x1C0;
}

/// First usable candidate for [system], created with mode 0700 where the
/// platform supports it.
///
/// Throws [CaptureDirUnavailableException] when none is usable. The caller
/// must then fail the recording. It must never fall back to the shared temp
/// folder.
Future<String> resolveCaptureDir(CaptureSystem system) async {
  final candidates = captureDirCandidates(system);
  for (final dir in candidates) {
    if (await ensurePrivateDir(dir, system)) return dir;
    _log.warning('Capture folder not usable, trying the next: $dir');
  }
  throw CaptureDirUnavailableException(candidates);
}

String? _resolvedCaptureDir;

/// Capture folder for this process, resolved once. Process spawns (`id`,
/// `stat`, `chmod`) are not repeated on every recording start, because the
/// hotkey-to-text path is latency-sensitive. Only a cheap existence and
/// symlink check runs per call, and a missing folder is recreated.
Future<String> currentCaptureDir() async {
  final cached = _resolvedCaptureDir;
  if (cached != null &&
      FileSystemEntity.typeSync(cached, followLinks: false) ==
          FileSystemEntityType.directory) {
    return cached;
  }
  final dir = await resolveCaptureDir(CaptureSystem.current());
  _resolvedCaptureDir = dir;
  return dir;
}

/// Deletes capture WAVs an earlier app version left in the shared temp
/// folder [tempDir]. Only files matching [isCaptureWavName] that were last
/// modified before [modifiedBefore] are removed.
///
/// Symlinks are never followed: `Directory.list` returns them as links, and
/// they are skipped. On POSIX a file must also be owned by the current user.
/// On Windows the ownership check is skipped because `%TEMP%` is per user.
/// Returns the number of files deleted.
Future<int> sweepLegacyTempWavs({
  required Directory tempDir,
  required DateTime modifiedBefore,
  required CaptureSystem system,
}) async {
  final posix = system.platform != CapturePlatform.windows;
  final me = posix ? await _currentUid(system) : null;
  if (posix && me == null) return 0;

  var deleted = 0;
  try {
    await for (final entity in tempDir.list()) {
      if (entity is! File) continue;
      if (!isCaptureWavName(p.basename(entity.path))) continue;
      try {
        final stat = await entity.stat();
        if (!stat.modified.isBefore(modifiedBefore)) continue;
        if (posix && await _ownerUid(system, entity.path) != me) continue;
        await entity.delete();
        deleted++;
      } on FileSystemException catch (e) {
        _log.warning('Skipping legacy WAV ${entity.path}: $e');
      }
    }
  } on FileSystemException catch (e) {
    _log.warning('Could not list ${tempDir.path}: $e');
  }
  if (deleted > 0) {
    _log.info('Legacy temp WAV cleanup: removed $deleted file(s)');
  }
  return deleted;
}

const _keyLegacyTempWavSweepDone = 'legacy_temp_wav_sweep_done';

/// Runs [sweepLegacyTempWavs] on [tempDir] once per install. The
/// SharedPreferences flag is set after the sweep. A failure before the flag
/// is written is retried on the next launch.
Future<int> sweepLegacyTempWavsOnce({
  required Directory tempDir,
  required DateTime modifiedBefore,
  required CaptureSystem system,
  required SharedPreferences prefs,
}) async {
  if (prefs.getBool(_keyLegacyTempWavSweepDone) == true) return 0;
  final deleted = await sweepLegacyTempWavs(
    tempDir: tempDir,
    modifiedBefore: modifiedBefore,
    system: system,
  );
  await prefs.setBool(_keyLegacyTempWavSweepDone, true);
  return deleted;
}

/// App entry point for [sweepLegacyTempWavsOnce] on the real system temp
/// folder. Never throws: a broken prefs read only logs, so startup continues.
Future<void> runLegacyTempWavSweepOnce({
  required DateTime modifiedBefore,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await sweepLegacyTempWavsOnce(
      tempDir: Directory.systemTemp,
      modifiedBefore: modifiedBefore,
      system: CaptureSystem.current(),
      prefs: prefs,
    );
  } on Exception catch (e) {
    _log.warning('Legacy temp WAV cleanup skipped: $e');
  }
}
