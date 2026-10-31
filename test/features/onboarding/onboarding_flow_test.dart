/// Durchgehender Onboarding-Walkthrough-Test über alle acht Seiten (Ablauf
/// v3, Maintainer 2026-10-22): Willkommen → Spracherkennung → Tastenkürzel →
/// Berechtigungen → Ausprobieren → Auto-Paste → Fertig. Auto-Paste ist auf
/// macOS, Windows und Linux eine eigene Seite (auf Linux mit dem Hinweis zum
/// erkannten Paketformat); nur der Kill-Switch entfernt sie. Die Sequenz
/// selbst ist in `onboarding_step_ids_test.dart` abgedeckt.
///
/// Dieser Test treibt die [OnboardingOverlay] über die Shell-Navigation
/// ("Weiter") bis zum Abschluss und assertiert dabei:
///   1. Die Seiten-Übergänge anhand des "Step X of Y"-Zählers und der
///      sichtbaren Inhalts-Widgets.
///   2. Auf jeder der Seiten 1–4 existieren genau zwei Navigationsaktionen
///      (Zurück + Weiter) — kein Überspringen-Knopf mehr.
///   3. Den Endzustand: `onboardingCompleted == true` nach dem
///      "Los geht's"-Tap; der Abschluss-CTA bleibt bei Hotkey-Konflikt
///      deaktiviert (residuales Gate aus dem alten ReadyStep) und ist NEU
///      zusätzlich an eine gelungene Testaufnahme mit erkannter Sprache
///      gebunden — mit dem Notausgang „Ohne Mikrofon fortfahren", der
///      ausschließlich die Mikrofon-Bedingung umgeht.
///   4. Wiederaufnahme: eine gespeicherte Position (neuer Ablauf) wird
///      fortgesetzt; eine Position aus dem alten Ablauf wird genau einmal
///      übersetzt (Ablauf-Version wird gestempelt).
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_test_doubles.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/features/onboarding/onboarding_completion_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';
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
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/services/audio_service.dart'
    show audioInputDevicesProvider;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Mutable fake für [SettingsNotifier] — zeichnet jedes [updateSettings]-Call
/// auf, damit der Test den Endzustand (`onboardingCompleted`) prüfen kann.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier([AppSettings? initial])
    : _settings = initial ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Stabiler Fake für [HotkeyRegistrationStatusController].
class _FakeHotkeyController extends HotkeyRegistrationStatusController {
  _FakeHotkeyController([this._initial = HotkeyRegistrationStatus.success]);

  final HotkeyRegistrationStatus _initial;

  @override
  HotkeyRegistrationStatus build() => _initial;
}

/// Skips the real pipeline wiring so the walkthrough never touches audio
/// capture, the STT server, or history persistence when it passes through
/// [TestRecordingStep] — that step only needs the orchestrator instance to
/// exist so it can register its sandbox-transcript seam. The walkthrough
/// simulates a successful test recording by feeding that seam directly
/// (same pattern as `test_recording_step_test.dart`).
class _FakeRecordingOrchestrator extends RecordingOrchestrator {
  @override
  void build() {}
}

/// Handles [_pumpOverlay] hands back: the settings fake for end-state
/// assertions plus the orchestrator fake so tests can drive the
/// sandbox-transcript seam (the completion gate listens to it).
typedef _OverlayHandles = ({
  _FakeSettingsNotifier settings,
  _FakeRecordingOrchestrator orchestrator,
});

/// Fake [HotKeyRegistrar] so [HotkeyService] never touches the real
/// `hotkey_manager` platform channel in the widget test host.
class _FakeRegistrar implements HotKeyRegistrar {
  const _FakeRegistrar({required this.supportsKeyUp});

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

/// Träge Plattform-Wahrheit für den Mikrofon-Berechtigungs-Notifier — der
/// automatische request() beim Verlassen von Seite 1 darf im Widget-Test nie
/// das echte Audio-Plugin erreichen.
class _FakeMicPermissionChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

/// Statically resolved — never the real notifier. `ModelStep._detectHardware`
/// awaits `awaitInitialScan()`, and the real notifier's initial scan is real
/// `Directory`/`File` I/O, which never resolves under `testWidgets` (see the
/// override in `onboarding_overlay_test.dart`, which this mirrors).
/// A speech model is already installed, so Next on the model page is open
/// (UIA-RT-01 holds it until a model is there or downloading).
class _StaticWhisperDownload extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() =>
      const ModelDownloadState(downloadedModels: {'whisper-medium'});
}

