/// Journey 5: errors and recovery.
///
/// a) Dictation without a model: the pipeline's info toast names the problem
///    and offers the next step (download, or open Settings at the STT section).
/// b) Crash during a recording: a journal with its WAV left behind shows the
///    recovery banner on the history page; restore transcribes it into a
///    history entry, discard removes journal and audio.
/// c) Defective imports: a broken file lands in "failed" with a reason, and the
///    queue keeps running the jobs after it.
///
/// Real providers, real widgets and an in-memory Drift database. Fakes are used
/// only for STT, audio capture, model download and the transcriber. UI is
/// addressed by key only. Real file I/O runs inside `tester.runAsync`, and
/// [_until] polls for it with short real waits.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/history/data/providers.dart'
    show archivedEntriesProvider, historyEntriesProvider, trashEntriesProvider;
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/audio_import_panel.dart';
import 'package:whispaste/features/history/widgets/history_head.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/services/paste/paste_failure_notifier.dart';
import 'package:whispaste/services/paste/paster.dart' show PasteOutcome;
import 'package:whispaste/services/path_service.dart'
    show
        appDataDirOverride,
        retainedAudioDir,
        retainedAudioDirOverride,
        sttDirOverride;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/transcription/transcriber.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes: STT, audio capture, model download, transcriber, settings, keys.
// ---------------------------------------------------------------------------

class _FakeSttService extends SttServerStateNotifier {
  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning({bool warmup = true}) async {}

  @override
  Future<String> transcribeBytesWithProgress(
    List<int> wavBytes, {
    String? language,
    void Function(double fraction)? onProgress,
  }) async {
    return 'unused';
  }

  @override
  Future<void> prewarm() async {}
}

class _FakeAudioService extends AudioServiceNotifier {
  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  _FakeModelDownloadNotifier({required this.scanned});

  /// False until the initial disk scan has landed. Then no model counts as
  /// missing, so the toast falls back to "open Settings".
  final bool scanned;
  final List<String> downloads = [];

  @override
  ModelDownloadState build() =>
      ModelDownloadState(downloadedModels: const {}, scanned: scanned);

  @override
  Future<void> downloadModel(String modelId) async {
    downloads.add(modelId);
  }
}

class _FakeTranscriber implements Transcriber {
  _FakeTranscriber(this.transcript);

  final String transcript;
  int calls = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    calls++;
    return transcript;
  }

  @override
  void release() {}
}

class _FakeSettingsNotifier extends SettingsNotifier {
  static const _settings = AppSettings(
    afterTranscriptionSection: AfterTranscriptionSettings(
      afterTranscription: 'clipboard',
    ),
    onboarding: OnboardingSettings(onboardingCompleted: true),
    stt: SttSettings(model: 'whisper-small', language: 'English'),
  );

  @override
  Future<AppSettings> build() async => _settings;
}

/// The same settings with Parakeet as the on-device engine (UIA-MDL-GATE b).
class _FakeParakeetSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => _FakeSettingsNotifier._settings.copyWith(
    sttEngine: OnDeviceEngine.parakeet.value,
  );
}

/// Parakeet bundle downloader that records requests instead of fetching.
class _FakeParakeetDownloadNotifier extends ParakeetDownloadNotifier {
  int downloads = 0;

  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();

  @override
  Future<void> downloadBundle() async => downloads++;
}

class _FakeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> store = {};

  @override
  Future<String?> readKey(String key) async => store[key];

  @override
  Future<void> writeKey(String key, String value) async => store[key] = value;

  @override
  Future<void> deleteKey(String key) async => store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => Map.of(store);
}

// ---------------------------------------------------------------------------
// Fixtures and helpers.
// ---------------------------------------------------------------------------

late Directory _root;

String get _journalDir => p.join(_root.path, 'recordings', 'journal');

