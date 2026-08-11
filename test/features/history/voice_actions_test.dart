/// Voice action tests — parser edge cases, VoiceNoteButton widget tests,
/// and integration flow tests (record → transcribe → dispatch).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
// SttServerState is re-exported from stt_bundle.dart.
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/widgets/voice_note_button.dart';
import 'package:whispaste/widgets/wp_voice_input_button.dart';
import 'package:whispaste/features/history/data/history_detail_provider.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/voice_action_service.dart';

// ---------------------------------------------------------------------------
// Fakes (mirrors recording_orchestrator_test.dart patterns)
// ---------------------------------------------------------------------------

class _FakeAudioService extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

  @override
  Future<void> startRecording() async {
    if (errorOnStart) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'mic_error',
      );
      return;
    }
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPathToReturn,
    );
  }

  @override
  Future<String?> stopRecording() async {
    state = AudioStatus(filePath: wavPathToReturn);
    return wavPathToReturn;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeSttService extends SttServerStateNotifier {
  String transcriptToReturn = 'Hello world';
  bool ensureRunningThrows = false;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning() async {
    if (ensureRunningThrows) {
      throw Exception('STT server failed to start');
    }
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    return transcriptToReturn;
  }

  @override
  Future<void> prewarm() async {}
}

/// Fake [WhisperEngine] — drives the real [SttServerStateNotifier] (no
/// notifier override) so the voice-note pipeline is verified against the
/// actual FFI engine seam (Issue 06), not a stand-in notifier.
///
/// `hangOnLoad`/`hangOnTranscribe` never complete, letting
/// [VoiceNoteButton]'s own 30 s/45 s `.timeout()` guards fire — used to
/// anchor the stuck-guard regression coverage.
class _FakeWhisperEngine implements WhisperEngine {
  _FakeWhisperEngine({
    this.transcriptToReturn = 'tag as engine-verified',
    this.hangOnLoad = false,
    this.hangOnTranscribe = false,
  });

  final String transcriptToReturn;
  final bool hangOnLoad;
  final bool hangOnTranscribe;

  bool _loaded = false;
  int loadCallCount = 0;
  int transcribeCallCount = 0;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    loadCallCount++;
    if (hangOnLoad) {
      await Completer<void>().future; // never completes
    }
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
  }) async {
    transcribeCallCount++;
    // SttServerStateNotifier._warmupInference() fires an untimed transcribe()
    // call as part of ensureRunning() (call #1) before the real
    // transcribeBytes() call (call #2+). Hanging only from the 2nd call
    // onward isolates the transcribeBytes() stuck-guard in tests without
    // also blocking ensureRunning() on the warmup.
    if (hangOnTranscribe && transcribeCallCount > 1) {
      await Completer<void>().future; // never completes
    }
    return transcriptToReturn;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Writes a minimum-size (>10 MiB) fake GGML model file so the real
/// [SttServerStateNotifier]'s corrupt-model guard does not short-circuit
/// [WhisperEngine.load] before the fake engine is ever reached. Mirrors
/// `test/services/stt/stt_server_state_notifier_test.dart`'s helper.
Future<Directory> _createFakeSttDir({String modelId = 'whisper-small'}) async {
  final dir = await Directory.systemTemp.createTemp('voice_note_engine_test_');
  final modelFilename =
      findSttModel(modelId)?.filename ?? 'ggml-small-q5_1.bin';
  await File(
    '${dir.path}/$modelFilename',
  ).writeAsBytes(Uint8List(11 * 1024 * 1024));
  paths.sttDirOverride = dir.path;
  return dir;
}

/// Wraps a [VoiceNoteButton] with the real [localSttBundleProvider]
/// (`SttServerStateNotifier`) driven by a fake [WhisperEngine] injected via
/// [whisperEngineProvider] — the actual FFI engine seam, as opposed to
/// [_makeTestableButton]'s [_FakeSttService] notifier stand-in.
Widget _makeTestableButtonViaEngine({
  required String entryId,
  required HistoryDatabase db,
  required _FakeAudioService fakeAudio,
  required WhisperEngine engine,
}) {
  final theme = wpDarkTheme();
  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      audioServiceProvider.overrideWith(() => fakeAudio),
      whisperEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(
        () => _FakeSettingsNotifier(
          AppSettings.defaults.copyWith(sttModel: 'whisper-small'),
        ),
      ),
      modelDownloadProvider.overrideWith(() => _FakeModelDownloadNotifier()),
      hw.gpuInfoProvider.overrideWith(
        (_) async =>
            const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(historyDetailProvider(entryId));
              return VoiceNoteButton(entryId: entryId);
            },
          ),
        ),
      ),
    ),
  );
}

