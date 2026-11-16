/// Single-source-of-truth contract between the floating button and the
/// recording pipeline.
///
/// The floating button (its own native window and render engine) must show
/// the phase of [recordingProvider] for every start and stop path: the
/// button itself, the overlay pill, the hotkey, and the dock. These tests run
/// the REAL [RecordingOrchestrator] with the REAL [FloatingButtonService] and
/// [FloatingOverlayService]; only the native controllers and the audio/STT/
/// paste seams are fakes. [_FakeButtonController] records every visual state
/// the native button receives.
///
/// Every test runs in fake time (`testWidgets`, #1491): the orchestrator's and
/// the button's timers advance with `tester.pump`, and the recording file
/// layer is injected ([_FakeRecordingFiles]), so no step waits real time.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_journal_provider.dart';
import 'package:whispaste/services/audio/recovery/transcription_journal.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;
import 'package:whispaste/services/recording_files.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/recording/safety_guard.dart';

// ── Native controller fakes ───────────────────────────────────────────────────

class _FakeButtonController implements FloatingButtonController {
  final _events = StreamController<FloatingButtonEvent>.broadcast();

  /// Every visual state pushed to the native button, in order.
  final states = <FloatingButtonVisualState>[];

  /// When set, the next `recording` push is acknowledged only once this
  /// completes, like a native channel round trip on a busy main thread.
  Completer<void>? holdRecordingAck;

  FloatingButtonVisualState? get lastState =>
      states.isEmpty ? null : states.last;

  /// Simulates a click on the floating button.
  void click() => _events.add(const FloatingButtonClicked());

  /// Simulates the user dragging the button to a new position.
  void drag(double x, double y) => _events.add(FloatingButtonDragEnded(x, y));

  @override
  Stream<FloatingButtonEvent> get events => _events.stream;

  @override
  Future<void> setState(FloatingButtonVisualState state) async {
    states.add(state);
    calls.add('state:${state.name}');
    if (state == FloatingButtonVisualState.recording &&
        holdRecordingAck != null) {
      await holdRecordingAck!.future;
    }
  }

  /// When set, `show` waits for it, like a native resize on a stalled main
  /// thread. Used to prove the look is not queued behind geometry.
  Completer<void>? holdShow;

  /// Native geometry and theme calls. Each one resizes or repaints the native
  /// panel, so an unrelated settings write must not produce any of them.
  int geometryCalls = 0;

  /// Last value applied per native call, so live-settings tests can assert the
  /// new appearance reached the button without a restart.
  int? lastSize;

  /// Ordered native calls (`state:<name>`, `ring:<bool>`) so a test can check
  /// which appearance was in force when a state arrived.
  final calls = <String>[];
  ({String background, String wave, FloatingButtonLook look})? lastTheme;

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) async {
    geometryCalls++;
    await holdShow?.future;
  }

  @override
  Future<void> hide() async {}

  @override
  Future<void> setPosition(double x, double y) async {}

  @override
  Future<void> setSize(int size) async {
    geometryCalls++;
    lastSize = size;
  }

  @override
  Future<void> setTheme({
    required String background,
    required String wave,
    FloatingButtonLook look = FloatingButtonLook.defaults,
  }) async {
    geometryCalls++;
    lastTheme = (background: background, wave: wave, look: look);
    calls.add('ring:${look.ring}');
  }

  @override
  Future<void> setContextMenuItems(
    List<Map<String, Object?>> items, {
    String appearance = 'system',
  }) async {}

  @override
  Future<({double x, double y})?> getPosition() async => null;

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

