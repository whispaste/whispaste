/// Tests for the Autosicherung service (Ticket 26 of `ui-overhaul`).
///
/// Three things are load-bearing here and each has its own group:
///
/// * **H1** — a background run must never reach a native file dialog. The
///   runner's collaborator set has no dialog seam to inject at all, so the
///   assertion that stands in for "the fake `PickPathFn` was never called" is
///   that an unresolvable bookmark *ends the run* instead of escalating:
///   nothing written, nothing forgotten, a reported failure. The structural
///   half of the same promise — that this code cannot acquire a dialog later
///   — lives in `settings_autosave_no_dialog_guard_test.dart`, and the
///   end-to-end half (enabling the feature never touches the export picker)
///   in `test/features/settings/settings_portability_section_test.dart`.
/// * **Rotation** (decision E11c=b) — five dated files, oldest out, and
///   nothing that is not this feature's own output ever deleted.
/// * **Debounce** (decision E11b) — a burst of changes is one write.
///
/// Everything runs against a `MemoryFileSystem` and a fake bookmark service,
/// so no platform channel and no real disk is involved.
library;

import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/secure_bookmark_service.dart';
import 'package:whispaste/services/settings_autosave_service.dart';
import 'package:whispaste/services/settings_portability_service.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Bookmark service under full test control. Defaults to the Windows/Linux
/// shape (unsupported), which is also the "no bookmark involved" case.
class _FakeBookmarks extends SecureBookmarkService {
  _FakeBookmarks({
    this.supported = false,
    this.accessGranted = true,
    this.created = 'fresh-bookmark',
  });

  final bool supported;
  BookmarkResolution? resolution;
  bool accessGranted;
  String? created;

  int startAccessCalls = 0;
  int stopAccessCalls = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<BookmarkResolution?> resolve(String bookmark) async => resolution;

  @override
  Future<bool> startAccess(String bookmark) async {
    startAccessCalls++;
    return accessGranted;
  }

  @override
  Future<void> stopAccess(String bookmark) async => stopAccessCalls++;

  @override
  Future<String?> create(String path) async => created;
}

const _bundle = SettingsExportBundle(
  settings: {'theme_mode': 'dark'},
  replacements: [],
);

MemoryFileSystem _fs() => MemoryFileSystem.test();

SettingsAutosaveSettings _config({
  bool enabled = true,
  String folder = '/backups',
  String bookmark = '',
  String lastSuccess = '',
  String lastError = '',
}) => SettingsAutosaveSettings(
  enabled: enabled,
  folder: folder,
  bookmark: bookmark,
  lastSuccess: lastSuccess,
  lastError: lastError,
);

/// A runner whose `run` is scripted, for the scheduler group.
class _ScriptedRunner extends SettingsAutosaveRunner {
  _ScriptedRunner({this.outcome, this.onRun})
    : super(gather: () async => _bundle);

  SettingsAutosaveOutcome? outcome;

  /// Fires while the run is "in flight", i.e. after the scheduler has read
  /// the config but before it writes the outcome back. Lets a test act like
  /// a user who re-points the feature mid-run.
  final void Function()? onRun;
  int calls = 0;
  final List<SettingsAutosaveSettings> seen = [];

  @override
  Future<SettingsAutosaveOutcome> run(SettingsAutosaveSettings config) async {
    calls++;
    seen.add(config);
    onRun?.call();
    return outcome ??
        SettingsAutosaveOutcome.written(
          path: '/backups/x.json',
          at: DateTime.utc(2026, 8, 11, 12),
        );
  }
}

