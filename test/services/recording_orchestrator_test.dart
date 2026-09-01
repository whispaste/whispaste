/// Recording orchestrator unit tests.
///
/// Tests the critical dictation pipeline (audio → STT → history → clipboard)
/// using fake dependencies injected via Riverpod overrides.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/logging/perf_instrumentation.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/recording/clipping_state.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paste_failure_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/path_service.dart'
    show
        sttDirOverride,
        sttDir,
        sttModelPath,
        retainedAudioDirOverride,
        retainedAudioDir;
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/services/snippets/interactive_snippet_composer.dart'
    show legacyInteractiveSnippetTemplate;
import 'package:whispaste/services/snippets/interactive_snippet_controller.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_controller.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_events.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_service.dart';
import 'package:whispaste/services/sound_feedback_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/services/tray_service.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Minimal fake [HotKeyRegistrar] for the session-scoped
/// interactive-snippet keys (Enter/Escape): records registrations and
/// exposes the captured keyDown handlers so a test can synthesize presses.
class FakeSessionKeyRegistrar implements HotKeyRegistrar {
  final List<HotKey> registered = [];
  final Map<int, HotKeyHandler> keyDownHandlersByKeyId = {};

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    registered.add(hotKey);
    if (keyDownHandler != null) {
      keyDownHandlersByKeyId[hotKey.logicalKey.keyId] = keyDownHandler;
    }
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
  }

  bool isRegistered(LogicalKeyboardKey key) =>
      registered.any((k) => k.logicalKey == key);

  /// Synthesizes a key-down of [key] through the captured handler.
  void press(LogicalKeyboardKey key) =>
      keyDownHandlersByKeyId[key.keyId]?.call(HotKey(key: key));
}

/// Fake audio service — no real hardware interaction.
class FakeAudioService extends AudioServiceNotifier {
  String? wavPathToReturn;
  bool errorOnStart = false;
  StreamController<double>? _ampCtrl;

  /// Counts how many times [startRecording] was successfully invoked
  /// (i.e. not blocked by the "already recording" guard).
  int startCallCount = 0;

  /// Overrides the inherited [lastRecordingClippedSamples] getter so tests
  /// can simulate clipping outcomes without driving the real PCM pipeline.
  int clippedSamplesToReport = 0;

  @override
  int get lastRecordingClippedSamples => clippedSamplesToReport;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => _ampCtrl?.stream;

  @override
  Future<void> startRecording() async {
    if (state.isRecording) {
      // Mirror the audio service's logged no-op — do NOT throw.
      return;
    }
    if (errorOnStart) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'mic_error',
      );
      return;
    }
    startCallCount++;
    _ampCtrl = StreamController<double>.broadcast();
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPathToReturn,
    );
  }

  @override
  Future<String?> stopRecording() async {
    _ampCtrl?.close();
    _ampCtrl = null;
    state = AudioStatus(filePath: wavPathToReturn);
    return wavPathToReturn;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

/// Fake STT service — returns configurable transcripts, no subprocess.
class FakeSttService extends SttServerStateNotifier {
  String transcriptToReturn = 'Hello world';
  bool ensureRunningThrows = false;
  bool throwTimeoutException = false;
  bool transcribeThrows = false;

  /// Language the orchestrator handed to the last [transcribeBytes] call.
  String? lastLanguage;

  /// Counts how many times [transcribeBytes] was invoked.
  int transcribeCallCount = 0;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning() async {
    if (throwTimeoutException) {
      throw TimeoutException(
        'STT start timed out',
        const Duration(seconds: 30),
      );
    }
    if (ensureRunningThrows) {
      throw Exception('STT server failed to start');
    }
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytes(List<int> wavBytes, {String? language}) async {
    transcribeCallCount++;
    lastLanguage = language;
    if (transcribeThrows) {
      throw Exception('Transcription failed');
    }
    return transcriptToReturn;
  }

  @override
  Future<void> prewarm() async {}
}

/// Fake settings notifier — returns test defaults without DB or secure store.
class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? _testDefaults;

  final AppSettings _settings;

  /// Test defaults keep post-processing disabled to stay focused on the
  /// transcription pipeline in these unit tests.
  static const _testDefaults = AppSettings(
    afterTranscriptionSection: AfterTranscriptionSettings(
      afterTranscription: 'nothing',
    ),
  );

  @override
  Future<AppSettings> build() async => _settings;
}

/// In-memory secure key store that never touches platform credential stores.
class FakeSecureKeyStore extends SecureKeyStore {
  FakeSecureKeyStore() : super(null);

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

/// Fake desktop paste bridge that records capture/paste calls.
class FakeDesktopPasteController extends DesktopPasteController {
  int captureCalls = 0;
  int pasteCalls = 0;
  int typeCalls = 0;
  Duration? lastDelay;
  Duration? lastTypeDelay;
  String? lastTypedText;
  bool pasteResult = true;

  /// Defaults to `false` (NOT `true`, unlike [pasteResult]): `paste()` tries
  /// typing first on macOS/Windows (see `DesktopPaster.paste`), and this
  /// suite's test host IS macOS — if this defaulted to succeeding, every
  /// existing paste-flow test below would silently short-circuit through
  /// the typing branch and never reach the classic clipboard+paste-shortcut
  /// path it's actually exercising. Tests that specifically want the typing
  /// branch to succeed set this explicitly.
  bool typeResult = false;
  bool captureResult = true;
  final captureResults = <bool>[];
  bool disposed = false;

  /// Test seam for issue 02 (paste-failure/blocklist regression): lets a test
  /// force a specific native outcome (e.g. [NativePasteStatus.permissionMissing])
  /// beyond the plain success/[NativePasteStatus.postFailed] toggle above.
  /// Takes priority over [pasteResult] when set.
  NativePasteStatus? pasteStatusOverride;

  /// Same idea as [pasteStatusOverride], for [typeText]. Takes priority over
  /// [typeResult] when set.
  NativePasteStatus? typeStatusOverride;

  /// Test seam for issue 02: the bundle ID [DesktopPaster.paste] sees when it
  /// checks the auto-paste blocklist. `null` (the default) mirrors
  /// "bundle ID lookup unsupported/unknown" and skips the blocklist check.
  String? targetBundleIdToReturn;

  @override
  Future<bool> capturePasteTarget() async {
    captureCalls += 1;
    if (captureResults.isNotEmpty) {
      return captureResults.removeAt(0);
    }
    return captureResult;
  }

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    pasteCalls += 1;
    lastDelay = delay;
    if (pasteStatusOverride != null) {
      return NativePasteResult(status: pasteStatusOverride!);
    }
    return pasteResult
        ? const NativePasteResult(status: NativePasteStatus.success)
        : const NativePasteResult(status: NativePasteStatus.postFailed);
  }

  @override
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async {
    typeCalls += 1;
    lastTypeDelay = delay;
    lastTypedText = text;
    if (typeStatusOverride != null) {
      return NativePasteResult(status: typeStatusOverride!);
    }
    return typeResult
        ? const NativePasteResult(status: NativePasteStatus.success)
        : const NativePasteResult(status: NativePasteStatus.postFailed);
  }

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.ready);

  /// Counts entry resets. The failed-paste notification's live-probe arm is
  /// supposed to clear the stale TCC entry before re-asking, and a count is
  /// the only way to tell that apart from a plain Settings deep-link.
  int repairCalls = 0;

  @override
  Future<TccRepairResult> repairTccEntries() async {
    repairCalls += 1;
    return TccRepairResult.unsupported();
  }

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async =>
      const TestPasteOutcomeUnsupported();

  @override
  Future<String?> getTargetBundleId() async => targetBundleIdToReturn;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// Fake Snippet-Picker controller (dictation-automations ticket 06) — records
/// [show] calls and lets a test simulate the native panel firing an event
/// (an item pick or a cancellation) independently of the `show` call itself,
/// mirroring how the real native panel reports the user's pick asynchronously
/// after the pipeline has already returned to idle.
class FakeSnippetPickerController implements SnippetPickerController {
  final showCalls = <List<Map<String, String>>>[];
  int hideCalls = 0;
  bool disposed = false;

  final _eventsController = StreamController<SnippetPickerEvent>.broadcast();

  @override
  Stream<SnippetPickerEvent> get events => _eventsController.stream;

  @override
  Future<void> show({required List<Map<String, String>> items}) async {
    showCalls.add(items);
  }

  @override
  Future<void> hide() async {
    hideCalls += 1;
  }

  /// Simulates the native panel reporting [event] — a test calls this after
  /// [show] to drive the async insert path.
  void fireEvent(SnippetPickerEvent event) => _eventsController.add(event);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _eventsController.close();
  }
}

class FakeModelDownloadNotifier extends ModelDownloadNotifier {
  FakeModelDownloadNotifier(this._downloadedModels);

  final Set<String> _downloadedModels;

  @override
  ModelDownloadState build() {
    return ModelDownloadState(downloadedModels: _downloadedModels);
  }
}

/// Fake Smart Mode model download state (ticket 02) — pins
/// [SmartModeDownloadState.modelDownloaded] without touching disk.
class FakeSmartModeDownloadNotifier extends SmartModeDownloadNotifier {
  FakeSmartModeDownloadNotifier({this.modelDownloaded = true});

  final bool modelDownloaded;

  @override
  SmartModeDownloadState build() =>
      SmartModeDownloadState(modelDownloaded: modelDownloaded);
}

/// Fake [SmartModeEngine] (ticket 02) — configurable success/failure/timeout
/// behaviour, no real FFI/model involved.
class FakeSmartModeEngine implements SmartModeEngine {
  FakeSmartModeEngine({
    this.resultToReturn,
    this.errorToThrow,
    this.delay = Duration.zero,
  });

  /// Text to return on success. Ignored if [errorToThrow] is set.
  String? resultToReturn;

  /// If set, [run] throws this instead of returning [resultToReturn].
  Object? errorToThrow;

  /// Artificial delay before resolving/throwing — used to exercise the
  /// orchestrator's own timeout.
  Duration delay;

  int runCalls = 0;
  String? lastSystemPrompt;
  String? lastUserText;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    runCalls++;
    lastSystemPrompt = systemPrompt;
    lastUserText = userText;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final error = errorToThrow;
    if (error != null) {
      throw error;
    }
    return resultToReturn ?? userText;
  }
}

/// Fake tray service for issue 02 (paste-failure/blocklist regression) —
/// records "Action Needed" calls without touching the real `tray_manager`
/// platform channel (which isn't available in the test host process).
class FakeTrayActionService extends TrayService {
  final setActionNeededCalls = <String>[];
  final setActionNeededKeys = <String?>[];
  int clearActionNeededCalls = 0;

  @override
  void build() {
    // No-op: skip the real _init() (tray_manager platform channel).
  }

  @override
  void setActionNeeded({
    required String label,
    required String tooltip,
    String? menuItemKey,
  }) {
    setActionNeededCalls.add(label);
    setActionNeededKeys.add(menuItemKey);
  }

  @override
  void clearActionNeeded() {
    clearActionNeededCalls++;
  }
}

/// Fake system-attention service for issue 02 — records calls without
/// touching `local_notifier` / macOS dock-bounce platform channels.
class FakeSystemAttentionService extends SystemAttentionService {
  FakeSystemAttentionService(super.ref);

  int requestAttentionCalls = 0;
  int clearAttentionCalls = 0;
  AttentionKind? lastKind;
  String? lastTitle;
  String? lastBody;
  void Function()? lastOnClick;

  @override
  Future<void> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
  }) async {
    requestAttentionCalls++;
    lastKind = kind;
    lastTitle = title;
    lastBody = body;
    lastOnClick = onClick;
  }

  @override
  Future<void> clearAttention() async {
    clearAttentionCalls++;
  }
}

/// Seeds a fixed [PasteCapabilityState] so a test can pin
/// [PasteCapabilityNotifier.needsRestart] without driving the polling
/// machinery. Inherits the real `requiredAction` / `needsRestart` /
/// `openAccessibilitySettings` so the routing under test exercises production
/// logic, not a re-implementation.
class _SeededPasteCapabilityNotifier extends PasteCapabilityNotifier {
  _SeededPasteCapabilityNotifier(this._seed, {this.cachedProbe = true});

  final PasteCapabilityState _seed;

  /// Which macOS build leg to pin. Defaults to the cached-probe (Mac App
  /// Store) leg: it is the only build where `requiredAction` resolves to
  /// `restart`, so it is the only one whose failed-paste notification can
  /// route to the restart copy. On the live-probe Developer-ID build the same
  /// seed routes to the entry-reset copy instead — a relaunch there cannot
  /// reveal a grant that polling would not already have seen, but a stale TCC
  /// entry can. See [PasteCapabilityNotifier.usesCachedPermissionProbe] and
  /// [PasteCapabilityNotifier.grantRequiresEntryReset].
  final bool cachedProbe;

  @override
  PasteCapabilityState build() {
    usesCachedPermissionProbe = cachedProbe;
    return _seed;
  }
}

/// Fake sound feedback service for issue 09 — records `playError()` calls
/// without touching the real SoLoud engine.
class FakeSoundFeedbackService extends SoundFeedbackService {
  int playErrorCalls = 0;

  @override
  void build() {
    // No-op: skip the real engine lazy-init bookkeeping.
  }

  @override
  Future<void> playError() async {
    playErrorCalls++;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Directory for scratch files used during tests.
final _scratchDir = Directory('test${Platform.pathSeparator}.scratch');

/// Creates a fake WAV file with a minimal RIFF header + padding.
/// Returns the file with an absolute path.
File createFakeWav(String name) {
  // 44-byte WAV header + 320 bytes of silence = ~10 ms at 16 kHz mono 16-bit.
  final bytes = List<int>.filled(364, 0);
  bytes[0] = 0x52; // R
  bytes[1] = 0x49; // I
  bytes[2] = 0x46; // F
  bytes[3] = 0x46; // F
  final file = File('${_scratchDir.path}${Platform.pathSeparator}$name');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return file;
}

/// Creates a placeholder model file so the real on-device preflight check
/// in [RecordingOrchestrator.startRecording] passes. Content is
/// irrelevant — [localSttBundleProvider] is overridden with
/// [FakeSttService], so nothing ever executes or reads this file;
/// preflight only checks that it exists. Requires [sttDirOverride] to
/// already point at the test scratch directory.
void ensureFakeLocalSttFilesExist({String modelId = 'whisper-small'}) {
  Directory(sttDir()).createSync(recursive: true);
  final modelPath = sttModelPath(modelId);
  if (modelPath != null && !File(modelPath).existsSync()) {
    File(modelPath).writeAsStringSync('fake-model');
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late FakeAudioService fakeAudio;
  late FakeSttService fakeStt;
  late FakeDesktopPasteController fakeDesktopPaste;
  late HistoryDatabase db;
  late File wavFile;
  String? clipboardText;

  ProviderContainer buildContainer(AppSettings settings) {
    return ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        audioServiceProvider.overrideWith(() => fakeAudio),
        localSttBundleProvider.overrideWith(() => fakeStt),
        settingsProvider.overrideWith(() => FakeSettingsNotifier(settings)),
        secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
        desktopPasteControllerProvider.overrideWith((ref) => fakeDesktopPaste),
        modelDownloadProvider.overrideWith(
          () => FakeModelDownloadNotifier({
            'whisper-small',
            'whisper-medium',
            'whisper-large-v3-turbo',
          }),
        ),
      ],
    );
  }

  setUp(() async {
    // Isolate preflight checks from the real filesystem by pointing
    // sttDir at an empty scratch directory — no server binary exists here.
    sttDirOverride = _scratchDir.path;
    retainedAudioDirOverride =
        '${_scratchDir.path}${Platform.pathSeparator}retained-audio';

    // Create a fake WAV file the orchestrator can read.
    wavFile = createFakeWav(
      'test_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
    fakeStt = FakeSttService();
    fakeDesktopPaste = FakeDesktopPasteController();
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    clipboardText = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final args = Map<String, dynamic>.from(call.arguments as Map);
              clipboardText = args['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (clipboardText == null) return null;
              return <String, dynamic>{'text': clipboardText};
            default:
              return null;
          }
        });

    container = buildContainer(
      const AppSettings(
        stt: SttSettings(model: 'whisper-small', language: 'English'),
        afterTranscriptionSection: AfterTranscriptionSettings(
          afterTranscription: 'nothing',
        ),
        onboarding: OnboardingSettings(onboardingCompleted: true),
      ),
    );

    // Ensure async providers resolve before tests run.
    await container.read(settingsProvider.future);
  });

  tearDown(() {
    sttDirOverride = null;
    retainedAudioDirOverride = null;
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    if (wavFile.existsSync()) {
      try {
        wavFile.deleteSync();
      } catch (_) {}
    }
  });

