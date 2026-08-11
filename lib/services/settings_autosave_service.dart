/// Autosicherung — the event-driven automatic backup of the portable
/// settings bundle (Ticket 26; decisions E11a–E11d).
///
/// Two collaborators live here, and neither of them can ever put anything on
/// screen:
///
/// * [SettingsAutosaveRunner] performs one backup — resolve the folder,
///   write a dated file, drop the oldest beyond [kAutosaveKeepCount].
/// * [SettingsAutosaveScheduler] decides *when* that happens: it collapses a
///   burst of changes into a single run ([kAutosaveDebounce]) and records the
///   outcome.
///
/// **H1 — a background run must never open a native file dialog.**
/// `SettingsPortabilityController`, the manual flow, answers every bookmark
/// failure by falling back to the `NSSavePanel`/`NSOpenPanel` flow. That is
/// right for a button the user just pressed and wrong here: the same fallback
/// on a timer means a save panel appearing over whatever the user is doing,
/// possibly mid-dictation, with no action of theirs behind it.
///
/// So this file has no dialog to fall back to. It does not import
/// `file_selector`, holds no [PickPathFn]-shaped seam, and an unresolvable
/// bookmark or an unreachable folder simply ends the run with
/// [SettingsAutosaveFailure.locationUnavailable]. The one place in the
/// feature that may open a directory dialog is
/// `settings_autosave_folder_chooser.dart`, which is reachable only from a
/// user gesture in the settings section — and
/// `test/services/settings_autosave_no_dialog_guard_test.dart` keeps the two
/// apart by scanning this file's source, so the guarantee survives a future
/// edit that "just needs a path here".
///
/// **The loop guard.** The scheduler writes its result back into
/// `AppSettings` — and `AppSettings` is one of the three sources that trigger
/// it. What breaks the circle is [autosaveTriggerSignature]: the trigger
/// compares the deny-list-filtered storage map, i.e. exactly the bytes that
/// would land in the backup file, and every `settings_autosave_*` key is on
/// [settingsPortabilityDenyList]. Recording a timestamp therefore changes
/// nothing the trigger can see. The same filter is what keeps window geometry
/// from scheduling a backup on every window drag.
library;

import 'dart:async';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import '../core/config/settings_provider.dart' show AppSettings;
import '../core/config/settings_sections.dart' show SettingsAutosaveSettings;
import '../core/logging/app_logger.dart';
import 'secure_bookmark_service.dart';
import 'settings_portability_service.dart';

final _log = AppLogger('SettingsAutosave');

// ---------------------------------------------------------------------------
// Tunables
// ---------------------------------------------------------------------------

/// How long the scheduler waits after the *last* change before writing
/// (decision E11b, debounce variant 1).
///
/// Four seconds sits above the pace of the bursts this must absorb — typing
/// in a replacement's trigger field, dragging a slider, pasting a snippet —
/// and below the point where a user who edits one setting and quits would
/// lose the run. Nothing is lost if it does not fire: the next change starts
/// the timer again, and the bundle is always gathered fresh at write time.
const Duration kAutosaveDebounce = Duration(seconds: 4);

/// How many dated backups the rotation folder keeps (decision E11c=b).
///
/// Five is enough that a bad state noticed a few edits late is still
/// recoverable, and small enough that the folder stays readable to a human
/// looking for the right file.
const int kAutosaveKeepCount = 5;

/// Filename prefix of a rotated autosave. Deliberately distinct from
/// [settingsExportFileName] so the automation can never be confused with —
/// or rotate away — a hand-made export that happens to share the folder.
const String kAutosaveFilePrefix = 'whispaste-settings-autosave-';

/// Matches exactly the files this feature writes, so rotation deletes only
/// its own output even when the user points it at a folder holding other
/// things.
final RegExp kAutosaveFilePattern = RegExp(
  '^${RegExp.escape(kAutosaveFilePrefix)}\\d{8}-\\d{6}\\.json\$',
);

/// The name for a backup taken at [at] — `…-20260811-140322.json`.
///
/// Local time, not UTC: the folder is something a person opens in Finder or
/// Explorer when they need the file from "yesterday evening", and a UTC stamp
/// there reads as the wrong evening. Ordering stays lexicographic, which is
/// what rotation sorts on; the one hour a year where a DST fall-back makes
/// two stamps compare out of order can at worst rotate two same-hour files in
/// the wrong order, never a file from another day.
String autosaveFileName(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  final d =
      '${at.year}${two(at.month)}${two(at.day)}'
      '-${two(at.hour)}${two(at.minute)}${two(at.second)}';
  return '$kAutosaveFilePrefix$d.json';
}

