/// Journey — the recording dock's Smart Mode and language choices drive the
/// next dictation.
///
/// Mounts the real [WhisPasteApp] (real shell, dock, settings page, recording
/// orchestrator, Drift database in memory) and drives it by keys only:
///   dock `dock-smart-mode` / `dock-language` → dropdown item in the dock
///   menu. Dictation runs through the hotkey trigger path
///   ([RecordingOrchestrator.toggleRecording]); `dock-dictate` starts and
///   stops a recording from the dock button.
///
/// Fakes only sit on the OS / model boundary: audio capture, STT, the Smart
/// Mode LLM, native paste and clipboard, the attention (notification) service,
/// the tray / hotkey / autostart / floating-window shell services.
///
/// The dock picks the value in place: `dock-smart-mode` and `dock-language`
/// open a dropdown whose items write the same settings as the Settings page.
/// The choice is a settings write (Drift `app_settings`), so it lasts across
/// dictations and is read back on the next start. Nothing in the dock is
/// per-session.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/app.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/config/smart_mode_labels.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/autostart_service.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/path_service.dart'
    show retainedAudioDirOverride, sttDir, sttDirOverride, sttModelPath;
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/smart_mode/smart_mode_engine.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeEngineProvider, smartModeLocalEngineAvailableProvider;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/services/review_prompt_service.dart';
import 'package:whispaste/services/support_prompt_service.dart';
import 'package:whispaste/services/update_service.dart';

import '../test_helpers/nudge_gate_open.dart';
import '../test_helpers/test_deadline.dart';

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
    // Like the real recorder, every recording writes its own WAV file. A file
    // parked by a failed save is therefore not missing for the next dictation.
    File(wavPath).writeAsBytesSync(List.filled(364, 0));
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

/// STT stand-in that records the language code each request carried.
class _FakeStt extends SttServerStateNotifier {
  _FakeStt(this.transcript, this.languages);

  final String transcript;

  /// One entry per transcription, in order: the `language` the pipeline sent.
  final List<String?> languages;

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
    languages.add(language);
    return transcript;
  }

  @override
  Future<void> prewarm() async {}

  // The real idle-unload timer would outlive the test; there is no engine.
  @override
  void notifyRecordingStopped() {}

  @override
  void notifyTranscriptionCompleted() {}
}

/// Smart Mode LLM stand-in. Returns [result] and records every system prompt
/// it was called with, so the preset in use is visible.
class _FakeLlm implements SmartModeEngine {
  _FakeLlm(this.result, this.systemPrompts);

  final String result;

  final List<String> systemPrompts;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    systemPrompts.add(systemPrompt);
    return result;
  }

  @override
  Future<void> cancel() async {}
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

  @override
  Future<bool> requestAttention({
    required AttentionKind kind,
    required String title,
    required String body,
    void Function()? onClick,
    bool showNotification = true,
  }) async => true;

  @override
  Future<void> clearAttention() async {}
}

/// Native paste bridge stand-in. [pastedTexts] holds the clipboard content at
/// the moment the native paste shortcut fires.
class _FakePaste extends DesktopPasteController {
  _FakePaste(this._readClipboard, this.pastedTexts);

  final String? Function() _readClipboard;

  final List<String?> pastedTexts;

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

// No-op shell services: tray, hotkey registration, autostart and the floating
// windows talk to the OS.
class _FakeHotkeyService extends HotkeyService {
  @override
  void build() {}
}

class _FakeTrayService extends TrayService {
  @override
  void build() {}
}

class _FakeAutostartService extends AutostartService {
  @override
  bool build() => false;
}

class _FakeFloatingButtonService extends FloatingButtonService {
  @override
  FloatingButtonController? createController() => null;
}

class _FakeFloatingOverlayService extends FloatingOverlayService {
  @override
  FloatingOverlayController? createController() => null;
}

/// Microphone permission is granted: no permission dialog over the dock.
class _GrantedMic implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => true;
}

class _NoSupportPrompt extends SupportPromptNotifier {
  @override
  Future<void> checkAndMaybePrompt() async {}
}

