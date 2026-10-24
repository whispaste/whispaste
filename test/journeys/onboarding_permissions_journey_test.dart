/// Journey: onboarding with microphone permissions.
///
/// a) First run: the overlay walks through its pages by the shell's Next key.
///    Leaving page 1 fires the one-time permission request, which is denied.
/// b) On the final page the microphone chip shows the denied state. Tapping it
///    calls the permission request again (the Settings deep-link path), and
///    the chip stays denied.
/// c) A test recording while the microphone is denied shows the recording
///    error toast with its next step instead of failing silently.
/// d) Permission granted, the chip is re-checked and reads granted. The test
///    recording then produces a transcript, the completion gate opens, and
///    "Los geht's" persists `onboardingCompleted`. A fresh start shows no
///    onboarding.
///
/// Platform is pinned to Windows through `debugDefaultTargetPlatformOverride`:
/// the chip is hidden on Linux, and Windows keeps the Auto-Paste page. The
/// Auto-Paste capability is faked as ready (paste is OS integration). Real
/// providers, real pages and an in-memory Drift database. Fakes cover the mic
/// permission platform check, audio capture, STT, the transcriber, native paste
/// and the attention service. UI is addressed by key only.
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
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart';
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
  Future<String?> stopRecording() async {
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

Key _micChip(String status) => ValueKey('onboarding-mic-chip-$status');

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeMicPermission mic;
  late _FakeAudio audio;
  late _FakeTranscriber transcriber;
  late _SettingsStore store;
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

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

        await tester.pumpWidget(
          makeTestable(
            const WpRecordingBehavior(child: OnboardingOverlay()),
            size: const Size(1280, 1600),
            locale: const Locale('en'),
            overrides: [
              settingsProvider.overrideWith(() => _FakeSettings(store)),
              secureKeyStoreProvider.overrideWithValue(_FakeSecureKeyStore()),
              micPermissionCheckerProvider.overrideWithValue(mic),
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

        // Leaving page 1 fires the one-time OS request, which is denied.
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
        expect(mic.requestCalls, 1);
        expect(
          container.read(micPermissionNotifierProvider).status,
          MicPermissionStatus.denied,
        );

        // Page through to the final page, where the microphone chip sits.
        for (var page = 1; page < 6; page++) {
          await tester.tap(find.byKey(kOnboardingNextButtonKey));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(kTestRecordingStepRecordButtonKey), findsOneWidget);

        // b) The denied chip is the hint. Its tap takes the request path again
        // (Settings deep-link plus polling), not a passive check.
        expect(find.byKey(_micChip('denied')), findsOneWidget);
        final checksBefore = mic.checkCalls;
        await tester.tap(find.byKey(_micChip('denied')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          mic.requestCalls,
          2,
          reason: 'chip must request, not just check',
        );
        expect(mic.checkCalls, checksBefore);
        expect(find.byKey(_micChip('denied')), findsOneWidget);

        // c) Dictating while denied: the start is refused and the toast names
        // the next step (allow it in system settings).
        await tester.tap(find.byKey(kTestRecordingStepRecordButtonKey));
        await tester.pump();
        // The toast renders the cause and the next step as an error notice.
        await _until(
          tester,
          () =>
              find.byKey(const Key('error-notice-cause')).evaluate().isNotEmpty,
          what: 'recording error toast',
        );
        expect(audio.startAttempts, 1);
        expect(transcriber.calls, 0);
        expect(
          tester.widget<Text>(find.byKey(const Key('error-notice-cause'))).data,
          l10n.errorNoticeMicCause,
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('error-notice-next-step')))
              .data,
          l10n.errorNoticeMicNext,
        );
        expect(
          container.read(recordingProvider).phase,
          isNot(RecordingPhase.recording),
        );
        expect(
          container.read(onboardingTestRecordingSucceededProvider),
          isFalse,
        );

        // d) Permission granted in the OS. The chip's tap re-checks and reads
        // granted.
        mic.granted = true;
        await tester.tap(find.byKey(_micChip('denied')));
        await tester.pumpAndSettle();
        expect(mic.requestCalls, 3);
        expect(find.byKey(_micChip('granted')), findsOneWidget);

        // The test recording now starts and stops through the real pipeline and
        // yields a transcript, which opens the completion gate.
        await tester.tap(find.byKey(kTestRecordingStepRecordButtonKey));
        await tester.pump();
        await _until(
          tester,
          () => audio.startAttempts == 2,
          what: 'second recording start',
        );
        await tester.tap(find.byKey(kTestRecordingStepRecordButtonKey));
        await tester.pump();
        await _until(
          tester,
          () => container.read(onboardingTestRecordingSucceededProvider),
          what: 'test recording transcript',
        );
        expect(transcriber.calls, 1);

        // Finish: the smart mode interstitial comes first, then onboarding is
        // persisted as completed. The toasts of the two recordings auto-dismiss
        // after 10 s (actionable minimum), and until then their overlay absorbs
        // taps on the footer.
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('toast-message')), findsNothing);
        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('onboarding-smart-mode-hint-skip')),
        );
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