// ---------------------------------------------------------------------------
// Outcome
// ---------------------------------------------------------------------------

/// Gathers the current bundle from live app state — see
/// [SettingsAutosaveRunner.gather] for why this is not the controller's
/// identically-shaped `GatherBundleFn`.
typedef AutosaveGatherFn = Future<SettingsExportBundle> Function();

/// Why a run did not produce a file. Kept as an enum rather than a message
/// so the localized wording lives in the ARB files with everything else.
enum SettingsAutosaveFailure {
  /// No folder configured, its bookmark could not be resolved, or the
  /// sandbox refused access. The run ends here — this is the case that must
  /// never turn into a dialog (H1).
  locationUnavailable,

  /// The folder was reachable but gathering or writing the bundle threw.
  writeFailed,
}

/// The result of one [SettingsAutosaveRunner.run] call.
class SettingsAutosaveOutcome {
  const SettingsAutosaveOutcome._({
    required this.at,
    this.writtenPath,
    this.failure,
    this.detail,
    this.resolvedFolder,
    this.refreshedBookmark,
  });

  factory SettingsAutosaveOutcome.written({
    required String path,
    required DateTime at,
    String? resolvedFolder,
    String? refreshedBookmark,
  }) => SettingsAutosaveOutcome._(
    at: at,
    writtenPath: path,
    resolvedFolder: resolvedFolder,
    refreshedBookmark: refreshedBookmark,
  );

  factory SettingsAutosaveOutcome.failed({
    required SettingsAutosaveFailure failure,
    required DateTime at,
    String? detail,
  }) => SettingsAutosaveOutcome._(at: at, failure: failure, detail: detail);

  /// When the run finished — the value persisted as the last success/failure.
  final DateTime at;

  final String? writtenPath;
  final SettingsAutosaveFailure? failure;

  /// Human-readable error text for the toast, when [failure] carries one.
  final String? detail;

  /// Set when the bookmark resolved to a different directory than the one
  /// stored (the user moved or renamed it) — the caller persists it so the
  /// section keeps showing where backups actually land.
  final String? resolvedFolder;

  /// Set when a stale bookmark was successfully recreated during this run.
  final String? refreshedBookmark;

  bool get ok => failure == null;
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

/// Performs one autosave: resolve, write, rotate. Holds no state and knows
/// nothing about settings persistence — it takes a configuration and returns
/// what happened, so the scheduler owns every write-back.
class SettingsAutosaveRunner {
  SettingsAutosaveRunner({
    required this.gather,
    FileSystem fileSystem = const LocalFileSystem(),
    SettingsPortabilityService? service,
    this.bookmarks = const SecureBookmarkService(),
    this.now = DateTime.now,
    this.keep = kAutosaveKeepCount,
  }) : _fileSystem = fileSystem,
       service = service ?? SettingsPortabilityService(fileSystem: fileSystem);

  /// Gathers the bundle to write.
  ///
  /// Structurally identical to `GatherBundleFn` in
  /// `settings_portability_controller.dart` and deliberately *not* that
  /// typedef: importing the controller would put `file_selector` one
  /// resolvable symbol away from this file, and H1 is worth more than a
  /// deduplicated four-word type alias.
  final AutosaveGatherFn gather;

  final FileSystem _fileSystem;
  final SettingsPortabilityService service;
  final SecureBookmarkService bookmarks;
  final DateTime Function() now;
  final int keep;