class _NoReviewPrompt extends ReviewPromptNotifier {
  @override
  Future<void> checkAndMaybePrompt({String? appVersion}) async {}
}

class _FakeUpdateNotifier extends UpdateNotifier {
  @override
  UpdateState build() => const UpdateState();
}

// ---------------------------------------------------------------------------
// Journey harness
// ---------------------------------------------------------------------------

const _rawTranscript = 'ich teste wisp paste heute';
const _cleanedText = 'Ich teste WhisPaste heute.';

/// Starting choice: no Smart Mode, German recognition.
const _startPreset = 'off';
const _startLanguage = 'de';

/// The dock's new choice: Smart Mode cleanup, English recognition.
const _newPreset = 'cleanup';
const _newLanguage = 'en';

late Directory _tmp;

/// Clipboard contents, served through a mocked platform channel.
String? _clipboard;

AppSettings _settings({
  required String smartPreset,
  required String language,
}) => AppSettings(
  stt: SttSettings(model: 'whisper-small', language: language),
  afterTranscriptionSection: const AfterTranscriptionSettings(
    afterTranscription: 'paste',
  ),
  // The post-dictation hints and the data-key explanation are one-time
  // dialogs that would sit over the dock: all are marked as already shown
  // (see [_Session.mount]). The data-key one only opens where the key is not
  // recorded yet, which is the case on Linux.
  onboarding: const OnboardingSettings(
    onboardingCompleted: true,
    smartModeUsageHintShown: true,
    dataKeyExplained: true,
  ),
  smartMode: SmartModeSettings(standardPreset: smartPreset, provider: 'local'),
);

/// One app instance on one database. The database outlives the instance so a
/// test can restart the app against the same settings.
class _Session {
  _Session({required this.tester, required this.db});

  final WidgetTester tester;
  final HistoryDatabase db;

  /// What the fakes observed, across every app instance on [db].
  final List<String?> sttLanguages = [];
  final List<String> llmPrompts = [];
  final List<String?> pastedTexts = [];

  late ProviderContainer container;

