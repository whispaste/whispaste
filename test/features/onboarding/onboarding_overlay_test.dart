/// Widget tests for the [OnboardingOverlay] shell.
///
/// The flow is eight steps on every platform (v4). Every test that
/// walks pages therefore pins [debugDefaultTargetPlatformOverride] explicitly
/// and derives the expected count from [buildOnboardingStepIds]; without that
/// the suite would silently depend on the host it runs on and the Linux path
/// would never actually be exercised. Covered here:
///  - the step counter reflects the eight-step total, and the Access page mounts
///    [AutoPasteStep] on every desktop platform;
///  - the shell-owned navigation row carries exactly two actions (Back +
///    Next) and no skip affordance, and the disabled first-page Back button
///    is visibly disabled;
///  - overlay dispose stops both shared pollers (paste capability + mic
///    permission) — no zombie timer survives a window close;
///  - the OS microphone request is never fired by paging: it waits for a user
///    tap on the access step (decision 2a);
///
/// Fit, overflow, text scale and RTL mirroring are design and are judged by
/// visual review, not here (test strategy 2026-10-30).
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show OnboardingSettings;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/core/onboarding/onboarding_revision.dart';
import 'package:whispaste/core/onboarding/onboarding_surface.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart'
    show kOnboardingFlowVersion, kV5Access, kV5Privacy, kV5Try;
import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/onboarding_select.dart';
import 'package:whispaste/services/speech_recommendation.dart'
    show systemLanguageCodesProvider;
import 'package:whispaste/services/stt/backend_utilization_notifier.dart'
    show processorCountProvider;
import 'package:whispaste/features/onboarding/mic_probe.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/features/onboarding/steps/access_mic_step.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart'
    show PrivacyStep;
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart'
    show kWelcomeModelSelectKey;
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart'
    show TestRecordingStep;
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/services/free_disk_space.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/features/onboarding/steps/permissions_step.dart';
import 'package:whispaste/services/linux_desktop_shortcut.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/audio_service.dart'
    show audioInputDevicesProvider;
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/fake_mic_recorder.dart';
import '../../fixtures/test_helpers.dart';
import 'onboarding_test_doubles.dart'
    show onboardingBack, onboardingPage, tapOnboardingNext;

import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;

late L10n l10n;

/// Total number of steps for [platform] — read from the production sequence
/// builder, never hard-coded: the count is platform-dependent now, and a
/// literal here would go stale the next time the flow changes.
int _totalSteps(TargetPlatform platform) => buildOnboardingStepIds().length;

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  /// Read-back for tests that need to assert what the overlay persisted
  /// (e.g. that the legacy-flow migration did or didn't stamp a new value).
  AppSettings get current => _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Minimal recording fake — counts [stopPolling] calls so the overlay
/// disposal test can verify the defensive cleanup fires.
class _RecordingPasteCapabilityNotifier extends PasteCapabilityNotifier {
  int stopPollingCalls = 0;

  @override
  PasteCapabilityState build() => const PasteCapabilityState();

  @override
  void stopPolling() {
    stopPollingCalls++;
  }
}

/// Same shape for the microphone permission poller — additionally pins the
/// status and records [request] calls so the leave-page-1 hook is provable
/// without any platform involvement.
class _RecordingMicPermissionNotifier extends MicPermissionNotifier {
  _RecordingMicPermissionNotifier([
    this.initialStatus = MicPermissionStatus.unknown,
  ]);

  final MicPermissionStatus initialStatus;
  int stopPollingCalls = 0;
  int requestCalls = 0;

  @override
  MicPermissionState build() => MicPermissionState(status: initialStatus);

  @override
  Future<bool> check() async => initialStatus == MicPermissionStatus.granted;

  @override
  Future<bool> request() async {
    requestCalls++;
    return false;
  }

  @override
  void stopPolling() {
    stopPollingCalls++;
  }
}

/// Inert platform truth for tests that run the *real* notifier — the mic
/// chip on the Access page checks on mount, and leaving that page may request;
/// neither call may ever reach the real audio plugin in a widget test.
class _FakeMicPermissionChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

/// Pins whether speech has been heard on the microphone page. Most tests walk
/// past that page and need "Weiter" to work, so the default is "heard".
class _FixedMicSpeech extends OnboardingMicSpeechNotifier {
  _FixedMicSpeech(this._heard);

  final bool _heard;

  @override
  bool build() => _heard;
}

class _FakeWaylandBinding extends WaylandHotkeyBindingController {
  _FakeWaylandBinding(this._value);

  final WaylandHotkeyBinding _value;

  @override
  WaylandHotkeyBinding build() => _value;
}

/// Pins the hotkey registration status for the conflict-branch fit test.
class _FakeHotkeyStatusController extends HotkeyRegistrationStatusController {
  _FakeHotkeyStatusController(this._initial);

  final HotkeyRegistrationStatus _initial;

  @override
  HotkeyRegistrationStatus build() => _initial;
}

class _FakeRegistrar implements HotKeyRegistrar {
  const _FakeRegistrar({this.supportsKeyUp = true});

  @override
  final bool supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}
}

/// [HotkeyService] whose `build()` never runs the real startup registration —
/// that would asynchronously overwrite the status the conflict test seeds
/// (same fake as `trigger_step_test.dart`).
class _NoopHotkeyService extends HotkeyService {
  @override
  void build() {}
}

HotkeyService _noopHotkeyService({bool supportsKeyUp = true}) {
  final svc = _NoopHotkeyService();
  svc.injectRegistrar(_FakeRegistrar(supportsKeyUp: supportsKeyUp));
  svc.injectMonitor(NoopKeyboardUpMonitor());
  return svc;
}

/// Both download providers pinned to a failed download, so whichever engine
/// the locale's recommendation selects renders the error branch.
class _StaticWhisperDownload extends ModelDownloadNotifier {
  _StaticWhisperDownload(this._started, this._initial);

  final ModelDownloadState _initial;

  /// Records the downloads the start page's consent asked for. Never fetches.
  final List<String> _started;

  @override
  ModelDownloadState build() => _initial;

  @override
  Future<void> downloadModel(String modelId) async => _started.add(modelId);
}

/// A whisper download whose state the test drives through [script], so a
/// running download can be aborted after the page was already passed
/// (UIA-MDL-GATE).
class _ScriptedWhisperDownload extends ModelDownloadNotifier {
  _ScriptedWhisperDownload(this._script);

  final ValueNotifier<ModelDownloadState> _script;

  @override
  ModelDownloadState build() {
    void onChange() => state = _script.value;
    _script.addListener(onChange);
    ref.onDispose(() => _script.removeListener(onChange));
    return _script.value;
  }
}

class _StaticParakeetDownload extends ParakeetDownloadNotifier {
  _StaticParakeetDownload(this._started, this._initial);

  final ParakeetDownloadState _initial;

  /// Records the bundle downloads the start page's consent asked for.
  final List<String> _started;

  @override
  ParakeetDownloadState build() => _initial;

  @override
  Future<void> downloadBundle() async => _started.add('parakeet');
}