  /// Writes one backup for [config].
  ///
  /// Never prompts. A folder that cannot be reached — no bookmark where one
  /// is required, a bookmark that no longer resolves, access refused — ends
  /// the run with [SettingsAutosaveFailure.locationUnavailable] and leaves
  /// the configuration untouched, so the user's chosen folder is still there
  /// when the drive is plugged back in. (The manual flow *forgets* an
  /// unusable path at this point, because it can immediately ask for a new
  /// one. This one cannot ask, and silently discarding the setting would
  /// leave a switch that is on with nowhere to write.)
  Future<SettingsAutosaveOutcome> run(SettingsAutosaveSettings config) async {
    if (config.folder.isEmpty) {
      return SettingsAutosaveOutcome.failed(
        failure: SettingsAutosaveFailure.locationUnavailable,
        at: now(),
      );
    }

    var folder = config.folder;
    String? resolvedFolder;
    String? refreshedBookmark;
    var session = '';

    if (bookmarks.isSupported && config.bookmark.isNotEmpty) {
      final resolution = await bookmarks.resolve(config.bookmark);
      if (resolution == null) {
        _log.warning('autosave: bookmark no longer resolves — run skipped');
        return SettingsAutosaveOutcome.failed(
          failure: SettingsAutosaveFailure.locationUnavailable,
          at: now(),
        );
      }
      if (!await bookmarks.startAccess(config.bookmark)) {
        _log.warning('autosave: sandbox refused access — run skipped');
        return SettingsAutosaveOutcome.failed(
          failure: SettingsAutosaveFailure.locationUnavailable,
          at: now(),
        );
      }
      session = config.bookmark;
      if (resolution.path != folder) {
        folder = resolution.path;
        resolvedFolder = resolution.path;
      }
      if (resolution.isStale) {
        // Best effort: a stale bookmark still resolved and still granted
        // access, so the run proceeds either way. Failing to recreate it
        // only means the next run tries the old blob again.
        refreshedBookmark = await bookmarks.create(resolution.path);
      }
    }

    try {
      final bundle = await gather();
      final at = now();
      final path = p.join(folder, autosaveFileName(at));
      await service.exportToFile(path, bundle);
      await _rotate(folder);
      return SettingsAutosaveOutcome.written(
        path: path,
        at: at,
        resolvedFolder: resolvedFolder,
        refreshedBookmark: refreshedBookmark,
      );
    } catch (e) {
      _log.warning('autosave: write failed: $e');
      return SettingsAutosaveOutcome.failed(
        failure: SettingsAutosaveFailure.writeFailed,
        at: now(),
        detail: _message(e),
      );
    } finally {
      if (session.isNotEmpty) await bookmarks.stopAccess(session);
    }
  }

  /// Keeps the [keep] newest autosaves in [folder] and deletes the rest.
  ///
  /// Deliberately swallows its own failures: the backup is already on disk
  /// at this point, and a folder that refuses a delete is not a reason to
  /// report the run as failed and toast the user. The only cost of a failed
  /// rotation is a folder that grows.
  Future<void> _rotate(String folder) async {
    try {
      final dir = _fileSystem.directory(folder);
      if (!await dir.exists()) return;
      final mine = <String>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (kAutosaveFilePattern.hasMatch(name)) mine.add(entity.path);
      }
      if (mine.length <= keep) return;
      // Names are fixed-width and time-ordered, so sorting them sorts by age.
      mine.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
      for (final stale in mine.take(mine.length - keep)) {
        await _fileSystem.file(stale).delete();
      }
    } catch (e) {
      _log.debug('autosave: rotation skipped (non-fatal): $e');
    }
  }

  static String _message(Object error) {
    if (error is SettingsImportFormatException) return error.message;
    final s = error.toString();
    const prefix = 'Exception: ';
    return s.startsWith(prefix) ? s.substring(prefix.length) : s;
  }
}

// ---------------------------------------------------------------------------
// Scheduler
// ---------------------------------------------------------------------------

/// Reads the current autosave configuration.
typedef AutosaveConfigGetterFn = SettingsAutosaveSettings Function();

/// Persists a change to the autosave section only.
typedef AutosaveConfigSetterFn =
    Future<void> Function(
      SettingsAutosaveSettings Function(SettingsAutosaveSettings current),
    );

/// Reports a failed run to the user (decision E11d: every failure toasts).
typedef AutosaveFailureReporterFn =
    void Function(SettingsAutosaveFailure failure, String? detail);

/// Collapses change events into runs and records their outcome.
///
/// The trigger is purely event-driven (decision E11a=b): there is no periodic
/// timer and no catch-up check at startup. The only clock involved is the
/// debounce, and it is always started by a change that just happened.
class SettingsAutosaveScheduler {
  SettingsAutosaveScheduler({
    required this.runner,
    required this.readConfig,
    required this.writeConfig,
    required this.reportFailure,
    this.debounce = kAutosaveDebounce,
  });

  final SettingsAutosaveRunner runner;
  final AutosaveConfigGetterFn readConfig;
  final AutosaveConfigSetterFn writeConfig;
  final AutosaveFailureReporterFn reportFailure;
  final Duration debounce;

  Timer? _timer;
  bool _running = false;
  bool _rerunRequested = false;
  bool _disposed = false;

  /// Test seam: completes with the run currently in flight, or immediately
  /// when idle. Lets a test await the effect of [scheduleRun]/[runNow]
  /// without sleeping on wall-clock guesses.
  Future<void> get settled => _inFlight ?? Future<void>.value();
  Future<void>? _inFlight;

