/// Journey: onboarding with microphone permissions (Onboarding v6 flow).
///
/// Pages: 1 welcome, 2 access (the microphone is a card here, V03), 3 mic
/// (level card, "Weiter" held until speech, V04), 4 hotkey, 5 practice, 6
/// privacy and start.
///
/// a) First run: page 1 fires nothing. The first, one-time permission request
///    comes from the microphone card on page 2 and is denied.
/// b) The microphone page shows the denied state as its next-step hint, and
///    "Weiter" is held. The hint's action requests again (the Settings
///    deep-link path) and the permission stays denied. "Überspringen" moves on.
/// c) A test recording on the practice page while the microphone is denied
///    shows the recording error toast with its next step instead of failing
///    silently.
/// d) Permission granted in the OS. Back on the microphone page the hint's
///    action re-requests and reads granted; the level probe hears speech and
///    "Weiter" opens. The practice dictation then produces a transcript, the
///    completion gate opens, and "Los geht's" persists `onboardingCompleted`.
///    A fresh start shows no onboarding.
///
/// Platform is pinned to Windows through `debugDefaultTargetPlatformOverride`:
/// the Windows access body lists the microphone card, and the Auto-Paste
/// capability is faked as ready (paste is OS integration). Real providers,
/// real pages and an in-memory Drift database. Fakes cover the mic permission
/// platform check, the level probe, audio capture, STT, the transcriber, native
/// paste and the attention service. UI is addressed by key or semantics
/// identifier only.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/onboarding_speech_consent.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show
        HotKeyRegistrar,
        HotkeyRegistrationStatus,
        HotkeyRegistrationStatusController,
        HotkeyService,
        hotkeyRegistrationStatusProvider,
        hotkeyServiceProvider;
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart'
    show retainedAudioDirOverride, sttDir, sttDirOverride, sttModelPath;
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart'
    show PasteCapability, PasteCapabilityStatus;
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/stt/on_device_engine_lifecycle.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/stt_engine_lifecycle_provider.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/transcription/transcriber.dart';
import 'package:whispaste/widgets/recording_behavior.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../features/onboarding/onboarding_test_doubles.dart';
import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fakes at the OS / model boundary
// ---------------------------------------------------------------------------

/// Stand-in for the platform microphone permission. [granted] is the state the
/// OS would report. The counters record which entry point the UI used:
/// `request` (dialog or Settings path) versus a passive `check`.
class _FakeMicPermission implements MicPermissionChecker {
  bool granted = false;
  int requestCalls = 0;
  int checkCalls = 0;

  @override
  Future<bool> check({required bool request}) async {
    if (request) {
      requestCalls++;
    } else {
      checkCalls++;
    }
    return granted;
  }
}

/// Audio capture. Refuses to start while the fake permission is denied, the
/// same way the real service does with `mic_permission_denied`.
class _FakeAudio extends AudioServiceNotifier {
  _FakeAudio(this.wavPath, this.mic);

  final String wavPath;
  final _FakeMicPermission mic;
  int startAttempts = 0;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => null;

  @override
  Future<void> startRecording({bool streamRawPcm = false}) async {
    if (state.isRecording) return;
    startAttempts++;
    if (!mic.granted) {
      state = const AudioStatus(
        captureState: AudioCaptureState.error,
        errorMessage: 'mic_permission_denied',
      );
      return;
    }
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPath,
    );
  }

  @override
  Future<String?> stopRecording({bool keepTail = true}) async {
    state = AudioStatus(filePath: wavPath);
    return wavPath;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeStt extends SttServerStateNotifier {
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
  }) async => 'hallo welt';

  @override
  Future<void> prewarm() async {}
}

/// Engine lifecycle is the STT boundary. The real whisper adapter arms
/// idle-shutdown timers of several minutes when a recording stops, which
/// would outlive the test.
class _FakeEngineLifecycle implements OnDeviceEngineLifecycle {
  @override
  EngineLifecycleStatus get status =>
      const EngineLifecycleStatus(isReady: true);

  @override
  Future<void> ensureRunning({bool warmup = true}) async {}

  @override
  Future<void> prewarm() async {}

  @override
  Future<void> stop() async {}

  @override
  void notifyRecordingStarted() {}

  @override
  void notifyRecordingStopped() {}

  @override
  void notifyTranscriptionCompleted() {}
}

class _FakeTranscriber implements Transcriber {
  int calls = 0;

  @override
  Future<void> prepare() async {}

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    calls++;
    return 'hallo welt';
  }

  @override
  void release() {}
}