/// A button whose render engine can stall (paints no frame) and be re-booted,
/// like the macOS render engine. A healthy engine acknowledges every render
/// message with a frame; a re-boot either heals the engine or leaves it stalled.
class _StallableButtonController extends _FakeButtonController
    implements RenderEngineRecovery {
  /// While true the render engine paints nothing, so nothing is acknowledged.
  bool frozen = false;

  /// Whether a re-boot yields a healthy engine.
  bool rebootHeals = true;

  int rebootCalls = 0;

  /// Call site of the latest re-boot request, reported on assertion failure.
  StackTrace? lastRebootTrace;

  /// Reboot count at the moment each state push arrived, parallel to [states].
  /// Read at push time, so the assertion does not depend on when the test
  /// looks: a re-push that happens before any reboot records 0.
  final rebootsAtState = <int>[];

  /// Every push (state, look or size), counted to script a heal at a chosen
  /// push via [healAtPush].
  int pushCount = 0;

  /// When set, the engine heals (and acknowledges) on that push number.
  int? healAtPush;

  /// Acknowledges a frame asynchronously, like a post-frame callback.
  void paintFrame() {
    scheduleMicrotask(() => _events.add(const FloatingButtonRenderFrame()));
  }

  void _ackIfHealthy() {
    if (!frozen) paintFrame();
  }

  void _countPush() {
    pushCount++;
    if (pushCount == healAtPush) {
      frozen = false;
      paintFrame();
    }
  }

  @override
  Future<void> setState(FloatingButtonVisualState state) async {
    rebootsAtState.add(rebootCalls);
    _countPush();
    await super.setState(state);
    _ackIfHealthy();
  }

  @override
  Future<void> setTheme({
    required String background,
    required String wave,
    FloatingButtonLook look = FloatingButtonLook.defaults,
  }) async {
    _countPush();
    await super.setTheme(background: background, wave: wave, look: look);
    _ackIfHealthy();
  }

  @override
  Future<void> setSize(int size) async {
    _countPush();
    await super.setSize(size);
    _ackIfHealthy();
  }

  @override
  Future<void> rebootRenderEngine() async {
    rebootCalls++;
    lastRebootTrace = StackTrace.current;
    if (rebootHeals) {
      frozen = false;
      paintFrame();
    }
  }
}

/// The tester of the running test; [_settle], [_waitFor] and
/// [_Harness.until] advance its fake clock.
late WidgetTester _tester;

/// Advances fake time in 1 ms steps until [condition] holds, failing after
/// 5 s of fake time. Used for events that must happen eventually, at the
/// step the watchdog's timers produce them.
Future<void> _waitFor(bool Function() condition, String what) async {
  for (var i = 0; !condition(); i++) {
    if (i >= 5000) fail('timed out waiting for $what');
    await _tester.pump(const Duration(milliseconds: 1));
  }
}

class _FakeOverlayController implements FloatingOverlayController {
  final _events = StreamController<FloatingOverlayEvent>.broadcast();

  /// Simulates a click on the body of the overlay pill (the stop action).
  void tapBody() => _events.add(const OverlayBodyClicked());

  /// Simulates the overlay close (X) button.
  void tapClose() => _events.add(const OverlayCloseClicked());

  /// Simulates the retry button shown in the error state.
  void tapRetry() => _events.add(const OverlayRetryClicked());

  @override
  Stream<FloatingOverlayEvent> get events => _events.stream;

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {}

  @override
  Future<void> setWaveformBars(List<double> bars) async {}

  @override
  Future<void> setPosition(
    double x,
    double y,
    OverlayAnchorMode anchor,
  ) async {}

  @override
  Future<void> setContextMenuItems(
    List<Map<String, Object?>> items, {
    String appearance = 'system',
  }) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class _TestableButtonService extends FloatingButtonService {
  _TestableButtonService(this._fake, this._frameDeadline);
  final _FakeButtonController _fake;
  final Duration _frameDeadline;

  /// Per-test deadline. Short where a stall must be observed, long where a
  /// healthy engine must never be judged stalled (see the heartbeat group).
  @override
  Duration get renderFrameDeadline => _frameDeadline;

  @override
  Duration get renderBootGrace => Duration.zero;

  @override
  FloatingButtonController? createController() => _fake;
}

class _TestableOverlayService extends FloatingOverlayService {
  _TestableOverlayService(this._fake);
  final _FakeOverlayController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

// ── Recording pipeline fakes (same seams as the orchestrator snapshot suite) ──

class _FakeAudioService extends AudioServiceNotifier {
  _FakeAudioService(this.wavPath);
  final String wavPath;
  StreamController<double>? _ampCtrl;