/// A valid 16 kHz mono 16-bit WAV with [frames] frames of silence.
Uint8List _wav({int frames = 1600, int sampleRate = 16000}) {
  final dataBytes = frames * 2;
  final view = ByteData(44 + dataBytes)
    ..setUint32(0, 0x46464952, Endian.little) // RIFF
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little) // WAVE
    ..setUint32(12, 0x20746d66, Endian.little) // 'fmt '
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little) // 'data'
    ..setUint32(40, dataBytes, Endian.little);
  return view.buffer.asUint8List();
}

File _writeFile(String name, List<int> bytes) {
  final file = File(p.join(_root.path, 'inputs', name));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return file;
}

/// Pumps [page] inside the real theme, localisations and a [ProviderScope]
/// with the shared fakes. Returns the scope's container for driving notifiers.
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required Widget page,
  required HistoryDatabase db,
  required _FakeModelDownloadNotifier modelDownload,
  required _FakeTranscriber transcriber,
  bool withRecordingBehavior = false,
  SettingsNotifier Function() settings = _FakeSettingsNotifier.new,
  List<Object> extra = const [],
}) async {
  // The toast sits at the bottom edge; the default 800x600 surface would put
  // its action button outside the hit-test bounds.
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      withRecordingBehavior ? WpRecordingBehavior(child: page) : page,
      locale: const Locale('en'),
      db: db,
      overrides: [
        settingsProvider.overrideWith(settings),
        secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore()),
        audioServiceProvider.overrideWith(_FakeAudioService.new),
        localSttBundleProvider.overrideWith(_FakeSttService.new),
        modelDownloadProvider.overrideWith(() => modelDownload),
        transcriberProvider.overrideWithValue(transcriber),
        historyEntriesProvider.overrideWith((ref) => Stream.value([])),
        archivedEntriesProvider.overrideWith((ref) => Stream.value([])),
        trashEntriesProvider.overrideWith((ref) => Stream.value([])),
        ...extra,
      ],
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

/// Polls until [condition] holds. Real file I/O and the queue's real work
/// complete between polls, so each poll yields to the real event loop once.
Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  String what = 'condition',
}) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(condition(), isTrue, reason: 'timed out waiting for $what');
}

bool _has(WidgetTester tester, Key key) =>
    find.byKey(key).evaluate().isNotEmpty;

/// The history head is one status line. Recovery rows show inline only once
/// the user opens the recovery section through its summary, so open it first.
Future<void> _openRecoveryRows(WidgetTester tester) async {
  const summary = ValueKey('history-recovery-summary');
  await _until(tester, () => _has(tester, summary), what: 'recovery summary');
  await tester.tap(find.byKey(summary));
  await tester.pump();
}

