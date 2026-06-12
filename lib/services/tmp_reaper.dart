/// Orphaned-`.tmp`-Reaper — identifies and removes stale download fragments.
///
/// Aborted STT-model and whisper-server downloads leave a `<filename>.tmp`
/// partial file on disk. Those fragments are intentionally kept alive while a
/// download is paused, because [HttpModelFetcher] can resume them. When a
/// download is abandoned (app crash, OS reboot, user uninstall-and-reinstall)
/// the fragment is orphaned and must eventually be cleaned up.
///
/// Design: the reap *decision* ([reapReadyEntries]) is a pure function, fully
/// testable without disk I/O. The I/O side ([sweepOrphanedTmpFiles]) is a thin
/// wrapper that reads directory stats, calls the decision function, and deletes
/// the returned entries.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';

final _log = AppLogger('TmpReaper');

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

/// Minimal description of a directory entry used by [reapReadyEntries].
///
/// [name] is the filename only (no directory part),
/// e.g. `ggml-small-q5_1.bin.tmp`.
/// [age] is the time elapsed since the file was last modified.
class TmpDirEntry {
  const TmpDirEntry({required this.name, required this.age});

  /// Filename (basename), without any directory component.
  final String name;

  /// Age of the file — time elapsed since its last-modified timestamp.
  final Duration age;
}

// ---------------------------------------------------------------------------
// Pure decision function — AC1
// ---------------------------------------------------------------------------

/// Returns the subset of [entries] that are ready to be reaped.
///
/// An entry is reap-ready iff **all** of the following hold:
///
/// 1. [TmpDirEntry.name] ends with `.tmp`.
/// 2. [TmpDirEntry.name] is **not** contained in [activeDownloadPaths]
///    (the set of filenames — basenames only — for downloads currently in
///    flight or paused and resumable).
/// 3. [TmpDirEntry.age] is strictly greater than [ageThreshold].
///
/// This is a **pure function** — no disk I/O, no providers, no side effects.
/// It can be called directly in unit tests with arbitrary inputs.
List<TmpDirEntry> reapReadyEntries({
  required List<TmpDirEntry> entries,
  required Set<String> activeDownloadPaths,
  required Duration ageThreshold,
}) {
  final result = <TmpDirEntry>[];
  for (final entry in entries) {
    if (!entry.name.endsWith('.tmp')) continue;
    if (activeDownloadPaths.contains(entry.name)) continue;
    if (entry.age <= ageThreshold) continue;
    result.add(entry);
  }
  return result;
}

// ---------------------------------------------------------------------------
// I/O delete wrapper — AC3
// ---------------------------------------------------------------------------

/// Sweeps [directory] for orphaned `.tmp` files and deletes the reap-ready ones.
///
/// [activeDownloadPaths] is the set of **absolute paths** (or basenames —
/// [p.basename] is applied internally) for `.tmp` files that belong to
/// downloads that are currently in flight or paused. These are **never** deleted.
///
/// [ageThreshold] is the minimum age a fragment must have before it is
/// considered reap-ready. Default: 1 hour. This prevents accidentally
/// deleting a fragment from a download that just started or was paused
/// moments ago.
///
/// Fire-and-forget safe: all errors are caught and logged; nothing is
/// rethrown. Call sites may `unawaited()` this without risk.
Future<void> sweepOrphanedTmpFiles({
  required String directory,
  Set<String> activeDownloadPaths = const {},
  Duration ageThreshold = const Duration(hours: 1),
}) async {
  final dir = Directory(directory);
  if (!dir.existsSync()) return;

  final now = DateTime.now();
  final entries = <TmpDirEntry>[];
  final fileByName = <String, File>{};

  // Collect .tmp files with their ages.
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.tmp')) continue;

      try {
        final stat = await entity.stat();
        final age = now.difference(stat.modified);
        entries.add(TmpDirEntry(name: name, age: age));
        fileByName[name] = entity;
      } catch (e) {
        _log.warning('TmpReaper: could not stat "$name": $e');
      }
    }
  } catch (e) {
    _log.warning('TmpReaper: could not list directory "$directory": $e');
    return;
  }

  if (entries.isEmpty) return;

  // Normalise active paths to basenames for the pure-function comparison.
  final activeNames = activeDownloadPaths.map(p.basename).toSet();

  final toReap = reapReadyEntries(
    entries: entries,
    activeDownloadPaths: activeNames,
    ageThreshold: ageThreshold,
  );

  if (toReap.isEmpty) return;

  _log.info('TmpReaper: found ${toReap.length} reap-ready .tmp fragment(s)');
  for (final entry in toReap) {
    final file = fileByName[entry.name];
    if (file == null) continue;
    try {
      await file.delete();
      _log.info('TmpReaper: reaped orphan "${entry.name}"');
    } catch (e) {
      _log.warning('TmpReaper: could not delete "${entry.name}": $e');
    }
  }
}