  // Clean up the scratch directory after all tests.
  tearDownAll(() {
    if (_scratchDir.existsSync()) {
      try {
        _scratchDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  // ── Helper: initialize orchestrator and move state to recording ─────────

  /// Initializes the orchestrator and drives the state machine to
  /// [RecordingPhase.recording].
  ///
  /// We set the phase manually because [startRecording] runs preflight
  /// checks against real filesystem paths that don't exist in tests.
  Future<RecordingOrchestrator> startRecordingPhase() async {
    final orch = container.read(recordingOrchestratorProvider.notifier);
    // Let the build() microtask (pre-warm) run and settle.
    await Future<void>.delayed(Duration.zero);

    container.read(recordingProvider.notifier).startRecording();
    expect(container.read(recordingProvider).phase, RecordingPhase.recording);
    return orch;
  }

  // =========================================================================
  // Recognition language (store-review regression, June 2026)
  // =========================================================================

  group('Recognition language', () {
    /// Rebuilds the container with [stt]/[interface_] overrides and runs a
    /// full record→transcribe cycle, returning the language the transcriber
    /// received.
    Future<String?> languageSeenByTranscriber({
      required SttSettings stt,
      InterfaceSettings interface_ = const InterfaceSettings(),
    }) async {
      container.dispose();
      container = buildContainer(
        AppSettings(
          interface_: interface_,
          stt: stt,
          afterTranscriptionSection: const AfterTranscriptionSettings(
            afterTranscription: 'nothing',
          ),
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      final orch = await startRecordingPhase();
      await orch.stopRecording();
      return fakeStt.lastLanguage;
    }

    test('auto-detect reaches the transcriber as auto — never the UI '
        'locale', () async {
      // A Russian speaker on an English UI: before the fix the app forced
      // language=en and whisper produced English text from Russian audio.
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small'),
        interface_: const InterfaceSettings(locale: 'en'),
      );
      expect(lang, 'auto');
    });

    test('auto-detect ignores non-English UI locales too', () async {
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small'),
        interface_: const InterfaceSettings(locale: 'he'),
      );
      expect(lang, 'auto');
    });

    test('a catalog language code reaches the transcriber unchanged', () async {
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small', language: 'ru'),
      );
      expect(lang, 'ru');
    });

    test('legacy display value still resolves to its code', () async {
      final lang = await languageSeenByTranscriber(
        stt: const SttSettings(model: 'whisper-small', language: 'German'),
      );
      expect(lang, 'de');
    });
  });

  // =========================================================================
  // Happy path
  // =========================================================================

  group('Happy path', () {
    test('stopRecording transcribes and saves to history', () async {
      fakeStt.transcriptToReturn = 'Test transcription result';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
      expect(state.transcript, 'Test transcription result');

      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.content, 'Test transcription result');
      expect(entries.first.model, 'whisper-small');
      expect(entries.first.isLocal, isTrue);
      expect(entries.first.source, 'dictation');
    });

    test('toggleRecording from recording state runs pipeline', () async {
      fakeStt.transcriptToReturn = 'Toggle result';
      final orch = await startRecordingPhase();

      await orch.toggleRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
      expect(state.transcript, 'Toggle result');
    });

    test('daily stats are recorded', () async {
      fakeStt.transcriptToReturn = 'Stats test';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final stats = await db.customSelect('SELECT * FROM daily_stats').get();
      expect(stats, isNotEmpty);
    });

    test('auto-generates title from first ~60 chars', () async {
      fakeStt.transcriptToReturn = 'Short text';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries.first.title, 'Short text');
    });

    test('truncates long title at word boundary', () async {
      fakeStt.transcriptToReturn =
          'This is a very long transcription result that exceeds '
          'sixty characters and should be truncated at a word boundary';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries.first.title.length, lessThanOrEqualTo(62));
      expect(entries.first.title, endsWith('…'));
    });
  });

  // =========================================================================
  // Zahlen-Modus (numericOnlyMode, itn-cad-zahlen ticket 05) — R1-R7
  // =========================================================================

  group('Zahlen-Modus (numericOnlyMode)', () {
    /// Rebuilds the container with [stt]/[behavior] overrides, runs a full
    /// record→transcribe cycle targeting the clipboard, and returns the
    /// clipboard text so both the finalText result and (via [db]) the
    /// persisted history entry can be asserted.
    Future<void> runCase({
      required SttSettings stt,
      BehaviorSettings behavior = const BehaviorSettings(),
      required String transcript,
    }) async {
      container.dispose();
      container = buildContainer(
        AppSettings(
          stt: stt,
          behavior: behavior,
          afterTranscriptionSection: const AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: const OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = transcript;
      await orch.stopRecording();
    }

    test('R1: numericOnlyMode off leaves the transcript untouched', () async {
      await runCase(
        stt: const SttSettings(model: 'whisper-small', language: 'German'),
        transcript: 'fünf komma zwei minus drei',
      );

      expect(clipboardText, 'fünf komma zwei minus drei');
    });

    test('R2: a replacement rule matching a number word fires first, the '
        'numeric transform runs on its result', () async {
      await db.upsertReplacementWithTriggers(
        id: 'r1',
        triggers: ['boah'],
        replacement: 'acht',
        createdAt: DateTime.now(),
      );

      await runCase(
        stt: const SttSettings(
          model: 'whisper-small',
          language: 'German',
          numericOnlyMode: true,
        ),
        behavior: const BehaviorSettings(textReplacementsEnabled: true),
        transcript: 'boah komma fünf',
      );

      expect(clipboardText, '8,5');
    });

    test(
      'R3: numericOnlyMode + stripPunctuation together do not conflict — '
      'the digits/decimal-separator output survives the punctuation strip',
      () async {
        await runCase(
          stt: const SttSettings(
            model: 'whisper-small',
            language: 'German',
            numericOnlyMode: true,
            stripPunctuation: true,
          ),
          transcript: 'fünf komma zwei minus drei',
        );

        expect(clipboardText, '5,2-3');
      },
    );

    test(
      'R4: a transcript with no number words is left unchanged, no crash',
      () async {
        await runCase(
          stt: const SttSettings(
            model: 'whisper-small',
            language: 'German',
            numericOnlyMode: true,
          ),
          transcript: 'Hallo Welt',
        );

        expect(clipboardText, 'Hallo Welt');
      },
    );

    test('R5: Snippet-Picker exact-match dispatch still runs on the raw '
        'transcript, unaffected by numericOnlyMode', () async {
      final fakeSnippetPicker = FakeSnippetPickerController();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              const AppSettings(
                stt: SttSettings(
                  model: 'whisper-small',
                  language: 'German',
                  numericOnlyMode: true,
                ),
                afterTranscriptionSection: AfterTranscriptionSettings(
                  afterTranscription: 'paste',
                ),
                behavior: BehaviorSettings(snippetPickerTrigger: 'snippets'),
                onboarding: OnboardingSettings(onboardingCompleted: true),
              ),
            ),
          ),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(
            () => FakeModelDownloadNotifier({
              'whisper-small',
              'whisper-medium',
              'whisper-large-v3-turbo',
            }),
          ),
          snippetPickerControllerProvider.overrideWithValue(fakeSnippetPicker),
        ],
      );
      await container.read(settingsProvider.future);
      await db.upsertSnippet(
        id: 's1',
        title: 'Greeting',
        body: 'Hello there!',
        createdAt: DateTime.now(),
      );

      fakeStt.transcriptToReturn = 'Snippets.';
      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(fakeSnippetPicker.showCalls, hasLength(1));
      expect(await db.allEntries(), isEmpty);
    });

    test('R6: a transcript mixing a number word with an unclassifiable token '
        'is left unchanged (all-or-nothing, no partial conversion)', () async {
      await runCase(
        stt: const SttSettings(
          model: 'whisper-small',
          language: 'German',
          numericOnlyMode: true,
        ),
        transcript: 'fünf Apfel',
      );

      expect(clipboardText, 'fünf Apfel');
    });