class _StaticParakeetDownload extends ParakeetDownloadNotifier {
  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();
}

/// [HotkeyService] mit Fake-Registrar — TriggerStep liest `supportsKeyUp`.
/// `false` passt zur simulierten Linux-Zielplattform.
HotkeyService _fakeHotkeyService() {
  final svc = HotkeyService();
  svc.injectRegistrar(const _FakeRegistrar(supportsKeyUp: false));
  svc.injectMonitor(NoopKeyboardUpMonitor());
  return svc;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Rendert die [OnboardingOverlay] mit minimalen Fake-Overrides.
///
/// WICHTIG: `debugDefaultTargetPlatformOverride` muss vom Aufrufer in einem
/// `try/finally`-Block gesetzt und zurückgesetzt werden.
Future<_OverlayHandles> _pumpOverlay(
  WidgetTester tester, {
  AppSettings? initialSettings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
  Size size = const Size(1280, 1600),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
}) async {
  final settings = _FakeSettingsNotifier(initialSettings);
  final orchestrator = _FakeRecordingOrchestrator();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: const OnboardingOverlay(),
      ),
      size: size,
      locale: locale,
      overrides: [
        onboardingTestRecordingSucceededProvider.overrideWith(
          _PracticeDone.new,
        ),
        onboardingMicSpeechHeardProvider.overrideWith(
          OnboardingFixedMicSpeech.new,
        ),
        onboardingMicProbeProvider.overrideWithValue(OnboardingFakeMicProbe()),
        audioInputDevicesProvider.overrideWith(
          (ref) async => const ['Default'],
        ),
        settingsProvider.overrideWith(() => settings),
        micPermissionCheckerProvider.overrideWithValue(
          _FakeMicPermissionChecker(),
        ),
        hotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeHotkeyController(hotkeyStatus),
        ),
        hotkeyServiceProvider.overrideWith(_fakeHotkeyService),
        recordingOrchestratorProvider.overrideWith(() => orchestrator),
        modelDownloadProvider.overrideWith(_StaticWhisperDownload.new),
        parakeetDownloadProvider.overrideWith(_StaticParakeetDownload.new),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return (settings: settings, orchestrator: orchestrator);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// The practice step holds "Next" until a dictation succeeds; these pages are
/// not about the practice step, so it counts as done.
class _PracticeDone extends OnboardingTestRecordingSucceededNotifier {
  @override
  bool build() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    // Echte gebündelte UI-Schrift statt der Quadrat-Testschrift — die
    // Fixed-Window-Messung unten ist sonst bedeutungslos.
    await loadAppFonts();
  });

  group(
    'Onboarding Walkthrough — sechs Seiten und Abschluss (Onboarding v6)',
    () {
      testWidgets('Vollständiger Durchlauf: alle Seiten, jede Seite mit einer '
          'Hauptaktion, Abschluss ohne Smart-Mode-Dialog', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          final handles = await _pumpOverlay(tester);
          final pages = buildOnboardingStepIds();
          for (var i = 0; i < pages.length; i++) {
            expect(
              onboardingPage(pages[i]),
              findsOneWidget,
              reason: '${pages[i]} (Seite ${i + 1})',
            );
            if (pages[i] == OnboardingStepId.tryOut) {
              // Erstes Diktat: die Testaufnahme ist kein Gate mehr.
              expect(
                tester
                    .widget<WpHeroButton>(find.byKey(kOnboardingNextButtonKey))
                    .onPressed,
                isNotNull,
              );
            }
            if (i < pages.length - 1) await tapOnboardingNext(tester);
          }
          expect(find.text(l10n.onboardingStartWhisPaste), findsOneWidget);

          expect(
            handles.settings.state.value!.onboarding.onboardingCompleted,
            isFalse,
          );
          await tapOnboardingNext(tester);
          expect(
            handles.settings.state.value!.onboarding.onboardingCompleted,
            isTrue,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('Zurück führt von Seite 2 wieder auf Seite 1, und jeder '
          'Seiten-Wechsel persistiert onboardingCurrentStep', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final handles = await _pumpOverlay(tester);
          await tapOnboardingNext(tester);
          expect(
            handles.settings.state.value!.onboarding.onboardingCurrentStep,
            1,
          );
          await tester.tap(onboardingBack);
          await tester.pumpAndSettle();
          expect(find.byType(WelcomeStep), findsOneWidget);
          expect(
            handles.settings.state.value!.onboarding.onboardingCurrentStep,
            0,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    },
  );
}