/// Wraps a [VoiceNoteButton] in a testable widget tree with all required
/// providers, localization, and theme.
///
/// A [Consumer] watches [historyDetailProvider] to pre-warm it — otherwise
/// the async build hasn't completed by the time the voice-action pipeline
/// dispatches to the notifier.
Widget _makeTestableButton({
  required String entryId,
  required HistoryDatabase db,
  required _FakeAudioService fakeAudio,
  required _FakeSttService fakeStt,
  bool isDark = true,
}) {
  final theme = isDark ? wpDarkTheme() : wpLightTheme();
  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      audioServiceProvider.overrideWith(() => fakeAudio),
      localSttBundleProvider.overrideWith(() => fakeStt),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      // Pin the locale so the error-toast assertion below matches the
      // English ARB entry regardless of the CI host's system language.
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) {
              // Pre-warm the detail provider so it's loaded before dispatch.
              ref.watch(historyDetailProvider(entryId));
              return VoiceNoteButton(entryId: entryId);
            },
          ),
        ),
      ),
    ),
  );
}

// ===========================================================================
// Tests
// ===========================================================================

late L10n l10n;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  // =========================================================================
  // 1. Parser edge cases (supplements existing 20 tests)
  // =========================================================================

  group('parseVoiceAction — edge cases', () {
    // ── Mixed-case prefixes ──────────────────────────────────────────────

    test('detects "TAG AS" all-caps prefix', () {
      final result = parseVoiceAction('TAG AS review');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'review');
    });

    test('detects "tAg aS" weird-case prefix', () {
      final result = parseVoiceAction('tAg aS random');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'random');
    });

    test('detects "TAG:" upper-case colon prefix', () {
      final result = parseVoiceAction('TAG:priority');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'priority');
    });

    test('detects "CORRECT:" all-caps prefix', () {
      final result = parseVoiceAction('CORRECT: Fixed text here');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Fixed text here');
    });

    test('detects "cOrReCt:" mixed-case prefix', () {
      final result = parseVoiceAction('cOrReCt: Something else');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Something else');
    });

    test('detects "KORREKTUR:" all-caps German prefix', () {
      final result = parseVoiceAction('KORREKTUR: Neuer Text');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Neuer Text');
    });

    test('detects "Korrektur:" title-case German prefix', () {
      final result = parseVoiceAction('Korrektur: Bearbeiteter Inhalt');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Bearbeiteter Inhalt');
    });

    // ── Unicode content after prefix ─────────────────────────────────────

    test('tag with Unicode emoji payload', () {
      final result = parseVoiceAction('tag as 🏷️ important');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, '🏷️ important');
    });

    test('correction with CJK characters', () {
      final result = parseVoiceAction('correct: 修正されたテキスト');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, '修正されたテキスト');
    });

    test('tag with German umlauts', () {
      final result = parseVoiceAction('tag as Büroarbeit');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'Büroarbeit');
    });

    test('korrektur with German umlauts in payload', () {
      final result = parseVoiceAction('korrektur: Ärger über Änderungen für Ü');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'Ärger über Änderungen für Ü');
    });

    test('note with Arabic script', () {
      final result = parseVoiceAction('مرحبا بالعالم');
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'مرحبا بالعالم');
    });

    // ── Very long input ──────────────────────────────────────────────────

    test('handles very long note input', () {
      final longText = 'a' * 10000;
      final result = parseVoiceAction(longText);
      expect(result!.type, VoiceActionType.note);
      expect(result.payload.length, 10000);
    });

    test('handles very long tag payload', () {
      final longTag = 'b' * 5000;
      final result = parseVoiceAction('tag as $longTag');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload.length, 5000);
    });

    test('handles very long correction payload', () {
      final longCorrection = 'c' * 5000;
      final result = parseVoiceAction('correct: $longCorrection');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload.length, 5000);
    });

    // ── Only first prefix should match ───────────────────────────────────

    test('tag prefix takes priority even with correction text inside', () {
      final result = parseVoiceAction('tag as correct: value');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'correct: value');
    });

    test('tag prefix takes priority even with korrektur text inside', () {
      final result = parseVoiceAction('tag as korrektur: something');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'korrektur: something');
    });

    test('correction payload may contain "tag as" without affecting type', () {
      final result = parseVoiceAction('correct: please tag as important later');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'please tag as important later');
    });

    test('note starting with "tag" but not "tag as " or "tag:" is note', () {
      final result = parseVoiceAction('tagging along for the ride');
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'tagging along for the ride');
    });

    test('"tag a" without trailing "s " is a note, not a tag', () {
      final result = parseVoiceAction('tag a new item');
      expect(result!.type, VoiceActionType.note);
    });

    test('"correct" without colon is a note', () {
      final result = parseVoiceAction('correct me if I am wrong');
      expect(result!.type, VoiceActionType.note);
    });

    test('"korrektur" without colon is a note', () {
      final result = parseVoiceAction('korrektur ist wichtig');
      expect(result!.type, VoiceActionType.note);
    });

    // ── Whitespace handling ──────────────────────────────────────────────

    test('tag with extra spaces between prefix and payload', () {
      final result = parseVoiceAction('tag as    spaced');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'spaced');
    });

    test('correction with extra leading spaces on payload', () {
      final result = parseVoiceAction('correct:     padded text');
      expect(result!.type, VoiceActionType.correction);
      expect(result.payload, 'padded text');
    });

    test('leading/trailing whitespace stripped before prefix matching', () {
      final result = parseVoiceAction('   tag as trimmed   ');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'trimmed');
    });

    // ── Newlines and special whitespace ───────────────────────────────────

    test('tag payload preserves internal newlines', () {
      final result = parseVoiceAction('tag as line1\nline2');
      expect(result!.type, VoiceActionType.tag);
      expect(result.payload, 'line1\nline2');
    });

    test('note with tab characters is preserved', () {
      final result = parseVoiceAction('item\tone\ttwo');
      expect(result!.type, VoiceActionType.note);
      expect(result.payload, 'item\tone\ttwo');
    });
  });

  // =========================================================================
  // 2. VoiceNoteButton widget tests
  // =========================================================================

  group('VoiceNoteButton', () {
    late HistoryDatabase db;
    late _FakeAudioService fakeAudio;
    late _FakeSttService fakeStt;
    const entryId = 'voice-btn-test-1';

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      fakeAudio = _FakeAudioService();
      fakeStt = _FakeSttService();

      // Seed an entry so HistoryDetailNotifier can load it.
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: entryId,
          timestamp: DateTime(2025, 7, 1, 12, 0),
          content: const Value('Original transcript'),
          title: const Value('Test Entry'),
          model: const Value('whisper-small'),
          isLocal: const Value(true),
          durationSec: const Value(5.0),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('renders mic icon in idle state', (tester) async {
      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Should find the mic icon.
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);

      // Should have a tooltip.
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('renders InkWell that is tappable', (tester) async {
      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNotNull);
    });

    testWidgets('shows stop icon after tap starts recording', (tester) async {
      fakeAudio.wavPathToReturn = 'fake_path.wav';

      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial mic icon.
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);

      // Tap to start recording.
      await tester.tap(find.byType(InkWell));
      await tester.pump();

      // Should now show the stop (square) icon.
      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.byIcon(LucideIcons.mic), findsNothing);
    });

    testWidgets('shows error state and returns to idle on mic error', (
      tester,
    ) async {
      fakeAudio.errorOnStart = true;

      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Tap to try recording — error on start.
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should show a WpToast error message (overlay-based, not SnackBar).
      expect(find.text(l10n.voiceNoteError), findsOneWidget);

      // Should return to idle (mic icon).
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);

      // Drain the WpToast auto-dismiss timer + animation controller.
      // Timeline: Future.delayed(3s) → controller.reverse(200ms) → dispose
      await tester.pump(const Duration(seconds: 3)); // fires Future.delayed
      await tester.pump(const Duration(milliseconds: 300)); // reverse completes
      await tester.pump(); // .then() callback disposes
    });

    testWidgets('does not start when main recording is active', (tester) async {
      // Simulate main dictation already recording.
      fakeAudio = _FakeAudioService();

      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
        ),
      );
      await tester.pumpAndSettle();

      // Manually set recording phase to recording (simulating main dictation).
      // VoiceNoteButton guards via recordingOrchestratorProvider.currentPhase
      // which reads recordingProvider — so we drive that directly.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VoiceNoteButton)),
      );
      container.read(recordingProvider.notifier).startRecording();
      await tester.pump();

      // Tap — should be ignored since orchestrator phase is recording.
      await tester.tap(find.byType(InkWell));
      await tester.pump();

      // Should still show mic icon (idle).
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    });

    testWidgets('renders correctly in light mode', (tester) async {
      await tester.pumpWidget(
        _makeTestableButton(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          fakeStt: fakeStt,
          isDark: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    });
  });

  // =========================================================================
  // 2b. VoiceNoteButton via the real FFI engine seam (Issue 06)
  //
  // Complements the group above: those tests fake the whole
  // SttServerStateNotifier (_FakeSttService), bypassing the engine seam
  // entirely. These tests drive the real notifier with a fake WhisperEngine
  // injected via whisperEngineProvider — anchoring that the voice-note
  // pipeline transcribes through the FFI engine, not a subprocess.
  // =========================================================================

  group('VoiceNoteButton — via FFI engine seam (Issue 06)', () {
    late HistoryDatabase db;
    late _FakeAudioService fakeAudio;
    late Directory sttDir;
    late Directory wavDir;
    late String wavPath;
    const entryId = 'voice-btn-engine-1';

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: entryId,
          timestamp: DateTime(2025, 7, 1, 12, 0),
          content: const Value('Original transcript'),
          title: const Value('Test Entry'),
          model: const Value('whisper-small'),
          isLocal: const Value(true),
          durationSec: const Value(5.0),
        ),
      );

      sttDir = await _createFakeSttDir();

      // A real, valid WAV file — VoiceNoteButton reads it off disk and its
      // pipeline pre-flight-rejects payloads without a RIFF/WAVE header, so
      // the fake audio path must point at an actual well-formed WAV.
      // Reuses SttBenchmark's own WAV generator rather than hand-rolling one.
      wavDir = await Directory.systemTemp.createTemp('voice_note_wav_test_');
      wavPath = '${wavDir.path}/note.wav';
      await File(wavPath).writeAsBytes(SttBenchmark.generateBenchmarkWav());

      fakeAudio = _FakeAudioService()..wavPathToReturn = wavPath;
    });

    tearDown(() async {
      paths.sttDirOverride = null;
      await db.close();
      await sttDir.delete(recursive: true);
      await wavDir.delete(recursive: true);
    });

    // _stopAndTranscribe() reads the WAV off real disk (dart:io File) — a
    // genuine async gap that flutter_test's FakeAsync zone cannot resolve via
    // pump() alone, so this taps inside tester.runAsync() to let real I/O
    // (and the shrunk real-time .timeout() below) actually complete. Because
    // the tap is dispatched from inside runAsync(), the whole downstream
    // async chain it kicks off — including the WpToast success/error
    // animation triggered at the end — stays zone-sticky to that real Zone
    // for its entire lifetime (Dart async functions keep the Zone captured
    // at their first invocation). So pipelineWait must cover the full toast
    // lifecycle (~2 s auto-dismiss + ~300 ms reverse) too — settling the
    // Ticker for good inside the real Zone — otherwise a leftover Ticker
    // ticks against flutter_test's FakeAsync clock on a *later* test's frame
    // and crashes with a negative-elapsed-time assertion.
    Future<void> recordStopAndDrain(
      WidgetTester tester, {
      required Duration pipelineWait,
    }) async {
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(find.byIcon(LucideIcons.square), findsOneWidget);

      final totalRealWait = pipelineWait + const Duration(milliseconds: 2600);
      await tester.runAsync(() async {
        await tester.tap(find.byType(InkWell));
        await Future<void>.delayed(totalRealWait);
      });
      await tester.pump(totalRealWait);
      await tester.pump();
    }

    testWidgets('transcribes via localSttBundleProvider + FakeWhisperEngine — '
        'tag action applied, no subprocess in path (AC1, AC2)', (tester) async {
      final engine = _FakeWhisperEngine(
        transcriptToReturn: 'tag as engine-verified',
      );

      await tester.pumpWidget(
        _makeTestableButtonViaEngine(
          entryId: entryId,
          db: db,
          fakeAudio: fakeAudio,
          engine: engine,
        ),
      );
      await tester.pumpAndSettle();

      await recordStopAndDrain(
        tester,
        pipelineWait: const Duration(milliseconds: 300),
      );

      // The FFI engine seam was actually exercised. Exact call counts
      // aren't asserted — ensureRunning() also fires an internal warmup
      // inference (and possibly a debounced re-warm), so only "at least
      // once" is a robust, non-flaky signal that the engine (not a
      // subprocess) handled the pipeline.
      expect(
        engine.loadCallCount,
        greaterThanOrEqualTo(1),
        reason: 'ensureRunning() must load via the engine, not a subprocess',
      );
      expect(
        engine.transcribeCallCount,
        greaterThanOrEqualTo(1),
        reason: 'transcribeBytes() must transcribe via the engine',
      );

      // The recognized tag action was applied (AC2).
      final tags = await db.tagsForEntry(entryId);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'engine-verified');

      // Back to idle.
      expect(find.byIcon(LucideIcons.mic), findsOneWidget);
      expect(find.byIcon(LucideIcons.loader), findsNothing);
    });

    testWidgets(
      'ensureRunning() stuck beyond its timeout ends in a clean idle error '
      'state, not a hang (AC3)',
      (tester) async {
        final originalTimeout = WpVoiceInputButton.ensureRunningTimeout;
        WpVoiceInputButton.ensureRunningTimeout = const Duration(
          milliseconds: 100,
        );
        addTearDown(
          () => WpVoiceInputButton.ensureRunningTimeout = originalTimeout,
        );

        final engine = _FakeWhisperEngine(hangOnLoad: true);

        await tester.pumpWidget(
          _makeTestableButtonViaEngine(
            entryId: entryId,
            db: db,
            fakeAudio: fakeAudio,
            engine: engine,
          ),
        );
        await tester.pumpAndSettle();

        await recordStopAndDrain(
          tester,
          pipelineWait: const Duration(milliseconds: 400),
        );

        expect(find.byIcon(LucideIcons.mic), findsOneWidget);
        expect(find.byIcon(LucideIcons.loader), findsNothing);
        expect(
          engine.loadCallCount,
          greaterThanOrEqualTo(1),
          reason:
              'ensureRunning() must have attempted to load via the '
              'engine before timing out',
        );
      },
    );

    testWidgets(
      'transcribeBytes() stuck beyond its timeout ends in a clean idle error '
      'state, not a hang (AC3)',
      (tester) async {
        final originalTimeout = WpVoiceInputButton.transcribeTimeout;
        WpVoiceInputButton.transcribeTimeout = const Duration(
          milliseconds: 100,
        );
        addTearDown(
          () => WpVoiceInputButton.transcribeTimeout = originalTimeout,
        );

        final engine = _FakeWhisperEngine(hangOnTranscribe: true);

        await tester.pumpWidget(
          _makeTestableButtonViaEngine(
            entryId: entryId,
            db: db,
            fakeAudio: fakeAudio,
            engine: engine,
          ),
        );
        await tester.pumpAndSettle();

        await recordStopAndDrain(
          tester,
          pipelineWait: const Duration(milliseconds: 400),
        );

        expect(find.byIcon(LucideIcons.mic), findsOneWidget);
        expect(find.byIcon(LucideIcons.loader), findsNothing);
        expect(
          engine.loadCallCount,
          greaterThanOrEqualTo(1),
          reason:
              'ensureRunning() must have succeeded before transcribe '
              'was attempted',
        );
        expect(
          engine.transcribeCallCount,
          greaterThanOrEqualTo(1),
          reason:
              'transcribeBytes() must have attempted to transcribe via '
              'the engine before timing out',
        );
      },
    );
  });

  // =========================================================================
  // 3. Voice action dispatch tests (parse → notifier → DB)
  //
  // Uses ProviderContainer (not widget tests) to directly verify the
  // parse-then-dispatch pipeline that VoiceNoteButton._dispatchAction runs.
  // This avoids the fire-and-forget async / File I/O issues of widget tests.
  // =========================================================================

  group('Voice action dispatch flow', () {
    late HistoryDatabase db;
    late ProviderContainer container;
    const entryId = 'voice-dispatch-1';

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());

      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: entryId,
          timestamp: DateTime(2025, 7, 1, 12, 0),
          content: const Value('Original content'),
          title: const Value('Flow Test Entry'),
          model: const Value('whisper-small'),
          isLocal: const Value(true),
          durationSec: const Value(5.0),
        ),
      );

      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
    });

    tearDown(() => container.dispose());

    /// Loads and returns the notifier, keeping a listener alive.
    Future<HistoryDetailNotifier> loadNotifier() async {
      container.listen(historyDetailProvider(entryId), (_, _) {});
      final state = await container.read(historyDetailProvider(entryId).future);
      expect(state.entry.id, entryId);
      return container.read(historyDetailProvider(entryId).notifier);
    }

    test('note: parseVoiceAction → addNote → note persisted', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('Buy groceries tomorrow');
      expect(action!.type, VoiceActionType.note);

      await notifier.addNote(action.payload);

      final notes = await db.notesForEntry(entryId);
      expect(notes, hasLength(1));
      expect(notes.first.content, 'Buy groceries tomorrow');
    });

    test('tag: parseVoiceAction "tag as X" → addTag → tag persisted', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('tag as important');
      expect(action!.type, VoiceActionType.tag);

      await notifier.addTag(action.payload);

      final tags = await db.tagsForEntry(entryId);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'important');
    });

    test('tag: parseVoiceAction "tag:work" → addTag → tag persisted', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('tag:work');
      expect(action!.type, VoiceActionType.tag);

      await notifier.addTag(action.payload);

      final tags = await db.tagsForEntry(entryId);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'work');
    });

    test('correction: parseVoiceAction "correct: X" → updateContent', () async {
      final notifier = await loadNotifier();

      final action = parseVoiceAction('correct: Updated transcript content');
      expect(action!.type, VoiceActionType.correction);

      await notifier.updateContent(action.payload);

      final entry = await db.getEntry(entryId);
      expect(entry!.content, 'Updated transcript content');
    });

    test(
      'correction: parseVoiceAction "korrektur: X" → updateContent',
      () async {
        final notifier = await loadNotifier();

        final action = parseVoiceAction('korrektur: Korrigierter Inhalt');
        expect(action!.type, VoiceActionType.correction);

        await notifier.updateContent(action.payload);

        final entry = await db.getEntry(entryId);
        expect(entry!.content, 'Korrigierter Inhalt');
      },
    );

    test('empty/null action not dispatched', () async {
      await loadNotifier();

      final action = parseVoiceAction('   ');
      expect(action, isNull);

      // Verify nothing changed.
      final notes = await db.notesForEntry(entryId);
      expect(notes, isEmpty);
      final entry = await db.getEntry(entryId);
      expect(entry!.content, 'Original content');
    });

    test('full dispatch switch matches VoiceNoteButton logic', () async {
      final notifier = await loadNotifier();

      // Simulate the exact dispatch logic from VoiceNoteButton._dispatchAction
      for (final input in [
        'Remember to call Bob',
        'tag as urgent',
        'correct: Fixed transcript',
      ]) {
        final action = parseVoiceAction(input)!;
        switch (action.type) {
          case VoiceActionType.note:
            await notifier.addNote(action.payload);
          case VoiceActionType.tag:
            await notifier.addTag(action.payload);
          case VoiceActionType.correction:
            await notifier.updateContent(action.payload);
        }
      }

      final notes = await db.notesForEntry(entryId);
      expect(notes, hasLength(1));
      expect(notes.first.content, 'Remember to call Bob');

      final tags = await db.tagsForEntry(entryId);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'urgent');

      final entry = await db.getEntry(entryId);
      expect(entry!.content, 'Fixed transcript');
    });
  });
}
