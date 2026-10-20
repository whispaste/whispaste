/// Journey 3 — dictation with a Smart Mode profile and dictionary replacements.
///
/// Drives the production pipeline end to end:
///   hotkey path ([RecordingOrchestrator.toggleRecording], what the hotkey
///   trigger calls) → fake audio + fake STT → real replacement rules from the
///   in-memory Drift database → fake Smart Mode engine → fake native paste
///   (the clipboard content at paste time is what was pasted) → history entry,
///   read back through the real [HistoryPage] by its row key.
///
/// Fakes only sit on the OS / model boundary: audio capture, STT, the Smart
/// Mode LLM, native paste and clipboard, the attention (notification) service.
///
/// "Profil" in the product means the Smart Mode standard preset
/// (`SmartModeSettings.standardPreset`: `off` or `cleanup` here).
///
/// The pipeline runs in a plain [ProviderContainer] with no widget mounted:
/// a mounted [HistoryPage] keeps live Drift stream queries running under
/// FakeAsync, which blocks the save step's writes. The page is pumped after
/// the dictation, against the same database.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale, ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/history/data/providers.dart'
    show archivedEntriesProvider, historyEntriesProvider, trashEntriesProvider;
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart'
    show retainedAudioDirOverride, sttDir, sttDirOverride, sttModelPath;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/system_attention_service.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes at the OS / model boundary
// ---------------------------------------------------------------------------

class _FakeAudio extends AudioServiceNotifier {
  _FakeAudio(this.wavPath);

  final String wavPath;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

  @override
  Future<void> startRecording({bool streamRawPcm = false}) async {
    if (state.isRecording) return;
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPath,
    );
  }

  @override
  Future<String?> stopRecording() async {
    state = AudioStatus(filePath: wavPath);
    return wavPath;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeStt extends SttServerStateNotifier {
  _FakeStt(this.transcript);

  /// Raw "Whisper" output the journey dictates.
  final String transcript;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning({bool warmup = true}) async {
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytes(
    List<int> wavBytes, {
    String? language,
  }) async => transcript;

  @override
  Future<void> prewarm() async {}
}

/// Smart Mode LLM stand-in. Echoes its input unless [result] is set; throws
/// [error] when set. Records what it was asked to refine.
class _FakeLlm implements SmartModeEngine {
  _FakeLlm({this.result, this.error});

  final String? result;
  final Object? error;

  int runCalls = 0;
  String? lastUserText;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    runCalls++;
    lastUserText = userText;
    final failure = error;
    if (failure != null) throw failure;
    return result ?? userText;
  }

  @override
  Future<void> cancel() async {}
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeSecureKeyStore extends SecureKeyStore {
  _FakeSecureKeyStore() : super(null);

  final _store = <String, String>{};

  @override
  Future<String?> readKey(String key) async => _store[key];

  @override
  Future<void> writeKey(String key, String value) async => _store[key] = value;

  @override
  Future<void> deleteKey(String key) async => _store.remove(key);

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

class _FakeModelDownload extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() =>
      const ModelDownloadState(downloadedModels: {'whisper-small'});
}

class _FakeSmartModeDownload extends SmartModeDownloadNotifier {
  @override
  SmartModeDownloadState build() =>
      const SmartModeDownloadState(modelDownloaded: true);
}

class _FakeSystemAttention extends SystemAttentionService {
  _FakeSystemAttention(super.ref);

  final List<AttentionKind> kinds = [];

  @override
  Future<void> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
  }) async {
    kinds.add(kind);
  }

  @override
  Future<void> clearAttention() async {}
}

/// Native paste bridge stand-in. [pastedTexts] collects the clipboard content
/// at the moment the native paste shortcut fires, i.e. what the target app
/// would receive.
///
/// [frontmost] plays the window in front. Like the native hosts, the paste
/// is refused when it is no longer the captured one (PAR-032).
class _FakePaste extends DesktopPasteController {
  _FakePaste(this._readClipboard);

  final String? Function() _readClipboard;

  final List<String?> pastedTexts = [];

  String frontmost = 'editor';
  String? captured;
  int captures = 0;