  /// Mounts the real app on a fresh container over [db].
  Future<void> mount() async {
    container = ProviderContainer(
      overrides: [
        nudgeGateOpenOverride(),
        historyDatabaseProvider.overrideWith((ref) => db),
        audioServiceProvider.overrideWith(
          () => _FakeAudio(File('${_tmp.path}/dictation.wav').absolute.path),
        ),
        localSttBundleProvider.overrideWith(
          () => _FakeStt(_rawTranscript, sttLanguages),
        ),
        secureKeyStoreProvider.overrideWith((ref) => _FakeSecureKeyStore()),
        desktopPasteControllerProvider.overrideWith(
          (ref) => _FakePaste(() => _clipboard, pastedTexts),
        ),
        modelDownloadProvider.overrideWith(_FakeModelDownload.new),
        smartModeDownloadProvider.overrideWith(_FakeSmartModeDownload.new),
        smartModeEngineProvider.overrideWith(
          (ref) => _FakeLlm(_cleanedText, llmPrompts),
        ),
        smartModeLocalEngineAvailableProvider.overrideWithValue(true),
        systemAttentionServiceProvider.overrideWith(_FakeSystemAttention.new),
        hotkeyServiceProvider.overrideWith(_FakeHotkeyService.new),
        trayServiceProvider.overrideWith(_FakeTrayService.new),
        autostartServiceProvider.overrideWith(_FakeAutostartService.new),
        floatingButtonServiceProvider.overrideWith(
          _FakeFloatingButtonService.new,
        ),
        floatingOverlayServiceProvider.overrideWith(
          _FakeFloatingOverlayService.new,
        ),
        updateProvider.overrideWith(_FakeUpdateNotifier.new),
        // No start-up dialogs: the support and review prompts stay silent.
        micPermissionCheckerProvider.overrideWith((ref) => _GrantedMic()),
        supportPromptProvider.overrideWith(_NoSupportPrompt.new),
        reviewPromptProvider.overrideWith(_NoReviewPrompt.new),
        gpuInfoProvider.overrideWith(
          (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WhisPasteApp(),
      ),
    );
    await tester.runAsync(() => container.read(settingsProvider.future));
    await tester.pumpAndSettle();
  }

  /// Unmounts the app. Drains pending frames so the test binding sees no
  /// leftover timers.
  Future<void> unmount() async {
    // Let the completion toast leave the overlay before the tree goes away.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
    // Closing the Drift stream queries schedules zero-length timers: run them.
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  L10n get l10n =>
      L10n.of(tester.element(find.byKey(const ValueKey('dock-smart-mode'))));

  /// Polls the real async state with real yields, with a separate hang guard
  /// below the per-test limit (test-strategy.md §3b), so a hang names what it
  /// waited for.
  Future<void> waitUntil(bool Function() done, String what) async {
    final deadline = TestDeadline(const Duration(seconds: 8));
    while (!done()) {
      if (deadline.expired) {
        fail('timed out waiting for: $what');
      }
      // One real event-loop turn per round, no fixed wait (#1491).
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      // Advancing the fake clock lets timers of the pipeline fire, such as the
      // no-receipt clipboard restore (500 ms after an unconfirmed paste).
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Settings as persisted in the database, read back through the real
  /// storage mapping.
  Future<AppSettings> persistedSettings() async {
    final values = await tester.runAsync(db.readAppSettings) ?? const {};
    return AppSettings.fromStorageMap(values);
  }

  /// Dock `dock-smart-mode` → dock menu item `dock-menu-smart-mode-[preset]`.
  Future<void> dockSetSmartPreset(String preset) async {
    await tester.tap(find.byKey(const ValueKey('dock-smart-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('dock-menu-smart-mode-$preset')));
    await tester.pumpAndSettle();
    await waitUntil(
      () =>
          container.read(settingsProvider).value?.smartMode.standardPreset ==
          preset,
      'smart mode preset $preset applied',
    );
  }

  /// Dock `dock-language` → dock menu item `dock-menu-language-[code]`.
  Future<void> dockSetLanguage(String code) async {
    await tester.tap(find.byKey(const ValueKey('dock-language')));
    await tester.pumpAndSettle();
    // The language list is long; the item may sit below the menu's fold.
    await tester.ensureVisible(
      find.byKey(ValueKey('dock-menu-language-$code')),
    );
    await tester.tap(find.byKey(ValueKey('dock-menu-language-$code')));
    await tester.pumpAndSettle();
    await waitUntil(
      () => container.read(settingsProvider).value?.sttLanguageCode == code,
      'recognition language $code applied',
    );
  }

  /// Closes the dictation result toast like a user would. Its auto-dismiss
  /// timer is armed inside the real-async zone of [dictateViaHotkey], so it
  /// never fires on the fake clock; left open it covers the dock.
  Future<void> dismissToasts() async {
    final toast = find.byKey(const ValueKey('toast-message'));
    // Toasts stack at one spot: a newer one covers the close button of an
    // older one, so only the topmost (last in tree order) is tappable. The
    // loop is bounded; a close tap that does not clear the toast fails here.
    const maxToasts = 6;
    for (var taps = 0; toast.evaluate().isNotEmpty; taps++) {
      if (taps >= maxToasts) {
        fail(
          'dismissToasts: toast still visible after $maxToasts dismiss taps '
          '(close button missed or not hit-testable)',
        );
      }
      final l10n = L10n.of(tester.element(toast.last));
      final close = find.byTooltip(l10n.actionDismiss);
      expect(close, findsWidgets, reason: 'toast has no close button');
      // A close button outside the window can never be tapped, so fail here
      // with the reason instead of tapping until the loop bound runs out.
      final view = tester.view;
      final windowSize = view.physicalSize / view.devicePixelRatio;
      final center = tester.getCenter(close.last);
      if (center.dy < 0 || center.dy > windowSize.height) {
        fail(
          'dismissToasts: close button of the topmost toast is off-screen at '
          'y=${center.dy} (window height ${windowSize.height}); the toast was '
          'created outside the visible area, not dismissed by the user',
        );
      }
      await tester.tap(close.last);
      await tester.pumpAndSettle();
    }
  }

  /// Hotkey press starts, second press stops and runs the whole pipeline.
  Future<void> dictateViaHotkey() async {
    final orchestrator = container.read(recordingOrchestratorProvider.notifier);
    await tester.runAsync(orchestrator.toggleRecording);
    expect(
      container.read(recordingProvider).phase,
      RecordingPhase.recording,
      reason: 'first hotkey press must start the recording',
    );
    // Stop without awaiting, then alternate real yields and pumps: the
    // pipeline's database writes share Drift's lock with stream queries that
    // run in the test's fake zone, so a stop awaited inside one runAsync
    // stalls until the real 5 s save budget expires.
    unawaited(orchestrator.toggleRecording());
    await waitUntil(
      () => container.read(recordingProvider).phase == RecordingPhase.done,
      'the dictation pipeline to finish',
    );
    await tester.pumpAndSettle();
    expect(container.read(recordingProvider).phase, RecordingPhase.done);
    await dismissToasts();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A tap that misses its target fails at once. A missed toast close tap
  // once spun the dismiss loop for 28 min and logged 3.7 GB of warnings.
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('wp40-dock-journey-');
    sttDirOverride = _tmp.path;
    retainedAudioDirOverride = '${_tmp.path}/retained-audio';
    // Preflight only checks that the model file exists; STT is faked.
    Directory(sttDir()).createSync(recursive: true);
    final modelPath = sttModelPath('whisper-small');
    if (modelPath != null && !File(modelPath).existsSync()) {
      File(modelPath).writeAsStringSync('fake-model');
    }
    File('${_tmp.path}/dictation.wav').writeAsBytesSync(List.filled(364, 0));
    _clipboard = null;
    // The app shell talks to the window manager on start; there is no window.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method.startsWith('is') ? false : null,
        );
    // Native side panel and recorder plugins: nothing to talk to in a test.
    for (final channel in [
      'com.whispaste.side_panel',
      'com.llfbandit.record/messages',
      'dev.leanflutter.plugins/hotkey_manager_event',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel(channel),
            (call) async => null,
          );
    }
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    for (final channel in [
      'com.whispaste.side_panel',
      'com.llfbandit.record/messages',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), null);
    }
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  // One dock menu per test: the first test of a run also pays the JIT warm-up
  // of the app (about 4 s) and the language menu builds all its rows at once,
  // so a test with both menus and a dictation came close to the 10 s limit on
  // a loaded host. The steps chain through the database instead: dock choice
  // → stored settings (first two tests) → start state and next dictation
  // (third test).
  testWidgets(
    'dock Smart Mode choice is stored and applies to the next dictation and '
    'to the one after it',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final s = _Session(
        tester: tester,
        db: HistoryDatabase.forTesting(NativeDatabase.memory()),
      );
      await tester.runAsync(
        () => s.db.writeAppSettings(
          _settings(
            smartPreset: _startPreset,
            language: _startLanguage,
          ).toStorageMap(),
        ),
      );
      await s.mount();

      // Starting state, as the dock shows it.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-smart-mode')),
          matching: find.text(smartModePresetDisplayName(_startPreset, s.l10n)),
        ),
        findsOneWidget,
      );
      // Dock menu: Smart Mode off → cleanup.
      await s.dockSetSmartPreset(_newPreset);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-smart-mode')),
          matching: find.text(smartModePresetDisplayName(_newPreset, s.l10n)),
        ),
        findsOneWidget,
      );
      expect(
        (await s.persistedSettings()).smartMode.standardPreset,
        _newPreset,
      );

      // Next dictation (hotkey path) uses the new choice.
      await s.dictateViaHotkey();
      expect(s.sttLanguages, [_startLanguage]);
      expect(s.llmPrompts, [smartModeSystemPromptFor(SmartModePreset.cleanup)]);
      expect(s.pastedTexts, [_cleanedText]);

      // The choice is not one-shot: the dictation after it still uses it.
      await s.dictateViaHotkey();
      expect(s.sttLanguages, [_startLanguage, _startLanguage]);
      expect(s.llmPrompts, hasLength(2));
      expect(s.pastedTexts, [_cleanedText, _cleanedText]);

      await s.unmount();
    },
  );

  testWidgets('dock language choice is stored and shown in the dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = _Session(
      tester: tester,
      db: HistoryDatabase.forTesting(NativeDatabase.memory()),
    );
    await tester.runAsync(
      () => s.db.writeAppSettings(
        _settings(
          smartPreset: _startPreset,
          language: _startLanguage,
        ).toStorageMap(),
      ),
    );
    await s.mount();

    // Dock menu: language de → en.
    await s.dockSetLanguage(_newLanguage);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dock-language')),
        matching: find.text('English'),
      ),
      findsOneWidget,
    );
    expect((await s.persistedSettings()).stt.language, _newLanguage);