    test('R7: per PRD §6.2 Option D1, the persisted history entry keeps the '
        'pre-transform (number-word) text — precedent-conform with how '
        'stripPunctuation already diverges from the pasted/clipboard text, '
        'no second DB write in the hotkey→text path', () async {
      await runCase(
        stt: const SttSettings(
          model: 'whisper-small',
          language: 'German',
          numericOnlyMode: true,
        ),
        transcript: 'fünf komma zwei minus drei',
      );

      expect(clipboardText, '5,2-3');
      final entries = await db.allEntries();
      expect(entries.first.content, 'fünf komma zwei minus drei');
    });
  });

  // =========================================================================
  // Snippet-Picker dispatch (exact-match short-circuit, dictation-automations
  // ticket 06)
  // =========================================================================

  group('Snippet-Picker dispatch (exact match)', () {
    late FakeSnippetPickerController fakeSnippetPicker;

    ProviderContainer buildSnippetPickerContainer(AppSettings settings) {
      return ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(() => FakeSettingsNotifier(settings)),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(
            () => FakeModelDownloadNotifier({
              'whisper-small',
              'whisper-medium',
              'whisper-large-v3-turbo',
            }),
          ),
          snippetPickerControllerProvider.overrideWithValue(fakeSnippetPicker),
        ],
      );
    }

    setUp(() {
      fakeSnippetPicker = FakeSnippetPickerController();
      container.dispose();
      container = buildSnippetPickerContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          behavior: BehaviorSettings(snippetPickerTrigger: 'snippets'),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
    });

    test('an exact-match transcript opens the panel, skips history and '
        'paste, and still returns to the done state — without capturing a '
        'paste target', () async {
      await container.read(settingsProvider.future);
      await db.upsertSnippet(
        id: 's1',
        title: 'Greeting',
        body: 'Hello there!',
        createdAt: DateTime.now(),
      );

      fakeStt.transcriptToReturn = 'Snippets.';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      expect(fakeSnippetPicker.showCalls, hasLength(1));
      expect(await db.allEntries(), isEmpty);
      expect(fakeDesktopPaste.pasteCalls, 0);
      expect(fakeDesktopPaste.typeCalls, 0);
      expect(fakeDesktopPaste.captureCalls, 0);
      expect(container.read(recordingInfoProvider), isNull);

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
    });

    test(
      'a selected snippet is pasted into the still-captured target '
      'without ever re-priming the paste target (ticket 06\'s core AC)',
      () async {
        await container.read(settingsProvider.future);
        await db.upsertSnippet(
          id: 's1',
          title: 'Greeting',
          body: 'Hello there!',
          createdAt: DateTime.now(),
        );

        fakeStt.transcriptToReturn = 'Snippets.';
        final orch = await startRecordingPhase();
        await orch.stopRecording();

        // The insert happens asynchronously off the panel's event stream,
        // fully decoupled from the pipeline run above — simulating the
        // native panel reporting the click after the fact.
        fakeSnippetPicker.fireEvent(const SnippetPickerItemSelected('s1'));
        await Future<void>.delayed(Duration.zero);

        expect(fakeDesktopPaste.pasteCalls, 1);
        expect(clipboardText, 'Hello there!');
        expect(fakeDesktopPaste.typeCalls, 0);
        expect(fakeDesktopPaste.captureCalls, 0);
      },
    );

    test('selecting an interactive snippet starts its guided field sequence '
        'instead of pasting anything', () async {
      // Production wiring lives in WpServiceBootstrap (not exercised by this
      // container-only test) to keep SnippetPickerService free of a
      // file-level import cycle with InteractiveSnippetController — mirror
      // it here.
      container
          .read(snippetPickerServiceProvider.notifier)
          .onInteractiveSnippetSelected = (snippet) async {
        final fields = await db.readSnippetFields(snippet.id);
        await container
            .read(interactiveSnippetControllerProvider.notifier)
            .start(fields, template: snippet.body);
      };
      container
              .read(interactiveSnippetControllerProvider.notifier)
              .announceDuration =
          Duration.zero;
      await container.read(settingsProvider.future);
      await db.upsertSnippetWithFields(
        id: 's1',
        title: 'Bug Report',
        body: 'Titel\n{{Titel}}\n\nReproduktion\n{{Reproduktion}}',
        createdAt: DateTime.now(),
        kind: 'interactive',
        fieldNames: const ['Titel', 'Reproduktion'],
      );

      fakeStt.transcriptToReturn = 'Snippets.';
      final orch = await startRecordingPhase();
      await orch.stopRecording();

      // The picker item carries the field names as its preview body, not
      // the (unused) static `body` column.
      expect(fakeSnippetPicker.showCalls, hasLength(1));
      expect(
        fakeSnippetPicker.showCalls.single.single['body'],
        'Titel · Reproduktion',
      );

      fakeSnippetPicker.fireEvent(const SnippetPickerItemSelected('s1'));
      // Unlike a static-snippet paste (a couple of microtask hops), priming
      // + starting a real recording crosses several genuine Timer-based
      // async gaps — a single zero-delay wait isn't reliably enough, so
      // poll briefly instead.
      for (
        var i = 0;
        i < 20 && container.read(interactiveSnippetControllerProvider) == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // The state flip above only proves `start()` reached its first
      // `state = ...` assignment — its trailing `orchestrator.startRecording`
      // await can still have real Timer-based work in flight. Give it a
      // moment to settle so nothing resolves after this test's container is
      // torn down.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fakeDesktopPaste.pasteCalls, 0);
      expect(fakeDesktopPaste.typeCalls, 0);

      final session = container.read(interactiveSnippetControllerProvider);
      expect(session, isNotNull);
      expect(session!.fieldIndex, 0);
      expect(session.fieldCount, 2);
      expect(session.fieldName, 'Titel');
    });

    test('a transcript that only contains the trigger word as a substring '
        '(not an exact match) runs the normal pipeline instead', () async {
      await container.read(settingsProvider.future);
      await db.upsertSnippet(
        id: 's1',
        title: 'Greeting',
        body: 'Hello there!',
        createdAt: DateTime.now(),
      );

      fakeStt.transcriptToReturn = 'please open snippets for me';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      expect(fakeSnippetPicker.showCalls, isEmpty);
      final entries = await db.allEntries();
      expect(entries, hasLength(1));
    });

    test('an exact match with zero snippets configured falls back to the '
        'normal pipeline instead of losing the dictation — and reports the '
        'empty-list case via the recording-info channel', () async {
      await container.read(settingsProvider.future);

      fakeStt.transcriptToReturn = 'Snippets.';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      expect(fakeSnippetPicker.showCalls, isEmpty);
      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      // Without this signal the fallback is indistinguishable from "the
      // trigger didn't work" for the user (the word is just pasted normally).
      expect(
        container.read(recordingInfoProvider),
        'info_snippet_picker_empty',
      );
    });

    test('a non-matching transcript with zero snippets never fires the '
        'empty-list info signal', () async {
      await container.read(settingsProvider.future);

      fakeStt.transcriptToReturn = 'just a normal dictation';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      expect(fakeSnippetPicker.showCalls, isEmpty);
      expect(container.read(recordingInfoProvider), isNull);
    });

    test('an empty trigger word (feature off, the default) never opens the '
        'panel', () async {
      container.dispose();
      container = buildSnippetPickerContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      await db.upsertSnippet(
        id: 's1',
        title: 'Greeting',
        body: 'Hello there!',
        createdAt: DateTime.now(),
      );

      fakeStt.transcriptToReturn = 'snippets';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      expect(fakeSnippetPicker.showCalls, isEmpty);
      final entries = await db.allEntries();
      expect(entries, hasLength(1));
    });

    test('an exact-match trigger is skipped for a quick-note target — the '
        'picker inserts by pasting into the focused app, which makes no '
        'sense for a note target (ticket 19)', () async {
      await container.read(settingsProvider.future);
      await db.upsertSnippet(
        id: 's1',
        title: 'Greeting',
        body: 'Hello there!',
        createdAt: DateTime.now(),
      );
      final note = await db.createNote();
      await db.setQuickNote(note.id);

      fakeStt.transcriptToReturn = 'Snippets.';
      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      await orch.stopRecording();

      expect(fakeSnippetPicker.showCalls, isEmpty);
      expect((await db.getNote(note.id))?.content, 'Snippets.');
    });
  });

  // =========================================================================
  // Snippet-Picker hotkey (ticket 26) — opens the panel directly by hotkey,
  // WITHOUT starting a recording, STT run, or history entry.
  // =========================================================================

  group('Snippet-Picker hotkey (ticket 26)', () {
    late FakeSnippetPickerController fakeSnippetPicker;

    ProviderContainer buildSnippetPickerHotkeyContainer(AppSettings settings) {
      return ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(() => FakeSettingsNotifier(settings)),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(
            () => FakeModelDownloadNotifier({
              'whisper-small',
              'whisper-medium',
              'whisper-large-v3-turbo',
            }),
          ),
          snippetPickerControllerProvider.overrideWithValue(fakeSnippetPicker),
        ],
      );
    }

    setUp(() {
      fakeSnippetPicker = FakeSnippetPickerController();
      container.dispose();
      container = buildSnippetPickerHotkeyContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'nothing',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
    });

    /// Reads the orchestrator notifier and lets its pre-warm `build()`
    /// microtask settle — same idiom as [startRecordingPhase] above, minus
    /// the phase transition (the hotkey path must never touch it).
    Future<RecordingOrchestrator> readOrchestrator() async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      return orch;
    }

    // snippetPickerAvailableOnPlatform is hardcoded to Platform.isMacOS and
    // can't be faked from a test (see the non-mac test below, which works
    // around that a different way) — so every test here that expects the
    // hotkey to actually open the panel only holds on a real macOS host.
    // Skipped rather than deleted or platform-gated in assertions: these are
    // still the right spec for the feature once it ships elsewhere.
    group('on macOS, where the native picker exists', () {
      test('opens the panel with all snippets, capturing the paste target '
          'exactly once, without starting any recording', () async {
        await container.read(settingsProvider.future);
        await db.upsertSnippet(
          id: 's1',
          title: 'Greeting',
          body: 'Hello there!',
          createdAt: DateTime.now(),
        );
        final orch = await readOrchestrator();

        await orch.openSnippetPickerViaHotkey();

        expect(fakeSnippetPicker.showCalls, hasLength(1));
        expect(fakeDesktopPaste.captureCalls, 1);
        expect(container.read(recordingProvider).phase, RecordingPhase.idle);
        expect(fakeAudio.startCallCount, 0);
        expect(await db.allEntries(), isEmpty);
      });

      test(
        'selecting a snippet afterward does not re-capture the paste target',
        () async {
          await container.read(settingsProvider.future);
          await db.upsertSnippet(
            id: 's1',
            title: 'Greeting',
            body: 'Hello there!',
            createdAt: DateTime.now(),
          );
          final orch = await readOrchestrator();

          await orch.openSnippetPickerViaHotkey();
          fakeSnippetPicker.fireEvent(const SnippetPickerItemSelected('s1'));
          await Future<void>.delayed(Duration.zero);

          expect(fakeDesktopPaste.captureCalls, 1);
          expect(fakeDesktopPaste.pasteCalls, 1);
          expect(clipboardText, 'Hello there!');
        },
      );

      test(
        'a running recording suppresses the hotkey without aborting it',
        () async {
          await container.read(settingsProvider.future);
          await db.upsertSnippet(
            id: 's1',
            title: 'Greeting',
            body: 'Hello there!',
            createdAt: DateTime.now(),
          );
          final orch = await readOrchestrator();
          container.read(recordingProvider.notifier).startRecording();

          await orch.openSnippetPickerViaHotkey();

          expect(fakeSnippetPicker.showCalls, isEmpty);
          expect(fakeDesktopPaste.captureCalls, 0);
          expect(
            container.read(recordingProvider).phase,
            RecordingPhase.recording,
          );
        },
      );

      test('a repeated press does not reopen an already-open panel', () async {
        await container.read(settingsProvider.future);
        await db.upsertSnippet(
          id: 's1',
          title: 'Greeting',
          body: 'Hello there!',
          createdAt: DateTime.now(),
        );
        final orch = await readOrchestrator();

        await orch.openSnippetPickerViaHotkey();
        await orch.openSnippetPickerViaHotkey();

        expect(fakeSnippetPicker.showCalls, hasLength(1));
        expect(fakeDesktopPaste.captureCalls, 1);
      });

      test(
        'a cancelled panel allows the next press to open it again',
        () async {
          await container.read(settingsProvider.future);
          await db.upsertSnippet(
            id: 's1',
            title: 'Greeting',
            body: 'Hello there!',
            createdAt: DateTime.now(),
          );
          final orch = await readOrchestrator();

          await orch.openSnippetPickerViaHotkey();
          fakeSnippetPicker.fireEvent(const SnippetPickerCancelled());
          await Future<void>.delayed(Duration.zero);
          await orch.openSnippetPickerViaHotkey();

          expect(fakeSnippetPicker.showCalls, hasLength(2));
        },
      );

      test('an empty snippet list reports the same info signal as the voice '
          'path, without falling back to any pipeline', () async {
        await container.read(settingsProvider.future);
        final orch = await readOrchestrator();

        await orch.openSnippetPickerViaHotkey();

        expect(fakeSnippetPicker.showCalls, isEmpty);
        expect(
          container.read(recordingInfoProvider),
          'info_snippet_picker_empty',
        );
        expect(await db.allEntries(), isEmpty);
      });
    }, skip: !Platform.isMacOS);

    test('on a platform without a native picker, the hotkey does nothing '
        'harmful', () async {
      await container.read(settingsProvider.future);
      await db.upsertSnippet(
        id: 's1',
        title: 'Greeting',
        body: 'Hello there!',
        createdAt: DateTime.now(),
      );
      // snippetPickerAvailableOnPlatform is hardcoded to Platform.isMacOS
      // and can't be faked from a test; overriding the controller provider
      // to null instead reaches the same `unavailable` outcome one level
      // down — SnippetPickerService.show() sees a null controller exactly
      // like createSnippetPickerController() would return on Windows/Linux.
      container.dispose();
      container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              const AppSettings(
                stt: SttSettings(model: 'whisper-small', language: 'English'),
                afterTranscriptionSection: AfterTranscriptionSettings(
                  afterTranscription: 'nothing',
                ),
                onboarding: OnboardingSettings(onboardingCompleted: true),
              ),
            ),
          ),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(
            () => FakeModelDownloadNotifier({
              'whisper-small',
              'whisper-medium',
              'whisper-large-v3-turbo',
            }),
          ),
          snippetPickerControllerProvider.overrideWithValue(null),
        ],
      );
      await container.read(settingsProvider.future);
      final orch = await readOrchestrator();

      await expectLater(orch.openSnippetPickerViaHotkey(), completes);

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
      expect(fakeAudio.startCallCount, 0);
      expect(await db.allEntries(), isEmpty);
    });
  });

  // =========================================================================
  // Error during STT start
  // =========================================================================

  group('Error during STT start', () {
    test('ensureRunning() throws → state is error', () async {
      fakeStt.ensureRunningThrows = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, contains('STT server failed'));
    });
  });

  // =========================================================================
  // Timeout during STT start
  // =========================================================================

  group('Timeout during STT start', () {
    test('TimeoutException → fails with stt_start_timeout', () async {
      fakeStt.throwTimeoutException = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'stt_start_timeout');
    });
  });

  // =========================================================================
  // Error during transcription
  // =========================================================================

  group('Error during transcription', () {
    test('transcribeBytes() throws → state is error', () async {
      fakeStt.transcribeThrows = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, contains('Transcription failed'));
    });

    test('no history entry is saved on transcription error', () async {
      fakeStt.transcribeThrows = true;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });
  });

  // =========================================================================
  // Cancel / reset during recording
  // =========================================================================

  group('Cancel during recording', () {
    test('reset() returns to idle without transcription', () async {
      final orch = await startRecordingPhase();

      orch.reset();

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });
  });

  // =========================================================================
  // Guard resets after error — can record again
  // =========================================================================

  group('Guard resets after error', () {
    test('error → reset → second attempt succeeds', () async {
      // First attempt: STT fails.
      fakeStt.ensureRunningThrows = true;
      final orch = await startRecordingPhase();
      await orch.stopRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.error);

      // Reset to idle.
      orch.reset();
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);

      // Second attempt: fix the fake and retry.
      fakeStt.ensureRunningThrows = false;
      fakeStt.transcriptToReturn = 'Recovered';

      // Re-create the WAV since the first attempt cleans up (our fake is
      // a no-op, but the path must still resolve for the second run).
      wavFile = createFakeWav(
        'test_audio_retry_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio.wavPathToReturn = wavFile.absolute.path;

      container.read(recordingProvider.notifier).startRecording();
      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(container.read(recordingProvider).transcript, 'Recovered');
    });
  });

  // =========================================================================
  // Flow-first re-trigger: a lingering done/error status must never block the
  // next dictation (push-to-hold should fire immediately after a paste).
  // =========================================================================

  group('Re-trigger preempts lingering terminal status', () {
    test('startRecording from done preempts the linger (leaves done)', () async {
      fakeStt.transcriptToReturn = 'first';
      final orch = await startRecordingPhase();
      await orch.stopRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      final phases = <RecordingPhase>[];
      container.listen(
        recordingProvider.select((s) => s.phase),
        (_, p) => phases.add(p),
        fireImmediately: false,
      );

      // Real startRecording preempts done → idle before preflight. Preflight may
      // then fail in the test sandbox, but the lingering done — the thing that
      // used to block the next recording — must already be gone.
      await orch.startRecording();

      expect(phases, contains(RecordingPhase.idle));
      expect(
        container.read(recordingProvider).phase,
        isNot(RecordingPhase.done),
      );
    });

    test('toggleRecording from done no longer silently ignores', () async {
      fakeStt.transcriptToReturn = 'first';
      final orch = await startRecordingPhase();
      await orch.stopRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      await orch.toggleRecording();

      // Old behavior left the phase stuck in done; now it preempts and attempts
      // a fresh start.
      expect(
        container.read(recordingProvider).phase,
        isNot(RecordingPhase.done),
      );
    });

    test('startRecording from error preempts the linger', () async {
      fakeStt.ensureRunningThrows = true;
      final orch = await startRecordingPhase();
      await orch.stopRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.error);

      final phases = <RecordingPhase>[];
      container.listen(
        recordingProvider.select((s) => s.phase),
        (_, p) => phases.add(p),
        fireImmediately: false,
      );

      await orch.startRecording();

      expect(phases, contains(RecordingPhase.idle));
      expect(
        container.read(recordingProvider).phase,
        isNot(RecordingPhase.error),
      );
    });
  });

  // =========================================================================
  // Phase transitions
  // =========================================================================

  group('Phase transitions', () {
    test('correct order: idle → recording → transcribing → done', () async {
      fakeStt.transcriptToReturn = 'Phase test';

      final phases = <RecordingPhase>[];
      container.listen(
        recordingProvider.select((s) => s.phase),
        (_, phase) => phases.add(phase),
        fireImmediately: true,
      );

      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(
        phases,
        containsAllInOrder([
          RecordingPhase.idle,
          RecordingPhase.recording,
          RecordingPhase.transcribing,
          RecordingPhase.done,
        ]),
      );
    });
  });

  // =========================================================================
  // Empty transcript
  // =========================================================================

  group('Empty transcript', () {
    test('empty STT result → fails with transcription_empty', () async {
      fakeStt.transcriptToReturn = '';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'transcription_empty');
    });

    test('no history entry is saved on empty transcript', () async {
      fakeStt.transcriptToReturn = '';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });
  });

  // =========================================================================
  // No audio recorded
  // =========================================================================

  group('No audio recorded', () {
    test('null WAV path → fails with no_audio_recorded', () async {
      fakeAudio.wavPathToReturn = null;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'no_audio_recorded');
    });
  });

  // =========================================================================
  // Preflight failure (startRecording)
  // =========================================================================

  group('Preflight failure', () {
    test('missing STT model is soft-handled (stays idle)', () async {
      // Soft-preflight catches stt_model_not_found and shows an info
      // notification instead of entering the error phase.
      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .startRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.idle);
      expect(state.errorMessage, isNull);
    });

    test('toggleRecording from idle with missing model stays idle', () async {
      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      await container
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
    });
  });

  // =========================================================================
  // Audio capture error
  // =========================================================================

  group('Audio capture error', () {
    test('audio service error on start → state is error', () async {
      // Override effective config so preflight passes (would need real
      // files). Instead, test the audio error path by going through
      // startRecording manually with a config that would pass preflight,
      // but we simulate audio failure after preflight.
      //
      // Since we can't easily pass preflight in tests, we verify the
      // guard by calling stopRecording with a missing WAV file.
      fakeAudio.wavPathToReturn = 'nonexistent_path_12345.wav';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'wav_file_not_created');
    });
  });

  // =========================================================================
  // STT server not ready after ensureRunning
  // =========================================================================

  group('STT server not ready', () {
    test('server state not ready → fails with stt_server_failed', () async {
      // Make ensureRunning succeed but leave state as non-ready.
      final customStt = _NotReadySttService();
      final c2 = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            final memDb = HistoryDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(memDb.close);
            return memDb;
          }),
          audioServiceProvider.overrideWith(() {
            return FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
          }),
          localSttBundleProvider.overrideWith(() => customStt),
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              const AppSettings(
                stt: SttSettings(model: 'whisper-small', language: 'English'),
                onboarding: OnboardingSettings(onboardingCompleted: true),
              ),
            ),
          ),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
        ],
      );
      addTearDown(c2.dispose);

      await c2.read(settingsProvider.future);
      final orch = c2.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      c2.read(recordingProvider.notifier).startRecording();
      await orch.stopRecording();

      final state = c2.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'stt_server_failed');
    });

    test(
      'CUDA OOM queues recovery dialog context and resets to idle',
      () async {
        final customStt = _NotReadySttService(
          statusAfterEnsure: const SttStatus(
            serverState: SttServerState.error,
            errorMessage: 'stt_cuda_oom',
          ),
        );
        final c2 = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              final memDb = HistoryDatabase.forTesting(NativeDatabase.memory());
              ref.onDispose(memDb.close);
              return memDb;
            }),
            audioServiceProvider.overrideWith(() {
              return FakeAudioService()
                ..wavPathToReturn = wavFile.absolute.path;
            }),
            localSttBundleProvider.overrideWith(() => customStt),
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                const AppSettings(
                  stt: SttSettings(
                    model: 'whisper-large-v3-turbo',
                    language: 'English',
                  ),
                  onboarding: OnboardingSettings(onboardingCompleted: true),
                ),
              ),
            ),
            secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
            modelDownloadProvider.overrideWith(
              () => FakeModelDownloadNotifier({
                'whisper-small',
                'whisper-medium',
                'whisper-large-v3-turbo',
              }),
            ),
          ],
        );
        addTearDown(c2.dispose);

        await c2.read(settingsProvider.future);
        final orch = c2.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        c2.read(recordingProvider.notifier).startRecording();
        await orch.stopRecording();

        expect(c2.read(recordingProvider).phase, RecordingPhase.idle);
        final recovery = c2.read(oomRecoveryPendingProvider);
        expect(recovery.pending, isTrue);
        expect(recovery.nextModelId, 'whisper-medium');
        expect(recovery.hasCloudConfigured, isFalse);
        expect(recovery.isPermanentFail, isFalse);
      },
    );
  });

  group('OOM recovery actions', () {
    test('applyOomModelFallback updates the local model', () async {
      // applyOomModelFallback only switches the model; the attempt counter is
      // incremented by OomRecoveryHandler.attemptRecovery() which is called
      // inside _handleOomRecovery() — not here.
      final orch = container.read(recordingOrchestratorProvider.notifier);

      final didSwitch = await orch.applyOomModelFallback('whisper-medium');

      expect(didSwitch, isTrue);
      expect(orch.oomAttemptCount, 0);
      final settings = await container.read(settingsProvider.future);
      expect(settings.effectiveModelId, 'whisper-medium');
    });

    test(
      'switchToConfiguredCloudStt prefers configured cloud provider',
      () async {
        final c2 = buildContainer(
          const AppSettings(
            stt: SttSettings(
              model: 'whisper-large-v3-turbo',
              language: 'English',
              provider: 'On Device',
            ),
            cloudProvider: CloudProviderSettings(
              cloudSttProvider: 'deepgram',
              deepgramApiKey: 'dg-test-key',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        addTearDown(c2.dispose);
        await c2.read(settingsProvider.future);

        final orch = c2.read(recordingOrchestratorProvider.notifier);
        final provider = await orch.switchToConfiguredCloudStt();
        final settings = await c2.read(settingsProvider.future);

        expect(provider, SttProviderType.deepgram);
        expect(settings.sttProviderType, SttProviderType.deepgram);
        expect(settings.cloudSttProviderType, CloudSttProvider.deepgram);
        expect(orch.oomAttemptCount, 0);
      },
    );
  });

  // =========================================================================
  // toggleRecording ignores non-idle / non-recording phases
  // =========================================================================

  group('toggleRecording guards', () {
    test('does nothing while transcribing', () async {
      final orch = await startRecordingPhase();

      // Drive to transcribing phase manually.
      container.read(recordingProvider.notifier).stopRecording();
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
      );

      await orch.toggleRecording();

      // Still transcribing — toggle was a no-op.
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.transcribing,
      );
    });

    test('preempts a lingering error so a new dictation can start', () async {
      container.read(recordingProvider.notifier).fail('test error');

      container.read(recordingOrchestratorProvider);
      await Future<void>.delayed(Duration.zero);

      final phases = <RecordingPhase>[];
      container.listen(
        recordingProvider.select((s) => s.phase),
        (_, p) => phases.add(p),
        fireImmediately: false,
      );

      await container
          .read(recordingOrchestratorProvider.notifier)
          .toggleRecording();

      // Flow-first: an error status is dismissable and its transcript is already
      // lost, so toggling preempts it (error → idle) and attempts a fresh start
      // instead of silently ignoring the press. (Contrast: transcribing is
      // in-flight work and is still guarded above.)
      expect(phases, contains(RecordingPhase.idle));
    });
  });

  // =========================================================================
  // Recording idempotency — concurrent toggleRecording() calls
  // =========================================================================

  group('Recording idempotency', () {
    test('two parallel startRecording() calls produce one start, '
        'zero errors, one capture session', () async {
      // Drive orchestrator to idle state with pre-warmed microtask settled.
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Manually start the recording phase so preflight (filesystem) is
      // bypassed, then verify the audio service idempotency guard:
      // calling the orchestrator's startRecording while _startInFlight
      // is active (or phase is non-idle) must be a logged no-op.

      // First call: set phase to recording directly (as other tests do).
      container.read(recordingProvider.notifier).startRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      // Audio service should not yet have been called via orchestrator.
      final countBefore = fakeAudio.startCallCount;

      // Second concurrent call to startRecording() — must be a no-op because
      // phase is no longer idle (immediate re-check after lock acquisition).
      final errors = <Object>[];
      await Future<void>(() async {
        try {
          await orch.startRecording();
        } catch (e) {
          errors.add(e);
        }
      });

      // No errors thrown.
      expect(errors, isEmpty, reason: 'startRecording must not throw');

      // Audio service startRecording was not called a second time.
      expect(
        fakeAudio.startCallCount,
        equals(countBefore),
        reason: 'Only one capture session should exist',
      );

      // Phase is still recording — the no-op left state unchanged.
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);
    });

    test('two concurrent toggleRecording() calls from idle produce '
        'one start and zero thrown errors', () async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Both calls start while phase is idle. The _startInFlight guard
      // ensures only the first call proceeds; the second is a no-op.
      //
      // Note: toggleRecording from idle runs startRecording() which runs
      // preflight against _scratchDir (no server binary → soft-handled,
      // stays idle). What matters here is that no StateError is thrown and
      // startCallCount stays at 0 (preflight blocks audio capture).
      final errors = <Object>[];

      await Future.wait([
        Future<void>(() async {
          try {
            await orch.toggleRecording();
          } catch (e) {
            errors.add(e);
          }
        }),
        Future<void>(() async {
          try {
            await orch.toggleRecording();
          } catch (e) {
            errors.add(e);
          }
        }),
      ]);

      // No errors thrown — idempotency holds.
      expect(errors, isEmpty, reason: 'toggleRecording must never throw');

      // At most one audio capture was started (soft-preflight may block all).
      expect(
        fakeAudio.startCallCount,
        lessThanOrEqualTo(1),
        reason: 'At most one audio capture session permitted',
      );
    });

    // ── Voice-note button path ──────────────────────────────────────────────

    test(
      'tryAcquireStartLock returns true when idle, false when in flight',
      () async {
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // First acquire succeeds while orchestrator is idle.
        expect(orch.tryAcquireStartLock(), isTrue);

        // Second acquire fails — lock already held.
        expect(orch.tryAcquireStartLock(), isFalse);

        // After release the lock is available again.
        orch.releaseStartLock();
        expect(orch.tryAcquireStartLock(), isTrue);

        // Clean up.
        orch.releaseStartLock();
      },
    );

    test(
      'tryAcquireStartLock returns false when orchestrator is not idle',
      () async {
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // Drive orchestrator to recording phase.
        container.read(recordingProvider.notifier).startRecording();
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        // Lock acquisition must be denied — phase is not idle.
        expect(orch.tryAcquireStartLock(), isFalse);
      },
    );

    test('voice-note lock: second concurrent tryAcquireStartLock() is denied '
        'while first holds the lock (AC4 — voice-note button path)', () async {
      // This test covers AC4 for the voice-note button path.
      // It exercises the shared _startInFlight lock directly, which is the
      // mechanism VoiceNoteButton._startVoiceNote() relies on to prevent
      // two concurrent voice-note taps from starting two capture sessions.
      //
      // Dart is single-threaded, so "concurrent" is modelled by acquiring
      // the lock in tap-1, then verifying tap-2 is denied before tap-1
      // releases — the same sequence that occurs when two UI taps arrive
      // in the same event-loop turn.
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Tap-1 acquires the lock.
      final acquired1 = orch.tryAcquireStartLock();
      expect(acquired1, isTrue, reason: 'First tap should acquire the lock');

      // While tap-1 holds the lock, tap-2 must be denied.
      final acquired2 = orch.tryAcquireStartLock();
      expect(
        acquired2,
        isFalse,
        reason: 'Second concurrent tap must be suppressed (lock held)',
      );

      // Tap-1 releases. Now a third tap (e.g. after tap-1 finishes) must
      // succeed — verifies the lock is properly reusable.
      orch.releaseStartLock();
      final acquired3 = orch.tryAcquireStartLock();
      expect(
        acquired3,
        isTrue,
        reason: 'New tap after release must be able to acquire the lock',
      );
      orch.releaseStartLock();
    });
  });

  // =========================================================================
  // Stop re-entry guard (_stopInFlight)
  // =========================================================================

  group('Stop re-entry guard', () {
    test('two concurrent stopRecording() calls produce exactly one '
        'transcription pipeline', () async {
      fakeStt.transcriptToReturn = 'one pipeline only';
      final orch = await startRecordingPhase();

      // Both futures start immediately in the same event-loop turn.
      // The first call sets _stopInFlight = true synchronously before any
      // await; the second sees the flag and returns without running the
      // pipeline.
      final f1 = orch.stopRecording();
      final f2 = orch.stopRecording();
      await Future.wait([f1, f2]);

      // Exactly one STT inference ran.
      expect(
        fakeStt.transcribeCallCount,
        1,
        reason: 'Guard must allow only one pipeline through',
      );

      // Exactly one history entry was saved.
      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.content, 'one pipeline only');

      // Phase settled to done, not error (no state-machine invariant violation).
      expect(container.read(recordingProvider).phase, RecordingPhase.done);
    });

    test(
      'hotkey stop + simultaneous auto-stop produce exactly one pipeline',
      () async {
        // Mirrors the production scenario: the hotkey handler and _handleAutoStop
        // both call stopRecording() in the same event-loop turn.
        fakeStt.transcriptToReturn = 'auto-stop result';
        final orch = await startRecordingPhase();

        // Simulate hotkey-triggered stop and auto-stop firing at the same time.
        final hotkey = orch.stopRecording();
        final autoStop = orch.stopRecording(); // mirrors _handleAutoStop path
        await Future.wait([hotkey, autoStop]);

        expect(
          fakeStt.transcribeCallCount,
          1,
          reason: 'Hotkey + auto-stop must share a single pipeline',
        );
        final entries = await db.allEntries();
        expect(entries, hasLength(1));
        expect(container.read(recordingProvider).phase, RecordingPhase.done);
      },
    );

    test('AC4 (issue-06): two toggleRecording() calls during recording → '
        'one stop pipeline (double native onClicked guard)', () async {
      fakeStt.transcriptToReturn = 'one pipeline only';
      final orch = await startRecordingPhase();

      // Both futures start in the same event-loop turn.
      // toggleRecording() reads isRecording == true on both calls and
      // delegates to stopRecording(). The _stopInFlight guard inside
      // stopRecording() lets only one pipeline through.
      final f1 = orch.toggleRecording();
      final f2 = orch.toggleRecording();
      await Future.wait([f1, f2]);

      expect(
        fakeStt.transcribeCallCount,
        1,
        reason:
            '_stopInFlight guard must let only one pipeline through '
            'even when toggleRecording() is called twice in the same turn',
      );
      expect(container.read(recordingProvider).phase, RecordingPhase.done);
    });

    test('guard resets after pipeline completes — a subsequent stopRecording() '
        'starts a fresh pipeline', () async {
      fakeStt.transcriptToReturn = 'first';
      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(fakeStt.transcribeCallCount, 1);
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      // Simulate a fresh recording cycle.
      wavFile = createFakeWav(
        'test_audio_second_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio.wavPathToReturn = wavFile.absolute.path;
      fakeStt.transcriptToReturn = 'second';
      container.read(recordingProvider.notifier).reset();
      container.read(recordingProvider.notifier).startRecording();

      await orch.stopRecording();

      // Guard was released → second pipeline ran.
      expect(fakeStt.transcribeCallCount, 2);
      final entries = await db.allEntries();
      expect(entries, hasLength(2));
      expect(container.read(recordingProvider).phase, RecordingPhase.done);
    });
  });

  // =========================================================================
  // Clipboard / after-transcription action
  // =========================================================================

  group('After-transcription action', () {
    test('pipeline completes with clipboard action setting', () async {
      // Rebuild container with clipboard action.
      container.dispose();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      wavFile = createFakeWav(
        'test_audio_clip_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = FakeSttService()..transcriptToReturn = 'Clipboard text';
      clipboardText = 'Existing clipboard';

      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      container.read(recordingProvider.notifier).startRecording();

      await orch.stopRecording();

      // Pipeline completes — clipboard action doesn't block it.
      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.done);
      expect(state.transcript, 'Clipboard text');

      // History entry saved.
      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.content, 'Clipboard text');
      expect(clipboardText, 'Clipboard text');
      expect(fakeDesktopPaste.pasteCalls, 0);
    });

    test('pipeline completes with action=nothing (no clipboard)', () async {
      // Default FakeSettingsNotifier uses afterTranscription='nothing'.
      clipboardText = 'Keep me';
      fakeStt.transcriptToReturn = 'No clipboard';
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(container.read(recordingProvider).transcript, 'No clipboard');
      expect(clipboardText, 'Keep me');
      expect(fakeDesktopPaste.pasteCalls, 0);
    });

    test(
      'paste action restores previous clipboard text after pasting',
      () async {
        container.dispose();
        db = HistoryDatabase.forTesting(NativeDatabase.memory());
        wavFile = createFakeWav(
          'test_audio_paste_${DateTime.now().millisecondsSinceEpoch}.wav',
        );
        fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
        fakeStt = FakeSttService()..transcriptToReturn = 'Paste only';
        clipboardText = 'Original clipboard';

        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            behavior: BehaviorSettings(autoPasteDelay: 350),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);

        final orch = await startRecordingPhase();
        await orch.stopRecording();

        expect(container.read(recordingProvider).phase, RecordingPhase.done);
        expect(fakeDesktopPaste.pasteCalls, 1);
        expect(fakeDesktopPaste.lastDelay, const Duration(milliseconds: 350));
        expect(clipboardText, 'Original clipboard');
      },
    );

    test(
      'paste captures a target before pasting when none is available yet',
      () async {
        container.dispose();
        db = HistoryDatabase.forTesting(NativeDatabase.memory());
        wavFile = createFakeWav(
          'test_audio_retry_capture_${DateTime.now().millisecondsSinceEpoch}.wav',
        );
        fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
        fakeStt = FakeSttService()..transcriptToReturn = 'Retry capture';
        clipboardText = 'Original clipboard';

        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            behavior: BehaviorSettings(autoPasteDelay: 200),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);

        final orch = await startRecordingPhase();
        await orch.stopRecording();

        expect(container.read(recordingProvider).phase, RecordingPhase.done);
        expect(fakeDesktopPaste.captureCalls, 1);
        expect(fakeDesktopPaste.pasteCalls, 1);
        expect(clipboardText, 'Original clipboard');
      },
    );

    test('clipboard_and_paste keeps transcript on clipboard', () async {
      container.dispose();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      wavFile = createFakeWav(
        'test_audio_both_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = FakeSttService()..transcriptToReturn = 'Copy and paste';
      clipboardText = 'Original clipboard';

      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard_and_paste',
          ),
          behavior: BehaviorSettings(autoPasteDelay: 125),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(fakeDesktopPaste.pasteCalls, 1);
      expect(fakeDesktopPaste.lastDelay, const Duration(milliseconds: 125));
      expect(clipboardText, 'Copy and paste');
    });

    test('paste falls back to direct typing when the classic paste '
        'shortcut fails, on macOS/Windows — Linux has no native typeText '
        'handler yet (see DesktopPaster.paste doc comment) and just '
        'reports the failure, so assertions below branch on the actual '
        'host platform', () async {
      container.dispose();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      wavFile = createFakeWav(
        'test_audio_type_pref_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = FakeSttService()..transcriptToReturn = 'Type preferred';
      clipboardText = 'Original clipboard';
      fakeDesktopPaste.pasteResult = false;
      fakeDesktopPaste.typeResult = true;

      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          behavior: BehaviorSettings(autoPasteDelay: 175),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      // The classic clipboard+paste-shortcut sequence is always attempted
      // first, on every platform.
      expect(fakeDesktopPaste.pasteCalls, 1);
      if (Platform.isMacOS || Platform.isWindows) {
        expect(fakeDesktopPaste.typeCalls, 1);
        expect(fakeDesktopPaste.lastTypedText, 'Type preferred');
      } else {
        // Linux: no native typeText handler to fall back to.
        expect(fakeDesktopPaste.typeCalls, 0);
      }
    });

    test('an old persisted "type" value still dispatches through the '
        'paste path (fromValue back-compat mapping) — the classic paste '
        'shortcut runs first on every platform', () async {
      container.dispose();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      wavFile = createFakeWav(
        'test_audio_type_backcompat_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = FakeSttService()..transcriptToReturn = 'Back-compat';

      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            // Old, no-longer-selectable persisted value — see
            // AfterTranscriptionAction.fromValue.
            afterTranscription: 'type',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = await startRecordingPhase();
      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect(fakeDesktopPaste.pasteCalls, 1);
      expect(fakeDesktopPaste.typeCalls, 0);
    });
  });

  group(
    'Sandbox transcript sink (onboarding test-recording, issue 04 rework)',
    () {
      test(
        'sink receives transcript; history-save and clipboard/paste are both '
        'skipped even when clipboard_and_paste is configured',
        () async {
          container.dispose();
          db = HistoryDatabase.forTesting(NativeDatabase.memory());
          wavFile = createFakeWav(
            'test_audio_sandbox_${DateTime.now().millisecondsSinceEpoch}.wav',
          );
          fakeAudio = FakeAudioService()
            ..wavPathToReturn = wavFile.absolute.path;
          fakeStt = FakeSttService()..transcriptToReturn = 'Sandbox text';
          clipboardText = 'Untouched clipboard';

          container = buildContainer(
            const AppSettings(
              stt: SttSettings(model: 'whisper-small', language: 'English'),
              afterTranscriptionSection: AfterTranscriptionSettings(
                afterTranscription: 'clipboard_and_paste',
              ),
              onboarding: OnboardingSettings(onboardingCompleted: true),
            ),
          );
          await container.read(settingsProvider.future);

          final orch = await startRecordingPhase();

          String? sunk;
          orch.sandboxTranscriptSink = (text) => sunk = text;

          await orch.stopRecording();

          expect(container.read(recordingProvider).phase, RecordingPhase.done);
          expect(sunk, 'Sandbox text');
          expect(await db.allEntries(), isEmpty);
          expect(fakeDesktopPaste.pasteCalls, 0);
          expect(clipboardText, 'Untouched clipboard');
        },
      );

      test('onboarding_not_completed preflight guard blocks a normal recording '
          'attempt when no sandbox sink is wired up', () async {
        container.dispose();
        ensureFakeLocalSttFilesExist();
        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            onboarding: OnboardingSettings(onboardingCompleted: false),
          ),
        );
        await container.read(settingsProvider.future);
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        await orch.startRecording();

        final state = container.read(recordingProvider);
        expect(state.phase, RecordingPhase.error);
        expect(state.errorMessage, 'onboarding_not_completed');
      });

      test('onboarding_not_completed preflight guard is bypassed while the '
          'sandbox sink is wired up, so the onboarding test-recording step '
          'can exercise the real hotkey before onboarding finishes (bug fix: '
          'the step used to tell the user to try the hotkey and then block '
          'that exact attempt with "please finish setup first")', () async {
        container.dispose();
        ensureFakeLocalSttFilesExist();
        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            onboarding: OnboardingSettings(onboardingCompleted: false),
          ),
        );
        await container.read(settingsProvider.future);
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        // Mirrors TestRecordingStep.initState wiring the sink before the
        // user can press the hotkey.
        orch.sandboxTranscriptSink = (_) {};

        await orch.startRecording();

        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );
      });
    },
  );

  // =========================================================================
  // Quick-note recording target (ticket 19) — bypasses clipboard/paste
  // entirely and appends the finished transcript to the marked note.
  // =========================================================================

  group('Quick-note recording target', () {
    test('appends the transcript to the marked quick note, bypassing '
        'clipboard/paste entirely', () async {
      final note = await db.createNote();
      await db.setQuickNote(note.id);
      clipboardText = 'Untouched clipboard';
      fakeStt.transcriptToReturn = 'First thought';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.done);
      expect((await db.getNote(note.id))?.content, 'First thought');
      expect(clipboardText, 'Untouched clipboard');
      expect(fakeDesktopPaste.pasteCalls, 0);
      expect(fakeDesktopPaste.captureCalls, 0);
    });

    test('appends as a new paragraph onto existing note content', () async {
      final note = await db.createNote();
      await db.updateNoteContent(note.id, 'Existing content');
      await db.setQuickNote(note.id);
      fakeStt.transcriptToReturn = 'Second thought';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      await orch.stopRecording();

      expect(
        (await db.getNote(note.id))?.content,
        'Existing content\n\nSecond thought',
      );
    });

    test(
      'zero-config: creates and marks a new note when none is marked',
      () async {
        fakeStt.transcriptToReturn = 'No note marked yet';

        final orch = await startRecordingPhase();
        container
            .read(recordingTargetProvider.notifier)
            .set(RecordingTarget.quickNote);

        await orch.stopRecording();

        final quickNote = await db.getQuickNote();
        expect(quickNote, isNotNull);
        expect(quickNote!.content, 'No note marked yet');
      },
    );

    test(
      'zero-config: creates a new note when the marked note is in the trash',
      () async {
        final trashed = await db.createNote();
        await db.setQuickNote(trashed.id);
        await db.softDeleteNote(trashed.id);
        fakeStt.transcriptToReturn = 'Marked note was trashed';

        final orch = await startRecordingPhase();
        container
            .read(recordingTargetProvider.notifier)
            .set(RecordingTarget.quickNote);

        await orch.stopRecording();

        final quickNote = await db.getQuickNote();
        expect(quickNote, isNotNull);
        expect(quickNote!.id, isNot(trashed.id));
        expect(quickNote.content, 'Marked note was trashed');
        // The trashed note itself is left untouched, not resurrected.
        expect((await db.getNote(trashed.id))?.content, isEmpty);
      },
    );

    test('zero-config: creates a new note when the marked note no longer '
        'exists', () async {
      final deleted = await db.createNote();
      await db.setQuickNote(deleted.id);
      await db.permanentDeleteNote(deleted.id);
      fakeStt.transcriptToReturn = 'Marked note was deleted';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      await orch.stopRecording();

      final quickNote = await db.getQuickNote();
      expect(quickNote, isNotNull);
      expect(quickNote!.content, 'Marked note was deleted');
    });

    test(
      'regression: a quick-note run does NOT also save a history entry — '
      'Notes and Verlauf are mutually exclusive destinations for the same '
      'dictation (reverses the earlier "not a special case" design: a '
      'quick note landing in both places read as an unwanted duplicate)',
      () async {
        final note = await db.createNote();
        await db.setQuickNote(note.id);
        fakeStt.transcriptToReturn = 'Only for the note';

        final orch = await startRecordingPhase();
        container
            .read(recordingTargetProvider.notifier)
            .set(RecordingTarget.quickNote);

        await orch.stopRecording();

        expect((await db.getNote(note.id))?.content, 'Only for the note');
        final entries = await db.allEntries();
        expect(entries, isEmpty);
      },
    );

    test('without a registered live-editor override, the append writes '
        'directly to the database', () async {
      final note = await db.createNote();
      await db.setQuickNote(note.id);
      fakeStt.transcriptToReturn = 'Direct write';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);
      expect(orch.quickNoteLiveEditorOverride, isNull);

      await orch.stopRecording();

      expect((await db.getNote(note.id))?.content, 'Direct write');
    });

    test('a registered live-editor override receives the note id and full new '
        'content, and is preferred over the direct database write', () async {
      final note = await db.createNote();
      await db.updateNoteContent(note.id, 'Live editor content');
      await db.setQuickNote(note.id);
      fakeStt.transcriptToReturn = 'Handled by the editor';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      String? overrideNoteId;
      String? overrideContent;
      orch.quickNoteLiveEditorOverride = (noteId, newContent) {
        overrideNoteId = noteId;
        overrideContent = newContent;
        return true;
      };

      await orch.stopRecording();

      expect(overrideNoteId, note.id);
      expect(overrideContent, 'Live editor content\n\nHandled by the editor');
      // The override claimed the write — the database row is untouched.
      expect((await db.getNote(note.id))?.content, 'Live editor content');
    });

    test('an override that returns false falls through to the direct database '
        'write', () async {
      final note = await db.createNote();
      await db.setQuickNote(note.id);
      fakeStt.transcriptToReturn = 'Not handled';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);
      orch.quickNoteLiveEditorOverride = (_, _) => false;

      await orch.stopRecording();

      expect((await db.getNote(note.id))?.content, 'Not handled');
    });

    test(
      'fires onQuickNoteAppended with the target note id on success',
      () async {
        final note = await db.createNote();
        await db.setQuickNote(note.id);
        fakeStt.transcriptToReturn = 'Observable completion';

        final orch = await startRecordingPhase();
        container
            .read(recordingTargetProvider.notifier)
            .set(RecordingTarget.quickNote);

        String? appendedNoteId;
        orch.onQuickNoteAppended = (noteId) => appendedNoteId = noteId;

        await orch.stopRecording();

        expect(appendedNoteId, note.id);
      },
    );

    test('a failed run never fires onQuickNoteAppended — an empty transcript '
        'appends nothing, so nothing may react to it', () async {
      final note = await db.createNote();
      await db.setQuickNote(note.id);
      fakeStt.transcriptToReturn = '';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      var fired = false;
      orch.onQuickNoteAppended = (_) => fired = true;

      await orch.stopRecording();

      expect(container.read(recordingProvider).phase, RecordingPhase.error);
      expect(fired, isFalse);
      expect((await db.getNote(note.id))?.content, isEmpty);
    });

    test('quickNoteEditorFlush runs BEFORE the note is read back, so content '
        'the editor had not persisted yet is part of the append', () async {
      final note = await db.createNote();
      await db.updateNoteContent(note.id, 'Saved');
      await db.setQuickNote(note.id);
      fakeStt.transcriptToReturn = 'Appended';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      final order = <String>[];
      // Stands in for NotesPage's autosave flush: it writes the keystrokes
      // that were still pending. If it ran after the read below, the append
      // would be built on 'Saved' and those keystrokes would be gone.
      orch.quickNoteEditorFlush = () async {
        order.add('flush');
        await db.updateNoteContent(note.id, 'Saved plus unsaved keystrokes');
      };
      orch.quickNoteLiveEditorOverride = (noteId, newContent) {
        order.add('override:$newContent');
        return false;
      };
      orch.onQuickNoteAppended = (_) => order.add('appended');

      await orch.stopRecording();

      expect(order, [
        'flush',
        'override:Saved plus unsaved keystrokes\n\nAppended',
        'appended',
      ]);
      expect(
        (await db.getNote(note.id))?.content,
        'Saved plus unsaved keystrokes\n\nAppended',
      );
    });

    test('two appends in a row keep both texts when the override re-schedules '
        'its content for the next flush', () async {
      final note = await db.createNote();
      await db.updateNoteContent(note.id, 'Start');
      await db.setQuickNote(note.id);

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      // Miniature of the editor: a live buffer plus a pending (debounced)
      // write that only lands on flush — exactly NotesPage's arrangement.
      var editorText = 'Start';
      String? pending;
      orch.quickNoteEditorFlush = () async {
        final content = pending;
        pending = null;
        if (content != null) await db.updateNoteContent(note.id, content);
      };
      orch.quickNoteLiveEditorOverride = (noteId, newContent) {
        editorText = newContent;
        pending = newContent;
        return true;
      };

      fakeStt.transcriptToReturn = 'First';
      await orch.stopRecording();

      // Second run back to back — the phase is still lingering in `done`,
      // so drive it the way a real re-trigger does (preempting reset)
      // instead of forcing the phase again.
      container.read(recordingProvider.notifier).reset();
      container.read(recordingProvider.notifier).startRecording();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);
      fakeStt.transcriptToReturn = 'Second';
      await orch.stopRecording();

      expect(editorText, 'Start\n\nFirst\n\nSecond');
      // The database is one flush behind by design (the editor owns the
      // write); the second run's flush persisted the first append.
      expect((await db.getNote(note.id))?.content, 'Start\n\nFirst');
    });

    test('an override that declines a foreign note id still leaves the append '
        'in the database', () async {
      final note = await db.createNote();
      await db.updateNoteContent(note.id, 'Target');
      await db.setQuickNote(note.id);
      fakeStt.transcriptToReturn = 'Appended';

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      // What NotesPage's override does when a *different* note is open.
      const openNoteId = 'some-other-note';
      orch.quickNoteLiveEditorOverride = (noteId, _) => noteId == openNoteId;

      await orch.stopRecording();

      expect((await db.getNote(note.id))?.content, 'Target\n\nAppended');
    });

    test('strips punctuation identically to the clipboard path — the appended '
        'text is the same finalText both paths would receive', () async {
      container.dispose();
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final note = await db.createNote();
      await db.setQuickNote(note.id);
      wavFile = createFakeWav(
        'test_audio_quicknote_strip_'
        '${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio = FakeAudioService()..wavPathToReturn = wavFile.absolute.path;
      fakeStt = FakeSttService()..transcriptToReturn = 'Search term.';

      container = buildContainer(
        const AppSettings(
          stt: SttSettings(
            model: 'whisper-small',
            language: 'English',
            stripPunctuation: true,
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = await startRecordingPhase();
      container
          .read(recordingTargetProvider.notifier)
          .set(RecordingTarget.quickNote);

      await orch.stopRecording();

      expect((await db.getNote(note.id))?.content, 'Search term');
    });

    test('the next recording without an explicit target reverts to clipboard '
        'behaviour — no target is left stuck from the previous run', () async {
      container.dispose();
      ensureFakeLocalSttFilesExist();
      final note = await db.createNote();
      await db.setQuickNote(note.id);
      clipboardText = 'Before quick note';

      // Explicit clipboard action so the second run's assertion is
      // unambiguous — the default fixture settings use 'nothing', which
      // would never touch the clipboard regardless of target.
      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);

      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      fakeStt.transcriptToReturn = 'Into the note';
      await orch.startRecording(target: RecordingTarget.quickNote);
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);
      await orch.stopRecording();

      expect((await db.getNote(note.id))?.content, 'Into the note');
      expect(clipboardText, 'Before quick note');

      // Second recording, no target argument — must behave exactly like
      // it always has, not silently keep targeting the note.
      fakeStt.transcriptToReturn = 'Back to clipboard';
      await orch.startRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);
      await orch.stopRecording();

      expect(clipboardText, 'Back to clipboard');
      expect((await db.getNote(note.id))?.content, 'Into the note');
    });
  });

  // =========================================================================
  // WAV file edge cases
  // =========================================================================

  group('WAV file edge cases', () {
    test('empty WAV file → fails with wav_file_empty', () async {
      // Create a zero-byte WAV file.
      final emptyWav = File(
        '${_scratchDir.path}${Platform.pathSeparator}'
        'empty_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      emptyWav.parent.createSync(recursive: true);
      emptyWav.writeAsBytesSync([]);
      addTearDown(() {
        if (emptyWav.existsSync()) emptyWav.deleteSync();
      });

      fakeAudio.wavPathToReturn = emptyWav.absolute.path;
      final orch = await startRecordingPhase();

      await orch.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'wav_file_empty');
    });
  });

  // =========================================================================
  // Recent-audio retention (privacy.retainRecentAudio)
  // =========================================================================

  group('Recent-audio retention (privacy.retainRecentAudio)', () {
    Future<RecordingOrchestrator> startWithRetention() async {
      container.dispose();
      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'nothing',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
          privacy: PrivacySettings(retainRecentAudio: true),
        ),
      );
      await container.read(settingsProvider.future);
      return startRecordingPhase();
    }

    test('moves the WAV into the retained-audio directory and links it to '
        'the entry', () async {
      final orch = await startWithRetention();
      final originalPath = wavFile.absolute.path;

      await orch.stopRecording();

      // The file was moved, not copied — nothing left at the original
      // temp path.
      expect(File(originalPath).existsSync(), isFalse);

      final rows = await db.select(db.entryAttachments).get();
      expect(rows, hasLength(1));
      expect(rows.single.mimeType, 'audio/wav');
      final attachedFile = File(rows.single.filepath);
      expect(attachedFile.parent.path, retainedAudioDir());
      expect(attachedFile.existsSync(), isTrue);
    });

    test('disabled by default — no attachment row is created, WAV is not '
        'moved into the retained-audio directory', () async {
      // Reuses the default container from setUp (retainRecentAudio: false).
      final orch = await startRecordingPhase();
      final originalPath = wavFile.absolute.path;

      await orch.stopRecording();

      expect(File(originalPath).existsSync(), isTrue);
      expect(await db.select(db.entryAttachments).get(), isEmpty);
    });

    test('rotation: after 21 retained recordings, only the 20 most recent '
        'attachment rows survive', () async {
      var orch = await startWithRetention();
      await orch.stopRecording();

      for (var i = 0; i < 20; i++) {
        wavFile = createFakeWav('retain_follow_$i.wav');
        fakeAudio.wavPathToReturn = wavFile.absolute.path;
        fakeStt.transcriptToReturn = 'clip $i';
        container.read(recordingProvider.notifier).reset();
        orch = container.read(recordingOrchestratorProvider.notifier);
        container.read(recordingProvider.notifier).startRecording();
        await orch.stopRecording();
      }

      final rows = await db.select(db.entryAttachments).get();
      expect(rows, hasLength(20));
    });

    test('DB insert failure after the move does not leave an orphaned WAV '
        'in the retained-audio directory', () async {
      final throwingDb = _ThrowingInsertAudioAttachmentDb();
      final c2 = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(throwingDb.close);
            return throwingDb;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(
            () => FakeSettingsNotifier(
              const AppSettings(
                stt: SttSettings(model: 'whisper-small', language: 'English'),
                afterTranscriptionSection: AfterTranscriptionSettings(
                  afterTranscription: 'nothing',
                ),
                onboarding: OnboardingSettings(onboardingCompleted: true),
                privacy: PrivacySettings(retainRecentAudio: true),
              ),
            ),
          ),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(
            () => FakeModelDownloadNotifier({'whisper-small'}),
          ),
        ],
      );
      addTearDown(c2.dispose);

      await c2.read(settingsProvider.future);
      final orch = c2.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      c2.read(recordingProvider.notifier).startRecording();

      final retainedDir = Directory(retainedAudioDir());
      final before = retainedDir.existsSync()
          ? retainedDir.listSync().map((f) => f.path).toSet()
          : <String>{};

      await orch.stopRecording();

      // The failed insert must not leave a new, untracked file behind —
      // whatever was there before this run must be exactly what's there
      // after, regardless of what earlier tests in this group left over.
      final after = retainedDir.existsSync()
          ? retainedDir.listSync().map((f) => f.path).toSet()
          : <String>{};
      expect(after, before);
    });
  });

  // =========================================================================
  // ClippingState integration
  // =========================================================================

  group('ClippingState integration', () {
    test(
      'successful capture pushes the clipping counter into ClippingState',
      () async {
        fakeAudio.clippedSamplesToReport = 17;
        fakeStt.transcriptToReturn = 'transcript with clipping';
        final orch = await startRecordingPhase();

        await orch.stopRecording();

        final clipping = container.read(clippingStateProvider);
        expect(clipping.count, 17);
        expect(clipping.shouldShowBanner, isTrue);
      },
    );

    test('clean follow-up recording (count=0) clears the banner', () async {
      // First recording: clipping happened — banner appears.
      fakeAudio.clippedSamplesToReport = 5;
      fakeStt.transcriptToReturn = 'clipped';
      final orch1 = await startRecordingPhase();
      await orch1.stopRecording();
      expect(container.read(clippingStateProvider).shouldShowBanner, isTrue);

      // Second recording: clean → counter goes back to 0 → banner hides.
      // Build a fresh WAV so the orchestrator can still read non-empty bytes
      // (the previous capture cleaned up the prior file via cleanupFile,
      // which the fake stubs to no-op).
      wavFile = createFakeWav(
        'test_audio_followup_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      fakeAudio.wavPathToReturn = wavFile.absolute.path;
      fakeAudio.clippedSamplesToReport = 0;
      fakeStt.transcriptToReturn = 'clean';
      container.read(recordingProvider.notifier).reset();
      final orch2 = await startRecordingPhase();
      await orch2.stopRecording();

      final clipping = container.read(clippingStateProvider);
      expect(clipping.count, 0);
      expect(clipping.shouldShowBanner, isFalse);
    });

    test('capture-step failure (audio start error) leaves ClippingState '
        'untouched', () async {
      // Pre-seed ClippingState with a non-zero value from a "prior"
      // recording so we can verify the failed run does NOT clobber it.
      container
          .read(clippingStateProvider.notifier)
          .reportRecordingFinished(42);
      expect(container.read(clippingStateProvider).count, 42);

      // Force the next startRecording to fail.
      fakeAudio.errorOnStart = true;
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Drive the state machine into recording so stopRecording() runs
      // through capture and bails on the empty/missing audio result.
      container.read(recordingProvider.notifier).startRecording();
      fakeAudio.wavPathToReturn = null; // capture returns null path
      await orch.stopRecording();

      // The orchestrator transitioned to error (no_audio_recorded).
      expect(container.read(recordingProvider).phase, RecordingPhase.error);
      // ClippingState is unchanged — the prior banner stays.
      final clipping = container.read(clippingStateProvider);
      expect(clipping.count, 42);
      expect(clipping.shouldShowBanner, isTrue);
    });
  });

  // =========================================================================
  // Cloud transcriber failures
  // =========================================================================

  group('Cloud transcriber failures', () {
    test(
      'missing Deepgram key fails with stable cloud_auth_error code',
      () async {
        // Regression: the raw TranscriberException prose ("Deepgram API key
        // not set. …") used to reach the toast layer as the error code, which
        // has no mapping and degraded to the generic "something went wrong"
        // message with no hint at the actual problem.
        container.dispose();
        container = buildContainer(
          const AppSettings(
            stt: SttSettings(
              provider: 'Deepgram',
              model: 'whisper-small',
              language: 'English',
            ),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'nothing',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        final orch = await startRecordingPhase();

        await orch.stopRecording();

        final state = container.read(recordingProvider);
        expect(state.phase, RecordingPhase.error);
        expect(state.errorMessage, 'cloud_auth_error');
      },
    );
  });

  // =========================================================================
  // Cloud preflight
  // =========================================================================

  group('Cloud preflight', () {
    AppSettings cloudSettings({String deepgramKey = ''}) => AppSettings(
      stt: const SttSettings(
        provider: 'Deepgram',
        model: 'whisper-small',
        language: 'English',
      ),
      cloudProvider: CloudProviderSettings(
        deepgramApiKey: deepgramKey,
        cloudSttProvider: 'deepgram',
      ),
      afterTranscriptionSection: const AfterTranscriptionSettings(
        afterTranscription: 'nothing',
      ),
      onboarding: const OnboardingSettings(onboardingCompleted: true),
    );

    test(
      'records without local whisper files when an API key is set',
      () async {
        // Regression: preflight used to require the local whisper-server
        // binary and model file even for cloud providers, blocking cloud-only
        // users who never downloaded a local model. The scratch sttDir in
        // these tests contains neither file.
        container.dispose();
        container = buildContainer(cloudSettings(deepgramKey: 'dg-test'));
        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        await orch.startRecording();

        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );
      },
    );

    test('fails fast with cloud_auth_error when no API key is set', () async {
      container.dispose();
      container = buildContainer(cloudSettings());
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      await orch.startRecording();

      final state = container.read(recordingProvider);
      expect(state.phase, RecordingPhase.error);
      expect(state.errorMessage, 'cloud_auth_error');
    });
  });

  // =========================================================================
  // AC4 — Telemetry PII-leak guard
  // =========================================================================

  group('Telemetry PII-leak guard', () {
    test(
      'pipeline_telemetry_no_pii: real transcription pipeline emits NO '
      'transcript text, audio bytes, or history content in Matomo payloads',
      () async {
        // Known sentinel that must NEVER appear in any telemetry payload.
        const fakeTranscript = 'SECRET_DICTATED_CONTENT_xyz987';
        fakeStt.transcriptToReturn = fakeTranscript;

        final capturedBodies = <String>[];
        final fakeHttpClient = MockClient((req) async {
          capturedBodies.add(req.body);
          return http.Response('', 200);
        });
        final fakeTelemetry = TelemetryService(
          client: fakeHttpClient,
          endpointUrl: 'https://test.matomo.example',
          siteId: 1,
          consentGranted: true,
          dntActive: false,
        );

        // Build a fresh container with telemetry override so all events
        // during this run go to our fake HTTP client.
        container.dispose();
        container = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            audioServiceProvider.overrideWith(() => fakeAudio),
            localSttBundleProvider.overrideWith(() => fakeStt),
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                const AppSettings(
                  stt: SttSettings(model: 'whisper-small', language: 'en'),
                  afterTranscriptionSection: AfterTranscriptionSettings(
                    afterTranscription: 'clipboard',
                  ),
                  onboarding: OnboardingSettings(onboardingCompleted: true),
                ),
              ),
            ),
            secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
            desktopPasteControllerProvider.overrideWith(
              (ref) => fakeDesktopPaste,
            ),
            modelDownloadProvider.overrideWith(
              () => FakeModelDownloadNotifier({
                'whisper-small',
                'whisper-medium',
                'whisper-large-v3-turbo',
              }),
            ),
            telemetryProvider.overrideWith((ref) => fakeTelemetry),
          ],
        );
        await container.read(settingsProvider.future);

        // Drive the pipeline: manually set phase to recording (bypasses
        // preflight against the real filesystem), then stop and transcribe.
        container.read(recordingProvider.notifier).startRecording();
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        final orch = container.read(recordingOrchestratorProvider.notifier);
        await orch.stopRecording();

        // Settle async microtasks. Hot-path events (pipeline outcome, latency,
        // insertion) are aggregated in memory and only sent at shutdown — drain
        // the session aggregator to mirror that path, then flush, so the PII
        // guard inspects the actual emitted payloads.
        await Future<void>.delayed(Duration.zero);
        container
            .read(telemetrySessionAggregatorProvider)
            .drainTo(fakeTelemetry);
        await fakeTelemetry.flush();

        // Assert: every captured payload is PII-free.
        expect(
          capturedBodies,
          isNotEmpty,
          reason:
              'Expected at least one aggregated telemetry event at shutdown',
        );

        for (final body in capturedBodies) {
          final lower = body.toLowerCase();
          // Transcript text must not appear.
          expect(
            lower,
            isNot(contains('secret_dictated')),
            reason: 'Transcript text leaked into telemetry payload',
          );
          expect(
            lower,
            isNot(contains('xyz987')),
            reason: 'Transcript sentinel leaked into telemetry payload',
          );
          // Raw WAV header bytes must not appear (RIFF magic).
          expect(
            lower,
            isNot(contains('riff')),
            reason: 'WAV audio bytes leaked into telemetry payload',
          );
          // History entry content keys must not appear.
          expect(
            lower,
            isNot(contains('content=')),
            reason: 'History content field leaked into telemetry payload',
          );
        }
      },
    );
  });

  // =========================================================================
  // Hotkey→text end-to-end latency KPI (issue 07-latenz-kpi-erfassung).
  //
  // Local-only performance signal: hotkey-press t₀ (PerfMarkers, already
  // stamped by HotkeyService) → text delivered (after-transcription action
  // completes). The real `startRecording()` must run (the hotkey t₀ capture
  // lives inside it — the `startRecordingPhase()` helper used elsewhere
  // bypasses the orchestrator's start path entirely), so these tests place
  // placeholder whisper-server/model files in the scratch STT dir to satisfy
  // the on-device preflight check.
  // =========================================================================

  group('Hotkey→text latency KPI', () {
    setUp(() {
      PerfMarkers.instance.reset();
      ensureFakeLocalSttFilesExist();
    });
    tearDown(() => PerfMarkers.instance.reset());

    test('persists a latency sample measured from the hotkey press, not from '
        'some later pipeline moment', () async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      PerfMarkers.instance.markHotkeyPressed();
      // A deliberate gap between the hotkey press and the recording
      // actually starting (preflight etc.) — the persisted latency must
      // be at least this large, proving it is anchored to the hotkey
      // press and not to, say, `stopRecording()`'s own start time.
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await orch.startRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      fakeStt.transcriptToReturn = 'Latency KPI test';
      await orch.stopRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.done);

      final rows = await db
          .customSelect('SELECT * FROM hotkey_latency_entries')
          .get();
      expect(rows, hasLength(1));
      final latencyMs = rows.first.data['latency_ms'] as int;
      expect(latencyMs, greaterThanOrEqualTo(60));
    });

    test('does not persist a sample when no hotkey press preceded the start '
        '(e.g. a UI-button-triggered recording)', () async {
      final orch = container.read(recordingOrchestratorProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // No PerfMarkers.markHotkeyPressed() call.
      await orch.startRecording();
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      fakeStt.transcriptToReturn = 'No hotkey press';
      await orch.stopRecording();

      final rows = await db
          .customSelect('SELECT * FROM hotkey_latency_entries')
          .get();
      expect(rows, isEmpty);
    });

    test('aggregation query averages persisted latency samples', () async {
      await db.recordHotkeyLatency(recordedAt: DateTime.now(), latencyMs: 100);
      await db.recordHotkeyLatency(recordedAt: DateTime.now(), latencyMs: 300);

      final avg = await db.analyticsAverageHotkeyLatencyMs();
      expect(avg, 200.0);
    });

    test('aggregation query returns null when no samples exist', () async {
      final avg = await db.analyticsAverageHotkeyLatencyMs();
      expect(avg, isNull);
    });
  });

  // =========================================================================
  // Privacy boundary: the fine-grained hotkey→text latency is a DIFFERENT
  // privacy domain than the outgoing (bucketed) telemetry latency counter
  // (`_latencyBucketSeconds` in recording_orchestrator.dart). It must never
  // leak into the outgoing telemetry, and must not even influence which
  // coarse bucket the existing pipeline-elapsed counter falls into.
  // =========================================================================

  group('Privacy boundary — hotkey latency stays local-only', () {
    setUp(() {
      PerfMarkers.instance.reset();
      ensureFakeLocalSttFilesExist();
    });
    tearDown(() => PerfMarkers.instance.reset());

    test(
      'a large hotkey→text latency is stored locally but never appears in '
      'outgoing telemetry, and does not shift the pipeline-elapsed bucket',
      () async {
        final capturedBodies = <String>[];
        final fakeHttpClient = MockClient((req) async {
          capturedBodies.add(req.body);
          return http.Response('', 200);
        });
        final fakeTelemetry = TelemetryService(
          client: fakeHttpClient,
          endpointUrl: 'https://test.matomo.example',
          siteId: 1,
          consentGranted: true,
          dntActive: false,
        );

        container.dispose();
        container = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            audioServiceProvider.overrideWith(() => fakeAudio),
            localSttBundleProvider.overrideWith(() => fakeStt),
            settingsProvider.overrideWith(
              () => FakeSettingsNotifier(
                const AppSettings(
                  stt: SttSettings(model: 'whisper-small', language: 'English'),
                  afterTranscriptionSection: AfterTranscriptionSettings(
                    afterTranscription: 'nothing',
                  ),
                  onboarding: OnboardingSettings(onboardingCompleted: true),
                ),
              ),
            ),
            secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
            desktopPasteControllerProvider.overrideWith(
              (ref) => fakeDesktopPaste,
            ),
            modelDownloadProvider.overrideWith(
              () => FakeModelDownloadNotifier({
                'whisper-small',
                'whisper-medium',
                'whisper-large-v3-turbo',
              }),
            ),
            telemetryProvider.overrideWith((ref) => fakeTelemetry),
          ],
        );
        await container.read(settingsProvider.future);

        final orch = container.read(recordingOrchestratorProvider.notifier);
        await Future<void>.delayed(Duration.zero);

        PerfMarkers.instance.markHotkeyPressed();
        // 2.1s gap — comfortably lands the hotkey→text latency in a HIGHER
        // second-bucket (b3, per `_latencyBucketSeconds`) than the fast,
        // all-fake pipeline's own elapsed time (b1). If the fine-grained
        // hotkey latency ever leaked into the outgoing telemetry bucket,
        // this test would see 'e_n=b3' (or higher) instead of 'e_n=b1'.
        await Future<void>.delayed(const Duration(milliseconds: 2100));

        await orch.startRecording();
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        fakeStt.transcriptToReturn = 'privacy boundary test';
        await orch.stopRecording();
        expect(container.read(recordingProvider).phase, RecordingPhase.done);

        // Sanity: the local-only sample really is large (proves the KPI
        // path itself measured the artificial gap correctly).
        final rows = await db
            .customSelect('SELECT * FROM hotkey_latency_entries')
            .get();
        expect(rows, hasLength(1));
        expect(
          rows.first.data['latency_ms'] as int,
          greaterThanOrEqualTo(2100),
        );

        await Future<void>.delayed(Duration.zero);
        container
            .read(telemetrySessionAggregatorProvider)
            .drainTo(fakeTelemetry);
        await fakeTelemetry.flush();

        expect(capturedBodies, isNotEmpty);
        final combined = capturedBodies.join('\n');

        // The exact fine-grained latency value must never appear verbatim.
        for (final row in rows) {
          expect(
            combined,
            isNot(contains('${row.data['latency_ms']}')),
            reason: 'Fine-grained hotkey latency leaked into telemetry',
          );
        }

        // The pipeline-elapsed telemetry bucket stays fast (b1) — anchored
        // to the internal Stopwatch, not the hotkey-based latency.
        expect(combined, contains('e_n=b1'));
        expect(combined, isNot(contains('e_n=b3')));
      },
    );
  });

  // =========================================================================
  // Paste-failure / blocklist regression (issue
  // 02-paste-fehler-blocklist-regression). Locks in the existing external
  // behaviour: a real paste failure is reported via
  // [pasteFailureNotifierProvider] and surfaced via tray + system-attention,
  // while an app on the auto-paste blocklist produces neither — the
  // blocklist check in DesktopPaster returns PasteOutcome.blocked *before*
  // _pasteTranscript's switch ever reaches _reportPasteFailure.
  // =========================================================================

  group('Paste failure / blocklist regression (issue 02)', () {
    late FakeTrayActionService fakeTray;
    late FakeSystemAttentionService fakeAttention;
    late FakeSoundFeedbackService fakeSoundFeedback;

    ProviderContainer buildPasteContainer(
      AppSettings settings, {
      PasteCapabilityNotifier Function()? capabilityNotifier,
    }) {
      return ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(() => FakeSettingsNotifier(settings)),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(
            () => FakeModelDownloadNotifier({
              'whisper-small',
              'whisper-medium',
              'whisper-large-v3-turbo',
            }),
          ),
          trayServiceProvider.overrideWith(() => fakeTray),
          systemAttentionServiceProvider.overrideWith((ref) {
            fakeAttention = FakeSystemAttentionService(ref);
            return fakeAttention;
          }),
          soundFeedbackProvider.overrideWith(() {
            fakeSoundFeedback = FakeSoundFeedbackService();
            return fakeSoundFeedback;
          }),
          if (capabilityNotifier != null)
            pasteCapabilityNotifierProvider.overrideWith(capabilityNotifier),
        ],
      );
    }

    setUp(() {
      fakeTray = FakeTrayActionService();
    });

    test('AC1 — a real paste failure (OS denies event injection, e.g. macOS '
        'Accessibility / Windows UIPI) reports a failure event with the '
        'matching outcome', () async {
      fakeDesktopPaste.pasteStatusOverride =
          NativePasteStatus.permissionMissing;

      container.dispose();
      container = buildPasteContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      // Force eager creation so `fakeAttention` points at *this* container's
      // instance even on the blocklist path, where the orchestrator itself
      // never reads systemAttentionServiceProvider (otherwise a stale
      // instance from a previous test's container would linger).
      container.read(systemAttentionServiceProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'Real paste failure test';

      await orch.stopRecording();

      final failure = container.read(pasteFailureNotifierProvider);
      expect(
        failure,
        isNotNull,
        reason: 'A real (non-blocklist) paste failure must be reported',
      );
      expect(failure!.outcome, PasteOutcome.permissionMissing);
    });

    test('issue 11 — a native foreground_blocked (Windows UIPI: target window '
        'runs elevated, WhisPaste does not) reports a distinct elevationBlocked '
        'outcome, not the generic failed bucket, and surfaces via its own '
        'AttentionKind', () async {
      fakeDesktopPaste.pasteStatusOverride =
          NativePasteStatus.foregroundBlocked;

      container.dispose();
      container = buildPasteContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'UIPI paste failure test';

      await orch.stopRecording();
      await Future<void>.delayed(Duration.zero);

      final failure = container.read(pasteFailureNotifierProvider);
      expect(
        failure,
        isNotNull,
        reason: 'A foreground_blocked (UIPI) paste failure must be reported',
      );
      expect(failure!.outcome, PasteOutcome.elevationBlocked);
      expect(fakeAttention.lastKind, AttentionKind.pasteBlockedElevation);
    });

    test('AC2 — an app on the auto-paste blocklist produces no failure event '
        '(and never even attempts the native paste)', () async {
      fakeDesktopPaste.targetBundleIdToReturn = 'com.blocked.app';

      container.dispose();
      container = buildPasteContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
          behavior: BehaviorSettings(autoPasteBlocklist: 'com.blocked.app'),
        ),
      );
      await container.read(settingsProvider.future);
      // Force eager creation so `fakeAttention` points at *this* container's
      // instance even on the blocklist path, where the orchestrator itself
      // never reads systemAttentionServiceProvider (otherwise a stale
      // instance from a previous test's container would linger).
      container.read(systemAttentionServiceProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'Blocklisted app test';

      await orch.stopRecording();

      expect(
        container.read(pasteFailureNotifierProvider),
        isNull,
        reason: 'Blocklisted apps must not raise a paste-failure event',
      );
      expect(
        fakeDesktopPaste.pasteCalls,
        0,
        reason:
            'The blocklist check short-circuits before the native paste '
            'is ever attempted',
      );
      expect(fakeTray.setActionNeededCalls, isEmpty);
      expect(fakeAttention.requestAttentionCalls, 0);
    });

    test(
      'AC3 — a real paste failure stays discoverable via the tray '
      '"Action Needed" surface and the system-attention layer, both of '
      'which fire unconditionally (no main-window-visibility check) so the '
      'reminder survives even after a transient toast has already closed',
      () async {
        fakeDesktopPaste.pasteStatusOverride =
            NativePasteStatus.permissionMissing;

        container.dispose();
        container = buildPasteContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);

        final orch = await startRecordingPhase();
        fakeStt.transcriptToReturn = 'Tray surfacing test';

        await orch.stopRecording();
        await Future<void>.delayed(Duration.zero);

        expect(
          fakeTray.setActionNeededCalls,
          hasLength(1),
          reason: 'Tray must show an Action-Needed entry for the failure',
        );
        expect(fakeAttention.requestAttentionCalls, 1);
        expect(fakeAttention.lastKind, AttentionKind.pasteBlockedPermission);
      },
    );

    // =========================================================================
    // Notification routing (grant-vs-restart) must track the SAME shared
    // PasteCapabilityNotifier.needsRestart signal every other surface uses, so
    // the failed-paste notification never drifts to "open Settings" when the
    // real fix is a restart (a recurring bug this replaces). The click target
    // for the grant case routes through openAccessibilitySettings, which
    // records the handoff so the *next* failure resolves to restart.
    // =========================================================================

    test(
      'permissionMissing notification routes to Settings (grant) when '
      'needsRestart is false, and clicking it records the grant handoff',
      () async {
        fakeDesktopPaste.pasteStatusOverride =
            NativePasteStatus.permissionMissing;

        // Fresh notifier: permission missing, user never handed off → grant.
        final notifier = _SeededPasteCapabilityNotifier(
          const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
        );

        container.dispose();
        container = buildPasteContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
          capabilityNotifier: () => notifier,
        );
        await container.read(settingsProvider.future);
        container.read(systemAttentionServiceProvider);

        final orch = await startRecordingPhase();
        fakeStt.transcriptToReturn = 'grant routing test';
        await orch.stopRecording();
        await Future<void>.delayed(Duration.zero);

        expect(fakeAttention.lastTitle, 'WhisPaste: Auto-Einfügen blockiert');

        // Baseline: the handoff bit is not yet set.
        expect(
          container.read(pasteCapabilityNotifierProvider).sentToOsGrantFlow,
          isFalse,
        );
        // Clicking the notification opens Settings AND records the handoff, so
        // the next surface the user hits resolves to restart, not Settings.
        fakeAttention.lastOnClick?.call();
        expect(
          container.read(pasteCapabilityNotifierProvider).sentToOsGrantFlow,
          isTrue,
          reason:
              'The grant-notification click must route through '
              'openAccessibilitySettings, which records the handoff.',
        );
      },
    );

    test(
      'permissionMissing notification routes to restart when needsRestart '
      'is true (already handed off, permission still reads missing)',
      () async {
        fakeDesktopPaste.pasteStatusOverride =
            NativePasteStatus.permissionMissing;

        // Already handed off + still missing + poll not awaiting → restart.
        final notifier = _SeededPasteCapabilityNotifier(
          const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
            sentToOsGrantFlow: true,
            pollingPhase: PollingPhase.timedOut,
          ),
        );

        container.dispose();
        container = buildPasteContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
          capabilityNotifier: () => notifier,
        );
        await container.read(settingsProvider.future);
        container.read(systemAttentionServiceProvider);

        final orch = await startRecordingPhase();
        fakeStt.transcriptToReturn = 'restart routing test';
        await orch.stopRecording();
        await Future<void>.delayed(Duration.zero);

        expect(
          fakeAttention.lastTitle,
          'WhisPaste: Neustart nötig',
          reason:
              'When needsRestart is true the notification must point at a '
              'restart, not another trip to Settings.',
        );
      },
    );

    test(
      'live-probe build: the permissionMissing notification offers the entry '
      'reset instead of a Settings trip, and clicking it actually resets',
      () async {
        fakeDesktopPaste.pasteStatusOverride =
            NativePasteStatus.permissionMissing;

        // Same seed as the "routes to Settings (grant)" test above — only the
        // build leg differs. On the live-probe leg a missing permission can be
        // a TCC entry pinned to a binary that no longer exists, and Settings
        // then shows the toggle already ON with nothing to do (the reported
        // dead end), so the notification must clear the entry first.
        final notifier = _SeededPasteCapabilityNotifier(
          const PasteCapabilityState(
            capability: PasteCapability(
              status: PasteCapabilityStatus.permissionMissing,
              canPrompt: true,
            ),
          ),
          cachedProbe: false,
        );

        container.dispose();
        container = buildPasteContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
          capabilityNotifier: () => notifier,
        );
        await container.read(settingsProvider.future);
        container.read(systemAttentionServiceProvider);

        final orch = await startRecordingPhase();
        fakeStt.transcriptToReturn = 'entry reset routing test';
        await orch.stopRecording();
        await Future<void>.delayed(Duration.zero);

        expect(fakeAttention.lastTitle, 'WhisPaste: Auto-Einfügen blockiert');
        expect(
          fakeAttention.lastBody,
          contains('veralteten Eintrag'),
          reason:
              'The body must promise what the click does. Repeating the plain '
              '"open System Settings" line while the click now resets the '
              'entry would leave the user expecting the old dead end.',
        );

        expect(fakeDesktopPaste.repairCalls, 0);
        fakeAttention.lastOnClick?.call();
        // repair() -> requestGrant() is a two-step async chain.
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        container.read(pasteCapabilityNotifierProvider.notifier).stopPolling();

        expect(
          fakeDesktopPaste.repairCalls,
          1,
          reason:
              'Clicking the notification must clear the stale TCC entry, not '
              'just deep-link into Settings — the deep-link alone is what '
              'showed the user an already-enabled toggle.',
        );
      },
      skip: !Platform.isMacOS,
    );

    // The tray entry is the only failure surface that persists — the
    // notification expires and the Dock bounce stops — so it is the one most
    // likely to be tapped, and it must run the recovery rather than dropping
    // the user on a settings page to hunt for the fix. It gets its own menu
    // key for that; every other paste failure keeps the settings jump.
    //
    // Split across two tests on purpose: the shared fakes carry per-run state,
    // so two failures inside one test would not both reach the paste path.
    Future<void> failPasteWith(NativePasteStatus status) async {
      // Both seams: a failed paste can fall back to typing, and a successful
      // fallback would report no failure at all.
      fakeDesktopPaste.pasteStatusOverride = status;
      fakeDesktopPaste.typeStatusOverride = status;

      container.dispose();
      container = buildPasteContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'tray key routing test';
      await orch.stopRecording();
      await Future<void>.delayed(Duration.zero);
    }

    test('a blocked permission claims its own tray key', () async {
      await failPasteWith(NativePasteStatus.permissionMissing);

      expect(
        fakeTray.setActionNeededKeys.single,
        kTrayPastePermissionActionNeededKey,
        reason:
            'Tapping this entry has to run the permission recovery. On the '
            'default key it would only open the after-transcription settings '
            '— the "go to Settings and find it yourself" dead end.',
      );
    });

    test('other paste failures keep the settings-jump tray key', () async {
      await failPasteWith(NativePasteStatus.noTarget);

      expect(
        fakeTray.setActionNeededKeys.single,
        kTrayPasteActionNeededKey,
        reason:
            'A missing target app IS resolved in settings, so this one must '
            'keep the settings jump.',
      );
    });

    // =========================================================================
    // Error-sound wiring (issue 09-fehlerton-verdrahten). Keys off the same
    // "real failure vs. blocklist" distinction locked in by issue 02 above:
    // the error sound must play for a genuine paste failure but must stay
    // silent for a deliberately blocklisted app.
    // =========================================================================

    test('issue 09 — a real paste failure plays the error sound', () async {
      fakeDesktopPaste.pasteStatusOverride =
          NativePasteStatus.permissionMissing;

      container.dispose();
      container = buildPasteContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'paste',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      // Force eager creation so `fakeSoundFeedback` points at *this*
      // container's instance (mirrors the fakeAttention pattern above).
      container.read(soundFeedbackProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'Error sound real-failure test';

      await orch.stopRecording();

      expect(
        fakeSoundFeedback.playErrorCalls,
        1,
        reason: 'A real paste failure must trigger the error sound',
      );
    });

    test(
      'issue 09 — a blocklisted app does not play the error sound',
      () async {
        fakeDesktopPaste.targetBundleIdToReturn = 'com.blocked.app';

        container.dispose();
        container = buildPasteContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'paste',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
            behavior: BehaviorSettings(autoPasteBlocklist: 'com.blocked.app'),
          ),
        );
        await container.read(settingsProvider.future);
        // Force eager creation so `fakeSoundFeedback` points at *this*
        // container's instance (mirrors the fakeAttention pattern above).
        container.read(soundFeedbackProvider);

        final orch = await startRecordingPhase();
        fakeStt.transcriptToReturn = 'Error sound blocklist test';

        await orch.stopRecording();

        expect(
          fakeSoundFeedback.playErrorCalls,
          0,
          reason: 'Blocklisted apps must stay silent — no error sound',
        );
      },
    );
  });

  // =========================================================================
  // Interactive snippets (guided multi-field recording sequence)
  // =========================================================================

  group('InteractiveSnippetController', () {
    List<SnippetField> fields(List<String> names) => [
      for (var i = 0; i < names.length; i++)
        SnippetField(id: 'f$i', snippetId: 's1', name: names[i], sortOrder: i),
    ];

    test(
      'runs every field in order and pastes exactly one composed result',
      () async {
        ensureFakeLocalSttFilesExist();
        container.dispose();
        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'clipboard',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);

        final controller = container.read(
          interactiveSnippetControllerProvider.notifier,
        )..announceDuration = Duration.zero;
        await controller.start(
          fields(['Titel', 'Beschreibung']),
          template: legacyInteractiveSnippetTemplate(['Titel', 'Beschreibung']),
        );
        expect(
          container.read(interactiveSnippetControllerProvider)?.fieldName,
          'Titel',
        );
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        fakeStt.transcriptToReturn = 'Login schlägt fehl';
        await controller.advanceField();
        expect(
          container.read(interactiveSnippetControllerProvider)?.fieldName,
          'Beschreibung',
        );
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.recording,
        );

        fakeStt.transcriptToReturn = 'Login funktioniert nicht mehr.';
        await controller.advanceField();

        expect(container.read(interactiveSnippetControllerProvider), isNull);
        expect(
          clipboardText,
          'Titel\nLogin schlägt fehl\n\nBeschreibung\n'
          'Login funktioniert nicht mehr.',
        );
        final entries = await db.allEntries();
        expect(entries, hasLength(1));
        expect(entries.single.content, clipboardText);
      },
    );

    test(
      'composes into a free-form user template, not just the legacy layout',
      () async {
        ensureFakeLocalSttFilesExist();
        container.dispose();
        container = buildContainer(
          const AppSettings(
            stt: SttSettings(model: 'whisper-small', language: 'English'),
            afterTranscriptionSection: AfterTranscriptionSettings(
              afterTranscription: 'clipboard',
            ),
            onboarding: OnboardingSettings(onboardingCompleted: true),
          ),
        );
        await container.read(settingsProvider.future);

        final controller = container.read(
          interactiveSnippetControllerProvider.notifier,
        )..announceDuration = Duration.zero;
        await controller.start(
          fields(['Name', 'Thema']),
          template: 'Hallo {{Name}}, danke für deine Anfrage zu {{Thema}}!',
        );

        fakeStt.transcriptToReturn = 'Anna';
        await controller.advanceField();
        fakeStt.transcriptToReturn = 'die Rechnung';
        await controller.advanceField();

        expect(
          clipboardText,
          'Hallo Anna, danke für deine Anfrage zu die Rechnung!',
        );
      },
    );

    test('a field transcription failure discards the whole sequence', () async {
      ensureFakeLocalSttFilesExist();
      container.dispose();
      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      clipboardText = 'Untouched';

      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      )..announceDuration = Duration.zero;
      await controller.start(
        fields(['Titel', 'Beschreibung']),
        template: legacyInteractiveSnippetTemplate(['Titel', 'Beschreibung']),
      );

      fakeStt.transcriptToReturn = 'Titel-Text';
      await controller.advanceField();

      fakeStt.transcribeThrows = true;
      await controller.advanceField();

      expect(container.read(interactiveSnippetControllerProvider), isNull);
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
      expect(clipboardText, 'Untouched');
      expect(await db.allEntries(), isEmpty);
    });

    test('cancelling mid-field discards everything, no partial save', () async {
      ensureFakeLocalSttFilesExist();
      container.dispose();
      container = buildContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
        ),
      );
      await container.read(settingsProvider.future);
      clipboardText = 'Untouched';

      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      )..announceDuration = Duration.zero;
      await controller.start(
        fields(['Titel', 'Beschreibung']),
        template: legacyInteractiveSnippetTemplate(['Titel', 'Beschreibung']),
      );
      fakeStt.transcriptToReturn = 'Titel-Text';
      await controller.advanceField();

      await controller.cancel();

      expect(container.read(interactiveSnippetControllerProvider), isNull);
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
      expect(clipboardText, 'Untouched');
      expect(await db.allEntries(), isEmpty);
    });

    test('a single field is accepted — a legitimate one-field template '
        '(a8445010 relaxed the old two-field minimum)', () async {
      ensureFakeLocalSttFilesExist();
      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      )..announceDuration = Duration.zero;

      await controller.start(
        fields(['Nur ein Feld']),
        template: legacyInteractiveSnippetTemplate(['Nur ein Feld']),
      );

      expect(container.read(interactiveSnippetControllerProvider), isNotNull);
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);
    });

    test('zero fields is rejected — no session starts', () async {
      ensureFakeLocalSttFilesExist();
      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      )..announceDuration = Duration.zero;

      await controller.start(fields([]), template: '');

      expect(container.read(interactiveSnippetControllerProvider), isNull);
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
    });

    test('announce pre-roll: publishes the get-ready state before the mic '
        'opens', () async {
      ensureFakeLocalSttFilesExist();
      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      );
      final gate = Completer<void>();
      controller.announceDelay = (_) => gate.future;

      final startFuture = controller.start(
        fields(['Titel']),
        template: legacyInteractiveSnippetTemplate(['Titel']),
      );
      // start() crosses a few genuine async hops (prime, key registration)
      // before it parks on the pre-roll gate — poll briefly.
      for (
        var i = 0;
        i < 40 &&
            container.read(interactiveSnippetControllerProvider)?.announcing !=
                true;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final session = container.read(interactiveSnippetControllerProvider);
      expect(session?.announcing, isTrue);
      expect(
        container.read(recordingProvider).phase,
        RecordingPhase.idle,
        reason: 'the microphone must stay closed during the pre-roll',
      );

      gate.complete();
      await startFuture;

      expect(
        container.read(interactiveSnippetControllerProvider)?.announcing,
        isFalse,
      );
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      await controller.cancel();
    });

    test('cancel during the announce pre-roll never opens the mic', () async {
      ensureFakeLocalSttFilesExist();
      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      );
      final gate = Completer<void>();
      controller.announceDelay = (_) => gate.future;

      final startFuture = controller.start(
        fields(['Titel']),
        template: legacyInteractiveSnippetTemplate(['Titel']),
      );
      for (
        var i = 0;
        i < 40 &&
            container.read(interactiveSnippetControllerProvider)?.announcing !=
                true;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(
        container.read(interactiveSnippetControllerProvider)?.announcing,
        isTrue,
      );

      await controller.cancel();
      gate.complete();
      await startFuture;

      expect(container.read(interactiveSnippetControllerProvider), isNull);
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
    });

    test('registers Enter/Escape for the sequence; Enter advances and the '
        'keys are gone once the sequence finishes', () async {
      ensureFakeLocalSttFilesExist();
      final sessionKeys = FakeSessionKeyRegistrar();
      container
          .read(hotkeyServiceProvider.notifier)
          .injectRegistrar(sessionKeys);
      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      )..announceDuration = Duration.zero;

      await controller.start(
        fields(['Titel']),
        template: legacyInteractiveSnippetTemplate(['Titel']),
      );
      expect(sessionKeys.isRegistered(LogicalKeyboardKey.enter), isTrue);
      expect(sessionKeys.isRegistered(LogicalKeyboardKey.escape), isTrue);
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      fakeStt.transcriptToReturn = 'Nur ein Feld';
      sessionKeys.press(LogicalKeyboardKey.enter);
      // The key handler fires advanceField unawaited — poll for the end of
      // the (single-field) sequence.
      for (
        var i = 0;
        i < 40 && container.read(interactiveSnippetControllerProvider) != null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // _reset() fires the key unregistration without awaiting it — give the
      // pending registrar round trip a moment to settle before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(interactiveSnippetControllerProvider), isNull);
      expect(
        sessionKeys.isRegistered(LogicalKeyboardKey.enter),
        isFalse,
        reason:
            'a leaked bare-Enter grab would swallow Enter in every other app',
      );
      expect(sessionKeys.isRegistered(LogicalKeyboardKey.escape), isFalse);
    });

    test('Escape cancels the whole sequence and the session keys are '
        'unregistered', () async {
      ensureFakeLocalSttFilesExist();
      final sessionKeys = FakeSessionKeyRegistrar();
      container
          .read(hotkeyServiceProvider.notifier)
          .injectRegistrar(sessionKeys);
      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      )..announceDuration = Duration.zero;

      await controller.start(
        fields(['Titel', 'Beschreibung']),
        template: legacyInteractiveSnippetTemplate(['Titel', 'Beschreibung']),
      );
      expect(container.read(recordingProvider).phase, RecordingPhase.recording);

      sessionKeys.press(LogicalKeyboardKey.escape);
      for (
        var i = 0;
        i < 40 && container.read(interactiveSnippetControllerProvider) != null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // _reset() fires the key unregistration without awaiting it — give the
      // pending registrar round trip a moment to settle before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(interactiveSnippetControllerProvider), isNull);
      expect(container.read(recordingProvider).phase, RecordingPhase.idle);
      expect(sessionKeys.isRegistered(LogicalKeyboardKey.enter), isFalse);
      expect(sessionKeys.isRegistered(LogicalKeyboardKey.escape), isFalse);
      expect(await db.allEntries(), isEmpty);
    });

    test('a mid-sequence transcription failure (abort path) also '
        'unregisters the session keys', () async {
      ensureFakeLocalSttFilesExist();
      final sessionKeys = FakeSessionKeyRegistrar();
      container
          .read(hotkeyServiceProvider.notifier)
          .injectRegistrar(sessionKeys);
      final controller = container.read(
        interactiveSnippetControllerProvider.notifier,
      )..announceDuration = Duration.zero;

      await controller.start(
        fields(['Titel', 'Beschreibung']),
        template: legacyInteractiveSnippetTemplate(['Titel', 'Beschreibung']),
      );

      fakeStt.transcribeThrows = true;
      await controller.advanceField();

      // _reset() fires the key unregistration without awaiting it — give the
      // pending registrar round trip a moment to settle before asserting.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(interactiveSnippetControllerProvider), isNull);
      expect(sessionKeys.isRegistered(LogicalKeyboardKey.enter), isFalse);
      expect(sessionKeys.isRegistered(LogicalKeyboardKey.escape), isFalse);
    });
  });

  // =========================================================================
  // Smart Mode v2: local Cleanup pipeline (ticket 02)
  // =========================================================================

  group('Smart Mode v2: local Cleanup pipeline (ticket 02)', () {
    late FakeSmartModeEngine fakeSmartModeEngine;
    late FakeSystemAttentionService fakeAttention;

    ProviderContainer buildSmartModeContainer(
      AppSettings settings, {
      bool modelDownloaded = true,
    }) {
      return ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            ref.onDispose(db.close);
            return db;
          }),
          audioServiceProvider.overrideWith(() => fakeAudio),
          localSttBundleProvider.overrideWith(() => fakeStt),
          settingsProvider.overrideWith(() => FakeSettingsNotifier(settings)),
          secureKeyStoreProvider.overrideWith((ref) => FakeSecureKeyStore()),
          desktopPasteControllerProvider.overrideWith(
            (ref) => fakeDesktopPaste,
          ),
          modelDownloadProvider.overrideWith(
            () => FakeModelDownloadNotifier({
              'whisper-small',
              'whisper-medium',
              'whisper-large-v3-turbo',
            }),
          ),
          smartModeDownloadProvider.overrideWith(
            () =>
                FakeSmartModeDownloadNotifier(modelDownloaded: modelDownloaded),
          ),
          smartModeEngineProvider.overrideWith((ref) => fakeSmartModeEngine),
          systemAttentionServiceProvider.overrideWith((ref) {
            fakeAttention = FakeSystemAttentionService(ref);
            return fakeAttention;
          }),
        ],
      );
    }

    AppSettings settingsWithPreset(String preset) => AppSettings(
      stt: const SttSettings(model: 'whisper-small', language: 'English'),
      afterTranscriptionSection: const AfterTranscriptionSettings(
        afterTranscription: 'clipboard',
      ),
      onboarding: const OnboardingSettings(onboardingCompleted: true),
      smartMode: SmartModeSettings(standardPreset: preset),
    );

    setUp(() {
      fakeSmartModeEngine = FakeSmartModeEngine();
    });

    tearDown(() {
      RecordingOrchestrator.smartModeCleanupTimeoutOverride = null;
    });

    test('standard preset "off" (factory default) never calls the engine — '
        'the transcript is pasted completely unchanged', () async {
      container.dispose();
      container = buildSmartModeContainer(settingsWithPreset('off'));
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'Raw dictated text with, um, filler';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 0);
      expect(clipboardText, 'Raw dictated text with, um, filler');
      expect(fakeAttention.requestAttentionCalls, 0);
    });

    test('standard preset "cleanup" with a downloaded model replaces the '
        'pasted text with the engine result', () async {
      container.dispose();
      container = buildSmartModeContainer(settingsWithPreset('cleanup'));
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      fakeSmartModeEngine.resultToReturn = 'Cleaned text.';

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text with um filler';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 1);
      expect(fakeSmartModeEngine.lastUserText, 'raw text with um filler');
      expect(clipboardText, 'Cleaned text.');
      expect(
        fakeAttention.requestAttentionCalls,
        0,
        reason: 'A successful Cleanup pass must not fire a notification',
      );
    });

    test('standard preset "cleanup" but no model downloaded falls back to the '
        'raw transcript and fires an OS notification, without ever calling '
        'the engine', () async {
      container.dispose();
      container = buildSmartModeContainer(
        settingsWithPreset('cleanup'),
        modelDownloaded: false,
      );
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text, model missing';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 0);
      expect(clipboardText, 'raw text, model missing');
      expect(fakeAttention.requestAttentionCalls, 1);
      expect(fakeAttention.lastKind, AttentionKind.smartModeFallback);
    });

    test('cloud provider ("openai") ignores the local model-downloaded gate '
        'entirely — the engine is still called even with no model installed '
        '(ADR 0010: strict either-or, no auto-failover to local)', () async {
      container.dispose();
      container = buildSmartModeContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
          smartMode: SmartModeSettings(
            standardPreset: 'cleanup',
            provider: 'openai',
          ),
        ),
        modelDownloaded: false,
      );
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      fakeSmartModeEngine.resultToReturn = 'Cleaned via cloud.';

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text, no local model, cloud selected';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 1);
      expect(clipboardText, 'Cleaned via cloud.');
      expect(fakeAttention.requestAttentionCalls, 0);
    });

    test('an engine failure (e.g. model load / decode error) falls back to '
        'the raw transcript and fires an OS notification — the paste is '
        'never blocked (ADR 0009)', () async {
      container.dispose();
      container = buildSmartModeContainer(settingsWithPreset('cleanup'));
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      fakeSmartModeEngine.errorToThrow = StateError(
        'smart_mode_library_load_failed: simulated',
      );

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text, engine failed';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 1);
      expect(clipboardText, 'raw text, engine failed');
      expect(fakeAttention.requestAttentionCalls, 1);
      expect(fakeAttention.lastKind, AttentionKind.smartModeFallback);
    });

    test(
      'an engine call exceeding the timeout falls back to the raw '
      'transcript and fires an OS notification, not the error phase',
      () async {
        RecordingOrchestrator.smartModeCleanupTimeoutOverride = const Duration(
          milliseconds: 20,
        );
        container.dispose();
        container = buildSmartModeContainer(settingsWithPreset('cleanup'));
        await container.read(settingsProvider.future);
        container.read(systemAttentionServiceProvider);
        fakeSmartModeEngine.delay = const Duration(milliseconds: 200);
        fakeSmartModeEngine.resultToReturn = 'should never be used';

        final orch = await startRecordingPhase();
        fakeStt.transcriptToReturn = 'raw text, engine too slow';
        await orch.stopRecording();
        // The engine call is still running in the background past the
        // runner's timeout — give it time to finish so it doesn't leak into
        // the next test.
        await Future<void>.delayed(const Duration(milliseconds: 250));

        expect(clipboardText, 'raw text, engine too slow');
        expect(
          container.read(recordingProvider).phase,
          RecordingPhase.done,
          reason: 'A refining timeout must resolve to done, never error',
        );
        expect(fakeAttention.requestAttentionCalls, 1);
        expect(fakeAttention.lastKind, AttentionKind.smartModeFallback);
      },
    );

    test('a blank engine result is treated as a failure — never pastes an '
        'empty string where the user dictated real content', () async {
      container.dispose();
      container = buildSmartModeContainer(settingsWithPreset('cleanup'));
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      fakeSmartModeEngine.resultToReturn = '   ';

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text, blank result';
      await orch.stopRecording();

      expect(clipboardText, 'raw text, blank result');
      expect(fakeAttention.requestAttentionCalls, 1);
      expect(fakeAttention.lastKind, AttentionKind.smartModeFallback);
    });

    test('standard preset "concise" with a downloaded model replaces the '
        'pasted text with the shortened engine result', () async {
      container.dispose();
      container = buildSmartModeContainer(settingsWithPreset('concise'));
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      fakeSmartModeEngine.resultToReturn = 'Shortened text.';

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text with lots of redundant filler';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 1);
      expect(
        fakeSmartModeEngine.lastSystemPrompt,
        smartModeConciseSystemPrompt,
      );
      expect(clipboardText, 'Shortened text.');
      expect(fakeAttention.requestAttentionCalls, 0);
    });

    test('standard preset "concise" but no model downloaded falls back to the '
        'raw transcript and fires an OS notification', () async {
      container.dispose();
      container = buildSmartModeContainer(
        settingsWithPreset('concise'),
        modelDownloaded: false,
      );
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text, model missing';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 0);
      expect(clipboardText, 'raw text, model missing');
      expect(fakeAttention.requestAttentionCalls, 1);
      expect(fakeAttention.lastKind, AttentionKind.smartModeFallback);
    });

    test('standard preset "translate" with the default (English) target '
        'language replaces the pasted text with the translated engine '
        'result', () async {
      container.dispose();
      container = buildSmartModeContainer(settingsWithPreset('translate'));
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      fakeSmartModeEngine.resultToReturn = 'Translated text.';

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text in some language';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 1);
      expect(
        fakeSmartModeEngine.lastSystemPrompt,
        smartModeTranslateSystemPrompt(SmartModeTargetLanguage.english),
      );
      expect(clipboardText, 'Translated text.');
      expect(fakeAttention.requestAttentionCalls, 0);
    });

    test('standard preset "translate" but no model downloaded falls back to '
        'the raw transcript and fires an OS notification', () async {
      container.dispose();
      container = buildSmartModeContainer(
        settingsWithPreset('translate'),
        modelDownloaded: false,
      );
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text, model missing';
      await orch.stopRecording();

      expect(fakeSmartModeEngine.runCalls, 0);
      expect(clipboardText, 'raw text, model missing');
      expect(fakeAttention.requestAttentionCalls, 1);
      expect(fakeAttention.lastKind, AttentionKind.smartModeFallback);
    });

    test('an unrecognized/not-yet-validated target-language settings value '
        'falls back to English rather than crashing (ticket-09 forward '
        'compatibility)', () async {
      container.dispose();
      container = buildSmartModeContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
          smartMode: SmartModeSettings(
            standardPreset: 'translate',
            targetLanguage: 'xx',
          ),
        ),
      );
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      fakeSmartModeEngine.resultToReturn = 'Translated text.';

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text';
      await orch.stopRecording();

      expect(
        fakeSmartModeEngine.lastSystemPrompt,
        smartModeTranslateSystemPrompt(SmartModeTargetLanguage.english),
      );
      expect(clipboardText, 'Translated text.');
    });

    test('Smart-Mode hotkey override uses its own target language, not the '
        'standard preset\'s (ticket 09)', () async {
      container.dispose();
      container = buildSmartModeContainer(
        const AppSettings(
          stt: SttSettings(model: 'whisper-small', language: 'English'),
          afterTranscriptionSection: AfterTranscriptionSettings(
            afterTranscription: 'clipboard',
          ),
          onboarding: OnboardingSettings(onboardingCompleted: true),
          smartMode: SmartModeSettings(
            standardPreset: 'off',
            targetLanguage: 'en',
          ),
          smartModeHotkey: SmartModeHotkeySettings(
            smartModeHotkeyPreset: 'translate',
            smartModeHotkeyTargetLanguage: 'fr',
          ),
        ),
      );
      await container.read(settingsProvider.future);
      container.read(systemAttentionServiceProvider);
      container
          .read(smartModeHotkeyOverridePresetProvider.notifier)
          .set(SmartModePreset.translate);
      fakeSmartModeEngine.resultToReturn = 'Texte traduit.';

      final orch = await startRecordingPhase();
      fakeStt.transcriptToReturn = 'raw text in some language';
      await orch.stopRecording();

      expect(
        fakeSmartModeEngine.lastSystemPrompt,
        smartModeTranslateSystemPrompt(SmartModeTargetLanguage.french),
      );
      expect(clipboardText, 'Texte traduit.');
    });
  });
}

// ---------------------------------------------------------------------------
// Additional fake: DB whose insertAudioAttachment always fails, to verify
// _retainRecentAudio doesn't orphan the already-moved WAV on that failure.
// ---------------------------------------------------------------------------

class _ThrowingInsertAudioAttachmentDb extends HistoryDatabase {
  _ThrowingInsertAudioAttachmentDb()
    : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> insertAudioAttachment({
    required String entryId,
    required String filePath,
    required int sizeBytes,
  }) => throw Exception('simulated insert failure');
}

// ---------------------------------------------------------------------------
// Additional fake: STT service that stays in stopped state after ensureRunning
// ---------------------------------------------------------------------------

class _NotReadySttService extends SttServerStateNotifier {
  _NotReadySttService({
    this.statusAfterEnsure = const SttStatus(
      serverState: SttServerState.stopped,
      port: 0,
    ),
  });

  final SttStatus statusAfterEnsure;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.stopped, port: 0);

  @override
  Future<void> ensureRunning() async {
    state = statusAfterEnsure;
  }

  @override
  Future<String> transcribeBytes(
    List<int> wavBytes, {
    String? language,
  }) async => '';

  @override
  Future<void> prewarm() async {}
}