/// Taps Next until the phase counter shows the page of [id]. Pages are
/// addressed by ID here, never by a number of clicks.
Future<void> goToOnboardingPage(
  WidgetTester tester,
  OnboardingStepId id,
) async {
  final sequence = buildOnboardingStepIds();
  final page = sequence.indexOf(id) + 1;
  expect(page, greaterThan(0), reason: '$id is not a page of the sequence');
  final target = onboardingPage(id);
  for (var tap = 0; tap < sequence.length; tap++) {
    if (target.evaluate().isNotEmpty) return;
    await tapOnboardingNext(tester);
  }
  expect(target, findsOneWidget, reason: 'page $page not reached');
}

/// Opens the model sub-view from the closing page. Used where a test needs
/// the model page and no speech model is installed: the closing CTA then
/// reads "Modell laden" and opens it. The start page's link exists on a
/// revision run only; a first run picks the model in the start page select.
Future<void> openModelSubViewFromClosingPage(WidgetTester tester) async {
  await goToOnboardingPage(tester, OnboardingStepId.privacy);
  await tapOnboardingNext(tester);
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  PasteCapabilityNotifier? paste,
  _RecordingMicPermissionNotifier? mic,
  _FakeSettingsNotifier? settings,
  Size size = const Size(1280, 980),
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  HotkeyRegistrationStatus? hotkeyStatus,
  // Forces the GPU verdict; the model page shows its CPU-fallback notice only
  // for a machine without a GPU, and the test host's probe is not one.
  hw.GpuInfo? gpu,
  bool downloadFailed = false,
  // Whether a Whisper model counts as installed. Most tests walk past the
  // model page and need Next to work, so the default is "installed".
  bool modelInstalled = true,
  // The practice counts as done unless a test is about the try page itself.
  bool practiceDone = true,
  ModelDownloadState? whisperDownload,
  ValueNotifier<ModelDownloadState>? whisperScript,
  ParakeetDownloadState? parakeetDownload,
  // Downloads the start page's consent starts, by model id ('parakeet' for
  // the bundle). Recorded, never fetched.
  List<String>? startedDownloads,
  // `false` for states that animate forever (the mic chip's `requesting`
  // spinner) — pumpAndSettle would time out on those.
  bool settle = true,
  bool manualReview = false,
  bool revisionRun = false,
  OnboardingRevisionRegistry? revisionRegistry,
  DesktopShortcutFallback? desktopShortcut,
  bool supportsKeyUp = true,
  WaylandHotkeyBinding? waylandBinding,
  bool micHeard = true,
}) async {
  const downloadError = 'Verbindung unterbrochen (HTTP 503)';
  final started = startedDownloads ?? <String>[];
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler,
          disableAnimations: true,
        ),
        child: OnboardingOverlay(
          manualReview: manualReview,
          revisionRun: revisionRun,
        ),
      ),
      size: size,
      locale: locale,
      gpuInfo: gpu,
      overrides: [
        // The start page recommends from system languages and CPU too; pin
        // both so the host the suite runs on never decides it.
        systemLanguageCodesProvider.overrideWithValue(const ['en']),
        processorCountProvider.overrideWithValue(8),
        onboardingTestRecordingSucceededProvider.overrideWith(
          () => _PracticeDone(practiceDone),
        ),
        settingsProvider.overrideWith(
          () => settings ?? _FakeSettingsNotifier(),
        ),
        // The model page's hardware detection awaits the disk probe; the real
        // one never completes under testWidgets, so the cards and the GPU
        // notice would never be built.
        freeDiskSpaceProbeProvider.overrideWithValue(
          (_) async => 500 * 1024 * 1024 * 1024,
        ),
        if (revisionRegistry != null)
          onboardingRevisionRegistryProvider.overrideWithValue(
            revisionRegistry,
          ),
        micPermissionCheckerProvider.overrideWithValue(
          _FakeMicPermissionChecker(),
        ),
        // The microphone page's level probe never opens a real recorder here.
        onboardingMicProbeProvider.overrideWithValue(
          OnboardingMicProbe(recorder: FakeMicRecorder(hasPermission: false)),
        ),
        audioInputDevicesProvider.overrideWith(
          (ref) async => const ['Default'],
        ),
        onboardingMicSpeechHeardProvider.overrideWith(
          () => _FixedMicSpeech(micHeard),
        ),
        if (desktopShortcut != null) ...[
          desktopShortcutFallbackProvider.overrideWith(
            (ref) async => desktopShortcut,
          ),
          gnomeToggleShortcutInstalledProvider.overrideWith(
            (ref) async => false,
          ),
          manualToggleCommandProvider.overrideWithValue(
            "'/opt/WhisPaste/whispaste' --toggle",
          ),
        ],
        if (paste != null)
          pasteCapabilityNotifierProvider.overrideWith(() => paste),
        if (mic != null) micPermissionNotifierProvider.overrideWith(() => mic),
        if (hotkeyStatus != null)
          hotkeyRegistrationStatusProvider.overrideWith(
            () => _FakeHotkeyStatusController(hotkeyStatus),
          ),
        // Without key-up the real service would still report it on macOS
        // (its monitor), so the override must apply whenever it is turned off.
        // The probe asks the native host; a fake keeps its timeout timer out of
        // the test clock.
        hotkeySecureInputProbeProvider.overrideWithValue(() async => false),
        if (hotkeyStatus != null || !supportsKeyUp)
          hotkeyServiceProvider.overrideWith(
            () => _noopHotkeyService(supportsKeyUp: supportsKeyUp),
          ),
        if (waylandBinding != null)
          waylandHotkeyBindingProvider.overrideWith(
            () => _FakeWaylandBinding(waylandBinding),
          ),
        // Always statically overridden — never the real notifier. Its
        // initial disk scan hits real `Directory`/`File` calls, which
        // `ModelStep._detectHardware()` now awaits before its first
        // `setState` (see `awaitInitialScan()`); those real calls never
        // resolve under `testWidgets`, hanging every test that reaches
        // ModelStep until `pumpAndSettle` times out.
        modelDownloadProvider.overrideWith(
          () => whisperScript != null
              ? _ScriptedWhisperDownload(whisperScript)
              : _StaticWhisperDownload(
                  started,
                  whisperDownload ??
                      (downloadFailed
                          ? const ModelDownloadState(
                              phase: DownloadPhase.error,
                              errorMessage: downloadError,
                            )
                          : ModelDownloadState(
                              downloadedModels: modelInstalled
                                  ? const {'whisper-medium'}
                                  : const {},
                            )),
                ),
        ),
        parakeetDownloadProvider.overrideWith(
          () => _StaticParakeetDownload(
            started,
            parakeetDownload ??
                (downloadFailed
                    ? const ParakeetDownloadState(
                        phase: ParakeetDownloadPhase.error,
                        errorMessage: downloadError,
                      )
                    : const ParakeetDownloadState()),
          ),
        ),
      ],
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// The practice step holds "Next" until a dictation succeeds; these pages are
/// not about the practice step, so it counts as done.
class _PracticeDone extends OnboardingTestRecordingSucceededNotifier {
  _PracticeDone([this._done = true]);