  @override
  AudioStatus build() => const AudioStatus();

  @override
  Stream<double>? get amplitudeStream => _ampCtrl?.stream;

  /// The guard reads raw dBFS (#984): a level of 0 stands for no signal.
  @override
  Stream<GuardSample>? get guardSampleStream => _ampCtrl?.stream.map(
    (l) => l == 0
        ? const GuardSample(dbFs: double.negativeInfinity, level: 0)
        : GuardSample(dbFs: -30, level: l),
  );

  @override
  Future<void> startRecording({bool streamRawPcm = false}) async {
    if (state.isRecording) return;
    _ampCtrl = StreamController<double>.broadcast();
    state = AudioStatus(
      captureState: AudioCaptureState.recording,
      filePath: wavPath,
    );
  }

  @override
  Future<String?> stopRecording({bool keepTail = true}) async {
    _ampCtrl?.close();
    _ampCtrl = null;
    state = AudioStatus(filePath: wavPath);
    return wavPath;
  }

  @override
  Future<void> cleanupFile(String? path) async {}
}

class _FakeSttService extends SttServerStateNotifier {
  /// When true, every transcription fails (the error exit of the pipeline).
  static bool failTranscription = false;

  @override
  SttStatus build() =>
      const SttStatus(serverState: SttServerState.ready, port: 9999);

  @override
  Future<void> ensureRunning({bool warmup = true}) async {
    state = state.copyWith(serverState: SttServerState.ready);
  }

  @override
  Future<String> transcribeBytesWithProgress(
    List<int> wavBytes, {
    String? language,
    void Function(double fraction)? onProgress,
    String? wavPath,
  }) async {
    if (failTranscription) throw Exception('Transcription failed');
    return 'Hello world';
  }

  @override
  Future<void> prewarm() async {}
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings(
    overlay: OverlaySettings(showFloatingButton: true),
    stt: SttSettings(model: 'whisper-small', language: 'English'),
    afterTranscriptionSection: AfterTranscriptionSettings(
      afterTranscription: 'nothing',
    ),
    onboarding: OnboardingSettings(onboardingCompleted: true),
  );

  /// In-memory write: a settings change re-runs the button's settings sync
  /// without touching the database.
  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    final current = state.value ?? const AppSettings();
    state = AsyncData(updater(current));
  }
}

class _FakeSecureKeyStore extends SecureKeyStore {
  _FakeSecureKeyStore() : super(null);

  @override
  Future<String?> readKey(String key) async => null;

  @override
  Future<void> writeKey(String key, String value) async {}

  @override
  Future<void> deleteKey(String key) async {}

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

class _FakePasteController extends DesktopPasteController {
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

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(
    downloadedModels: {
      'whisper-small',
      'whisper-medium',
      'whisper-large-v3-turbo',
    },
  );
}

/// The recording file layer without disk I/O: real file futures only
/// complete in real time, which the fake clock of `testWidgets` never waits
/// for. The captured WAV is the same minimal file [_prepareFiles] writes.
class _FakeRecordingFiles implements RecordingFiles {
  final _wav = List<int>.filled(364, 0);

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<int> length(String path) async => _wav.length;

  @override
  Future<List<int>> readAsBytes(String path) async => _wav;

  @override
  Future<bool> directoryExists(String path) async => true;

  @override
  Future<void> createDirectory(String path) async {}
}

/// The crash journal without its file write (real I/O, see above).
class _FakeTranscriptionJournal extends TranscriptionJournal {
  _FakeTranscriptionJournal() : super(RecordingJournal('unused'));

  @override
  Future<String?> begin({
    required String wavPath,
    required String entryId,
    required DateTime now,
  }) async => transcriptionJournalId(entryId);

