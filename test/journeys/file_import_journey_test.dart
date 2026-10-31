/// Journey 4, file transcription: a short WAV goes from the history page's
/// "Add files" button through the import queue (status by status, on the
/// real provider state) to a history entry, is reviewed in the detail panel,
/// and is exported through the format picker and the save dialog.
///
/// Real: the import providers and queue, the WAV decoder, the Drift database
/// (in memory), the history page, the detail panel and the export flow.
/// Fake: the STT engine, the open and save dialogs (file_selector channel),
/// the app-data locations, and the recording state (no dictation runs).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/history_head.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/path_service.dart'
    show appDataDirOverride, retainedAudioDirOverride;
import 'package:whispaste/services/transcription/transcriber.dart';

import '../fixtures/test_helpers.dart';

const _fileSelectorChannel = MethodChannel('plugins.flutter.io/file_selector');
const _transcript = 'Hallo Welt aus der Datei';

/// 0.5 s of a 440 Hz sine, 16 kHz mono 16-bit, written as a real WAV file.
Future<String> _writeSineWav(Directory dir, String name) async {
  const frames = 8000;
  final pcm = Int16List(frames);
  for (var i = 0; i < frames; i++) {
    pcm[i] = (8000 * math.sin(2 * math.pi * 440 * i / 16000)).round();
  }
  final bytes = encodePcm16MonoWav(pcm);
  final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
  return file.path;
}

/// Replaces the STT engine. A non-null [hold] keeps the next transcription
/// open until the test completes it, so the job stays in its transcribing
/// state while the test interacts with it.
class _FakeTranscriber implements Transcriber {
  Completer<void>? hold;
  int calls = 0;
  final List<int> wavLengths = [];

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    calls++;
    wavLengths.add(wavBytes.length);
    final gate = hold;
    if (gate != null) await gate.future;
    return _transcript;
  }

  @override
  void release() {}
}

class _FakeRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings({this.saveHistory = true});

  final bool saveHistory;

  @override
  Future<AppSettings> build() async {
    const settings = AppSettings();
    return settings.copyWithSections(
      history: settings.history.copyWith(saveHistory: saveHistory),
    );
  }
}

/// Answers the next `openFile` call of the file dialog with [picks], and any
/// `getSavePath` call (the export save dialog) with [savePath].
void _queuePicks(List<List<String>> picks, {String? savePath}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_fileSelectorChannel, (call) async {
        if (call.method == 'getSavePath') return savePath;
        if (call.method != 'openFile') return null;
        return picks.removeAt(0);
      });
}

/// Lets real file IO and database streams progress until [done] holds.
///
/// Each round yields a few real milliseconds, so the bound is wall-clock time
/// rather than a number of event-loop turns: how many turns the file IO needs
/// depends on the host platform and its load. [describe] adds state to the
/// failure message.
Future<void> _settle(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  String Function()? describe,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    // Advances the fake clock, so animations (the detail split) finish too.
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!done()) {
    final state = describe == null ? '' : ' (${describe()})';
    fail('timed out waiting for: $what$state');
  }
}

/// Plays one event of the desktop_drop plugin's native side, as the file
/// manager drag would. Locations are window coordinates.
Future<void> _dropEvent(WidgetTester tester, String method, Object args) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
  await tester.pump();
}