  final bool _done;

  @override
  bool build() => _done;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    // Load the real bundled UI font (Inter) instead of the Ahem test font.
    // The fixed-window fit assertions below measure whether a page fits
    // 1100×800 without scrolling — with Ahem every glyph is a full em
    // square, roughly doubling text width vs. Inter, which makes captions
    // wrap to lines that never occur in the real app. Real metrics keep the
    // gate meaningful.
    await loadAppFonts();
  });

  group('start page consent (Onboarding v6, V02)', () {
    testWidgets(
      'Einrichten starts the recommended download once and moves on; nothing '
      'downloads before that',
      (tester) async {
        final started = <String>[];
        await _pumpOverlay(
          tester,
          modelInstalled: false,
          startedDownloads: started,
        );
        expect(find.byKey(kOnboardingNextButtonKey), findsOneWidget);
        expect(started, isEmpty, reason: 'no download without the consent');

        await tapOnboardingNext(tester);

        expect(started, hasLength(1));
        expect(onboardingPage(buildOnboardingStepIds()[1]), findsOneWidget);
      },
    );

    testWidgets('another model picked in the start page select starts nothing; '
        'Einrichten then downloads exactly that choice once', (tester) async {
      // The list opens below the line; on the default 800×600 surface its
      // rows lie outside the hit-test area.
      tester.view
        ..physicalSize = kOnboardingWindowSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final started = <String>[];
      await _pumpOverlay(
        tester,
        modelInstalled: false,
        startedDownloads: started,
        size: kOnboardingWindowSize,
      );
      final select = tester.widget<OnboardingSelect<String>>(
        find.byKey(kWelcomeModelSelectKey),
      );
      final other = select.options.firstWhere(
        (o) => o.enabled && o.value != select.selected,
      );

      final semantics = tester.ensureSemantics();
      await tester.tap(find.bySemanticsIdentifier('onboarding-welcome-model'));
      await tester.pumpAndSettle();
      final option = find.bySemanticsIdentifier(
        'onboarding-welcome-model-option-${other.id}',
      );
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
      semantics.dispose();
      expect(started, isEmpty, reason: 'choosing is no consent to download');

      await tapOnboardingNext(tester);
      expect(started, [other.value]);
    });
  });

  // ── Step sequence: eight steps on every desktop platform ────────────────

  group('OnboardingOverlay — focus moves to the page heading (V09)', () {
    // The header of every page takes keyboard focus when the page mounts, so
    // a screen reader announces the title and Enter acts on the page.
    void expectHeadingFocused({Finder? on}) {
      final node = FocusManager.instance.primaryFocus;
      expect(
        node?.debugLabel,
        'onboardingHeading',
        reason: 'primary focus is on ${node?.debugLabel ?? 'nothing'}',
      );
      if (on != null) {
        expect(
          find.descendant(
            of: on,
            matching: find.byWidget(node!.context!.widget),
          ),
          findsOneWidget,
          reason: 'the focused heading is not on the expected page',
        );
      }
    }

    testWidgets('the heading has focus when the flow opens', (tester) async {
      await _pumpOverlay(tester, mic: _RecordingMicPermissionNotifier());
      await tester.pump();

      expectHeadingFocused();
    });

    testWidgets('focus follows every page change, forwards and back', (
      tester,
    ) async {
      await _pumpOverlay(tester, mic: _RecordingMicPermissionNotifier());
      await tester.pump();

      final second = onboardingPage(buildOnboardingStepIds()[1]);
      await tapOnboardingNext(tester);
      expectHeadingFocused(on: second);

      await tester.tap(onboardingBack);
      await tester.pumpAndSettle();
      expectHeadingFocused();

      await tapOnboardingNext(tester);
      expectHeadingFocused(on: second);
    });

    testWidgets('on the Hotkey page the autofocused recorder keeps the keys; '
        'the next page takes focus back to its heading', (tester) async {
      tester.view
        ..physicalSize = kOnboardingWindowSize
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final settings = _FakeSettingsNotifier();
      await _pumpOverlay(
        tester,
        settings: settings,
        size: kOnboardingWindowSize,
        // A conflict opens the recorder inline on the page.
        hotkeyStatus: HotkeyRegistrationStatus.conflict,
      );
      await goToOnboardingPage(tester, OnboardingStepId.hotkey);
      expect(find.byKey(kTriggerStepInlineRecorderKey), findsOneWidget);
      // The heading gets no focus, so the page is announced instead.
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains(contains(l10n.onboardingTriggerTitle)),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final save = find.bySemanticsIdentifier('hotkey-recorder-save');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(settings.current.hotkeyKey, 'F5');
      // The app registers the saved combination; here it simply took.
      ProviderScope.containerOf(tester.element(find.byType(OnboardingOverlay)))
          .read(hotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.success);
      await tester.pumpAndSettle();

      final sequence = buildOnboardingStepIds();
      await tapOnboardingNext(tester);
      expectHeadingFocused(
        on: onboardingPage(
          sequence[sequence.indexOf(OnboardingStepId.hotkey) + 1],
        ),
      );
      semantics.dispose();
    });
  });

  // ── Supported languages + RTL mirroring ─────────────────────────────────
  //
  // The language list is read from L10n.supportedLocales — never hard-coded
  // — so a newly added locale is automatically covered.

  // ── Minimum window size + enlarged system text ──────────────────────────

  // ── Microphone request timing (decision 2a) ─────────────────────────────
  //
  // PRD: the OS permission dialog fires when *leaving* page 1 (never on
  // appear), and only when the user hasn't triggered it themselves. `unknown`
  // is the proof of that — request() has never run this process, so the
  // one-time dialog budget is guaranteed unspent.

  group('OnboardingOverlay — mic request waits for the access step', () {
    testWidgets(
      'status unknown: tapping Next on page 1 fires no request — the OS '
      'dialog waits for the access step (decision 2a)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final mic = _RecordingMicPermissionNotifier();
          await _pumpOverlay(tester, mic: mic);

          await tapOnboardingNext(tester);

          expect(onboardingPage(buildOnboardingStepIds()[1]), findsOneWidget);
          expect(mic.requestCalls, 0);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    for (final status in [
      MicPermissionStatus.requesting,
      MicPermissionStatus.granted,
      MicPermissionStatus.denied,
    ]) {
      testWidgets(
        'status $status: leaving page 1 fires nothing — something already '
        'resolved the permission (the startup gate, or the chip on the last '
        'page during an earlier pass), so a second call is pointless',
        (tester) async {
          final mic = _RecordingMicPermissionNotifier(status);
          await _pumpOverlay(tester, mic: mic);

          await tapOnboardingNext(tester);

          expect(mic.requestCalls, 0);
        },
      );
    }

    testWidgets(
      'the Mic page holds Weiter until speech is heard (S3); Überspringen '
      'moves on without speech',
      (tester) async {
        await _pumpOverlay(tester, micHeard: false);
        await goToOnboardingPage(tester, OnboardingStepId.mic);

        final next = find.byKey(kOnboardingNextButtonKey);
        expect(tester.widget<WpHeroButton>(next).onPressed, isNull);
        expect(
          find.bySemanticsIdentifier('onboarding-mic-skip'),
          findsOneWidget,
        );

        await tester.tap(find.bySemanticsIdentifier('onboarding-mic-skip'));
        await tester.pumpAndSettle();

        final sequence = buildOnboardingStepIds();
        expect(
          onboardingPage(sequence[sequence.indexOf(OnboardingStepId.mic) + 1]),
          findsOneWidget,
        );
      },
    );

    testWidgets('Enter on a focused button activates that button, not Weiter', (
      tester,
    ) async {
      await _pumpOverlay(tester, micHeard: false);
      await goToOnboardingPage(tester, OnboardingStepId.mic);

      final skip = find.descendant(
        of: find.byKey(const ValueKey('onboarding-mic-skip')),
        matching: find.byType(TextButton),
      );
      tester.widget<TextButton>(skip).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final sequence = buildOnboardingStepIds();
      expect(
        onboardingPage(sequence[sequence.indexOf(OnboardingStepId.mic) + 1]),
        findsOneWidget,
      );
    });

    testWidgets('leaving pages 1 and 2 never fires request()', (tester) async {
      final mic = _RecordingMicPermissionNotifier();
      await _pumpOverlay(tester, mic: mic);

      await goToOnboardingPage(tester, OnboardingStepId.hotkey);

      expect(mic.requestCalls, 0, reason: 'only a user tap may request');
    });
  });

  // ── Fixed onboarding window size — no page may scroll ───────────────────
  //
  // The onboarding window is pinned to 1100×800 (kOnboardingWindowSize). At
  // the system text scale that leaves a 579-px scroll viewport and a 539-px
  // content area for the page itself (the viewport minus the scroll view's
  // 2 × `lg` vertical padding). Neither number is constant across text
  // scales, because the footer grows with the text:
  //
  //   viewport   579 px @ 1.0    573 px @ 1.15    567 px @ 1.3
  //
  // and the page's own area is 40 px less in each case. Every page has to fit
  // inside it: there is no way for the user to make the window bigger, so a
  // page that scrolls is a page whose bottom half is easy to miss entirely.
  //
  // It was a flat 551 px until the footer stack put the dots and the "step X
  // of Y" counter on one line and `_kOnboardingBottomGap` went `xxl` → `lg`.
  // That is where the +28 px came from, and it is why every number below is
  // larger than the set this table used to carry while the pages themselves
  // grew *less* crowded, not more — the viewport moved under them.
  //
  // Measured with real Inter metrics (see setUpAll — with the square-glyph
  // test font the numbers are meaningless), macOS unless noted, the dictation
  // language seeded to the UI locale, and the GPU-fallback notice asserted
  // present on the model page, i.e. the worst case. Natural content height
  // against the viewport, German / English / Hebrew.
  //
  // These are *natural* heights: what the page's blocks come to with every
  // gap at its minimum. The leftover height trails below the body rather than
  // being split around it ([OnboardingPageBody] is unconditionally top-
  // aligned now; it used to be centred, with sparse pages opting out per call
  // site), so a page shorter than the viewport still occupies the full
  // viewport whatever these numbers say — they are still the ones that decide
  // whether a page fits at all, and the ones to re-measure before adding to a
  // page.
  //
  // ── Re-measured wholesale on 2026-08-10 (ticket 20, phase 6) ────────────
  //
  // One harness run, one day, the whole set — the rule the 2026-08-09
  // re-measurement wrote down, and the reason the density pass left this
  // table standing with a stale marker rather than patching the rows it
  // happened to touch. Everything moved: the footer lost a line (above), the
  // body is top-aligned, the reading measure dropped to 640 px, and pages 1,
  // 2, 4, 5 and 6 rebuilt their rows or their content. Treat the numbers as a
  // set; when you re-measure, re-measure all of them.
  //
  // Measured before the seven-step v3 flow (the old flow still had Privacy
  // and Appearance pages), so the page numbers in this block are that
  // flow's. Re-measure before trusting them.
  //
  // Scale 1.0, macOS, against the 579-px viewport:
  //
  //   page 1  Welcome       517 / 517 / 517
  //   page 2  Privacy       307 / 307 / 307
  //   page 3  Model         434 / 413 / 438
  //   page 4  Hotkey        278 / 278 / 278   (still the sparsest page in the
  //                                            flow: two setting rows, and
  //                                            the ~60 % of trailing empty
  //                                            space under them is the
  //                                            documented correct outcome,
  //                                            see OnboardingPageBody)
  //   page 5  Appearance    390 / 390 / 390   (theme tiles + autostart row)
  //   page 6  Auto-Paste    301 / 301 / 301   (macOS/Windows only; one status
  //                                            card + why + skip, the shape
  //                                            every phase of the page now
  //                                            shares)
  //   page 7  Try & Go      483 / 467 / 467   (the flow's tallest nominal
  //                                            page, and the one the mic-
  //                                            bypass guard below watches)
  //
  // Linux runs the same pages 1–5 — identical page for page to the numbers
  // above — and ends on Try & Go as page 6, measured 443 / 427 / 427 there.
  //
  // ── The binding cases (scale 1.3, 567-px viewport) ─────────────────────
  //
  // 1.0 is not where this flow is decided any more. These are the rows a
  // change breaks first, and the only 1.3 numbers worth carrying here:
  //
  //   page 1  Welcome,  de        567 of 567    0 px — an exact fit
  //   page 7  Try & Go, de        563 of 567    4 px
  //   page 3  Model,    he        550 of 567   17 px
  //   page 1  Welcome,  en / he   543 of 567   24 px
  //   page 7  Try & Go, en / he   536 of 567   31 px
  //
  // Everything else keeps ≥ 46 px at 1.3. Page 1 in German is the tightest
  // case in the flow and it is a deliberate landing, not an accident: the one
  // post that separates German from the other two is beat 1's caption
  // wrapping to a third line. Anyone who needs slack there has 24 px in the
  // other locales to spend first.
  //
  // ── The three branch cases ─────────────────────────────────────────────
  //
  // German / Hebrew, the two locales the tests cover. This is the one part of
  // the table where the higher scales are not derivable from the 1.0 row,
  // because two of the three branches stop fitting:
  //
  //   page 4, confirmed hotkey conflict (warn box + full inline recorder).
  //   The branch the page split was for — on the merged Model & Hotkey page
  //   it came to 914 px against a 551-px viewport. It pays for the fit three
  //   ways: the heading drops its subtitle while a conflict is up, the gap
  //   under that heading is `sm` rather than [kOnboardingHeaderGap] (the
  //   flow's one deliberate deviation, declared at the call site), and the
  //   warn box is vertically tighter than it is wide.
  //     1.0    579 / 562     fits (German on exactly 0 px of slack)
  //     1.15   585 / 585     12 px past the fold, RenderFlex overflow in both
  //     1.3    636 / 615     69 / 48 px past it, overflow in Hebrew (German
  //                          scrolls instead of throwing at that scale)
  //   page 3, failed model download (error banner + retry button)
  //     1.0    491 / 495     fits
  //     1.15   542 / 527     fits
  //     1.3    576 / 605     9 / 38 px past the fold
  //   page 6, Auto-Paste troubleshoot (missing + sent-to-OS-grant-flow + poll
  //   timed out, Repair tapped and resolved to "nothing cleared" — skip +
  //   repair + the result banner's own restart button, the tallest state the
  //   page has)
  //     1.0    504 / 504     fits
  //     1.15   521 / 521     fits
  //     1.3    563 / 541     fits
  //
  // ⚠ OPEN FINDING — reported, not fixed (ticket 20, phase 6). The conflict
  // and download branches run past the fold above scale 1.0. No test is red:
  // both are covered at 1.0 only, because the fold matrix walks the nominal
  // flow and never enters either branch, and the troubleshoot branch is the
  // one that was extended to all three scales (and fixed there). What can be
  // said precisely, and what cannot:
  //
  //   * At 1.0 the conflict branch went from 17 px of slack (534 px against
  //     the old 551-px viewport) to 0 px in German. That tightening is this
  //     ticket's doing — the setting rows on that page grew, and the density
  //     pass records paying 3 px back in Hebrew for exactly that reason.
  //   * At 1.15 and 1.3 the origin is UNDETERMINED. No commit ever measured
  //     either branch above 1.0, so there is no baseline to have regressed
  //     from. These numbers are neither "newly broken" nor "pre-existing";
  //     they are newly *known*.
  //
  // Fixing it is layout work on two branch states and belongs in its own
  // ticket with its own visual sign-off. Adding a `foldRatchet` row instead
  // would be precisely the misuse that table forbids.
  //
  // Hebrew is the tightest on the model page for a reason worth keeping in
  // mind when re-measuring: the loop seeds the *dictation* language, and
  // Hebrew is not one of the languages the Parakeet engine covers, so its
  // card renders an extra "unsupported language" line that IntrinsicHeight
  // applies to both engine cards. Measuring with the default dictation
  // language would miss 24 px on that page.

  // ── Disposal — no poll timer survives the window closing ────────────────

  group('OnboardingOverlay disposal', () {
    testWidgets(
      'dispose explicitly stops Auto-Paste AND mic-permission polling — '
      'defends against zombie timers when the overlay tears down '
      '(window close, app quit, re-mount)',
      (tester) async {
        final paste = _RecordingPasteCapabilityNotifier();
        final mic = _RecordingMicPermissionNotifier();

        await _pumpOverlay(tester, paste: paste, mic: mic);
        // Replace the whole tree: the overlay unmounts before its provider
        // scope, and the fakes count no stop of their own on disposal.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(
          paste.stopPollingCalls,
          greaterThanOrEqualTo(1),
          reason: 'Overlay dispose must stop the paste-capability poller',
        );
        expect(
          mic.stopPollingCalls,
          greaterThanOrEqualTo(1),
          reason: 'Overlay dispose must stop the mic-permission poller',
        );
      },
    );
  });

  // ── Step counter semantics (UIA-ONB-10) ─────────────────────────────────

  testWidgets('the step counter is a live region and the dots stay out of '
      'the semantics tree', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpOverlay(
      tester,
      mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
    );
    final total = _totalSteps(defaultTargetPlatform);

    final node = tester.getSemantics(find.byKey(kOnboardingStepCounterKey));
    expect(node.label, l10n.onboardingStepOf(1, total));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  // ── Keyboard navigation (UIA-ONB-01) ────────────────────────────────────

  group('OnboardingOverlay keyboard navigation', () {
    testWidgets('Enter advances like Next, Escape goes back, and Escape on '
        'page 1 stays put', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(
          tester,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
        );
        expect(onboardingPage(buildOnboardingStepIds()[0]), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(onboardingPage(buildOnboardingStepIds()[0]), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(onboardingPage(buildOnboardingStepIds()[1]), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
        await tester.pumpAndSettle();
        expect(onboardingPage(buildOnboardingStepIds()[2]), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(onboardingPage(buildOnboardingStepIds()[1]), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a focused inline hotkey recorder keeps Enter and Escape '
        '(UIA-ONB-01/08)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(
          tester,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          hotkeyStatus: HotkeyRegistrationStatus.conflict,
        );
        await goToOnboardingPage(tester, OnboardingStepId.hotkey);
        expect(find.byKey(kTriggerStepInlineRecorderKey), findsOneWidget);
        await tester.tap(find.byKey(kTriggerStepInlineRecorderKey));
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(seconds: 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(seconds: 1));

        expect(onboardingPage(OnboardingStepId.hotkey), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Enter on the last page with a hotkey conflict opens the hotkey '
        'page instead of completing', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final settings = _FakeSettingsNotifier();
        await _pumpOverlay(
          tester,
          settings: settings,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          hotkeyStatus: HotkeyRegistrationStatus.success,
        );
        await goToOnboardingPage(tester, OnboardingStepId.privacy);
        expect(onboardingPage(OnboardingStepId.privacy), findsOneWidget);
        // A conflict that shows up only after the Hotkey page closes the gate.
        ProviderScope.containerOf(
              tester.element(find.byType(OnboardingOverlay)),
            )
            .read(hotkeyRegistrationStatusProvider.notifier)
            .set(HotkeyRegistrationStatus.conflict);
        await tester.pumpAndSettle();
        final before = settings.current;

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(onboardingPage(OnboardingStepId.hotkey), findsOneWidget);
        expect(settings.current.onboarding.onboardingCompleted, isFalse);
        expect(before.onboarding.onboardingCompleted, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ── Hotkey page: key test and Next (Onboarding v6, screen 5) ─────────────

  group('Hotkey page — key test and Next', () {
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(OnboardingOverlay)),
        );

    WpHeroButton nextButton(WidgetTester tester) =>
        tester.widget<WpHeroButton>(find.byKey(kOnboardingNextButtonKey));

    final skip = find.byKey(const ValueKey('onboarding-hotkey-skip'));

    testWidgets('Next waits for a start and stop of the key; "Später testen" '
        'walks on without it', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(
          tester,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          hotkeyStatus: HotkeyRegistrationStatus.success,
        );
        await goToOnboardingPage(tester, OnboardingStepId.hotkey);
        final sequence = buildOnboardingStepIds();
        final page = sequence.indexOf(OnboardingStepId.hotkey) + 1;

        expect(nextButton(tester).onPressed, isNull);
        expect(skip, findsOneWidget);

        await tester.tap(skip);
        await tester.pumpAndSettle();

        expect(onboardingPage(sequence[page]), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('one press to start and one to stop release Next (toggle '
        'mode)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(
          tester,
          settings: _FakeSettingsNotifier(
            AppSettings.defaults.copyWith(pushToTalk: false),
          ),
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          hotkeyStatus: HotkeyRegistrationStatus.success,
        );
        await goToOnboardingPage(tester, OnboardingStepId.hotkey);
        final activity = containerOf(
          tester,
        ).read(dictationHotkeyActivityProvider.notifier);

        activity.pressed(keyUpSupported: true);
        activity.released();
        await tester.pump();
        expect(nextButton(tester).onPressed, isNull, reason: 'only started');

        activity.pressed(keyUpSupported: true);
        activity.released();
        await tester.pumpAndSettle();

        expect(nextButton(tester).onPressed, isNotNull);
        expect(skip, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a confirmed conflict holds Next and the skip, and resolving '
        'it brings the key test back', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(
          tester,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          hotkeyStatus: HotkeyRegistrationStatus.conflict,
        );
        await goToOnboardingPage(tester, OnboardingStepId.hotkey);

        expect(nextButton(tester).onPressed, isNull);
        expect(skip, findsNothing);

        containerOf(tester)
            .read(hotkeyRegistrationStatusProvider.notifier)
            .set(HotkeyRegistrationStatus.success);
        await tester.pumpAndSettle();

        expect(skip, findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('on Wayland with the hotkey unbound, Next is free at once and '
        'the notice says why', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpOverlay(
          tester,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          hotkeyStatus: HotkeyRegistrationStatus.waylandUnbound,
          waylandBinding: WaylandHotkeyBinding.noAppId,
        );
        await goToOnboardingPage(tester, OnboardingStepId.hotkey);

        expect(
          find.byKey(const ValueKey('onboarding-wayland-hotkey-notice')),
          findsOneWidget,
        );
        expect(nextButton(tester).onPressed, isNotNull);
        expect(skip, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ── Speech model or cloud key, and the closing page (UIA-MDL-GATE) ──────

  group(
    'OnboardingOverlay — cloud key and closing-page gate (UIA-MDL-GATE)',
    () {
      bool nextEnabled(WidgetTester tester) =>
          tester
              .widget<WpHeroButton>(find.byKey(kOnboardingNextButtonKey))
              .onPressed !=
          null;

      Future<void> pumpToModelPage(
        WidgetTester tester, {
        AppSettings? settings,
        bool modelInstalled = false,
        ValueNotifier<ModelDownloadState>? script,
      }) async {
        await _pumpOverlay(
          tester,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          settings: settings == null ? null : _FakeSettingsNotifier(settings),
          modelInstalled: modelInstalled,
          whisperScript: script,
        );
        await openModelSubViewFromClosingPage(tester);
        expect(find.text(l10n.onboardingModelTitle), findsOneWidget);
      }

      // Leaves the model sub-view and goes to the last page.
      // Goes to the last page from wherever the walk is (page 1 has no Back).
      Future<void> walkToClosingPage(WidgetTester tester) async {
        await goToOnboardingPage(tester, OnboardingStepId.privacy);
      }

      const aborted = ModelDownloadState(
        phase: DownloadPhase.error,
        errorMessage: 'Verbindung unterbrochen (HTTP 503)',
      );
      const running = ModelDownloadState(
        phase: DownloadPhase.downloading,
        activeModelId: 'whisper-medium',
        progressPercent: 10,
      );

      testWidgets('a chosen cloud provider with a saved key lets Next through '
          'without any model', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await _pumpOverlay(
            tester,
            mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
            settings: _FakeSettingsNotifier(
              AppSettings.defaults.copyWith(
                sttProvider: SttProviderType.openAI.value,
                openAiApiKey: 'sk-test-key',
              ),
            ),
            modelInstalled: false,
          );
          await walkToClosingPage(tester);

          // The cloud provider with a saved key is a speech model: the last
          // page starts WhisPaste and never sends the user to the model page.
          expect(nextEnabled(tester), isTrue);
          expect(find.text(l10n.onboardingStartWhisPaste), findsOneWidget);
          expect(find.text(l10n.onboardingLoadModel), findsNothing);
          expect(find.byKey(kModelStepNextBlockedKey), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      // G1a: a saved key alone does not open the gate while the local engine
      // is chosen (dictation would fail with "model missing"). The page
      // offers the cloud provider as an explicit choice instead, so nobody
      // is stuck and nothing switches silently.
      testWidgets('a saved key with the local engine chosen offers the cloud '
          'provider and switches only on tap (UIA-MDL-GATE G1a)', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final settings = _FakeSettingsNotifier(
          AppSettings.defaults.copyWith(deepgramApiKey: 'dg-test-key'),
        );
        try {
          await _pumpOverlay(
            tester,
            mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
            settings: settings,
            modelInstalled: false,
          );
          await openModelSubViewFromClosingPage(tester);
          await tester.pumpAndSettle();

          expect(nextEnabled(tester), isFalse);
          expect(find.byKey(kModelStepNextBlockedKey), findsOneWidget);
          expect(
            find.text(l10n.onboardingModelUseCloud('Deepgram')),
            findsOneWidget,
          );
          expect(settings.current.sttProviderType, SttProviderType.onDevice);

          // Reachability first: a real user must be able to see and press the
          // button inside the onboarding window. A miss here is a layout
          // problem, not a flaky tap.
          final cloudButton = find.byKey(kModelStepUseCloudKey);
          expect(cloudButton, findsOneWidget);
          final window = tester.getRect(find.byType(OnboardingOverlay));
          final cloudRect = tester.getRect(cloudButton);
          expect(
            window.contains(cloudRect.center),
            isTrue,
            reason:
                'the cloud button ($cloudRect) lies outside the onboarding '
                'window ($window): a user cannot reach it',
          );
          await tester.ensureVisible(cloudButton);
          await tester.pumpAndSettle();
          await tester.tap(cloudButton);
          await tester.pumpAndSettle();

          expect(settings.current.sttProviderType, SttProviderType.deepgram);
          expect(nextEnabled(tester), isTrue);
          expect(find.byKey(kModelStepUseCloudKey), findsNothing);

          await tester.tap(find.byKey(kModelStepUseLocalKey));
          await tester.pumpAndSettle();

          expect(settings.current.sttProviderType, SttProviderType.onDevice);
          expect(nextEnabled(tester), isFalse);
          expect(find.byKey(kModelStepUseCloudKey), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('without any saved key no cloud choice is shown', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpToModelPage(tester);

          expect(find.byKey(kModelStepUseCloudKey), findsNothing);
          expect(find.byKey(kModelStepUseLocalKey), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('a blank cloud key does not count as set up', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpToModelPage(
            tester,
            settings: AppSettings.defaults.copyWith(openAiApiKey: '   '),
          );

          expect(nextEnabled(tester), isFalse);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets(
        'without a model, download or key the reason is readable text '
        'under its key (UIA-MDL-GATE)',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await pumpToModelPage(tester);

            expect(nextEnabled(tester), isFalse);
            expect(
              tester.widget<Text>(find.byKey(kModelStepNextBlockedKey)).data,
              l10n.onboardingModelNextBlocked,
            );
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      testWidgets('a download aborted on the model page closes Next again '
          '(UIA-MDL-GATE)', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final script = ValueNotifier(const ModelDownloadState());
        try {
          await pumpToModelPage(tester, script: script);
          script.value = running;
          await tester.pumpAndSettle();
          expect(nextEnabled(tester), isTrue);

          script.value = aborted;
          await tester.pumpAndSettle();

          expect(nextEnabled(tester), isFalse);
          expect(find.byKey(kModelStepNextBlockedKey), findsOneWidget);
        } finally {
          script.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      });

      // Onboarding v6: the last page's main action is "Modell laden" whenever
      // no model is ready. A download that fails later changes nothing about
      // that, and the action still leads to the model sub-view with its error.
      testWidgets('a download aborted while on the last page keeps "Modell '
          'laden" and opens the model sub-view (UIA-MDL-GATE)', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final script = ValueNotifier<ModelDownloadState>(running);
        try {
          await _pumpOverlay(
            tester,
            mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
            modelInstalled: false,
            whisperScript: script,
          );
          await walkToClosingPage(tester);
          // A running download already counts as speech-ready, so the last
          // page starts WhisPaste; "Modell laden" comes back after an abort.
          expect(nextEnabled(tester), isTrue, reason: 'running download');
          expect(find.text(l10n.onboardingStartWhisPaste), findsOneWidget);

          script.value = aborted;
          await tester.pumpAndSettle();

          expect(nextEnabled(tester), isTrue);
          expect(find.text(l10n.onboardingLoadModel), findsOneWidget);
          await tester.tap(find.byKey(kOnboardingNextButtonKey));
          await tester.pumpAndSettle();
          expect(find.byType(ModelStep), findsOneWidget);
        } finally {
          script.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      });

      for (final (label, settings, installed) in [
        ('an installed model', null, true),
        (
          'a chosen cloud provider with a saved key',
          AppSettings.defaults.copyWith(
            sttProvider: SttProviderType.openAI.value,
            openAiApiKey: 'sk-test-key',
          ),
          false,
        ),
      ]) {
        testWidgets('the last page starts WhisPaste with $label and no Load '
            'model action (UIA-MDL-GATE)', (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await _pumpOverlay(
              tester,
              mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
              settings: settings == null
                  ? null
                  : _FakeSettingsNotifier(settings),
              modelInstalled: installed,
            );
            await walkToClosingPage(tester);

            expect(nextEnabled(tester), isTrue);
            expect(find.text(l10n.onboardingStartWhisPaste), findsOneWidget);
            expect(find.text(l10n.onboardingLoadModel), findsNothing);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    },
  );

  // ── Model page: Next needs a model or a running download (UIA-RT-01) ─────

  group('OnboardingOverlay — model sub-view gates Next (UIA-RT-01)', () {
    const downloading = ModelDownloadState(
      phase: DownloadPhase.downloading,
      activeModelId: 'whisper-medium',
      progressPercent: 10,
    );

    /// The model is a sub-view, not a page of the sequence (Onboarding v6,
    /// V01); only without a model and without a download does the closing
    /// page open it. [whisper] is the state the download reaches once the
    /// sub-view is open.
    Future<void> pumpToModelSubView(
      WidgetTester tester, {
      ModelDownloadState? whisper,
    }) async {
      final script = ValueNotifier(const ModelDownloadState());
      addTearDown(script.dispose);
      await _pumpOverlay(
        tester,
        mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
        modelInstalled: false,
        whisperScript: script,
      );
      await openModelSubViewFromClosingPage(tester);
      expect(find.byType(ModelStep), findsOneWidget);
      if (whisper != null) {
        script.value = whisper;
        await tester.pumpAndSettle();
      }
    }

    bool nextEnabled(WidgetTester tester) =>
        tester
            .widget<WpHeroButton>(find.byKey(kOnboardingNextButtonKey))
            .onPressed !=
        null;

    testWidgets('without a model and without a download Next is disabled', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpToModelSubView(tester);

        expect(nextEnabled(tester), isFalse);
        expect(
          find.text(l10n.onboardingModelNextBlocked),
          findsOneWidget,
          reason: 'The reason is visible text, not only a disabled button.',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a running download lets Next through (it continues in the '
        'background)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpToModelSubView(tester, whisper: downloading);

        expect(nextEnabled(tester), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('an installed model lets Next through', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpToModelSubView(
          tester,
          whisper: const ModelDownloadState(
            downloadedModels: {'whisper-small'},
          ),
        );

        expect(nextEnabled(tester), isTrue);
        expect(find.text(l10n.onboardingModelNextBlocked), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a model step request from a notice opens the model sub-view '
        'from the last page (UIA-RT-01)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pumpOverlay(
          tester,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
          modelInstalled: false,
          whisperDownload: downloading,
        );
        await goToOnboardingPage(tester, OnboardingStepId.privacy);

        ProviderScope.containerOf(
          tester.element(find.byType(OnboardingOverlay)),
        ).read(onboardingModelStepRequestProvider.notifier).request();
        await tester.pumpAndSettle();

        expect(find.byType(ModelStep), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // Onboarding v6 drops the Smart Mode pitch from the flow: finishing starts
    // WhisPaste with or without a model, and no dialog is shown on the way.
    testWidgets('finishing onboarding with a model starts WhisPaste without a '
        'Smart Mode dialog', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final settings = _FakeSettingsNotifier();
        await _pumpOverlay(
          tester,
          settings: settings,
          mic: _RecordingMicPermissionNotifier(MicPermissionStatus.granted),
        );
        await goToOnboardingPage(tester, OnboardingStepId.privacy);
        await tapOnboardingNext(tester);

        expect(find.byType(Dialog), findsNothing);
        expect(
          settings.current.onboarding.onboardingCompleted,
          isTrue,
          reason: 'The flow must finish.',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Onboarding v6, ticket V01: six pages and the closing page, one primary
  // action per page, the closing page's gate, the model detour, the resume
  // migration and the keyboard path.
  // ---------------------------------------------------------------------------
  group('OnboardingOverlay — six pages (Onboarding v6, V01)', () {
    /// Runs [body] with the Windows platform override and always resets it.
    /// The reset must happen inside the test body: flutter_test checks that
    /// foundation debug variables are unset right after the body, before any
    /// tearDown runs.
    Future<void> onWindows(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets(
      'walks every page, the last one starts WhisPaste',
      (tester) => onWindows(() async {
        await _pumpOverlay(tester, size: kOnboardingWindowSize);
        final sequence = buildOnboardingStepIds();
        expect(onboardingPage(sequence.first), findsOneWidget);
        expect(onboardingBack, findsNothing);

        for (final id in sequence.skip(1)) {
          await tapOnboardingNext(tester);
          expect(onboardingPage(id), findsOneWidget, reason: '$id');
          expect(onboardingBack, findsOneWidget);
        }
        expect(find.text(l10n.onboardingStartWhisPaste), findsOneWidget);
      }),
    );

    testWidgets(
      'a stored v4 privacy position resumes on the last page and is '
      'stamped as v5',
      (tester) => onWindows(() async {
        final settings = _FakeSettingsNotifier(
          const AppSettings(
            onboarding: OnboardingSettings(
              onboardingCurrentStep: 7,
              onboardingFlowVersion: 4,
            ),
          ),
        );
        await _pumpOverlay(
          tester,
          settings: settings,
          size: kOnboardingWindowSize,
        );
        expect(find.byType(PrivacyStep), findsOneWidget);
        expect(settings.current.onboarding.onboardingCurrentStep, kV5Privacy);
        expect(
          settings.current.onboarding.onboardingFlowVersion,
          kOnboardingFlowVersion,
        );
      }),
    );

    testWidgets(
      'a restart with the model page open resumes on the model page (D)',
      (tester) => onWindows(() async {
        await _pumpOverlay(
          tester,
          settings: _FakeSettingsNotifier(
            AppSettings(
              onboarding: OnboardingSettings(
                // One past the last page: the model page was open on quit.
                onboardingCurrentStep: buildOnboardingStepIds().length,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          ),
          size: kOnboardingWindowSize,
        );
        expect(find.byType(ModelStep), findsOneWidget);
        expect(find.byType(PrivacyStep), findsNothing);
      }),
    );

    testWidgets(
      'a restart in the permission or microphone step resumes in that step '
      '(D)',
      (tester) => onWindows(() async {
        await _pumpOverlay(
          tester,
          settings: _FakeSettingsNotifier(
            const AppSettings(
              onboarding: OnboardingSettings(
                onboardingCurrentStep: kV5Access,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          ),
          size: kOnboardingWindowSize,
        );
        expect(find.byType(PermissionsStep), findsOneWidget);
        expect(find.byType(AccessMicStep), findsNothing);
      }),
    );

    testWidgets(
      'without a speech model the last page reads Load model, opens '
      'the model sub-view and comes back to the same page',
      (tester) => onWindows(() async {
        await _pumpOverlay(
          tester,
          size: kOnboardingWindowSize,
          modelInstalled: false,
          settings: _FakeSettingsNotifier(
            const AppSettings(
              onboarding: OnboardingSettings(
                onboardingCurrentStep: kV5Privacy,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          ),
        );
        expect(find.byType(PrivacyStep), findsOneWidget);
        expect(find.text(l10n.onboardingLoadModel), findsOneWidget);
        expect(find.text(l10n.onboardingStartWhisPaste), findsNothing);

        await tapOnboardingNext(tester);
        expect(find.byType(ModelStep), findsOneWidget);
        expect(find.byType(PrivacyStep), findsNothing);

        // Back returns to the last page; the stored position never moved.
        await tester.tap(onboardingBack);
        await tester.pumpAndSettle();
        expect(find.byType(PrivacyStep), findsOneWidget);
        expect(find.text(l10n.onboardingLoadModel), findsOneWidget);
      }),
    );

    testWidgets(
      'only a confirmed hotkey conflict changes the main action to "Hotkey '
      'ändern" (never grey)',
      (tester) => onWindows(() async {
        await _pumpOverlay(
          tester,
          size: kOnboardingWindowSize,
          hotkeyStatus: HotkeyRegistrationStatus.success,
        );
        await goToOnboardingPage(tester, OnboardingStepId.privacy);
        ProviderScope.containerOf(
              tester.element(find.byType(OnboardingOverlay)),
            )
            .read(hotkeyRegistrationStatusProvider.notifier)
            .set(HotkeyRegistrationStatus.conflict);
        await tester.pumpAndSettle();
        final conflict = tester.widget<WpHeroButton>(
          find.byKey(kOnboardingNextButtonKey),
        );
        expect(conflict.onPressed, isNotNull, reason: 'never a grey action');
        expect(find.text(l10n.onboardingReadyFixHotkey), findsOneWidget);

        // A fresh tree: the ProviderScope reads its overrides only once, so
        // the status has to come from a new mount, not from a re-pump.
        await tester.pumpWidget(const SizedBox());
        await _pumpOverlay(
          tester,
          size: kOnboardingWindowSize,
          hotkeyStatus: HotkeyRegistrationStatus.success,
        );
        await goToOnboardingPage(tester, OnboardingStepId.privacy);
        final ok = tester.widget<WpHeroButton>(
          find.byKey(kOnboardingNextButtonKey),
        );
        expect(ok.onPressed, isNotNull);
      }),
    );

    testWidgets(
      'a missing model is not a modal dialog on a first run, and the '
      'last page keeps exactly one main action',
      (tester) => onWindows(() async {
        await _pumpOverlay(
          tester,
          size: kOnboardingWindowSize,
          modelInstalled: false,
        );
        expect(find.byType(Dialog), findsNothing);
        await goToOnboardingPage(tester, OnboardingStepId.privacy);
        expect(
          find.descendant(
            of: find.byType(PrivacyStep),
            matching: find.byType(WpHeroButton),
          ),
          findsOneWidget,
        );
      }),
    );

    testWidgets(
      'the start page link opens the model sub-view and Back returns',
      (tester) => onWindows(() async {
        final semantics = tester.ensureSemantics();
        // The link is on the revision run's start page; the first run's
        // full-bleed page picks the model in its select instead.
        await _pumpOverlay(
          tester,
          size: kOnboardingWindowSize,
          revisionRun: true,
        );
        final link = find.bySemanticsIdentifier(
          'onboarding-welcome-model-link',
        );
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();

        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(find.byType(ModelStep), findsOneWidget);

        await tester.tap(onboardingBack);
        await tester.pumpAndSettle();
        expect(onboardingPage(OnboardingStepId.welcome), findsOneWidget);
        semantics.dispose();
      }),
    );

    testWidgets(
      'the try page has a secondary text link that moves on without '
      'a dictation',
      (tester) => onWindows(() async {
        await _pumpOverlay(
          tester,
          size: kOnboardingWindowSize,
          practiceDone: false,
          settings: _FakeSettingsNotifier(
            const AppSettings(
              onboarding: OnboardingSettings(
                onboardingCurrentStep: kV5Try,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          ),
        );
        expect(find.byType(TestRecordingStep), findsOneWidget);
        final semantics = tester.ensureSemantics();
        final later = find.bySemanticsIdentifier('onboarding-tryout-later');
        await tester.ensureVisible(later);
        await tester.tap(later);
        await tester.pumpAndSettle();
        semantics.dispose();
        expect(find.byType(PrivacyStep), findsOneWidget);
      }),
    );
  });

  group('round feedback button in onboarding', () {
    test('is shown on the intro as before, and hidden on the try-out page', () {
      expect(
        contactLauncherShown(
          fullBleed: false,
          halfway: false,
          step: OnboardingStepId.about,
        ),
        isTrue,
      );
      expect(
        contactLauncherShown(
          fullBleed: true,
          halfway: false,
          step: OnboardingStepId.welcome,
        ),
        isFalse,
        reason: 'the intro shows it only once halfway through',
      );
      expect(
        contactLauncherShown(
          fullBleed: false,
          halfway: false,
          step: OnboardingStepId.tryOut,
        ),
        isFalse,
        reason: 'it would cover the practice field and the dictation result',
      );
    });
  });
}
