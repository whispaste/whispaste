/// Durchgehender Onboarding-Walkthrough-Test über die sechs Linux-Seiten:
/// Willkommen → Datenschutz → Modell → Hotkey → Erscheinungsbild (inkl.
/// Autostart-Umschalter) → Ausprobieren & Los. Auf macOS/Windows liegt
/// zwischen Erscheinungsbild und der letzten Seite zusätzlich die
/// Auto-Paste-Seite (sieben Seiten) — die Sequenz-Differenz selbst ist in
/// `onboarding_step_ids_test.dart` und `onboarding_overlay_test.dart`
/// abgedeckt; hier wird bewusst der kürzere Linux-Pfad durchgespielt.
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
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/appearance_step.dart';
import 'package:whispaste/features/onboarding/steps/autostart_toggle.dart';
import 'package:whispaste/features/onboarding/steps/mic_permission_chip.dart';
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart';
import 'package:whispaste/features/onboarding/steps/ready_step.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
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
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

import '../../fixtures/test_helpers.dart';

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
}) async {
  final settings = _FakeSettingsNotifier(initialSettings);
  final orchestrator = _FakeRecordingOrchestrator();

  await tester.pumpWidget(
    makeTestable(
      const OnboardingOverlay(),
      size: const Size(1280, 1600),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => settings),
        micPermissionCheckerProvider.overrideWithValue(
          _FakeMicPermissionChecker(),
        ),
        hotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeHotkeyController(hotkeyStatus),
        ),
        hotkeyServiceProvider.overrideWith(_fakeHotkeyService),
        recordingOrchestratorProvider.overrideWith(() => orchestrator),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return (settings: settings, orchestrator: orchestrator);
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(kOnboardingNextButtonKey));
  await tester.pumpAndSettle();
}