void main() {
  late Directory tmp;
  late Directory exportDir;
  late Directory inputs;
  late _FakeTranscriber transcriber;
  late ProviderContainer container;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp40-file-import-');
    exportDir = Directory('${tmp.path}/exportDir')..createSync();
    inputs = Directory('${tmp.path}/inputs')..createSync();
    appDataDirOverride = '${tmp.path}/appdata';
    retainedAudioDirOverride = '${tmp.path}/retained';
    transcriber = _FakeTranscriber();
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_fileSelectorChannel, null);
    appDataDirOverride = null;
    retainedAudioDirOverride = null;
    await tmp.delete(recursive: true);
  });

  Future<void> mountHistory(
    WidgetTester tester,
    HistoryDatabase db, {
    bool saveHistory = true,
  }) async {
    // Desktop-sized surface, so the split detail and its popup menu fit.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        const HistoryPage(),
        db: db,
        locale: const Locale('en'),
        overrides: [
          transcriberProvider.overrideWithValue(transcriber),
          recordingProvider.overrideWith(_FakeRecording.new),
          settingsProvider.overrideWith(
            () => _FakeSettings(saveHistory: saveHistory),
          ),
        ],
      ),
    );
    await tester.pump();
    container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryPage)),
    );
    // Job rows show inline only while the import section is expanded.
    container
        .read(historyHeadOpenProvider.notifier)
        .toggle(HistoryHeadSection.import);
    await tester.pump();
  }

  List<ImportJob> jobs() => container.read(audioImportQueueProvider);

  /// Job states for a timeout message, e.g. `memo.wav: decoding`.
  String jobState() => jobs().isEmpty
      ? 'no jobs'
      : jobs()
            .map(
              (j) =>
                  '${j.fileName}: ${j.status.name}'
                  '${j.failure == null ? '' : ' / ${j.failure!.name}'}',
            )
            .join(', ');

  /// Tears the page down and lets drift's stream cleanup timers run out, so
  /// no timer is still pending when the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Status of the job for [fileName], or null while it is not enqueued yet.
  ImportStatus? statusOf(String fileName) {
    for (final j in jobs()) {
      if (j.fileName == fileName) return j.status;
    }
    return null;
  }

  String idOf(String fileName) =>
      jobs().singleWhere((j) => j.fileName == fileName).id;

  testWidgets(
    'import runs through every status to a history entry, which exports',
    (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final wav = await _writeSineWav(inputs, 'memo.wav');
      _queuePicks([
        [wav],
      ], savePath: '${exportDir.path}/export.txt');
      await mountHistory(tester, db);

      // Record each distinct status the job passes through, in order.
      final seen = <ImportStatus>[];
      container.listen<List<ImportJob>>(audioImportQueueProvider, (_, next) {
        if (next.isEmpty) return;
        final status = next.last.status;
        if (seen.isEmpty || seen.last != status) seen.add(status);
      });

      expect(find.byKey(const ValueKey('history-import-add')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-import-add')));
      await tester.pump();

      await _settle(
        tester,
        () => jobs().isNotEmpty && jobs().single.status == ImportStatus.done,
        describe: jobState,
        what: 'import job reaches done',
      );
      final job = jobs().single;
      expect(seen, [
        ImportStatus.queued,
        ImportStatus.copying,
        ImportStatus.decoding,
        ImportStatus.transcribing,
        ImportStatus.done,
      ]);
      expect(job.failure, isNull);
      expect(job.entryId, isNotNull);
      await tester.pump();
      expect(
        find.byKey(ValueKey('history-import-job-${job.id}')),
        findsOneWidget,
      );
      // The decoder fed the engine a 16 kHz WAV of the fixture length (0.5 s).
      expect(transcriber.calls, 1);
      expect(transcriber.wavLengths.single, greaterThan(44));

      // Result: one history entry with the transcript and the import source.
      final entry = (await tester.runAsync(() => db.getEntry(job.entryId!)))!;
      expect(entry.content, _transcript);
      expect(entry.source, 'import');
      expect(entry.durationSec, closeTo(0.5, 0.001));
      expect(entry.title, isNotEmpty);

      // Review: the entry appears in the list and its detail shows the text.
      await _settle(
        tester,
        () => find.byKey(ValueKey(job.entryId!)).evaluate().isNotEmpty,
        what: 'imported entry is listed',
      );
      await tester.tap(find.byKey(ValueKey(job.entryId!)).first);
      await _settle(
        tester,
        () => find
            .byKey(const ValueKey('history-detail-menu'))
            .evaluate()
            .isNotEmpty,
        what: 'detail panel shows its menu',
      );
      expect(find.text(_transcript), findsWidgets);

      // Export: the detail menu's export item opens the format picker; the
      // chosen txt file lands in the export folder with the transcript.
      await tester.tap(find.byKey(const ValueKey('history-detail-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('history-detail-menu-export')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('export-format-txt')));
      await tester.pump(const Duration(milliseconds: 300));

      await _settle(
        tester,
        () => exportDir.listSync().whereType<File>().any(
          (f) => f.path.endsWith('.txt'),
        ),
        what: 'txt export written to the export folder',
      );
      final exported = exportDir.listSync().whereType<File>().singleWhere(
        (f) => f.path.endsWith('.txt'),
      );
      expect(exported.readAsStringSync(), contains(_transcript));

      await unmount(tester);
    },
  );

  // "Save recordings" covers dictations only; an import is an explicit
  // request for a history entry and keeps creating one.
  testWidgets('an import creates its entry while saving recordings is off', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final wav = await _writeSineWav(inputs, 'memo.wav');
    _queuePicks([
      [wav],
    ]);
    await mountHistory(tester, db, saveHistory: false);

    await tester.tap(find.byKey(const ValueKey('history-import-add')));
    await tester.pump();
    await _settle(
      tester,
      () => jobs().isNotEmpty && jobs().single.status == ImportStatus.done,
      describe: jobState,
      what: 'import job reaches done',
    );
    final job = jobs().single;
    expect(job.failure, isNull);
    expect(job.entryId, isNotNull);
    final entry = (await tester.runAsync(() => db.getEntry(job.entryId!)))!;
    expect(entry.content, _transcript);
    expect(entry.source, 'import');

    await unmount(tester);
  });

  testWidgets('a file added while another transcribes waits in the queue', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final first = await _writeSineWav(inputs, 'first.wav');
    final second = await _writeSineWav(inputs, 'second.wav');
    _queuePicks([
      [first],
      [second],
    ]);
    await mountHistory(tester, db);

    transcriber.hold = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('history-import-add')));
    await tester.pump();
    await _settle(
      tester,
      () => transcriber.calls == 1,
      what: 'first job reaches the engine',
    );

    await tester.tap(find.byKey(const ValueKey('history-import-add')));
    await tester.pump();
    await _settle(
      tester,
      () => jobs().length == 2,
      describe: jobState,
      what: 'second job is listed',
    );
    expect(statusOf('second.wav'), ImportStatus.queued);
    expect(transcriber.calls, 1, reason: 'one transcription at a time');

    transcriber.hold!.complete();
    transcriber.hold = null;
    await _settle(
      tester,
      () => jobs().every((j) => j.status == ImportStatus.done),
      describe: jobState,
      what: 'both jobs done',
    );
    expect(transcriber.calls, 2);
    final entries = (await tester.runAsync(() => db.allEntries()))!;
    expect(entries.where((e) => e.source == 'import'), hasLength(2));

    await unmount(tester);
  });

  testWidgets('cancelling a running job drops its result and keeps retry', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final wav = await _writeSineWav(inputs, 'cancel-me.wav');
    _queuePicks([
      [wav],
    ]);
    await mountHistory(tester, db);

    transcriber.hold = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('history-import-add')));
    await tester.pump();
    await _settle(
      tester,
      () => transcriber.calls == 1,
      what: 'job reaches the engine',
    );
    final id = jobs().single.id;

    await tester.tap(find.byKey(ValueKey('history-import-cancel-$id')));
    await tester.pump();
    transcriber.hold!.complete();
    transcriber.hold = null;

    await _settle(
      tester,
      () => jobs().single.status == ImportStatus.cancelled,
      describe: jobState,
      what: 'job is cancelled',
    );
    expect(jobs().single.entryId, isNull);
    expect(find.byKey(ValueKey('history-import-retry-$id')), findsOneWidget);
    expect(find.byKey(ValueKey('history-import-cancel-$id')), findsNothing);
    final entries = (await tester.runAsync(() => db.allEntries()))!;
    expect(entries.where((e) => e.source == 'import'), isEmpty);

    await unmount(tester);
  });

  testWidgets('folders and missing files are rejected with a message', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final folder = Directory('${inputs.path}/a-folder')..createSync();
    _queuePicks([
      [folder.path, '${inputs.path}/gone.wav'],
    ]);
    await mountHistory(tester, db);

    await tester.tap(find.byKey(const ValueKey('history-import-add')));
    await tester.pump();
    await _settle(
      tester,
      () =>
          find
              .byKey(const ValueKey('history-import-rejection'))
              .evaluate()
              .length ==
          2,
      what: 'two rejection messages',
    );
    expect(jobs(), isEmpty);
    expect(transcriber.calls, 0);

    await unmount(tester);
  });

  // Imported history entries can be taken over as a Notiz from the detail
  // panel (history-detail-take-as-note).
  testWidgets('import can be taken over as a Notiz', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final wav = await _writeSineWav(inputs, 'to-note.wav');
    _queuePicks([
      [wav],
    ]);
    await mountHistory(tester, db);
    await tester.tap(find.byKey(const ValueKey('history-import-add')));
    await tester.pump();
    await _settle(
      tester,
      () => jobs().isNotEmpty && jobs().single.status == ImportStatus.done,
      describe: jobState,
      what: 'job done',
    );
    await tester.tap(find.byKey(ValueKey(jobs().single.entryId!)).first);
    await _settle(
      tester,
      () => find
          .byKey(const ValueKey('history-detail-take-as-note'))
          .evaluate()
          .isNotEmpty,
      what: 'detail panel offers take-as-note',
    );
    await tester.tap(find.byKey(const ValueKey('history-detail-take-as-note')));
    await tester.pump();
    var notes = <Note>[];
    for (var i = 0; i < 100 && notes.isEmpty; i++) {
      notes = (await tester.runAsync(() => db.select(db.notes).get()))!;
      if (notes.isEmpty) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
    }
    expect(notes.map((n) => n.content), contains(_transcript));
    await tester.pump();
    final l10n = L10n.of(tester.element(find.byType(HistoryPage)));
    expect(find.text(l10n.historyTakenAsNote), findsOneWidget);
    expect(find.text(l10n.historyOpenNote), findsOneWidget);
    // The actionable toast lasts at least 10 s (WCAG 2.2.1).
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  // Was a bug until WP-43a: cancel() dropped the source path, so the retry
  // of a job that never started failed with copyFailed.
  testWidgets('retry after cancelling a queued job completes it', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final first = await _writeSineWav(inputs, 'a.wav');
    final second = await _writeSineWav(inputs, 'b.wav');
    _queuePicks([
      [first, second],
    ]);
    await mountHistory(tester, db);

    transcriber.hold = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('history-import-add')));
    await tester.pump();
    await _settle(
      tester,
      () => statusOf('a.wav') == ImportStatus.transcribing,
      describe: jobState,
      what: 'first job transcribes',
    );
    final queuedId = idOf('b.wav');
    await tester.tap(find.byKey(ValueKey('history-import-cancel-$queuedId')));
    await tester.pump();
    expect(statusOf('b.wav'), ImportStatus.cancelled);

    transcriber.hold!.complete();
    transcriber.hold = null;
    await _settle(
      tester,
      () => statusOf('a.wav') == ImportStatus.done,
      describe: jobState,
      what: 'first job done',
    );

    await tester.tap(find.byKey(ValueKey('history-import-retry-$queuedId')));
    await tester.pump();
    await _settle(
      tester,
      () => statusOf('b.wav') == ImportStatus.done,
      describe: jobState,
      what: 'retried job done',
    );
    expect(jobs().singleWhere((j) => j.fileName == 'b.wav').failure, isNull);
    await unmount(tester);
  });

  // XP-5-12: files dragged from the file manager onto the history page take
  // the same path as "Add files".
  group('drag and drop', () {
    const dropZone = ValueKey('history-import-drop-zone');
    const inside = [640.0, 400.0];

    testWidgets('a dropped WAV is imported, another file type is refused', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final wav = await _writeSineWav(inputs, 'memo.wav');
      final text = File('${inputs.path}/notes.txt')..writeAsStringSync('x');
      await mountHistory(tester, db);

      expect(find.byKey(dropZone), findsNothing);
      await _dropEvent(tester, 'entered', inside);
      expect(find.byKey(dropZone), findsOneWidget);
      expect(
        find.text(
          L10n.of(
            tester.element(find.byType(HistoryPage)),
          ).historyImportDropHere,
        ),
        findsOneWidget,
      );

      await _dropEvent(tester, 'performOperation', [wav, text.path]);
      expect(find.byKey(dropZone), findsNothing);
      await _settle(
        tester,
        () => statusOf('memo.wav') == ImportStatus.done,
        describe: jobState,
        what: 'dropped WAV is imported',
      );
      expect(jobs().map((j) => j.fileName), ['memo.wav']);
      expect(transcriber.calls, 1);
      await tester.pump();
      final refused = find.byKey(const ValueKey('history-import-rejection'));
      expect(refused, findsOneWidget);
      expect(
        tester.widget<Text>(refused).data,
        startsWith('notes.txt: This file type cannot be imported.'),
      );

      await unmount(tester);
    });

    testWidgets('a drag that leaves again imports nothing', (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await mountHistory(tester, db);

      await _dropEvent(tester, 'entered', inside);
      expect(find.byKey(dropZone), findsOneWidget);
      await _dropEvent(tester, 'exited', inside);
      expect(find.byKey(dropZone), findsNothing);
      expect(jobs(), isEmpty);

      await unmount(tester);
    });

    testWidgets('a dropped folder gets the folder message', (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final folder = Directory('${inputs.path}/a-folder')..createSync();
      await mountHistory(tester, db);

      await _dropEvent(tester, 'entered', inside);
      await _dropEvent(tester, 'performOperation', [folder.path]);
      await _settle(
        tester,
        () => find
            .byKey(const ValueKey('history-import-rejection'))
            .evaluate()
            .isNotEmpty,
        what: 'folder rejection message',
      );
      expect(jobs(), isEmpty);

      await unmount(tester);
    });
  });
}