    await s.unmount();
  });

  testWidgets(
    'stored dock choices are read back on start; reverting Smart Mode in the '
    'dock brings the old choice back for the next dictation',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final s = _Session(
        tester: tester,
        db: HistoryDatabase.forTesting(NativeDatabase.memory()),
      );
      // Starts where the first two tests end: cleanup and en are stored.
      await tester.runAsync(
        () => s.db.writeAppSettings(
          _settings(
            smartPreset: _newPreset,
            language: _newLanguage,
          ).toStorageMap(),
        ),
      );
      await s.mount();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-smart-mode')),
          matching: find.text(smartModePresetDisplayName(_newPreset, s.l10n)),
        ),
        findsOneWidget,
        reason: 'the Smart Mode choice must be read back on start',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-language')),
          matching: find.text('English'),
        ),
        findsOneWidget,
        reason: 'the language choice must be read back on start',
      );

      // Revert in the dock: back to off.
      await s.dockSetSmartPreset(_startPreset);

      // The dictation after the revert: stored language, no LLM call, raw
      // text pasted.
      await s.dictateViaHotkey();
      expect(s.sttLanguages, [_newLanguage]);
      expect(
        s.llmPrompts,
        isEmpty,
        reason: 'preset off must not call the Smart Mode LLM',
      );
      expect(s.pastedTexts, [_rawTranscript]);

      await s.unmount();
    },
  );

  testWidgets(
    'dock Dictate button starts and stops a dictation; the dock status '
    'follows the recording',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final s = _Session(
        tester: tester,
        db: HistoryDatabase.forTesting(NativeDatabase.memory()),
      );
      await tester.runAsync(
        () => s.db.writeAppSettings(
          _settings(
            smartPreset: _startPreset,
            language: _startLanguage,
          ).toStorageMap(),
        ),
      );
      await s.mount();
      final l10n = s.l10n;

      // Idle: the button offers Dictate, the dock reports the local engine.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-dictate')),
          matching: find.text(l10n.dockDictate),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-status')),
          matching: find.text('${l10n.statusReady} · ${l10n.statusLocal}'),
        ),
        findsOneWidget,
      );

      // First tap starts the recording from the dock.
      await tester.tap(find.byKey(const ValueKey('dock-dictate')));
      await tester.pump();
      await s.waitUntil(
        () =>
            s.container.read(recordingProvider).phase ==
            RecordingPhase.recording,
        'dock button started the recording',
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-dictate')),
          matching: find.text(l10n.dockStopDictation),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-status')),
          matching: find.text(l10n.statusBarRecording),
        ),
        findsOneWidget,
      );

      // Second tap stops it; the pipeline finishes on real async I/O, so the
      // wait polls with real yields.
      await tester.tap(find.byKey(const ValueKey('dock-dictate')));
      await tester.pump();
      await s.waitUntil(
        () => s.container.read(recordingProvider).phase == RecordingPhase.done,
        'dictation from the dock button finished',
      );
      await tester.pump();

      expect(s.sttLanguages, [_startLanguage]);
      expect(s.llmPrompts, isEmpty, reason: 'preset off: no Smart Mode call');
      expect(s.pastedTexts, [_rawTranscript]);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-dictate')),
          matching: find.text(l10n.dockDictate),
        ),
        findsOneWidget,
      );

      await s.unmount();
    },
  );
}