  @override
  Future<bool> capturePasteTarget() async {
    captures++;
    captured = frontmost;
    return true;
  }

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    if (captured != frontmost) {
      return const NativePasteResult(status: NativePasteStatus.targetChanged);
    }
    pastedTexts.add(_readClipboard());
    return const NativePasteResult(status: NativePasteStatus.success);
  }

  @override
  Future<NativePasteResult> copySelection({required Duration delay}) async =>
      const NativePasteResult(status: NativePasteStatus.unknown);

  @override
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async => const NativePasteResult(status: NativePasteStatus.postFailed);

  @override
  Future<bool> writeClipboardTextExcludingHistory(String text) async => false;

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

  @override
  Future<String?> getTargetBundleId() async => null;

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Journey harness
// ---------------------------------------------------------------------------

const _rawTranscript = 'ich teste wisp paste heute';
// The LLM receives the dictionary-corrected text (replacements run before
// Smart Mode), so it hands back the corrected term.
const _llmOutput = 'Ich teste WhisPaste heute.';

late Directory _tmp;

/// Clipboard contents, served through a mocked platform channel.
String? _clipboard;

AppSettings _settings({required String smartPreset}) => AppSettings(
  stt: const SttSettings(model: 'whisper-small', language: 'English'),
  afterTranscriptionSection: const AfterTranscriptionSettings(
    afterTranscription: 'paste',
  ),
  onboarding: const OnboardingSettings(onboardingCompleted: true),
  behavior: const BehaviorSettings(textReplacementsEnabled: true),
  smartMode: SmartModeSettings(standardPreset: smartPreset, provider: 'local'),
);

class _Journey {
  _Journey({
    required this.tester,
    required this.db,
    required this.container,
    required this.llm,
    required this.paste,
    required this.attention,
  });

  final WidgetTester tester;
  final HistoryDatabase db;
  final ProviderContainer container;
  final _FakeLlm llm;
  final _FakePaste paste;
  final _FakeSystemAttention attention;

  /// Seeds the in-memory dictionary through the real upsert path.
  Future<void> seedReplacement() => tester.runAsync(
    () => db.upsertReplacementWithTriggers(
      id: 'wp-dictionary-whispaste',
      triggers: const ['wisp paste'],
      replacement: 'WhisPaste',
      createdAt: DateTime(2026, 10, 17),
    ),
  );

  RecordingOrchestrator get orchestrator =>
      container.read(recordingOrchestratorProvider.notifier);

  /// Hotkey press starts, second press stops and runs the whole pipeline.
  /// [whileRecording] runs between the two presses (the user acting while
  /// the dictation is under way).
  Future<void> dictate({void Function()? whileRecording}) async {
    await tester.runAsync(orchestrator.toggleRecording);
    expect(
      container.read(recordingProvider).phase,
      RecordingPhase.recording,
      reason: 'first hotkey press must start the recording',
    );
    whileRecording?.call();
    await tester.runAsync(orchestrator.toggleRecording);
  }

  Future<List<HistoryEntry>> entries() async =>
      await tester.runAsync(db.allEntries) ?? const [];

  /// Renders the real History page on the same database and checks the row.
  ///
  /// The page gets a one-shot snapshot of the real rows instead of its live
  /// Drift streams, which would leave pending timers under the test binding.
  Future<void> expectHistoryRow(String entryId, String text) async {
    final rows = await tester.runAsync(db.allEntries) ?? const [];
    await tester.pumpWidget(
      makeTestable(
        const HistoryPage(),
        locale: const Locale('en'),
        db: db,
        overrides: [
          historyEntriesProvider.overrideWith((ref) => Stream.value(rows)),
          archivedEntriesProvider.overrideWith(
            (ref) => Stream.value(const <HistoryEntry>[]),
          ),
          trashEntriesProvider.overrideWith(
            (ref) => Stream.value(const <HistoryEntry>[]),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey(entryId)),
      findsOneWidget,
      reason: 'history row for the dictation must appear',
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey(entryId)),
        matching: find.textContaining(text),
      ),
      findsWidgets,
    );
  }
}

