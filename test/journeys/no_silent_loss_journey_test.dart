/// Journey 6 — no silent loss, and silence ends in a hint instead of a paste.
///
/// Drives the hotkey dictation path ([RecordingOrchestrator.toggleRecording])
/// through the real pipeline: real recording state, real safety guard, real
/// [SttServerStateNotifier] (including its hallucination filter and bracket
/// strip), real Smart Mode fallback logic, real in-memory Drift database and
/// the real error toast ([WpRecordingBehavior]).
///
/// Fakes sit only at the OS / model boundary: audio capture and its amplitude
/// stream, the Whisper engine (the model itself), the Smart Mode LLM, the
/// native paste and clipboard, the attention (notification) service, and the
/// cloud HTTP client.
///
/// UI is addressed by key only (`toast-message`). Expected hint texts are
/// read from the L10n delegate, not hard-coded.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/history/data/providers.dart'
    show archivedEntriesProvider, historyEntriesProvider, trashEntriesProvider;
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
import 'package:whispaste/services/transcription/openai_transcriber.dart';
import 'package:whispaste/services/transcription/transcriber.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes at the OS / model boundary
// ---------------------------------------------------------------------------

const _raw = 'ich teste wisp paste heute';
const _sampleRate = 16000;

class _FakeAudio extends AudioServiceNotifier {
  _FakeAudio(this.wavPath, this.levels);

  final String wavPath;

  /// Broadcast controller for the live level stream, or `null` for a backend
  /// without level metering (then the safety guard is not wired up).
  final StreamController<double>? levels;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => levels?.stream;

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

/// Whisper model stand-in: returns [responseText] for every inference.
class _FakeWhisperEngine implements WhisperEngine {
  _FakeWhisperEngine({this.responseText = ''});