class _FakeModelDownload extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(
    downloadedModels: {'whisper-small'},
    scanned: true,
  );
}

class _StaticParakeetDownload extends ParakeetDownloadNotifier {
  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();
}

/// Auto-Paste capability is OS integration, so it is faked as ready.
class _FakePasteCapability extends PasteCapabilityNotifier {
  @override
  PasteCapabilityState build() => const PasteCapabilityState(
    capability: PasteCapability(status: PasteCapabilityStatus.ready),
  );

  @override
  Future<void> check({bool prompt = false}) async {}

  @override
  void stopPolling() {}
}

/// Native paste bridge stand-in. Nothing is pasted in this journey: the test
/// recording goes to the sandbox sink, so these are never reached.
class _FakePaste extends DesktopPasteController {
  @override
  Future<bool> capturePasteTarget() async => true;

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async =>
      const NativePasteResult(status: NativePasteStatus.success);

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

HotkeyService _hotkeyService() {
  final service = HotkeyService()
    ..injectRegistrar(const _FakeRegistrar())
    ..injectMonitor(NoopKeyboardUpMonitor());
  return service;
}

class _FakeSystemAttention extends SystemAttentionService {
  _FakeSystemAttention(super.ref);

  @override
  Future<void> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
  }) async {}

  @override
  Future<void> clearAttention() async {}
}

class _FakeHotkeyController extends HotkeyRegistrationStatusController {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.success;
}

class _FakeRegistrar implements HotKeyRegistrar {
  const _FakeRegistrar();

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

/// Settings persisted outside the widget tree, so a second container (a
/// restart) reads what the first one wrote.
class _SettingsStore {
  _SettingsStore(this.value);

  AppSettings value;
}

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this.store);

  final _SettingsStore store;

  @override
  Future<AppSettings> build() async => store.value;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    store.value = updater(store.value);
    state = AsyncData(store.value);
  }
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

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

late Directory _tmp;

/// Valid 16 kHz mono 16-bit WAV with [frames] frames of silence.
Uint8List _wav({int frames = 1600}) {
  final dataBytes = frames * 2;
  final view = ByteData(44 + dataBytes)
    ..setUint32(0, 0x46464952, Endian.little)
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little)
    ..setUint32(12, 0x20746d66, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little)
    ..setUint32(40, dataBytes, Endian.little);
  return view.buffer.asUint8List();
}

AppSettings _initialSettings() => const AppSettings(
  stt: SttSettings(model: 'whisper-small', language: 'English'),
  afterTranscriptionSection: AfterTranscriptionSettings(
    afterTranscription: 'clipboard',
  ),
  onboarding: OnboardingSettings(),
);

/// Polls until [condition] holds. Real file I/O of the recording pipeline
/// completes between polls, so each poll yields to the real event loop once.
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

const _micCard = 'onboarding-permissions-mic';
const _micCardAction = 'onboarding-permissions-mic-allow';
const _micAllow = 'onboarding-mic-allow';
const _micSkip = 'onboarding-mic-skip';
// The practice page's missing-microphone note is found by its action.
const _practiceMicNote = 'onboarding-practice-mic-action';
const _hotkeySkip = 'onboarding-hotkey-skip';
const _tryOutHeading = 'onboarding-tryout-heading';