  @override
  Future<void> end(String? id) async {}
}

// ── Harness ───────────────────────────────────────────────────────────────────

final _scratchDir = Directory(
  '${Directory.systemTemp.path}/whispaste_fb_state_sync_test',
);

/// Creates the fake whisper-server binary and model file the orchestrator's
/// preflight checks for, plus a minimal WAV for the captured recording.
String _prepareFiles() {
  _scratchDir.createSync(recursive: true);
  File('${_scratchDir.path}/whisper-server').writeAsBytesSync([0]);
  File('${_scratchDir.path}/ggml-small-q5_1.bin').writeAsBytesSync([0]);
  final wav = File('${_scratchDir.path}/dictation.wav');
  wav.writeAsBytesSync(List<int>.filled(364, 0));
  return wav.absolute.path;
}

class _Harness {
  _Harness._(this.container, this.button, this.overlay);

  final ProviderContainer container;
  final _FakeButtonController button;
  final _FakeOverlayController overlay;

  RecordingOrchestrator get orchestrator =>
      container.read(recordingOrchestratorProvider.notifier);

  /// Harnesses of the running test; [disposeAll] ends them inside the test
  /// body, so no timer of theirs outlives it.
  static final _live = <_Harness>[];

  static void disposeAll() {
    for (final h in _live) {
      h.dispose();
    }
    _live.clear();
  }