void main() {
  group('SettingsAutosaveRunner — writing', () {
    test('writes one dated file into the configured folder', () async {
      final fs = _fs();
      final runner = SettingsAutosaveRunner(
        gather: () async => _bundle,
        fileSystem: fs,
        bookmarks: _FakeBookmarks(),
        now: () => DateTime(2026, 8, 11, 14, 3, 22),
      );

      final outcome = await runner.run(_config());

      expect(outcome.ok, isTrue);
      expect(
        p.basename(outcome.writtenPath!),
        'whispaste-settings-autosave-20260811-140322.json',
      );
      expect(await fs.file(outcome.writtenPath!).exists(), isTrue);
      // The file is a real export, not a placeholder — same encoder, same
      // format version, and the deny list still applied at the boundary.
      final written = await fs.file(outcome.writtenPath!).readAsString();
      expect(written, contains('"format_version": 2'));
      expect(written, contains('theme_mode'));
    });

    test('carries no autosave bookkeeping into the file — the deny list '
        'holds at the writing boundary', () async {
      final fs = _fs();
      final runner = SettingsAutosaveRunner(
        gather: () async => SettingsExportBundle(
          settings: AppSettings.defaults
              .copyWithSections(autosave: _config(folder: '/secret-folder'))
              .toStorageMap(),
          replacements: const [],
        ),
        fileSystem: fs,
        bookmarks: _FakeBookmarks(),
        now: () => DateTime(2026, 8, 11, 14, 3, 22),
      );

      final outcome = await runner.run(_config());
      final written = await fs.file(outcome.writtenPath!).readAsString();

      for (final key in [
        'settings_autosave_enabled',
        'settings_autosave_folder',
        'settings_autosave_bookmark',
        'settings_autosave_last_success',
        'settings_autosave_last_error',
      ]) {
        expect(written, isNot(contains(key)), reason: '$key must not travel');
      }
      expect(written, isNot(contains('secret-folder')));
    });

    test('a throwing gather is reported as a write failure, not a crash', () {
      final runner = SettingsAutosaveRunner(
        gather: () async => throw Exception('database locked'),
        fileSystem: _fs(),
        bookmarks: _FakeBookmarks(),
      );

      return runner.run(_config()).then((outcome) {
        expect(outcome.ok, isFalse);
        expect(outcome.failure, SettingsAutosaveFailure.writeFailed);
        expect(outcome.detail, 'database locked');
      });
    });
  });

  group('SettingsAutosaveRunner — rotation (E11c=b)', () {
    Future<List<String>> namesIn(MemoryFileSystem fs, String folder) async {
      final entries = await fs.directory(folder).list().toList();
      return entries.map((e) => p.basename(e.path)).toList()..sort();
    }

    test('keeps the newest five and drops the oldest', () async {
      final fs = _fs();
      var minute = 0;
      final runner = SettingsAutosaveRunner(
        gather: () async => _bundle,
        fileSystem: fs,
        bookmarks: _FakeBookmarks(),
        now: () => DateTime(2026, 8, 11, 9, minute),
      );

      for (var i = 0; i < 7; i++) {
        minute = i;
        await runner.run(_config());
      }

      final names = await namesIn(fs, '/backups');
      expect(names, hasLength(kAutosaveKeepCount));
      expect(names.first, 'whispaste-settings-autosave-20260811-090200.json');
      expect(names.last, 'whispaste-settings-autosave-20260811-090600.json');
    });

    test('never deletes anything it did not write', () async {
      final fs = _fs();
      await fs.directory('/backups').create(recursive: true);
      await fs
          .file('/backups/whispaste-settings-export.json')
          .writeAsString('{}');
      await fs.file('/backups/holiday-photos.txt').writeAsString('x');

      var minute = 0;
      final runner = SettingsAutosaveRunner(
        gather: () async => _bundle,
        fileSystem: fs,
        bookmarks: _FakeBookmarks(),
        now: () => DateTime(2026, 8, 11, 9, minute),
      );
      for (var i = 0; i < 8; i++) {
        minute = i;
        await runner.run(_config());
      }

      final names = await namesIn(fs, '/backups');
      expect(names, contains('whispaste-settings-export.json'));
      expect(names, contains('holiday-photos.txt'));
      expect(
        names.where((n) => n.startsWith(kAutosaveFilePrefix)),
        hasLength(kAutosaveKeepCount),
      );
    });
  });

  group('SettingsAutosaveRunner — H1: a run never escalates to a dialog', () {
    test('an unresolvable bookmark ends the run and writes nothing', () async {
      final fs = _fs();
      final bookmarks = _FakeBookmarks(supported: true);
      final runner = SettingsAutosaveRunner(
        gather: () async =>
            fail('the bundle must not even be gathered for a dead location'),
        fileSystem: fs,
        bookmarks: bookmarks,
        now: () => DateTime(2026, 8, 11, 14),
      );

      final config = _config(bookmark: 'stored-bookmark');
      final outcome = await runner.run(config);

      expect(outcome.ok, isFalse);
      expect(outcome.failure, SettingsAutosaveFailure.locationUnavailable);
      expect(await fs.directory('/backups').exists(), isFalse);
      // The remembered location survives: unlike the manual flow, this one
      // cannot ask for a replacement, so forgetting it would leave a switch
      // that is on with nowhere to write. An unplugged drive comes back.
      expect(outcome.resolvedFolder, isNull);
      expect(bookmarks.startAccessCalls, 0);
    });

    test('a refused access session ends the run and is balanced', () async {
      final bookmarks = _FakeBookmarks(supported: true, accessGranted: false)
        ..resolution = const BookmarkResolution(
          path: '/backups',
          isStale: false,
        );
      final runner = SettingsAutosaveRunner(
        gather: () async => fail('no bundle without access'),
        fileSystem: _fs(),
        bookmarks: bookmarks,
      );

      final outcome = await runner.run(_config(bookmark: 'stored'));

      expect(outcome.failure, SettingsAutosaveFailure.locationUnavailable);
      expect(bookmarks.startAccessCalls, 1);
      expect(
        bookmarks.stopAccessCalls,
        0,
        reason: 'a session that never started must not be stopped',
      );
    });

    test('a folder that was never chosen fails instead of asking', () async {
      final runner = SettingsAutosaveRunner(
        gather: () async => fail('nothing to gather without a destination'),
        fileSystem: _fs(),
        bookmarks: _FakeBookmarks(),
      );

      final outcome = await runner.run(_config(folder: ''));

      expect(outcome.failure, SettingsAutosaveFailure.locationUnavailable);
    });
  });

  group('SettingsAutosaveRunner — bookmark upkeep', () {
    test('a moved folder is followed and reported back', () async {
      final fs = _fs();
      final bookmarks = _FakeBookmarks(supported: true)
        ..resolution = const BookmarkResolution(
          path: '/moved-backups',
          isStale: false,
        );
      final runner = SettingsAutosaveRunner(
        gather: () async => _bundle,
        fileSystem: fs,
        bookmarks: bookmarks,
        now: () => DateTime(2026, 8, 11, 14),
      );

      final outcome = await runner.run(_config(bookmark: 'stored'));

      expect(outcome.ok, isTrue);
      expect(p.dirname(outcome.writtenPath!), '/moved-backups');
      expect(outcome.resolvedFolder, '/moved-backups');
      expect(
        bookmarks.stopAccessCalls,
        1,
        reason: 'every started session is balanced, success or not',
      );
    });

    test('a stale bookmark is recreated and reported back', () async {
      final bookmarks = _FakeBookmarks(
        supported: true,
        created: 'renewed',
      )..resolution = const BookmarkResolution(path: '/backups', isStale: true);
      final runner = SettingsAutosaveRunner(
        gather: () async => _bundle,
        fileSystem: _fs(),
        bookmarks: bookmarks,
        now: () => DateTime(2026, 8, 11, 14),
      );

      final outcome = await runner.run(_config(bookmark: 'stored'));

      expect(outcome.ok, isTrue);
      expect(outcome.refreshedBookmark, 'renewed');
    });
  });

  group('SettingsAutosaveScheduler — debounce (E11b)', () {
    ({
      SettingsAutosaveScheduler scheduler,
      _ScriptedRunner runner,
      List<SettingsAutosaveSettings> writes,
      List<SettingsAutosaveFailure> failures,
    })
    build({
      SettingsAutosaveSettings? config,
      SettingsAutosaveOutcome? outcome,
      Duration debounce = const Duration(milliseconds: 20),
    }) {
      var current = config ?? _config();
      final writes = <SettingsAutosaveSettings>[];
      final failures = <SettingsAutosaveFailure>[];
      final runner = _ScriptedRunner(outcome: outcome);
      final scheduler = SettingsAutosaveScheduler(
        runner: runner,
        readConfig: () => current,
        writeConfig: (update) async {
          current = update(current);
          writes.add(current);
        },
        reportFailure: (failure, _) => failures.add(failure),
        debounce: debounce,
      );
      return (
        scheduler: scheduler,
        runner: runner,
        writes: writes,
        failures: failures,
      );
    }

    test('six rapid changes produce exactly one write', () async {
      final h = build();
      addTearDown(h.scheduler.dispose);

      for (var i = 0; i < 6; i++) {
        h.scheduler.scheduleRun();
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await h.scheduler.settled;

      expect(h.runner.calls, 1);
    });

    test('a change after the debounce elapsed starts a second run', () async {
      final h = build();
      addTearDown(h.scheduler.dispose);

      h.scheduler.scheduleRun();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await h.scheduler.settled;
      h.scheduler.scheduleRun();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await h.scheduler.settled;

      expect(h.runner.calls, 2);
    });

    test('nothing runs while the feature is off', () async {
      final h = build(config: _config(enabled: false));
      addTearDown(h.scheduler.dispose);

      h.scheduler.scheduleRun();
      h.scheduler.runNow();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(h.runner.calls, 0);
    });

    test('runNow does not wait out the debounce', () async {
      final h = build(debounce: const Duration(seconds: 30));
      addTearDown(h.scheduler.dispose);

      h.scheduler.runNow();
      await h.scheduler.settled;

      expect(h.runner.calls, 1);
    });

    test('a disposed scheduler stops scheduling', () async {
      final h = build();
      h.scheduler.dispose();

      h.scheduler.scheduleRun();
      h.scheduler.runNow();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(h.runner.calls, 0);
    });
  });

  group('SettingsAutosaveScheduler — recording the outcome (E11d)', () {
    test(
      'success stamps the time, clears the failure, and says nothing',
      () async {
        var current = _config(lastError: '2026-08-10T09:00:00.000Z');
        final failures = <SettingsAutosaveFailure>[];
        final scheduler = SettingsAutosaveScheduler(
          runner: _ScriptedRunner(
            outcome: SettingsAutosaveOutcome.written(
              path: '/backups/a.json',
              at: DateTime.utc(2026, 8, 11, 12, 30),
            ),
          ),
          readConfig: () => current,
          writeConfig: (update) async => current = update(current),
          reportFailure: (failure, _) => failures.add(failure),
        );
        addTearDown(scheduler.dispose);

        scheduler.runNow();
        await scheduler.settled;

        expect(current.lastSuccess, '2026-08-11T12:30:00.000Z');
        expect(current.lastError, isEmpty);
        expect(
          failures,
          isEmpty,
          reason: 'a successful backup must not interrupt anyone',
        );
      },
    );

    test('every failure toasts and keeps the last good timestamp', () async {
      var current = _config(lastSuccess: '2026-08-10T09:00:00.000Z');
      final failures = <SettingsAutosaveFailure>[];
      final scheduler = SettingsAutosaveScheduler(
        runner: _ScriptedRunner(
          outcome: SettingsAutosaveOutcome.failed(
            failure: SettingsAutosaveFailure.locationUnavailable,
            at: DateTime.utc(2026, 8, 11, 12, 30),
          ),
        ),
        readConfig: () => current,
        writeConfig: (update) async => current = update(current),
        reportFailure: (failure, _) => failures.add(failure),
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);

      scheduler.runNow();
      await scheduler.settled;
      scheduler.runNow();
      await scheduler.settled;

      // Decision E11d takes the literal reading: *every* failed run reports,
      // not only a repeated one. The cost is that an unreachable folder plus
      // a long editing session means one toast per debounce window — a
      // maintainer decision, not an oversight.
      expect(failures, hasLength(2));
      expect(current.lastError, '2026-08-11T12:30:00.000Z');
      expect(
        current.lastSuccess,
        '2026-08-10T09:00:00.000Z',
        reason: 'a failure must not erase the last backup that did work',
      );
    });

    test('a folder chosen mid-run survives the write-back', () async {
      var current = _config(folder: '/old', bookmark: 'old-mark');
      final scheduler = SettingsAutosaveScheduler(
        runner: _ScriptedRunner(
          // The run started on /old and resolved its bookmark to a moved
          // location — a correction that is only true for /old.
          outcome: SettingsAutosaveOutcome.written(
            path: '/old-moved/whispaste-settings-autosave-20260811-120000.json',
            at: DateTime.utc(2026, 8, 11, 12),
            resolvedFolder: '/old-moved',
            refreshedBookmark: 'old-mark-v2',
          ),
          // ...but while it ran, the user picked a different folder in the
          // panel. A write takes real time; this race is reachable.
          onRun: () => current = current.copyWith(
            folder: '/user-picked',
            bookmark: 'picked-mark',
          ),
        ),
        readConfig: () => current,
        writeConfig: (update) async => current = update(current),
        reportFailure: (_, _) {},
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);

      scheduler.runNow();
      await scheduler.settled;

      expect(
        current.folder,
        '/user-picked',
        reason: 'the stale correction must not overwrite a fresher choice',
      );
      expect(current.bookmark, 'picked-mark');
      // The run itself did happen, so its timestamp is still recorded — only
      // the location fields are withheld.
      expect(current.lastSuccess, '2026-08-11T12:00:00.000Z');
    });
  });

  group('Trigger', () {
    test('the signature ignores everything a backup would not contain', () {
      final base = AppSettings.defaults;
      final withAutosaveState = base.copyWithSections(
        autosave: _config(lastSuccess: '2026-08-11T12:00:00.000Z'),
      );
      final withGeometry = base.copyWithSections(
        windowPosition: base.windowPosition.copyWith(windowX: 512),
      );
      final withRealChange = base.copyWithSections(
        interface_: base.interface_.copyWith(locale: 'he'),
      );

      // This is the loop guard: recording a run must be invisible to the
      // thing that starts runs.
      expect(
        autosaveTriggerSignature(withAutosaveState),
        autosaveTriggerSignature(base),
      );
      expect(
        autosaveTriggerSignature(withGeometry),
        autosaveTriggerSignature(base),
      );
      expect(
        autosaveTriggerSignature(withRealChange),
        isNot(autosaveTriggerSignature(base)),
      );
    });

    test('only arming the feature runs immediately — never a launch', () {
      const off = SettingsAutosaveSettings();
      const on = SettingsAutosaveSettings(enabled: true, folder: '/backups');
      const moved = SettingsAutosaveSettings(enabled: true, folder: '/other');

      expect(autosaveNeedsImmediateRun(off, on), isTrue);
      expect(autosaveNeedsImmediateRun(on, moved), isTrue);
      expect(autosaveNeedsImmediateRun(on, on), isFalse);
      expect(autosaveNeedsImmediateRun(on, off), isFalse);
      // Hydration: H2 (catch up at startup) was deleted with the interval
      // trigger, so an already-enabled installation must not back up on
      // launch.
      expect(autosaveNeedsImmediateRun(null, on), isFalse);
    });
  });
}
