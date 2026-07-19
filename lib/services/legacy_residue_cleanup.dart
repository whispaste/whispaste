/// Legacy pre-FFI server-binary residue cleanup — removes stray files that
/// the whisper-server download/subprocess stack (removed in the 2026
/// whisper-ffi-engine migration, see `.scratch/whisper-ffi-engine/issues/
/// 07-abbau-server-binary-acquisition-stack.md`) used to place in
/// `sttDir()`. The engine has run in-process via `dart:ffi` against a
/// bundled `libwhisper` (next to the executable, NOT in `sttDir()`) ever
/// since, so any of these files found in `sttDir()` today are guaranteed
/// dead weight left over from an upgrade across that migration.
///
/// Design mirrors `tmp_reaper.dart`: the reap *decision*
/// ([isLegacyServerResidue]) is a pure function, fully testable without disk
/// I/O. The I/O side ([sweepLegacyServerResidue]) is a thin wrapper. A
/// SharedPreferences-backed version gate ([sweepLegacyResidueIfNeeded])
/// ensures the sweep runs at most once per app version, not on every single
/// startup.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('LegacyResidueCleanup');

// ---------------------------------------------------------------------------
// Pure decision function
// ---------------------------------------------------------------------------

/// Whether [name] (basename only, as found on disk) is a known pre-FFI
/// server-binary residue file that should be removed from `sttDir()`.
///
/// Matches the exact filename patterns the removed `WhisperServerDownloader`
/// used to write: the server binary itself, every shared-library extension
/// it extracted alongside it, and its (non-`.tmp`-suffixed) temp zip name —
/// see `isServerFile` in the deleted `whisper_server_downloader.dart` (git
/// history) for the original reference list. Model files (`ggml-*.bin`,
/// `*.onnx`, `tokens.txt`) never match.
@visibleForTesting
bool isLegacyServerResidue(String name) {
  final lower = name.toLowerCase();
  if (lower == 'whisper-server' || lower == 'whisper-server.exe') return true;
  if (lower.endsWith('.dll') || lower.endsWith('.dylib')) return true;
  if (lower.endsWith('.so') || lower.endsWith('.metallib')) return true;
  if (lower == '_whisper-server.zip') return true;
  return false;
}

// ---------------------------------------------------------------------------
// I/O wrapper — one-shot sweep
// ---------------------------------------------------------------------------

/// Sweeps [directory] for legacy residue files and deletes them.
///
/// Fire-and-forget safe: all errors are caught and logged; nothing is
/// rethrown. Returns the number of files actually deleted (for logging and
/// tests).
Future<int> sweepLegacyServerResidue({required String directory}) async {
  final dir = Directory(directory);
  if (!dir.existsSync()) return 0;

  var deleted = 0;
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!isLegacyServerResidue(name)) continue;
      try {
        await entity.delete();
        deleted++;
        _log.info('Removed legacy server-binary residue "$name"');
      } catch (e) {
        _log.warning('Could not delete legacy residue "$name": $e');
      }
    }
  } catch (e) {
    _log.warning('Could not list directory "$directory": $e');
  }
  return deleted;
}

// ---------------------------------------------------------------------------
// Version-gated wrapper — runs the sweep at most once per app version
// ---------------------------------------------------------------------------

const _keyLastResidueCleanupVersion = 'legacy_residue_cleanup_version';

/// Runs [sweepLegacyServerResidue] on [directory] at most once per
/// [currentVersion] — subsequent starts on the same version skip the
/// directory scan entirely. Persists [currentVersion] via SharedPreferences
/// after a sweep (even a zero-residue one, so a clean install doesn't
/// re-scan every startup).
///
/// Fire-and-forget safe: all errors are caught and logged; nothing is
/// rethrown, so a broken prefs read/write never blocks startup.
Future<void> sweepLegacyResidueIfNeeded({
  required String directory,
  required String currentVersion,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final lastVersion = prefs.getString(_keyLastResidueCleanupVersion);
    if (lastVersion == currentVersion) return;

    final deleted = await sweepLegacyServerResidue(directory: directory);
    if (deleted > 0) {
      _log.info('Legacy residue cleanup: removed $deleted file(s)');
    }
    await prefs.setString(_keyLastResidueCleanupVersion, currentVersion);
  } catch (e) {
    _log.debug('Legacy residue cleanup gate failed (non-fatal): $e');
  }
}
