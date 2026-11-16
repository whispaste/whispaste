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

import 'package:clock/clock.dart';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';

final _log = AppLogger('TmpReaper');

/// Absolute paths of `.tmp` fragments whose download is in progress or was
/// interrupted in this session and can still be resumed. A sweep never deletes
/// these, whatever their age: a sibling download's post-completion sweep would
/// otherwise remove a paused fragment that the user is about to resume.
///
/// In-memory and process-wide. After an app restart the registry is empty and
/// the age rule applies again, which is what reaps truly abandoned fragments.
final Set<String> _resumableFragments = <String>{};

String _fragmentKey(String tmpPath) => p.normalize(p.absolute(tmpPath));

/// Marks [tmpPath] as a resumable download fragment (see [_resumableFragments]).
void registerResumableFragment(String tmpPath) =>
    _resumableFragments.add(_fragmentKey(tmpPath));

/// Removes [tmpPath] from the resumable registry, e.g. after its rename to the
/// final file, so the next sweep may reap it again if it is ever orphaned.
void releaseResumableFragment(String tmpPath) =>
    _resumableFragments.remove(_fragmentKey(tmpPath));

/// Whether [tmpPath] is currently registered as resumable.
bool isResumableFragment(String tmpPath) =>
    _resumableFragments.contains(_fragmentKey(tmpPath));

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

/// Minimal description of a directory entry used by [reapReadyEntries].
///
/// [name] is the filename only (no directory part),
/// e.g. `ggml-small-q5_1.bin.tmp`.
/// [age] is the time elapsed since the file was last modified.
class TmpDirEntry {
  const TmpDirEntry({
    required this.name,
    required this.age,
    this.identified = false,
  });

  /// Filename (basename), without any directory component.
  final String name;

  /// Age of the file — time elapsed since its last-modified timestamp.
  final Duration age;

  /// Whether the fragment has an identity sidecar (`<name>.json`, written
  /// by `prepareFragmentIdentity`), i.e. it is a resumable part of a known
  /// registry file rather than an anonymous leftover.
  final bool identified;
}

/// How long an identified fragment ([TmpDirEntry.identified]) is kept for a
/// resume after the app was closed. The age rule of one hour reaped every
/// fragment at the next start, so a large download interrupted in the
/// evening started from byte 0 the next morning.
const Duration kIdentifiedFragmentMaxAge = Duration(days: 7);

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
/// 3. [TmpDirEntry.age] is strictly greater than [ageThreshold], or, for an
///    identified fragment, than the larger of [ageThreshold] and
///    [identifiedAgeThreshold].
///
/// This is a **pure function** — no disk I/O, no providers, no side effects.
/// It can be called directly in unit tests with arbitrary inputs.
List<TmpDirEntry> reapReadyEntries({
  required List<TmpDirEntry> entries,
  required Set<String> activeDownloadPaths,
  required Duration ageThreshold,
  Duration identifiedAgeThreshold = kIdentifiedFragmentMaxAge,
}) {
  final result = <TmpDirEntry>[];
  for (final entry in entries) {
    if (!entry.name.endsWith('.tmp')) continue;
    if (activeDownloadPaths.contains(entry.name)) continue;
    final threshold = entry.identified && identifiedAgeThreshold > ageThreshold
        ? identifiedAgeThreshold
        : ageThreshold;
    if (entry.age <= threshold) continue;
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

  final now = clock.now();
  final tmpFiles = <String, (File, Duration)>{};
  final sidecars = <String, (File, Duration)>{};

  // Collect .tmp fragments and their identity sidecars (`.tmp.json`).
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final isTmp = name.endsWith('.tmp');
      if (!isTmp && !name.endsWith('.tmp.json')) continue;
      try {
        final stat = await entity.stat();
        final entry = (entity, now.difference(stat.modified));
        (isTmp ? tmpFiles : sidecars)[name] = entry;
      } catch (e) {
        _log.warning('TmpReaper: could not stat "$name": $e');
      }
    }
  } catch (e) {
    _log.warning('TmpReaper: could not list directory "$directory": $e');
    return;
  }

  final entries = <TmpDirEntry>[
    for (final MapEntry(key: name, value: (file, age)) in tmpFiles.entries)
      if (!isResumableFragment(file.path))
        TmpDirEntry(
          name: name,
          age: age,
          identified: sidecars.containsKey('$name.json'),
        ),
  ];

  // Normalise active paths to basenames for the pure-function comparison.
  final activeNames = activeDownloadPaths.map(p.basename).toSet();

  final toReap = reapReadyEntries(
    entries: entries,
    activeDownloadPaths: activeNames,
    ageThreshold: ageThreshold,
  );

  if (toReap.isNotEmpty) {
    _log.info('TmpReaper: found ${toReap.length} reap-ready .tmp fragment(s)');
  }
  for (final entry in toReap) {
    final file = tmpFiles[entry.name]?.$1;
    if (file == null) continue;
    try {
      await file.delete();
      tmpFiles.remove(entry.name);
      _log.info('TmpReaper: reaped orphan "${entry.name}"');
    } catch (e) {
      _log.warning('TmpReaper: could not delete "${entry.name}": $e');
    }
  }

  // A sidecar whose fragment is gone describes nothing any more. A fresh one
  // may belong to a download that has not written its first byte yet, so the
  // plain age rule applies.
  for (final MapEntry(key: name, value: (file, age)) in sidecars.entries) {
    final tmpName = name.substring(0, name.length - '.json'.length);
    if (tmpFiles.containsKey(tmpName)) continue;
    if (isResumableFragment(p.join(directory, tmpName))) continue;
    if (age <= ageThreshold) continue;
    try {
      await file.delete();
    } catch (e) {
      _log.warning('TmpReaper: could not delete "$name": $e');
    }
  }
}