  /// One of the three bundle sources changed — write once, a debounce after
  /// the last of them (decision E11b).
  void scheduleRun() {
    if (_disposed || !readConfig().enabled) return;
    _timer?.cancel();
    _timer = Timer(debounce, runNow);
  }

  /// Runs without waiting out the debounce. Used when the user turns the
  /// feature on: they just asked for backups, so the first one happens now
  /// rather than after their next unrelated edit — and if the folder they
  /// picked does not work, they find out while they are still looking at the
  /// switch they flipped.
  ///
  /// This is not an interval catch-up (H2, deleted with decision E11a=b):
  /// nothing here compares elapsed time against a schedule, and nothing runs
  /// at app start.
  void runNow() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (!readConfig().enabled) return;
    if (_running) {
      // A change that landed mid-write is not covered by the file being
      // written, so ask for one more pass afterwards.
      _rerunRequested = true;
      return;
    }
    _running = true;
    _inFlight = _run().whenComplete(() {
      _running = false;
      if (_rerunRequested && !_disposed) {
        _rerunRequested = false;
        scheduleRun();
      }
    });
  }

  Future<void> _run() async {
    final config = readConfig();
    if (!config.enabled) return;
    final outcome = await runner.run(config);
    final stamp = outcome.at.toUtc().toIso8601String();

    await writeConfig((current) {
      // A run takes as long as a file write, and the user can point the
      // feature somewhere else during it. The corrections this run
      // discovered describe the location it *started* from, so they may only
      // be written back if that is still the configured one — otherwise a
      // folder resolved from the old bookmark would silently overwrite the
      // one just chosen in the panel.
      final sameLocation =
          current.folder == config.folder &&
          current.bookmark == config.bookmark;
      return current.copyWith(
        folder: sameLocation ? outcome.resolvedFolder : null,
        bookmark: sameLocation ? outcome.refreshedBookmark : null,
        lastSuccess: outcome.ok ? stamp : null,
        // A success clears the previous failure; a failure leaves the last
        // success standing, so the status line can say both "last good
        // backup was at X" and "the most recent attempt failed".
        lastError: outcome.ok ? '' : stamp,
      );
    });

    if (!outcome.ok) {
      reportFailure(outcome.failure!, outcome.detail);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

// ---------------------------------------------------------------------------
// Trigger signature
// ---------------------------------------------------------------------------

/// The part of [settings] a backup would actually contain, as one comparable
/// string.
///
/// Two settings objects with equal signatures produce byte-identical
/// `settings` sections in the export file, so a change between them is not
/// worth a backup. This is what makes the feature safe to hang off
/// `settingsProvider` at all: it filters out both the autosave feature's own
/// bookkeeping (which would otherwise re-trigger itself forever) and the
/// machine-bound keys that change constantly on their own — window geometry
/// alone emits on every drag of the window edge.
/// Whether a settings transition is a *user arming the feature* rather than
/// a change worth backing up — turning it on, or pointing it at a different
/// folder while on. Both deserve a backup straight away: the user just asked
/// for backups, and if the folder they picked does not work they should learn
/// it now, not at some unrelated moment hours later.
///
/// [previous] being `null` means the provider is hydrating, not that anything
/// happened, and returns `false` — an already-enabled installation must not
/// back up on launch. That would be the interval catch-up (H2) that decision
/// E11a=b deleted along with intervals themselves.
bool autosaveNeedsImmediateRun(
  SettingsAutosaveSettings? previous,
  SettingsAutosaveSettings next,
) {
  if (previous == null || !next.enabled) return false;
  return !previous.enabled || previous.folder != next.folder;
}

/// Fingerprint of exactly those settings a backup file would contain.
///
/// This is the loop guard. The scheduler writes its own result back into
/// [AppSettings], which is itself a trigger source; because every
/// `settings_autosave_*` key is on [settingsPortabilityDenyList], recording a
/// run leaves this signature untouched and cannot schedule the next one.
/// Window geometry is filtered out for the same reason, so dragging a window
/// no longer counts as a settings change worth backing up.
String autosaveTriggerSignature(AppSettings settings) {
  final entries =
      settings
          .toStorageMap()
          .entries
          .where((e) => !settingsPortabilityDenyList.contains(e.key))
          .map((e) => '${e.key}=${e.value}')
          .toList()
        ..sort();
  // Separator: a literal NUL escape, because it cannot occur inside a
  // settings key or value and therefore cannot forge a signature match.
  // Written as an escape on purpose — a raw NUL byte in the source makes
  // git and grep treat this file as binary.
  return entries.join('\x00');
}