Future<_Journey> _setUpJourney(
  WidgetTester tester, {
  required AppSettings settings,
  required _FakeLlm llm,
}) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  final wav = File('${_tmp.path}/dictation.wav')
    ..writeAsBytesSync(List<int>.filled(364, 0));
  final paste = _FakePaste(() => _clipboard);

  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) => db),
      audioServiceProvider.overrideWith(() => _FakeAudio(wav.absolute.path)),
      localSttBundleProvider.overrideWith(() => _FakeStt(_rawTranscript)),
      settingsProvider.overrideWith(() => _FakeSettings(settings)),
      secureKeyStoreProvider.overrideWith((ref) => _FakeSecureKeyStore()),
      desktopPasteControllerProvider.overrideWith((ref) => paste),
      modelDownloadProvider.overrideWith(_FakeModelDownload.new),
      smartModeDownloadProvider.overrideWith(_FakeSmartModeDownload.new),
      smartModeEngineProvider.overrideWith((ref) => llm),
      systemAttentionServiceProvider.overrideWith(_FakeSystemAttention.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.runAsync(() => container.read(settingsProvider.future));

  return _Journey(
    tester: tester,
    db: db,
    container: container,
    llm: llm,
    paste: paste,
    attention:
        container.read(systemAttentionServiceProvider) as _FakeSystemAttention,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The pipeline's fire-and-forget review/support prompt checks read
    // SharedPreferences; without a backend getInstance fails and the error
    // can escape into the test zone, depending on timing.
    SharedPreferences.setMockInitialValues({});
    _tmp = Directory.systemTemp.createTempSync('wp40-dictation-journey-');
    sttDirOverride = _tmp.path;
    retainedAudioDirOverride = '${_tmp.path}/retained-audio';
    // Preflight only checks that the model file exists; STT is faked.
    Directory(sttDir()).createSync(recursive: true);
    final modelPath = sttModelPath('whisper-small');
    if (modelPath != null && !File(modelPath).existsSync()) {
      File(modelPath).writeAsStringSync('fake-model');
    }
    _clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final args = Map<String, dynamic>.from(call.arguments as Map);
              _clipboard = args['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (_clipboard == null) return null;
              return <String, dynamic>{'text': _clipboard};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    sttDirOverride = null;
    retainedAudioDirOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  testWidgets(
    'Smart Mode profile: dictionary replacement applied to the refined text, '
    'pasted, and shown in History',
    (tester) async {
      final journey = await _setUpJourney(
        tester,
        settings: _settings(smartPreset: 'cleanup'),
        llm: _FakeLlm(result: _llmOutput),
      );
      await journey.seedReplacement();

      await journey.dictate();

      final state = journey.container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
      expect(state.transcript, 'Ich teste WhisPaste heute.');

      // The dictionary runs before Smart Mode, so the LLM sees the corrected
      // term instead of the raw phrase.
      expect(journey.llm.runCalls, 1);
      expect(journey.llm.lastUserText, 'ich teste WhisPaste heute');

      // Exactly what reached the native paste: replaced, refined text.
      expect(journey.paste.pastedTexts, ['Ich teste WhisPaste heute.']);

      final entries = await journey.entries();
      expect(entries, hasLength(1));
      expect(entries.single.content, 'Ich teste WhisPaste heute.');
      expect(entries.single.originalTranscript, _rawTranscript);
      expect(entries.single.source, 'dictation');
      expect(journey.attention.kinds, isEmpty);

      await journey.expectHistoryRow(entries.single.id, 'WhisPaste');
    },
  );

  testWidgets(
    'Smart Mode LLM throws: raw text falls back, dictionary still applied, '
    'paste and History entry still happen',
    (tester) async {
      final journey = await _setUpJourney(
        tester,
        settings: _settings(smartPreset: 'cleanup'),
        llm: _FakeLlm(error: StateError('llm backend unavailable')),
      );
      await journey.seedReplacement();

      await journey.dictate();

      expect(
        journey.container.read(recordingProvider).phase,
        RecordingPhase.done,
      );
      expect(journey.llm.runCalls, 1);

      // Fallback is the raw transcript; the dictionary still applies to it.
      const fallbackFinal = 'ich teste WhisPaste heute';
      expect(journey.paste.pastedTexts, [fallbackFinal]);

      final entries = await journey.entries();
      expect(entries, hasLength(1));
      expect(entries.single.content, fallbackFinal);
      expect(entries.single.originalTranscript, _rawTranscript);

      // Informational notice that Smart Mode was skipped.
      expect(journey.attention.kinds, [AttentionKind.smartModeFallback]);

      await journey.expectHistoryRow(entries.single.id, 'WhisPaste');
    },
  );

  testWidgets(
    'profile without Smart Mode: only dictionary replacements run, no LLM '
    'call, entry is saved',
    (tester) async {
      final journey = await _setUpJourney(
        tester,
        settings: _settings(smartPreset: 'off'),
        llm: _FakeLlm(result: _llmOutput),
      );
      await journey.seedReplacement();

      await journey.dictate();

      expect(
        journey.container.read(recordingProvider).phase,
        RecordingPhase.done,
      );
      expect(journey.llm.runCalls, 0, reason: 'preset off must skip the LLM');

      const replacedOnly = 'ich teste WhisPaste heute';
      expect(journey.paste.pastedTexts, [replacedOnly]);

      final entries = await journey.entries();
      expect(entries, hasLength(1));
      expect(entries.single.content, replacedOnly);
      expect(entries.single.originalTranscript, _rawTranscript);
      expect(journey.attention.kinds, isEmpty);

      await journey.expectHistoryRow(entries.single.id, 'WhisPaste');
    },
  );

  // PAR-032 / briefing B3: the paste goes to the window that was in front at
  // hotkey time. Capturing again right before the paste would follow the
  // user into whatever app they switched to.
  group('paste target', () {
    Future<_Journey> journey(WidgetTester tester) => _setUpJourney(
      tester,
      settings: _settings(smartPreset: 'off'),
      llm: _FakeLlm(result: _llmOutput),
    );

    testWidgets('a dictation captures the target once, at the hotkey', (
      tester,
    ) async {
      final j = await journey(tester);

      await j.dictate();

      expect(j.paste.captures, 1);
      expect(j.paste.pastedTexts, [_rawTranscript]);
    });

    testWidgets('a window switch during processing refuses the paste', (
      tester,
    ) async {
      final j = await journey(tester);

      await j.dictate(whileRecording: () => j.paste.frontmost = 'browser');

      expect(j.paste.captures, 1);
      expect(j.paste.captured, 'editor');
      expect(j.paste.pastedTexts, isEmpty, reason: 'never into the browser');
    });

    testWidgets('a cancelled dictation leaves no target behind', (
      tester,
    ) async {
      final j = await journey(tester);
      await tester.runAsync(j.orchestrator.toggleRecording);
      await tester.runAsync(j.orchestrator.cancelRecording);
      j.paste.frontmost = 'terminal';

      await j.dictate();

      expect(j.paste.captures, 2, reason: 'the retry captures again');
      expect(j.paste.captured, 'terminal');
      expect(j.paste.pastedTexts, [_rawTranscript]);
    });

    testWidgets('a paste without a recording start captures before pasting', (
      tester,
    ) async {
      final j = await journey(tester);

      await tester.runAsync(
        () => j.orchestrator.completeInteractiveSnippet(
          composedText: 'Betreff: Test',
          audioDuration: const Duration(seconds: 1),
        ),
      );

      expect(j.paste.captures, 1);
      expect(j.paste.pastedTexts, ['Betreff: Test']);
    });

    testWidgets('an interactive snippet keeps the target from its start', (
      tester,
    ) async {
      final j = await journey(tester);
      await tester.runAsync(j.orchestrator.primeForInteractiveSnippet);
      j.paste.frontmost = 'browser';

      await tester.runAsync(
        () => j.orchestrator.completeInteractiveSnippet(
          composedText: 'Betreff: Test',
          audioDuration: const Duration(seconds: 1),
        ),
      );

      expect(j.paste.captures, 1);
      expect(j.paste.pastedTexts, isEmpty);
    });
  });
}