/// Assertiert die Shell-Navigation der aktuellen Seite: genau zwei
/// Navigationsaktionen (Zurück + Weiter), kein Überspringen.
void _expectExactlyTwoNavActions(WidgetTester tester, {required int page}) {
  final navRow = find.byKey(kOnboardingNavRowKey);
  final textButtons = tester
      .widgetList(
        find.descendant(of: navRow, matching: find.byType(TextButton)),
      )
      .length;
  final accentButtons = tester
      .widgetList(
        find.descendant(of: navRow, matching: find.byType(WpAccentButton)),
      )
      .length;
  expect(
    textButtons + accentButtons,
    2,
    reason:
        'Seite $page: die Navigations-Zeile muss genau zwei Aktionen tragen',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
    // Echte gebündelte UI-Schrift statt der Quadrat-Testschrift — die
    // Fixed-Window-Messung unten ist sonst bedeutungslos.
    final fontLoader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Bold.ttf'));
    await fontLoader.load();
  });

  group('Onboarding Walkthrough — sechs Seiten bis zum Abschluss', () {
    testWidgets(
      'Seite 1: Willkommen (WelcomeStep) wird als erste Seite angezeigt '
      '(1 of 6); die Seite trägt gar keinen Mikrofon-Chip mehr — auf Linux '
      'verspräche er zusätzlich '
      'eine Aktion (Settings-Deep-Link), die es dort nicht gibt',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpOverlay(tester);

          expect(find.byType(WelcomeStep), findsOneWidget);
          expect(find.byType(MicPermissionChip), findsNothing);
          expect(find.text(l10n.onboardingStepOf(1, 6)), findsOneWidget);
          _expectExactlyTwoNavActions(tester, page: 1);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('Vollständiger Durchlauf über alle sechs Seiten: '
        'onboardingCompleted = true nach gelungener Testaufnahme und '
        '"Los geht\'s"', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final (:settings, :orchestrator) = await _pumpOverlay(tester);

        // Seite 1: Willkommen (Demo-Beats + Sprachauswahl; Linux ohne Chip).
        expect(find.byType(WelcomeStep), findsOneWidget);
        expect(find.byType(MicPermissionChip), findsNothing);
        expect(find.text(l10n.onboardingStepOf(1, 6)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 1);
        await _tapNext(tester);

        // Seite 2: Datenschutz.
        expect(find.byType(PrivacyStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(2, 6)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 2);
        await _tapNext(tester);

        // Seite 3: Modell — nur noch die Engine-Wahl, ohne Hotkey-Block.
        expect(find.byType(ModelStep), findsOneWidget);
        expect(find.byType(TriggerStep), findsNothing);
        expect(find.text(l10n.onboardingStepOf(3, 6)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 3);
        await _tapNext(tester);

        // Seite 4: Hotkey — eigene Seite seit der Aufteilung.
        expect(find.byType(TriggerStep), findsOneWidget);
        expect(find.byType(ModelStep), findsNothing);
        expect(find.text(l10n.onboardingStepOf(4, 6)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 4);
        await _tapNext(tester);

        // Seite 5: Erscheinungsbild — Theme-Auswahl UND Autostart-Umschalter.
        expect(find.byType(AppearanceStep), findsOneWidget);
        expect(find.byType(OnboardingAutostartToggle), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(5, 6)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 5);
        await _tapNext(tester);

        // Seite 6: Ausprobieren & Los.
        expect(find.byType(TestRecordingStep), findsOneWidget);
        expect(find.byType(ReadyStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(6, 6)), findsOneWidget);
        // Der Abschluss-CTA trägt das "Los geht's"-Label statt "Weiter".
        expect(find.text(l10n.onboardingStartUsing), findsOneWidget);

        // Mikrofon-Gate: ohne gelungene Testaufnahme (und ohne Notausgang)
        // bleibt der Abschluss-CTA deaktiviert — und der Grund ist benannt.
        expect(
          find.text(l10n.onboardingTestRecordingCompletionHint),
          findsOneWidget,
        );
        expect(
          tester
              .widget<WpAccentButton>(find.byKey(kOnboardingNextButtonKey))
              .onPressed,
          isNull,
          reason:
              'Ohne gelungene Testaufnahme darf der Abschluss nicht '
              'möglich sein.',
        );

        // Gelungene Testaufnahme simulieren: nicht-leerer Transkript-Text
        // am Sandbox-Sink (den TestRecordingStep beim Mount verdrahtet hat).
        orchestrator.sandboxTranscriptSink!('Hallo aus der Sandbox.');
        await tester.pumpAndSettle();
        expect(find.text('Hallo aus der Sandbox.'), findsOneWidget);
        expect(
          tester
              .widget<WpAccentButton>(find.byKey(kOnboardingNextButtonKey))
              .onPressed,
          isNotNull,
          reason: 'Nach erkannter Sprache muss der Abschluss-CTA aktiv werden.',
        );

        // Vor dem abschließenden Tap ist onboardingCompleted noch false.
        expect(settings.state.value!.onboarding.onboardingCompleted, isFalse);

        await _tapNext(tester);

        expect(
          settings.state.value!.onboarding.onboardingCompleted,
          isTrue,
          reason:
              'onboardingCompleted muss nach dem "Los geht\'s"-Tap true sein.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Zurück führt von Seite 2 wieder auf Seite 1', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpOverlay(tester);
        await _tapNext(tester);
        expect(find.text(l10n.onboardingStepOf(2, 6)), findsOneWidget);

        await tester.tap(find.byKey(kOnboardingBackButtonKey));
        await tester.pumpAndSettle();

        expect(find.text(l10n.onboardingStepOf(1, 6)), findsOneWidget);
        expect(find.byType(WelcomeStep), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Jeder Seiten-Wechsel persistiert onboardingCurrentStep', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final (:settings, orchestrator: _) = await _pumpOverlay(tester);
        expect(settings.state.value!.onboarding.onboardingCurrentStep, 0);

        await _tapNext(tester);
        expect(settings.state.value!.onboarding.onboardingCurrentStep, 1);

        await _tapNext(tester);
        expect(settings.state.value!.onboarding.onboardingCurrentStep, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Hotkey-Konflikt: Abschluss-CTA auf der letzten Seite ist deaktiviert '
      '(residuales Gate), Konflikt-Hinweis sichtbar',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpOverlay(
            tester,
            hotkeyStatus: HotkeyRegistrationStatus.conflict,
            initialSettings: AppSettings.defaults.copyWithSections(
              onboarding: AppSettings.defaults.onboarding.copyWith(
                onboardingCurrentStep: 5,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          );

          expect(find.text(l10n.onboardingStepOf(6, 6)), findsOneWidget);
          expect(
            find.text(l10n.onboardingTriggerHotkeyConflictTitle),
            findsWidgets,
          );
          final cta = tester.widget<WpAccentButton>(
            find.byKey(kOnboardingNextButtonKey),
          );
          expect(
            cta.onPressed,
            isNull,
            reason:
                'Bei bestätigtem Hotkey-Konflikt muss der Abschluss-CTA '
                'deaktiviert bleiben.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Notausgang "Ohne Mikrofon fortfahren": aktiviert den Abschluss ohne '
      'Testaufnahme, zeigt den ehrlichen Hinweis, und "Los geht\'s" setzt '
      'onboardingCompleted',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final (:settings, orchestrator: _) = await _pumpOverlay(
            tester,
            initialSettings: AppSettings.defaults.copyWithSections(
              onboarding: AppSettings.defaults.onboarding.copyWith(
                onboardingCurrentStep: 5,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          );

          expect(find.text(l10n.onboardingStepOf(6, 6)), findsOneWidget);
          // Ohne Testaufnahme: CTA deaktiviert, Grund benannt.
          expect(
            tester
                .widget<WpAccentButton>(find.byKey(kOnboardingNextButtonKey))
                .onPressed,
            isNull,
          );
          expect(
            find.text(l10n.onboardingTestRecordingCompletionHint),
            findsOneWidget,
          );

          // Notausgang nehmen.
          final bypass = find.text(l10n.onboardingTestRecordingMicBypassCta);
          await tester.ensureVisible(bypass);
          await tester.tap(bypass);
          await tester.pumpAndSettle();

          // Ehrlicher Hinweis sichtbar, CTA aktiv.
          expect(
            find.text(l10n.onboardingTestRecordingMicBypassHint),
            findsOneWidget,
          );
          expect(
            tester
                .widget<WpAccentButton>(find.byKey(kOnboardingNextButtonKey))
                .onPressed,
            isNotNull,
            reason: 'Der Notausgang muss die Mikrofon-Bedingung umgehen.',
          );

          await _tapNext(tester);
          expect(settings.state.value!.onboarding.onboardingCompleted, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('Notausgang umgeht NUR die Mikrofon-Bedingung: bei bestätigtem '
        'Hotkey-Konflikt bleibt der Abschluss-CTA trotz Bypass deaktiviert', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpOverlay(
          tester,
          hotkeyStatus: HotkeyRegistrationStatus.conflict,
          initialSettings: AppSettings.defaults.copyWithSections(
            onboarding: AppSettings.defaults.onboarding.copyWith(
              onboardingCurrentStep: 5,
              onboardingFlowVersion: kOnboardingFlowVersion,
            ),
          ),
        );

        final bypass = find.text(l10n.onboardingTestRecordingMicBypassCta);
        await tester.ensureVisible(bypass);
        await tester.tap(bypass);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<WpAccentButton>(find.byKey(kOnboardingNextButtonKey))
              .onPressed,
          isNull,
          reason:
              'Das Hotkey-Konflikt-Gate gilt auch für den Notausgang — '
              'der Konflikt-Hinweis verweist zurück auf Schritt 3.',
        );
        // Der bestehende Konflikt-Heads-up erklärt die Lage weiterhin.
        expect(
          find.text(l10n.onboardingTriggerHotkeyConflictTitle),
          findsWidgets,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Onboarding Wiederaufnahme & Ablauf-Migration', () {
    testWidgets('Neustart mit persistierter Position aus dem NEUEN Ablauf '
        '(flowVersion aktuell) setzt genau dort fort', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final (:settings, orchestrator: _) = await _pumpOverlay(
          tester,
          initialSettings: AppSettings.defaults.copyWithSections(
            onboarding: AppSettings.defaults.onboarding.copyWith(
              onboardingCurrentStep: 2,
              onboardingFlowVersion: kOnboardingFlowVersion,
            ),
          ),
        );

        expect(find.byType(ModelStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(3, 6)), findsOneWidget);
        expect(find.byType(WelcomeStep), findsNothing);
        // Keine erneute Übersetzung: Position bleibt unangetastet.
        expect(settings.state.value!.onboarding.onboardingCurrentStep, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Neustart mit Position aus dem ALTEN Ablauf (flowVersion 0): die '
      'Position wird fachlich übersetzt und die Ablauf-Version genau einmal '
      'gestempelt — alter Linux-Index 4 (trigger) landet auf Seite 4 '
      '(Hotkey), die diesen Schritt jetzt allein trägt',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final (:settings, orchestrator: _) = await _pumpOverlay(
            tester,
            initialSettings: AppSettings.defaults.copyWithSections(
              onboarding: AppSettings.defaults.onboarding.copyWith(
                onboardingCurrentStep: 4, // Legacy-Linux: trigger
                // onboardingFlowVersion bleibt auf dem Default 0 (Alt-Stand).
              ),
            ),
          );

          expect(find.byType(TriggerStep), findsOneWidget);
          expect(find.byType(ModelStep), findsNothing);
          expect(find.text(l10n.onboardingStepOf(4, 6)), findsOneWidget);

          final onboarding = settings.state.value!.onboarding;
          expect(
            onboarding.onboardingCurrentStep,
            3,
            reason: 'Die übersetzte Position muss persistiert sein.',
          );
          expect(
            onboarding.onboardingFlowVersion,
            kOnboardingFlowVersion,
            reason:
                'Die Ablauf-Version muss gestempelt sein, damit die '
                'Übersetzung nie erneut greift.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Alte Position jenseits des alten Ablaufs (flowVersion 0, Index 9) '
      'fällt auf Seite 1 zurück',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final (:settings, orchestrator: _) = await _pumpOverlay(
            tester,
            initialSettings: AppSettings.defaults.copyWithSections(
              onboarding: AppSettings.defaults.onboarding.copyWith(
                onboardingCurrentStep: 9,
              ),
            ),
          );

          expect(find.byType(WelcomeStep), findsOneWidget);
          expect(find.text(l10n.onboardingStepOf(1, 6)), findsOneWidget);
          expect(settings.state.value!.onboarding.onboardingCurrentStep, 0);
          expect(
            settings.state.value!.onboarding.onboardingFlowVersion,
            kOnboardingFlowVersion,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'Migration greift NICHT, wenn das Onboarding bereits abgeschlossen ist '
      '— das ist ein eigenständiges, hier nicht behandeltes Feature '
      '(erneutes Onboarding nach Abschluss), kein Wiederaufnahme-Fall',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final (:settings, orchestrator: _) = await _pumpOverlay(
            tester,
            initialSettings: AppSettings.defaults.copyWithSections(
              onboarding: AppSettings.defaults.onboarding.copyWith(
                onboardingCompleted: true,
                onboardingCurrentStep: 4, // Legacy-Linux: trigger
                // onboardingFlowVersion bleibt auf dem Default 0.
              ),
            ),
          );

          // Kein Übersetzungs-Schreibvorgang: weder Position noch
          // Ablauf-Version werden angetastet.
          final onboarding = settings.state.value!.onboarding;
          expect(onboarding.onboardingCurrentStep, 4);
          expect(onboarding.onboardingFlowVersion, 0);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  });

  // Die teuerste Ausprägung der letzten Seite: ein Transkript, das das
  // Sandbox-Feld bis an sein Zeilen-Limit füllt. Die Fixed-Window-Gruppe in
  // `onboarding_overlay_test.dart` misst nur den Ausgangszustand — hier
  // braucht es den Fake-Orchestrator, um überhaupt ein Transkript zu liefern.
  group('Letzte Seite im festen Fenster (1100x720) mit vollem Transkript', () {
    testWidgets('scrollt auch dann nicht, wenn das Sandbox-Feld sein '
        'Zeilen-Limit ausschöpft und der Erfolgs-Block erscheint', (
      tester,
    ) async {
      tester.view.physicalSize = kOnboardingWindowSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // Index der letzten Seite aus der echten Sequenz ableiten: auf
        // macOS sind es sieben Seiten, auf Linux sechs — eine feste Zahl
        // hier hätte die Messung stillschweigend auf die Auto-Paste-Seite
        // gelenkt.
        final lastIndex =
            buildOnboardingStepIds(
              platform: TargetPlatform.macOS,
              autoPasteSupported: true,
            ).length -
            1;
        final (settings: _, :orchestrator) = await _pumpOverlay(
          tester,
          initialSettings: AppSettings.defaults.copyWithSections(
            onboarding: AppSettings.defaults.onboarding.copyWith(
              onboardingCurrentStep: lastIndex,
              onboardingFlowVersion: kOnboardingFlowVersion,
            ),
          ),
        );

        expect(find.byType(TestRecordingStep), findsOneWidget);
        orchestrator.sandboxTranscriptSink!(
          'Dies ist ein bewusst langes Diktat, das das Sandbox-Feld bis an '
          'sein Zeilenlimit fuellt, damit die Hoehenmessung den teuersten '
          'Zustand dieser Seite trifft und nicht den leeren Platzhalter. '
          'Es laeuft ueber mehrere Zeilen und wird danach abgeschnitten, '
          'weil das Feld ein Nachweis ist und kein Transkript-Betrachter.',
        );
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final available = tester
            .renderObject<RenderBox>(find.byType(SingleChildScrollView).first)
            .constraints
            .maxHeight;
        final content =
            scrollable.position.viewportDimension +
            scrollable.position.maxScrollExtent;

        expect(tester.takeException(), isNull);
        expect(
          content,
          lessThanOrEqualTo(available),
          reason:
              'Die letzte Seite braucht mit vollem Transkript $content px '
              'von $available px — sie wuerde scrollen.',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