/// Whether the shell's "Weiter" is currently wired to an action.
bool _nextEnabled(WidgetTester tester) =>
    tester
        .widget<WpHeroButton>(find.byKey(kOnboardingNextButtonKey))
        .onPressed !=
    null;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeMicPermission mic;
  late _FakeAudio audio;
  late _FakeTranscriber transcriber;
  late _SettingsStore store;

  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('wp40-onboarding-permissions-');
    sttDirOverride = _tmp.path;
    retainedAudioDirOverride = '${_tmp.path}/retained-audio';
    Directory(sttDir()).createSync(recursive: true);
    final modelPath = sttModelPath('whisper-small');
    if (modelPath != null && !File(modelPath).existsSync()) {
      File(modelPath).writeAsStringSync('fake-model');
    }
    final wavFile = File(p.join(_tmp.path, 'recording.wav'))
      ..writeAsBytesSync(_wav());
    mic = _FakeMicPermission();
    audio = _FakeAudio(wavFile.absolute.path, mic);
    transcriber = _FakeTranscriber();
    store = _SettingsStore(_initialSettings());
  });

  tearDown(() {
    sttDirOverride = null;
    retainedAudioDirOverride = null;
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  testWidgets(
    'first run: denied microphone gets a next-step hint, a grant completes '
    'onboarding and a restart shows none',
    (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        // The onboarding runs in its own window size; on the default 800×600
        // surface the v6 welcome page's Next button lies outside the hit-test
        // area and the tap goes nowhere.
        tester.view
          ..physicalSize = kOnboardingWindowSize
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          makeTestable(
            const WpRecordingBehavior(child: OnboardingOverlay()),
            size: const Size(1280, 1600),
            locale: const Locale('en'),
            // The welcome scene loops its bars for as long as it is shown
            // (3ab472865), so pumpAndSettle never settles. Reduced motion
            // is the setting the other onboarding tests use for this.
            disableAnimations: true,
            overrides: [
              settingsProvider.overrideWith(() => _FakeSettings(store)),
              secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore()),
              micPermissionCheckerProvider.overrideWithValue(mic),
              // The start page's consent saves the offered model; offering the
              // model on disk keeps the practice recording's preflight green
              // instead of the host machine's recommendation.
              welcomeSpeechOfferProvider.overrideWith(
                (ref) async => const WelcomeSpeechOffer(
                  engine: OnDeviceEngine.whisper,
                  whisperModelId: 'whisper-small',
                  sizeBytes: 466 * 1024 * 1024,
                ),
              ),
              onboardingMicProbeProvider.overrideWithValue(
                OnboardingFakeMicProbe(),
              ),
              audioInputDevicesProvider.overrideWith(
                (ref) async => const <String>[],
              ),
              audioServiceProvider.overrideWith(() => audio),
              localSttBundleProvider.overrideWith(_FakeStt.new),
              onDeviceEngineLifecycleProvider.overrideWithValue(
                _FakeEngineLifecycle(),
              ),
              transcriberProvider.overrideWithValue(transcriber),
              modelDownloadProvider.overrideWith(_FakeModelDownload.new),
              parakeetDownloadProvider.overrideWith(
                _StaticParakeetDownload.new,
              ),
              desktopPasteControllerProvider.overrideWith(
                (ref) => _FakePaste(),
              ),
              pasteCapabilityNotifierProvider.overrideWith(
                _FakePasteCapability.new,
              ),
              systemAttentionServiceProvider.overrideWith(
                _FakeSystemAttention.new,
              ),
              hotkeyRegistrationStatusProvider.overrideWith(
                _FakeHotkeyController.new,
              ),
              hotkeyServiceProvider.overrideWith(_hotkeyService),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OnboardingOverlay)),
        );

        // a) First run: onboarding is on top, nothing is requested yet.
        expect(container.read(onboardingSurfaceActiveProvider), isTrue);
        expect(mic.requestCalls, 0);

        // Leaving the welcome page: the speech-model consent awaits real async
        // work before it moves on, so the About page is waited for, not pumped
        // once.
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await _until(
          tester,
          () => find
              .bySemanticsIdentifier('onboarding-about-next')
              .evaluate()
              .isNotEmpty,
          what: 'about page',
        );
        expect(mic.requestCalls, 0);

        // About you (1) sits between Welcome and Access (337aa0cbb). It has two
        // views, the name and then roles and attribution; every answer is
        // optional, so Next twice leads on without input.
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await _until(
          tester,
          () => find.bySemanticsIdentifier(_micCard).evaluate().isNotEmpty,
          what: 'access page',
        );
        expect(mic.requestCalls, 0);

        // Access page (2): the microphone is a card here with its own action.
        // The first, one-time OS request comes from that tap; it is denied.
        expect(find.bySemanticsIdentifier(_micCard), findsOneWidget);
        await tester.tap(find.bySemanticsIdentifier(_micCardAction));
        await tester.pumpAndSettle();
        expect(mic.requestCalls, 1);
        expect(
          container.read(micPermissionNotifierProvider).status,
          MicPermissionStatus.denied,
        );

        // Weiter with the microphone still missing asks once whether to skip
        // it; confirming leads on to the microphone page (3).
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier('confirm-dialog-confirm'));
        await tester.pumpAndSettle();

        // Microphone page (3): the denied permission is the next-step hint, and
        // "Weiter" stays held until speech has been heard.
        expect(find.bySemanticsIdentifier(_micAllow), findsOneWidget);
        expect(_nextEnabled(tester), isFalse);

        // b) The hint's action takes the request path again (Settings
        // deep-link plus polling), and the permission stays denied.
        await tester.tap(find.bySemanticsIdentifier(_micAllow));
        await tester.pumpAndSettle();
        expect(
          mic.requestCalls,
          2,
          reason: 'the hint must request, not just check',
        );
        expect(
          container.read(micPermissionNotifierProvider).status,
          MicPermissionStatus.denied,
        );
        expect(find.bySemanticsIdentifier(_micAllow), findsOneWidget);
        expect(_nextEnabled(tester), isFalse);

        // "Überspringen" is the way past the page without speech: hotkey page
        // (4), then the practice page (5).
        // The hotkey page holds "Weiter" until the hotkey was tried once; its
        // own skip leads on without trying it.
        await tester.tap(find.bySemanticsIdentifier(_micSkip));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(_hotkeySkip));
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(_tryOutHeading), findsOneWidget);

        // c) Dictating while denied: the practice chat collects the missing
        // microphone into one note with the next step ("Allow microphone"),
        // and nothing is recorded (AK 3, V06).
        // Not awaited, as the button's tap is not: the pipeline finishes in
        // the pumps below, and awaiting it inside the fake clock would hang.
        container
            .read(recordingOrchestratorProvider.notifier)
            .toggleRecording();
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(_practiceMicNote), findsOneWidget);
        expect(transcriber.calls, 0);
        expect(
          container.read(recordingProvider).phase,
          isNot(RecordingPhase.recording),
        );
        expect(
          container.read(onboardingTestRecordingSucceededProvider),
          isFalse,
        );

        // d) Permission granted in the OS. Back to the microphone page (past the
        // practice and hotkey pages); its hint reads granted and the level probe
        // hears speech, so "Weiter" opens.
        // Each v6 page carries its own back link.
        await tester.tap(find.bySemanticsIdentifier('onboarding-tryout-back'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier('onboarding-hotkey-back'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(_micAllow), findsOneWidget);
        mic.granted = true;
        await tester.tap(find.bySemanticsIdentifier(_micAllow));
        await tester.pumpAndSettle();
        expect(mic.requestCalls, 3);
        expect(
          container.read(micPermissionNotifierProvider).status,
          MicPermissionStatus.granted,
        );
        expect(_nextEnabled(tester), isTrue);

        // Forward again to the practice page.
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsIdentifier(_hotkeySkip));
        await tester.pumpAndSettle();
        expect(find.bySemanticsIdentifier(_tryOutHeading), findsOneWidget);

        // The test recording now starts and stops through the real pipeline and
        // yields a transcript, which opens the completion gate.
        // Relative to the starts so far: the denied tap in c) already
        // reached the audio start and was refused there.
        final startsBefore = audio.startAttempts;
        // Not awaited, as the button's tap is not: the pipeline finishes in
        // the pumps below, and awaiting it inside the fake clock would hang.
        container
            .read(recordingOrchestratorProvider.notifier)
            .toggleRecording();
        await tester.pump();
        await _until(
          tester,
          () => audio.startAttempts == startsBefore + 1,
          what: 'second recording start',
        );
        // Not awaited, as the button's tap is not: the pipeline finishes in
        // the pumps below, and awaiting it inside the fake clock would hang.
        container
            .read(recordingOrchestratorProvider.notifier)
            .toggleRecording();
        await tester.pump();
        await _until(
          tester,
          () => container.read(onboardingTestRecordingSucceededProvider),
          what: 'test recording transcript',
        );
        expect(transcriber.calls, 1);

        // Finish: the privacy and start page persists onboarding as completed
        // (no smart mode interstitial since V07). The toasts of the two recordings auto-dismiss
        // after 10 s (actionable minimum), and until then their overlay absorbs
        // taps on the footer.
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('toast-message')), findsNothing);
        // The privacy and start page comes after the practice page; its main
        // action completes the flow.
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsIdentifier('onboarding-ready-start'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
        expect(store.value.onboarding.onboardingCompleted, isTrue);
        expect(container.read(onboardingSurfaceActiveProvider), isFalse);

        // Unmount inside the test body so the overlay's polling and the
        // recording watchdog are disposed before the binding checks for timers.
        await tester.pumpWidget(const SizedBox());
        // Let the toast auto-dismiss timers fire before the binding checks for
        // pending timers.
        await tester.pump(const Duration(seconds: 11));

        // Restart: a fresh container reads the persisted settings and shows no
        // onboarding.
        final restarted = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(() => _FakeSettings(store)),
          ],
        );
        addTearDown(restarted.dispose);
        await restarted.read(settingsProvider.future);
        expect(restarted.read(onboardingSurfaceActiveProvider), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