  String responseText;
  final List<int> callSizes = [];
  bool _loaded = false;

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async {
    callSizes.add(wavBytes.length);
    return responseText;
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

/// Smart Mode LLM stand-in driven by [respond]; counts calls and cancels.
class _FakeLlm implements SmartModeEngine {
  _FakeLlm(this.respond);

  final Future<String> Function() respond;

  int runCalls = 0;
  int cancelCalls = 0;
  String? lastUserText;

  @override
  Future<String> run({required String systemPrompt, required String userText}) {
    runCalls++;
    lastUserText = userText;
    return respond();
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeSecureKeyStore extends SecureKeyStore {
  _FakeSecureKeyStore() : super(null);

  final _store = <String, String>{'wp_openai_api_key': 'sk-test'};

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

/// Native paste bridge stand-in. [pastedTexts] holds the clipboard content at
/// the moment the native paste shortcut fires, i.e. what the target app gets.
class _FakePaste extends DesktopPasteController {
  _FakePaste(this._readClipboard);

  final String? Function() _readClipboard;

  final List<String?> pastedTexts = [];

  @override
  Future<bool> capturePasteTarget() async => true;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
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
// WAV fixtures (16 kHz mono 16-bit, written by the test itself)
// ---------------------------------------------------------------------------

/// [seconds] of PCM alternating between +[amplitude] and -[amplitude].
/// `amplitude: 0` is digital silence; a small value such as 2 is a very low
/// RMS hiss.
Uint8List _wav({required double seconds, required int amplitude}) {
  final samples = (seconds * _sampleRate).round();
  final dataSize = samples * 2;
  final bytes = ByteData(44 + dataSize);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, _sampleRate, Endian.little);
  bytes.setUint32(28, _sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples; i++) {
    bytes.setInt16(
      44 + i * 2,
      i.isEven ? amplitude : -amplitude,
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}

/// Non-silent audio: full-scale alternation for 2 s.
Uint8List _speechWav() => _wav(seconds: 2, amplitude: 8000);

Uint8List _silenceWav() => _wav(seconds: 3, amplitude: 0);

// ---------------------------------------------------------------------------
// Journey harness
// ---------------------------------------------------------------------------

late Directory _tmp;

/// Clipboard contents, served through a mocked platform channel.
String? _clipboard;

AppSettings _settings({
  String smartPreset = 'off',
  SttProviderType provider = SttProviderType.onDevice,
  double deadMicTimeout = 3.0,
}) => AppSettings(
  stt: SttSettings(model: 'whisper-small', provider: provider.value),
  afterTranscriptionSection: const AfterTranscriptionSettings(
    afterTranscription: 'paste',
  ),
  onboarding: const OnboardingSettings(onboardingCompleted: true),
  behavior: const BehaviorSettings(textReplacementsEnabled: true),
  smartMode: SmartModeSettings(standardPreset: smartPreset, provider: 'local'),
  recordingSafety: RecordingSafetySettings(deadMicTimeout: deadMicTimeout),
  cloudProvider: const CloudProviderSettings(openAiApiKey: 'sk-test'),
);

class _Harness {
  _Harness({
    required this.tester,
    required this.container,
    required this.db,
    required this.engine,
    required this.llm,
    required this.paste,
    required this.attention,
  });

  final WidgetTester tester;
  final ProviderContainer container;
  final HistoryDatabase db;
  final _FakeWhisperEngine engine;
  final _FakeLlm llm;
  final _FakePaste paste;
  final _FakeSystemAttention attention;

  RecordingState get recording => container.read(recordingProvider);

  Future<List<HistoryEntry>> entries() async =>
      await tester.runAsync(db.allEntries) ?? const [];

  /// Hotkey press starts the recording and returns once the pipeline is done.
  Future<void> dictate() async {
    final orchestrator = container.read(recordingOrchestratorProvider.notifier);
    await tester.runAsync(orchestrator.toggleRecording);
    expect(
      recording.phase,
      RecordingPhase.recording,
      reason: 'first hotkey press must start the recording',
    );
    await tester.runAsync(orchestrator.toggleRecording);
  }

  /// Starts a recording without stopping it (guards end it on their own).
  Future<void> startOnly() async {
    final orchestrator = container.read(recordingOrchestratorProvider.notifier);
    await tester.runAsync(orchestrator.toggleRecording);
    expect(
      recording.phase,
      RecordingPhase.recording,
      reason: 'hotkey press must start the recording',
    );
    // The engine load started by the press runs on after the press returns.
    // Let it finish here, so it does not outlive the test's provider scope.
    await _until(
      tester,
      () => container.read(localSttBundleProvider).isReady,
      what: 'engine load after the start',
    );
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required AppSettings settings,
  required Uint8List wav,
  required _FakeWhisperEngine engine,
  _FakeLlm? llm,
  StreamController<double>? levels,
  List<Object> extra = const [],
  bool hints = false,
}) async {
  // The toast sits at the bottom edge; keep its action inside the surface.
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final file = File('${_tmp.path}/recording.wav')..writeAsBytesSync(wav);
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  final paste = _FakePaste(() => _clipboard);
  final fakeLlm = llm ?? _FakeLlm(() async => '');

  await tester.pumpWidget(
    makeTestable(
      hints
          ? const WpRecordingBehavior(child: SizedBox.shrink())
          : const SizedBox.shrink(),
      locale: const Locale('en'),
      db: db,
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettings(settings)),
        secureKeyStoreProvider.overrideWith((ref) => _FakeSecureKeyStore()),
        audioServiceProvider.overrideWith(
          () => _FakeAudio(file.absolute.path, levels),
        ),
        whisperEngineProvider.overrideWithValue(engine),
        modelDownloadProvider.overrideWith(_FakeModelDownload.new),
        smartModeDownloadProvider.overrideWith(_FakeSmartModeDownload.new),
        smartModeEngineProvider.overrideWith((ref) => fakeLlm),
        desktopPasteControllerProvider.overrideWith((ref) => paste),
        systemAttentionServiceProvider.overrideWith(_FakeSystemAttention.new),
        historyEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        ...extra,
      ],
    ),
  );
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  await tester.runAsync(() => container.read(settingsProvider.future));

  return _Harness(
    tester: tester,
    container: container,
    db: db,
    engine: engine,
    llm: fakeLlm,
    paste: paste,
    attention:
        container.read(systemAttentionServiceProvider) as _FakeSystemAttention,
  );
}

/// Polls until [condition] holds. Each poll yields once to the real event
/// loop, so the pipeline and real timers can finish between polls.
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

bool _hasToast(WidgetTester tester) =>
    find.byKey(const ValueKey('toast-message')).evaluate().isNotEmpty;

String _toastText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('toast-message'))).data ?? '';

/// Drains the toast's auto-dismiss timer and disposes the tree, so no timer
/// outlives the test.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Smart Mode failure: the raw text (after the usual transforms, here none)
/// is still pasted and saved, and the user gets the informational notice.
void _expectRawFallback(_Harness h, String raw, {required int llmCalls}) {
  expect(h.recording.phase, RecordingPhase.done);
  expect(h.llm.runCalls, llmCalls);
  expect(h.paste.pastedTexts, [raw]);
  expect(h.attention.kinds, [AttentionKind.smartModeFallback]);
}

Future<void> _expectRawEntry(_Harness h, String raw) async {
  final entries = await h.entries();
  expect(entries, hasLength(1), reason: 'the dictation must be in History');
  expect(entries.single.content, raw);
  expect(entries.single.originalTranscript, raw);
}

/// Silence / empty result: nothing pasted, no History entry, a visible hint.
Future<void> _expectNothingPastedWithHint(
  WidgetTester tester,
  _Harness h, {
  required String errorCode,
  required String hint,
}) async {
  await _until(
    tester,
    () => h.recording.phase == RecordingPhase.error,
    what: 'error phase',
  );
  expect(
    h.recording.errorMessage,
    errorCode,
    reason: 'the pipeline must end with the hint code',
  );
  expect(h.paste.pastedTexts, isEmpty, reason: 'nothing may be pasted');
  expect(await h.entries(), isEmpty, reason: 'no empty History entry');
  await _until(tester, () => _hasToast(tester), what: 'hint toast');
  expect(_toastText(tester), hint);
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
    _tmp = Directory.systemTemp.createTempSync('wp40-no-silent-loss-');
    sttDirOverride = _tmp.path;
    retainedAudioDirOverride = '${_tmp.path}/retained-audio';
    // The notifier's preflight only checks the model file; its size must pass
    // the minimum-size guard (>10 MB). The engine itself is faked.
    Directory(sttDir()).createSync(recursive: true);
    File(
      sttModelPath('whisper-small')!,
    ).writeAsBytesSync(Uint8List(11 * 1024 * 1024));
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
    RecordingOrchestrator.smartModeCleanupTimeoutOverride = null;
    sttDirOverride = null;
    retainedAudioDirOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  // =========================================================================
  // 1) Smart Mode never costs the dictation
  // =========================================================================

  group('1) Smart Mode failure keeps the raw text', () {
    testWidgets(
      'LLM returns an empty string: raw text is pasted and saved, notice shown',
      (tester) async {
        final h = await _pump(
          tester,
          settings: _settings(smartPreset: 'cleanup'),
          wav: _speechWav(),
          engine: _FakeWhisperEngine(responseText: _raw),
          llm: _FakeLlm(() async => ''),
        );

        await h.dictate();

        _expectRawFallback(h, _raw, llmCalls: 1);
        await _expectRawEntry(h, _raw);
        await _teardown(tester);
      },
    );

    testWidgets('LLM returns only whitespace: treated like an empty result', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        settings: _settings(smartPreset: 'cleanup'),
        wav: _speechWav(),
        engine: _FakeWhisperEngine(responseText: _raw),
        llm: _FakeLlm(() async => ' \n\t  '),
      );

      await h.dictate();

      _expectRawFallback(h, _raw, llmCalls: 1);
      await _expectRawEntry(h, _raw);
      await _teardown(tester);
    });

    testWidgets('LLM throws: raw text is pasted and saved, notice shown', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        settings: _settings(smartPreset: 'cleanup'),
        wav: _speechWav(),
        engine: _FakeWhisperEngine(responseText: _raw),
        llm: _FakeLlm(() async => throw StateError('llm backend unavailable')),
      );

      await h.dictate();

      _expectRawFallback(h, _raw, llmCalls: 1);
      await _expectRawEntry(h, _raw);
      await _teardown(tester);
    });

    testWidgets(
      'LLM hangs past the cleanup budget: raw text is pasted, generation cancelled',
      (tester) async {
        RecordingOrchestrator.smartModeCleanupTimeoutOverride = const Duration(
          milliseconds: 50,
        );
        final h = await _pump(
          tester,
          settings: _settings(smartPreset: 'cleanup'),
          wav: _speechWav(),
          engine: _FakeWhisperEngine(responseText: _raw),
          llm: _FakeLlm(() => Completer<String>().future),
        );

        await h.dictate();

        _expectRawFallback(h, _raw, llmCalls: 1);
        expect(
          h.llm.cancelCalls,
          1,
          reason: 'the abandoned run must be stopped',
        );
        await _expectRawEntry(h, _raw);
        await _teardown(tester);
      },
    );
  });