/// Drains the toast's auto-dismiss timer and disposes the tree, so no timer
/// outlives the test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Every test opens its own in-memory database and closes it on teardown.
  // Drift only warns that another instance was alive while a test's previous
  // database is still closing.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUp(() {
    // The pipeline's fire-and-forget review/support prompt checks read
    // SharedPreferences; without a backend getInstance fails and the error
    // can escape into the test zone, depending on timing.
    SharedPreferences.setMockInitialValues({});
    _root = Directory.systemTemp.createTempSync('wp40-errors-recovery-');
    appDataDirOverride = _root.path;
    sttDirOverride = p.join(_root.path, 'stt');
    retainedAudioDirOverride = p.join(_root.path, 'retained-audio');
  });

  tearDown(() {
    appDataDirOverride = null;
    sttDirOverride = null;
    retainedAudioDirOverride = null;
    try {
      _root.deleteSync(recursive: true);
    } on FileSystemException {
      // A job may still be cleaning its scratch folder; the temp root is
      // removed by the OS in that case.
    }
  });

  // =========================================================================
  // a) Model missing
  // =========================================================================

  group('a) dictation without a model', () {
    testWidgets('the message names the missing model and offers its download', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final download = _FakeModelDownloadNotifier(scanned: true);
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final container = await _pumpApp(
        tester,
        page: const SizedBox.shrink(),
        db: db,
        modelDownload: download,
        transcriber: _FakeTranscriber('unused'),
        withRecordingBehavior: true,
      );

      // The dictation attempt: the real orchestrator runs preflight, finds no
      // model file under the (empty) STT directory and raises the info code.
      await tester.runAsync(
        () => container
            .read(recordingOrchestratorProvider.notifier)
            .startRecording(),
      );
      await _until(
        tester,
        () => _has(tester, const ValueKey('toast-message')),
        what: 'model-missing toast',
      );

      final missing = container.read(missingSelectedSpeechModelProvider)!;
      final message = tester.widget<Text>(
        find.byKey(const ValueKey('toast-message')),
      );
      expect(message.data, l10n.infoModelMissingSelected(missing.sizeLabel));
      expect(_has(tester, const ValueKey('toast-action')), isTrue);
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      await tester.pump(
        const Duration(milliseconds: 400),
      ); // entrance animation
      await tester.tap(find.byKey(const ValueKey('toast-action')));
      await tester.pump();
      expect(download.downloads, ['whisper-small']);

      await _teardown(tester);
    });

    // UIA-MDL-GATE b: Parakeet without its bundle gets the same message and
    // the bundle download as its action, not a detour through Settings.
    testWidgets('a missing Parakeet bundle is named and offered for download', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final parakeet = _FakeParakeetDownloadNotifier();
      final download = _FakeModelDownloadNotifier(scanned: true);
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final container = await _pumpApp(
        tester,
        page: const SizedBox.shrink(),
        db: db,
        modelDownload: download,
        transcriber: _FakeTranscriber('unused'),
        withRecordingBehavior: true,
        settings: _FakeParakeetSettingsNotifier.new,
        extra: [parakeetDownloadProvider.overrideWith(() => parakeet)],
      );

      await tester.runAsync(
        () => container
            .read(recordingOrchestratorProvider.notifier)
            .startRecording(),
      );
      await _until(
        tester,
        () => _has(tester, const ValueKey('toast-message')),
        what: 'model-missing toast',
      );

      final missing = container.read(missingSelectedSpeechModelProvider)!;
      expect(missing.engine, SpeechModelEngine.parakeet);
      final message = tester.widget<Text>(
        find.byKey(const ValueKey('toast-message')),
      );
      expect(message.data, l10n.infoModelMissingSelected(missing.sizeLabel));
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('toast-action')));
      await tester.pump();
      expect(parakeet.downloads, 1);
      expect(download.downloads, isEmpty);

      await _teardown(tester);
    });

    testWidgets(
      'when the model status is not known yet, the action opens Settings at the STT section',
      (tester) async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final container = await _pumpApp(
          tester,
          page: const SizedBox.shrink(),
          db: db,
          modelDownload: _FakeModelDownloadNotifier(scanned: false),
          transcriber: _FakeTranscriber('unused'),
          withRecordingBehavior: true,
        );
        expect(container.read(activePageProvider), isNot('settings'));

        await tester.runAsync(
          () => container
              .read(recordingOrchestratorProvider.notifier)
              .startRecording(),
        );
        await _until(
          tester,
          () => _has(tester, const ValueKey('toast-action')),
          what: 'model-missing toast with settings action',
        );

        await tester.pump(
          const Duration(milliseconds: 400),
        ); // entrance animation
        await tester.tap(find.byKey(const ValueKey('toast-action')));
        await tester.pump();

        expect(container.read(activePageProvider), 'settings');
        // ticket: the model row, `stt` migrated to its row id (spec 07 §4).
        expect(container.read(settingsScrollTargetProvider), 'stt-model');
        await _teardown(tester);
      },
    );

    testWidgets(
      'inside the onboarding flow the missing model raises no toast and never '
      'leads out to Settings (UIA-RT-01)',
      (tester) async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final container = await _pumpApp(
          tester,
          page: const SizedBox.shrink(),
          db: db,
          modelDownload: _FakeModelDownloadNotifier(scanned: false),
          transcriber: _FakeTranscriber('unused'),
          withRecordingBehavior: true,
          extra: [onboardingSurfaceActiveProvider.overrideWithValue(true)],
        );

        await tester.runAsync(
          () => container
              .read(recordingOrchestratorProvider.notifier)
              .startRecording(),
        );
        // The onboarding page answers the cause itself, so the toast is
        // dropped and its event consumed (6e769fdac).
        await tester.pump();
        expect(_has(tester, const ValueKey('toast-message')), isFalse);
        expect(_has(tester, const ValueKey('toast-action')), isFalse);
        expect(container.read(recordingInfoProvider), isNull);
        expect(container.read(recordingProvider).phase, RecordingPhase.idle);
        expect(container.read(activePageProvider), isNot('settings'));
        await _teardown(tester);
      },
    );
  });

  // =========================================================================
  // b) Crash during a recording
  // =========================================================================

  group('b) recovery after a crash during a recording', () {
    /// Simulates the crash: the recorder wrote its journal entry and the WAV
    /// it was appending to, and the app died before `end()` removed the entry.
    Future<({String id, String wavPath})> leaveInterruptedRecording(
      WidgetTester tester,
    ) async {
      const id = 'crash-1';
      // With retention on, the recorder writes into the retained audio
      // folder, the only place recovery imports or deletes audio from.
      final wavPath = p.join(retainedAudioDir(), '$id.wav');
      File(wavPath)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(_wav(frames: 16000));
      await tester.runAsync(
        () => RecordingJournal(_journalDir).begin(
          id: id,
          startedAt: DateTime(2026, 10, 17, 9, 30),
          wavPath: wavPath,
        ),
      );
      return (id: id, wavPath: wavPath);
    }

    testWidgets('the history page offers the recovery banner', (tester) async {
      final crash = await leaveInterruptedRecording(tester);
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await _pumpApp(
        tester,
        page: const HistoryPage(),
        db: db,
        modelDownload: _FakeModelDownloadNotifier(scanned: true),
        transcriber: _FakeTranscriber('Recovered words'),
      );

      final row = ValueKey('recovery-row-${crash.id}');
      await _openRecoveryRows(tester);
      await _until(tester, () => _has(tester, row), what: 'recovery banner');
      expect(_has(tester, ValueKey('recovery-restore-${crash.id}')), isTrue);
      expect(_has(tester, ValueKey('recovery-discard-${crash.id}')), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'restore transcribes the audio into a history entry and clears journal and WAV',
      (tester) async {
        final crash = await leaveInterruptedRecording(tester);
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final transcriber = _FakeTranscriber('Recovered words');
        await _pumpApp(
          tester,
          page: const HistoryPage(),
          db: db,
          modelDownload: _FakeModelDownloadNotifier(scanned: true),
          transcriber: transcriber,
        );
        final row = ValueKey('recovery-row-${crash.id}');
        await _openRecoveryRows(tester);
        await _until(tester, () => _has(tester, row), what: 'recovery banner');

        await tester.tap(find.byKey(ValueKey('recovery-restore-${crash.id}')));
        await tester.pump();
        await _until(
          tester,
          () => !_has(tester, row),
          what: 'recovered row to leave the banner',
        );

        expect(transcriber.calls, 1);
        final entries = await tester.runAsync(db.allEntries) ?? [];
        expect(entries, hasLength(1));
        expect(entries.single.content, 'Recovered words');
        expect(entries.single.source, 'import');
        expect(File(crash.wavPath).existsSync(), isFalse);
        expect(File(_journalFile(crash.id)).existsSync(), isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets('discard removes journal and WAV without transcribing', (
      tester,
    ) async {
      final crash = await leaveInterruptedRecording(tester);
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final transcriber = _FakeTranscriber('must not appear');
      await _pumpApp(
        tester,
        page: const HistoryPage(),
        db: db,
        modelDownload: _FakeModelDownloadNotifier(scanned: true),
        transcriber: transcriber,
      );
      final row = ValueKey('recovery-row-${crash.id}');
      await _openRecoveryRows(tester);
      await _until(tester, () => _has(tester, row), what: 'recovery banner');

      await tester.tap(find.byKey(ValueKey('recovery-discard-${crash.id}')));
      await tester.pump();
      // Discarding is destructive and asks first (UIA-HIS-03).
      await _until(
        tester,
        () => _has(tester, const ValueKey('confirm-dialog-confirm')),
        what: 'discard confirmation',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
      await tester.pump();
      await _until(
        tester,
        () => !_has(tester, row),
        what: 'discarded row to leave the banner',
      );

      expect(transcriber.calls, 0);
      expect(await tester.runAsync(db.allEntries), isEmpty);
      expect(File(crash.wavPath).existsSync(), isFalse);
      expect(File(_journalFile(crash.id)).existsSync(), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  // =========================================================================
  // c) Defective imports
  // =========================================================================

  group('c) defective import', () {
    testWidgets(
      'broken files fail with a reason and the queue keeps running the next job',
      (tester) async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final transcriber = _FakeTranscriber('good transcript');
        final container = await _pumpApp(
          tester,
          page: const AudioImportPanel(),
          db: db,
          modelDownload: _FakeModelDownloadNotifier(scanned: true),
          transcriber: transcriber,
        );

        // Header cut off inside the fmt chunk: the decoder reports a
        // truncated fmt chunk.
        final cut = _writeFile('cut.wav', _wav().sublist(0, 20));
        // Not a RIFF file at all: the format sniffer rejects it.
        final notWav = _writeFile('not-a-wav.wav', List<int>.filled(64, 0x41));
        // A valid RIFF/WAVE header without any data chunk.
        final noData = _writeFile('no-data.wav', _wav().sublist(0, 36));
        // A valid file, queued between the broken ones.
        final good = _writeFile('good.wav', _wav(frames: 3200));

        final result = await tester.runAsync(
          () => container.read(audioImportQueueProvider.notifier).addFiles([
            cut.path,
            notWav.path,
            good.path,
            noData.path,
          ]),
        );
        await tester.pump();

        expect(result!.rejections, isEmpty);
        final jobs = {
          for (final job in container.read(audioImportQueueProvider))
            job.fileName: job,
        };
        expect(jobs['cut.wav']!.status, ImportStatus.failed);
        expect(jobs['cut.wav']!.failure, ImportFailure.decodeFailed);
        expect(jobs['not-a-wav.wav']!.status, ImportStatus.failed);
        expect(jobs['not-a-wav.wav']!.failure, ImportFailure.unsupportedFormat);
        expect(jobs['good.wav']!.status, ImportStatus.done);
        expect(jobs['no-data.wav']!.status, ImportStatus.failed);
        expect(jobs['no-data.wav']!.failure, ImportFailure.decodeFailed);
        expect(transcriber.calls, 1);

        // Job rows show inline only while the import section is expanded.
        container
            .read(historyHeadOpenProvider.notifier)
            .toggle(HistoryHeadSection.import);
        await tester.pump();

        // The first jobs show inline, the rest sit behind "show all"; a
        // failed one offers retry.
        final queue = container.read(audioImportQueueProvider);
        for (final job in queue.take(kHistoryInlineRows)) {
          expect(
            _has(tester, ValueKey('history-import-job-${job.id}')),
            isTrue,
          );
        }
        expect(queue.length, greaterThan(kHistoryInlineRows));
        expect(_has(tester, const ValueKey('history-import-show-all')), isTrue);
        final failedId = jobs['cut.wav']!.id;
        expect(
          _has(tester, ValueKey('history-import-retry-$failedId')),
          isTrue,
        );

        final entries = await tester.runAsync(db.allEntries) ?? [];
        expect(entries, hasLength(1));
        expect(entries.single.content, 'good transcript');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'a data chunk cut mid-stream is imported with the audio that is present',
      (tester) async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final container = await _pumpApp(
          tester,
          page: const AudioImportPanel(),
          db: db,
          modelDownload: _FakeModelDownloadNotifier(scanned: true),
          transcriber: _FakeTranscriber('partial transcript'),
        );

        // Declared 3200 data bytes, only 101 present (odd count, mid-sample).
        final bytes = _wav(frames: 1600).sublist(0, 44 + 101);
        final truncated = _writeFile('truncated-data.wav', bytes);

        await tester.runAsync(
          () => container.read(audioImportQueueProvider.notifier).addFiles([
            truncated.path,
          ]),
        );
        await tester.pump();

        final job = container.read(audioImportQueueProvider).single;
        expect(job.status, ImportStatus.done);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'an implausible sample rate fails the job instead of leaving it in decoding',
      (tester) async {
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final transcriber = _FakeTranscriber('after the bad header');
        final container = await _pumpApp(
          tester,
          page: const AudioImportPanel(),
          db: db,
          modelDownload: _FakeModelDownloadNotifier(scanned: true),
          transcriber: transcriber,
        );

        // Header claims 1 Hz, so resampling to 16 kHz needs ~64 GB.
        final absurdRate = _writeFile(
          'absurd-rate.wav',
          _wav(frames: 1000000, sampleRate: 1),
        );
        final good = _writeFile('good.wav', _wav(frames: 3200));

        await tester.runAsync(
          () => container.read(audioImportQueueProvider.notifier).addFiles([
            absurdRate.path,
            good.path,
          ]),
        );
        await tester.pump();

        final jobs = {
          for (final job in container.read(audioImportQueueProvider))
            job.fileName: job,
        };
        expect(jobs['absurd-rate.wav']!.status, ImportStatus.failed);
        expect(jobs['absurd-rate.wav']!.failure, ImportFailure.decodeFailed);
        expect(jobs['good.wav']!.status, ImportStatus.done);
        expect(transcriber.calls, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      // testWidgets takes a bool skip only, so the bug reason is in the name.
    );
  });

  // =========================================================================
  // e) Failed paste: the error toast keeps priority (XP-5-07)
  // =========================================================================

  group('e) failed paste after a transcription', () {
    Future<String?> runToEnd(WidgetTester tester, {required bool fail}) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final container = await _pumpApp(
        tester,
        page: const SizedBox.shrink(),
        db: db,
        modelDownload: _FakeModelDownloadNotifier(scanned: true),
        transcriber: _FakeTranscriber('unused'),
        withRecordingBehavior: true,
      );
      // The orchestrator's order: the paste failure is reported first, the
      // run is then completed with pasteFailed set.
      final recording = container.read(recordingProvider.notifier)
        ..startRecording()
        ..stopRecording();
      if (fail) {
        container
            .read(pasteFailureNotifierProvider.notifier)
            .report(PasteOutcome.failed);
      }
      await tester.pump();
      recording.completeTranscription('hello world', pasteFailed: fail);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final message = find.byKey(const ValueKey('toast-message'));
      return message.evaluate().isEmpty
          ? null
          : tester.widget<Text>(message).data;
    }

    // The 6 s paste toast starts its exit animation from a timer; give that
    // animation its own frame before the shared teardown disposes the tree.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(seconds: 1));
      await _teardown(tester);
    }

    testWidgets(
      'the paste error stays on screen, no "Transcription complete" over it',
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
      (tester) async {
        final l10n = await L10n.delegate.load(const Locale('en'));
        final message = await runToEnd(tester, fail: true);
        // The notice follows the platform target (a20a4da21, 134b6b548): with
        // the macOS variant it names ⌘V even on a Linux host. In the app the
        // target is the real OS, so the user always sees the key to press.
        expect(
          message,
          l10n.pasteFailureGeneric(pasteShortcutLabel(l10n: l10n)),
        );
        expect(find.textContaining(l10n.statusTranscriptionDone), findsNothing);
        await settle(tester);
      },
    );

    testWidgets(
      'a run that pasted still shows the success toast (control)',
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
      (tester) async {
        final l10n = await L10n.delegate.load(const Locale('en'));
        final message = await runToEnd(tester, fail: false);
        expect(message, startsWith(l10n.statusTranscriptionDone));
        await settle(tester);
      },
    );
  });
}

String _journalFile(String id) => p.join(_journalDir, '$id.json');