  static Future<_Harness> create({
    _FakeButtonController? button,
    Duration frameDeadline = const Duration(milliseconds: 40),
  }) async {
    sttDirOverride = _scratchDir.path;
    final wavPath = _prepareFiles();
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final fake = button ?? _FakeButtonController();
    final overlay = _FakeOverlayController();
    final container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        audioServiceProvider.overrideWith(() => _FakeAudioService(wavPath)),
        localSttBundleProvider.overrideWith(_FakeSttService.new),
        settingsProvider.overrideWith(_FakeSettingsNotifier.new),
        secureKeyStoreProvider.overrideWith((ref) => _FakeSecureKeyStore()),
        desktopPasteControllerProvider.overrideWith(
          (ref) => _FakePasteController(),
        ),
        recordingFilesProvider.overrideWithValue(_FakeRecordingFiles()),
        // GPU detection runs a real process; a fixed answer keeps fake time.
        hw.gpuInfoProvider.overrideWith(
          (_) async => const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'CPU'),
        ),
        transcriptionJournalProvider.overrideWithValue(
          _FakeTranscriptionJournal(),
        ),
        modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
        floatingButtonServiceProvider.overrideWith(
          () => _TestableButtonService(fake, frameDeadline),
        ),
        floatingOverlayServiceProvider.overrideWith(
          () => _TestableOverlayService(overlay),
        ),
      ],
    );
    // Both floating services are keep-alive in the app; mirror that here.
    container.read(floatingButtonServiceProvider);
    container.read(floatingOverlayServiceProvider);
    await container.read(settingsProvider.future);
    final harness = _Harness._(container, fake, overlay);
    _live.add(harness);
    return harness;
  }

  RecordingPhase get phase => container.read(recordingPhaseProvider);

  /// Advances fake time until [target] is reached (or 5 s have passed).
  Future<void> until(bool Function(RecordingPhase) target) async {
    for (var i = 0; i < 1000 && !target(phase); i++) {
      await _tester.pump(const Duration(milliseconds: 5));
    }
  }

  void dispose() {
    container.dispose();
    sttDirOverride = null;
    if (_scratchDir.existsSync()) _scratchDir.deleteSync(recursive: true);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Harness h;

  /// A test in fake time with a fresh harness [h]; every harness the test
  /// creates is disposed before the body returns.
  void fakeTimeTest(String description, Future<void> Function() body) {
    testWidgets(description, (tester) async {
      _tester = tester;
      // Display enumeration answers at once, as the missing plugin it is in
      // tests: an unanswered channel call never completes in fake time.
      const displays = MethodChannel(
        'dev.leanflutter.plugins/screen_retriever',
      );
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(displays, (_) async => null);
      flashDurationScale = 0.02; // 2 s flash -> 40 ms, 3 s -> 60 ms
      _FakeSttService.failTranscription = false;
      try {
        h = await _Harness.create();
        await body();
      } finally {
        _Harness.disposeAll();
        flashDurationScale = 1;
        messenger.setMockMethodCallHandler(displays, null);
      }
    });
  }

  // Every start path crossed with every stop path. Each case must leave the
  // native button in the visual state of the recording phase: recording while
  // recording, idle once the cycle has ended.
  final starts = <String, Future<void> Function(_Harness)>{
    'floating button click': (h) async => h.button.click(),
    'hotkey toggle': (h) => _drive(h.orchestrator.toggleRecording()),
  };
  final stops = <String, Future<void> Function(_Harness)>{
    'overlay body tap': (h) async => h.overlay.tapBody(),
    'overlay close (cancel)': (h) async => h.overlay.tapClose(),
    'floating button click': (h) async => h.button.click(),
    // Fired like the other stop paths: the stop call only returns after the
    // pipeline's cleanup, which deletes files on disk (real I/O that fake
    // time does not wait for). The test then waits for the phase.
    'hotkey toggle': (h) async => unawaited(h.orchestrator.toggleRecording()),
  };

  fakeTimeTest(
    'start: floating button click -> stop: overlay body tap, transcription fails',
    () async {
      _FakeSttService.failTranscription = true;
      h.button.click();
      await h.until((p) => p == RecordingPhase.recording);
      h.overlay.tapBody();
      await h.until(
        (p) => p == RecordingPhase.error || p == RecordingPhase.done,
      );
      await _settle(150);
      expect(h.phase, RecordingPhase.error);
      expect(
        h.button.lastState,
        FloatingButtonVisualState.idle,
        reason: 'button sequence: ${h.button.states}',
      );
    },
  );

  fakeTimeTest(
    'restart inside the done window with a slow ack keeps the button recording',
    () async {
      h.button.click();
      await h.until((p) => p == RecordingPhase.recording);
      h.overlay.tapBody();
      await h.until((p) => p == RecordingPhase.done);
      // Start again while the 2 s done flash is still scheduled, and hold the
      // native acknowledgement of the new recording push.
      h.button.holdRecordingAck = Completer<void>();
      h.button.click();
      await h.until((p) => p == RecordingPhase.recording);
      // Let the done flash expire while the recording push is still in flight.
      await _settle(120);
      h.button.holdRecordingAck!.complete();
      await _settle(50);

      expect(h.phase, RecordingPhase.recording);
      expect(
        h.button.lastState,
        FloatingButtonVisualState.recording,
        reason: 'button sequence: ${h.button.states}',
      );
    },
  );

  fakeTimeTest('error -> overlay retry returns the button to idle', () async {
    _FakeSttService.failTranscription = true;
    h.button.click();
    await h.until((p) => p == RecordingPhase.recording);
    h.overlay.tapBody();
    await h.until((p) => p == RecordingPhase.error);
    expect(h.button.lastState, FloatingButtonVisualState.error);

    h.overlay.tapRetry();
    await h.until((p) => p == RecordingPhase.idle);
    expect(h.phase, RecordingPhase.idle);
    expect(
      h.button.lastState,
      FloatingButtonVisualState.idle,
      reason: 'button sequence: ${h.button.states}',
    );
  });

  fakeTimeTest(
    'settings write during recording keeps the button recording',
    () async {
      h.button.click();
      await h.until((p) => p == RecordingPhase.recording);
      await h.container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(floatingButtonX: 640));
      await _settle(50);
      expect(
        h.button.lastState,
        FloatingButtonVisualState.recording,
        reason: 'button sequence: ${h.button.states}',
      );

      h.overlay.tapBody();
      await h.until(
        (p) => p == RecordingPhase.done || p == RecordingPhase.idle,
      );
      await _settle(120);
      expect(
        h.button.lastState,
        FloatingButtonVisualState.idle,
        reason: 'button sequence: ${h.button.states}',
      );
    },
  );

  fakeTimeTest(
    'a changed ring reaches the button before a stalled native show returns',
    () async {
      await _settle(20);
      h.button.holdShow = Completer<void>();
      await h.container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(floatingButtonRing: false));
      await _settle(50);
      expect(
        h.button.lastTheme?.look.ring,
        isFalse,
        reason: 'ring queued behind show: ${h.button.calls}',
      );
      h.button.holdShow!.complete();
      h.button.holdShow = null;
    },
  );

  for (final ring in [true, false]) {
    fakeTimeTest(
      'recording state is pushed with the ring setting (ring=$ring)',
      () async {
        await _settle(20);
        await h.container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(floatingButtonRing: ring));
        await _settle(20);

        h.button.click();
        await h.until((p) => p == RecordingPhase.recording);
        await _settle(20);

        final at = h.button.calls.indexOf('state:recording');
        expect(at, isNot(-1), reason: 'calls: ${h.button.calls}');
        final ringBefore = h.button.calls
            .sublist(0, at)
            .lastWhere((c) => c.startsWith('ring:'), orElse: () => 'none');
        expect(
          ringBefore,
          'ring:$ring',
          reason:
              'ring must be in force when recording arrives: ${h.button.calls}',
        );
      },
    );
  }

  fakeTimeTest(
    'unrelated settings write does not touch the native button geometry',
    () async {
      // The initial sync ends with its first state push. Capture the baseline
      // only after it, or a slow runner counts that sync as a settings-write
      // reaction.
      await _waitFor(() => h.button.states.isNotEmpty, 'the initial sync');
      final before = h.button.geometryCalls;
      await h.container
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(
              overlayShowLiveTranscript: !s.overlayShowLiveTranscript,
            ),
          );
      await _settle(50);
      expect(
        h.button.geometryCalls,
        before,
        reason: 'native geometry calls on an unrelated write',
      );
    },
  );

  group('live appearance settings reach the button without a restart', () {
    final cases =
        <
          ({
            String name,
            AppSettings Function(AppSettings) change,
            void Function(_FakeButtonController b) expect,
          })
        >[
          (
            name: 'ring off',
            change: (s) => s.copyWith(floatingButtonRing: false),
            expect: (b) => expect(b.lastTheme?.look.ring, isFalse),
          ),
          (
            name: 'size large',
            change: (s) => s.copyWith(floatingButtonSize: 'large'),
            expect: (b) => expect(
              b.lastSize,
              FloatingButtonLook.fromValues(size: 'large').diameter.toInt(),
            ),
          ),
          (
            name: 'square shape',
            change: (s) => s.copyWith(floatingButtonShape: 'square'),
            expect: (b) => expect(b.lastTheme?.look.square, isTrue),
          ),
          (
            name: 'idle opacity 40',
            change: (s) => s.copyWith(floatingButtonIdleOpacity: '40'),
            expect: (b) =>
                expect(b.lastTheme?.look.idleAlpha, closeTo(0.4, 0.01)),
          ),
          (
            name: 'background amber',
            change: (s) => s.copyWith(overlayBackground: 'amber'),
            expect: (b) => expect(b.lastTheme?.background, 'amber'),
          ),
          (
            name: 'wave coral',
            change: (s) => s.copyWith(overlayWave: 'coral'),
            expect: (b) => expect(b.lastTheme?.wave, 'coral'),
          ),
        ];
    for (final c in cases) {
      fakeTimeTest('${c.name} is pushed to the button right away', () async {
        final h = await _Harness.create();
        await _settle(20);
        await h.container
            .read(settingsProvider.notifier)
            .updateSettings(c.change);
        await _settle(50);
        c.expect(h.button);
      });
    }
  });

  fakeTimeTest(
    'button drag right before start: start still shows recording',
    () async {
      h.button.drag(640, 300);
      await _settle(50);
      h.button.click();
      await h.until((p) => p == RecordingPhase.recording);
      await _settle(50);
      expect(
        h.button.lastState,
        FloatingButtonVisualState.recording,
        reason: 'button sequence: ${h.button.states}',
      );

      h.overlay.tapBody();
      await h.until(
        (p) => p == RecordingPhase.done || p == RecordingPhase.idle,
      );
      await _settle(120);
      expect(
        h.button.lastState,
        FloatingButtonVisualState.idle,
        reason: 'button sequence: ${h.button.states}',
      );
    },
  );

  for (final start in starts.entries) {
    for (final stop in stops.entries) {
      fakeTimeTest(
        'start: ${start.key} -> stop: ${stop.key} ends with idle button',
        () async {
          await start.value(h);
          await h.until((p) => p == RecordingPhase.recording);
          expect(
            h.button.lastState,
            FloatingButtonVisualState.recording,
            reason: 'button after start: ${h.button.states}',
          );

          await stop.value(h);
          await h.until(
            (p) => p == RecordingPhase.done || p == RecordingPhase.idle,
          );
          // The done state auto-resets the native button to idle after 2 s.
          await _settle(120);

          expect(
            h.button.lastState,
            FloatingButtonVisualState.idle,
            reason: 'button sequence: ${h.button.states}',
          );
        },
      );
    }
  }

  group('render-engine frame heartbeat', () {
    // Stall tests use a short deadline (40 ms) so a stall shows up quickly.
    // Nothing asserts a wall-clock duration: positive events are awaited with
    // [_waitFor], and reboot counts are read at the moment of each push.
    Future<(_Harness, _StallableButtonController)> stallable({
      Duration frameDeadline = const Duration(milliseconds: 40),
    }) async {
      final button = _StallableButtonController();
      final harness = await _Harness.create(
        button: button,
        frameDeadline: frameDeadline,
      );
      return (harness, button);
    }

    fakeTimeTest(
      'a healthy engine acknowledges every push and is never re-booted',
      () async {
        final (h2, b) = await stallable(
          frameDeadline: const Duration(seconds: 2),
        );
        // Let the initial sync land first, then the write and any sync it
        // triggers, and only then take the baseline. Otherwise the first show
        // of the session is counted as a reaction to the write.
        await _waitFor(() => b.states.isNotEmpty, 'the initial sync');
        await h2.container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(floatingButtonRing: false));
        await _settle(60);
        final pushes = b.states.length;
        final geometry = b.geometryCalls;

        await _settle(60);

        expect(
          b.rebootCalls,
          0,
          reason: 'reboot requested from: ${b.lastRebootTrace}',
        );
        expect(b.states.length, pushes, reason: 'no re-push without a stall');
        expect(b.geometryCalls, geometry, reason: 'no re-push without a stall');
      },
    );

    fakeTimeTest(
      'a stalled engine gets the latest look and phase re-pushed',
      () async {
        final (h2, b) = await stallable();
        b.frozen = true;
        await h2.container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(floatingButtonRing: false));
        h2.orchestrator.toggleRecording();

        await _waitFor(
          () =>
              b.states
                  .where((s) => s == FloatingButtonVisualState.recording)
                  .length >=
              2,
          'the stall re-push of the recording state',
        );

        final recordingPushes = [
          for (var i = 0; i < b.states.length; i++)
            if (b.states[i] == FloatingButtonVisualState.recording) i,
        ];
        expect(
          recordingPushes,
          hasLength(greaterThanOrEqualTo(2)),
          reason: 'the phase push and the stall re-push',
        );
        expect(
          b.rebootsAtState[recordingPushes[1]],
          0,
          reason:
              'the first miss only re-pushes; no re-boot before the re-push',
        );
        expect(
          b.lastTheme?.look.ring,
          isFalse,
          reason: 'the re-push carries the latest look, not the stale one',
        );
      },
    );

    fakeTimeTest(
      'a re-push that still gets no frame re-boots the engine once',
      () async {
        final (h2, b) = await stallable();
        b.frozen = true;
        await h2.container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(floatingButtonRing: false));

        await _waitFor(() => b.rebootCalls >= 1, 'the single re-boot');
        expect(b.rebootCalls, 1);
        expect(
          b.frozen,
          isFalse,
          reason: 'the fake re-boot yields a healthy engine',
        );
        await _settle(60);
        expect(
          b.rebootCalls,
          1,
          reason: 'a healed engine is not re-booted again',
        );
      },
    );

    fakeTimeTest(
      'a frame that arrives after the re-push ends the stall without a re-boot',
      () async {
        final (h2, b) = await stallable();
        b.frozen = true;
        // The engine heals on the second push: the re-push itself. The ack
        // then lands before the next deadline, so no re-boot may follow.
        b.healAtPush = 2;
        await h2.container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(floatingButtonRing: false));

        await _waitFor(() => !b.frozen, 'the engine to heal on the re-push');
        await _settle(60);

        expect(b.rebootCalls, 0);
      },
    );

    fakeTimeTest(
      'the session budget bounds the re-boots of a engine that never heals',
      () async {
        final (h2, b) = await stallable();
        b.frozen = true;
        b.rebootHeals = false;
        await h2.container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(floatingButtonRing: false));

        await _waitFor(
          () => b.rebootCalls >= 3,
          'the full re-boot budget to be spent',
        );
        await _settle(60);
        expect(
          b.rebootCalls,
          3,
          reason: 'kRenderRebootBudget re-boots, then stop',
        );
      },
    );

    fakeTimeTest(
      'the next recording restores a spent budget and re-pushes the stop state',
      () async {
        // #977: an engine that stayed blank through the whole budget used to
        // keep the button empty until an app restart.
        final (h2, b) = await stallable();
        b.frozen = true;
        b.rebootHeals = false;
        h2.orchestrator.toggleRecording();
        await h2.until((p) => p == RecordingPhase.recording);
        await _waitFor(
          () => b.rebootCalls >= 3,
          'the full re-boot budget to be spent',
        );
        await _settle(60);
        expect(b.rebootCalls, 3, reason: 'the budget bounds the episode');

        h2.orchestrator.toggleRecording();
        await h2.until(
          (p) => p == RecordingPhase.done || p == RecordingPhase.idle,
        );
        await _settle(60);
        expect(
          b.rebootCalls,
          3,
          reason: 'stopping a recording does not restore the budget',
        );

        final pushesBefore = b.states.length;
        h2.orchestrator.toggleRecording();
        await h2.until((p) => p == RecordingPhase.recording);
        await _waitFor(
          () => b.rebootCalls >= 4,
          'a re-boot from the restored budget',
        );
        expect(
          b.states.skip(pushesBefore),
          contains(FloatingButtonVisualState.recording),
          reason: 'the new recording pushes the stop state to the engine',
        );
        await _waitFor(
          () => b.rebootCalls >= 6,
          'the restored budget to be spent',
        );
        await _settle(60);
        expect(
          b.rebootCalls,
          6,
          reason: 'the restored budget is bounded like the first one',
        );
      },
    );

    fakeTimeTest('hiding the button stops the heartbeat', () async {
      final (h2, b) = await stallable();
      b.frozen = true;
      await h2.container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(floatingButtonRing: false));
      await h2.container
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(showFloatingButton: false));
      final geometry = b.geometryCalls;

      await _settle(60);

      expect(b.rebootCalls, 0, reason: 'a hidden shell is never re-booted');
      expect(b.geometryCalls, geometry, reason: 'no re-push while hidden');
    });
  });
}

/// Lets [ms] milliseconds of fake time pass: the orchestrator's and the
/// button's timers run, nothing waits real time (#1491).
Future<void> _settle(int ms) => _tester.pump(Duration(milliseconds: ms));

/// Awaits [future] while fake time runs in 1 ms steps (at most 5 s), so a
/// call that waits on the orchestrator's own timers can finish.
Future<void> _drive(Future<void> future) async {
  var done = false;
  final result = future.whenComplete(() => done = true);
  for (var i = 0; i < 5000 && !done; i++) {
    await _tester.pump(const Duration(milliseconds: 1));
  }
  await result;
}