  // =========================================================================
  // 2) Empty STT result for real audio
  // =========================================================================

  group('2) STT returns no text for real audio', () {
    testWidgets(
      'empty transcript: no paste, no empty History entry, error hint shown',
      (tester) async {
        final h = await _pump(
          tester,
          settings: _settings(),
          wav: _speechWav(),
          engine: _FakeWhisperEngine(responseText: ''),
          hints: true,
        );
        final l10n = await L10n.delegate.load(const Locale('en'));

        await h.dictate();

        await _expectNothingPastedWithHint(
          tester,
          h,
          errorCode: 'transcription_empty',
          hint: l10n.errorTranscriptionEmpty,
        );
        await _teardown(tester);
      },
    );
  });

  // =========================================================================
  // 3) Silence: no paste, a hint instead
  // =========================================================================

  group('3) silence ends in a hint, not a paste', () {
    testWidgets(
      'dead-mic guard: 3 s of digital silence stops the recording before STT',
      (tester) async {
        final levels = StreamController<double>.broadcast();
        addTearDown(levels.close);
        final h = await _pump(
          tester,
          settings: _settings(),
          wav: _silenceWav(),
          engine: _FakeWhisperEngine(responseText: _raw),
          levels: levels,
          hints: true,
        );
        final l10n = await L10n.delegate.load(const Locale('en'));

        await h.startOnly();
        // The engine is warmed up on recording start; only calls made after
        // this point could come from the silent audio.
        // 3 s of zero level at the metering rate; the default dead-mic
        // timeout is 3 s.
        for (var i = 0; i < 3 * amplitudeSamplesPerSecond + 5; i++) {
          levels.add(0);
        }

        await _expectNothingPastedWithHint(
          tester,
          h,
          errorCode: 'recording_guard_failed',
          hint: l10n.recordingGuardFailed,
        );
        // The silent recording must not be pasted or saved; the engine is
        // warmed up on start, so its call count proves nothing here.
        expect(h.paste.pastedTexts, isEmpty);
        await _teardown(tester);
      },
    );

    for (final phrase in const [
      'Untertitel im Auftrag des ZDF',
      'Thank you for watching.',
      '[Musik]',
    ]) {
      testWidgets(
        'silence, STT returns "$phrase": not pasted, not saved, hint shown',
        (tester) async {
          final h = await _pump(
            tester,
            settings: _settings(deadMicTimeout: 0),
            wav: _silenceWav(),
            engine: _FakeWhisperEngine(responseText: phrase),
            hints: true,
          );
          final l10n = await L10n.delegate.load(const Locale('en'));

          await h.dictate();

          await _expectNothingPastedWithHint(
            tester,
            h,
            errorCode: 'transcription_empty',
            hint: l10n.errorTranscriptionEmpty,
          );
          await _teardown(tester);
        },
      );
    }

    testWidgets(
      'a lone sound annotation "(Musik)" from silence is not pasted',
      (tester) async {
        final h = await _pump(
          tester,
          settings: _settings(deadMicTimeout: 0),
          wav: _silenceWav(),
          engine: _FakeWhisperEngine(responseText: '(Musik)'),
          hints: true,
        );
        final l10n = await L10n.delegate.load(const Locale('en'));

        await h.dictate();

        await _expectNothingPastedWithHint(
          tester,
          h,
          errorCode: 'transcription_empty',
          hint: l10n.errorTranscriptionEmpty,
        );
        await _teardown(tester);
      },
    );

    testWidgets('one loud sample in silence keeps the dead-mic guard armed', (
      tester,
    ) async {
      final levels = StreamController<double>.broadcast();
      addTearDown(levels.close);
      final h = await _pump(
        tester,
        settings: _settings(),
        wav: _silenceWav(),
        engine: _FakeWhisperEngine(responseText: _raw),
        levels: levels,
        hints: true,
      );
      final l10n = await L10n.delegate.load(const Locale('en'));

      await h.startOnly();
      // One sample just above the 0.02 threshold, then 3 s of silence.
      levels.add(0.05);
      for (var i = 0; i < 3 * amplitudeSamplesPerSecond + 5; i++) {
        levels.add(0);
      }

      await _expectNothingPastedWithHint(
        tester,
        h,
        errorCode: 'recording_guard_failed',
        hint: l10n.recordingGuardFailed,
      );
      await _teardown(tester);
    });

    testWidgets(
      'a cloud (OpenAI) hallucination "Thank you for watching." is not pasted',
      (tester) async {
        final client = http_testing.MockClient(
          (_) async => http.Response(
            jsonEncode({'text': 'Thank you for watching.'}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
        final h = await _pump(
          tester,
          settings: _settings(
            provider: SttProviderType.openAI,
            deadMicTimeout: 0,
          ),
          wav: _silenceWav(),
          engine: _FakeWhisperEngine(),
          hints: true,
          extra: [
            transcriberProvider.overrideWith(
              (ref) => OpenAiTranscriber(ref: ref, httpClient: client),
            ),
          ],
        );
        final l10n = await L10n.delegate.load(const Locale('en'));

        await h.dictate();

        await _expectNothingPastedWithHint(
          tester,
          h,
          errorCode: 'transcription_empty',
          hint: l10n.errorTranscriptionEmpty,
        );
        await _teardown(tester);
      },
    );
  });
}
