/// Durchgehender Onboarding-Walkthrough-Test über die fünf Seiten:
/// Willkommen → Datenschutz → Modell & Hotkey → Autostart & Auto-Paste →
/// Ausprobieren & Los (Sequenz auf allen Plattformen identisch; hier wird
/// der Linux-Pfad gefahren, auf dem Seite 4 nur den Autostart-Umschalter
/// zeigt).
///
/// Dieser Test treibt die [OnboardingOverlay] über die Shell-Navigation
/// ("Weiter") bis zum Abschluss und assertiert dabei:
///   1. Die Seiten-Übergänge anhand des "Step X of Y"-Zählers und der
///      sichtbaren Inhalts-Widgets.
///   2. Auf jeder der Seiten 1–4 existieren genau zwei Navigationsaktionen
///      (Zurück + Weiter) — kein Überspringen-Knopf mehr.
///   3. Den Endzustand: `onboardingCompleted == true` nach dem
///      "Los geht's"-Tap; der Abschluss-CTA bleibt bei Hotkey-Konflikt
///      deaktiviert (residuales Gate aus dem alten ReadyStep).
///   4. Wiederaufnahme: eine gespeicherte Position (neuer Ablauf) wird
///      fortgesetzt; eine Position aus dem alten Ablauf wird genau einmal
///      übersetzt (Ablauf-Version wird gestempelt).
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/autostart_toggle.dart';
import 'package:whispaste/features/onboarding/steps/microphone_step.dart';
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
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

import '../../fixtures/fake_onboarding_mic.dart';
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
/// exist so it can register its sandbox-transcript seam.
class _FakeRecordingOrchestrator extends RecordingOrchestrator {
  @override
  void build() {}
}

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
Future<_FakeSettingsNotifier> _pumpOverlay(
  WidgetTester tester, {
  AppSettings? initialSettings,
  HotkeyRegistrationStatus hotkeyStatus = HotkeyRegistrationStatus.success,
}) async {
  final settings = _FakeSettingsNotifier(initialSettings);

  await tester.pumpWidget(
    makeTestable(
      OnboardingOverlay(
        micProbeFactory: FakeOnboardingMicProbe.new,
        micRouting: FakeAudioRoutingService(),
      ),
      size: const Size(1280, 1600),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => settings),
        hotkeyRegistrationStatusProvider.overrideWith(
          () => _FakeHotkeyController(hotkeyStatus),
        ),
        hotkeyServiceProvider.overrideWith(_fakeHotkeyService),
        recordingOrchestratorProvider.overrideWith(
          _FakeRecordingOrchestrator.new,
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return settings;
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
  });

  group('Onboarding Walkthrough — fünf Seiten bis zum Abschluss', () {
    testWidgets(
      'Seite 1: Willkommen (WelcomeStep + MicrophoneStep) wird als erste '
      'Seite angezeigt (1 of 5)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await _pumpOverlay(tester);

          expect(find.byType(WelcomeStep), findsOneWidget);
          expect(find.byType(MicrophoneStep), findsOneWidget);
          expect(find.text(l10n.onboardingStepOf(1, 5)), findsOneWidget);
          _expectExactlyTwoNavActions(tester, page: 1);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('Vollständiger Durchlauf über alle fünf Seiten: '
        'onboardingCompleted = true nach "Los geht\'s"', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final settings = await _pumpOverlay(tester);

        // Seite 1: Willkommen (Welcome + Mikrofon).
        expect(find.byType(WelcomeStep), findsOneWidget);
        expect(find.byType(MicrophoneStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(1, 5)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 1);
        await _tapNext(tester);

        // Seite 2: Datenschutz.
        expect(find.byType(PrivacyStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(2, 5)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 2);
        await _tapNext(tester);

        // Seite 3: Modell & Hotkey.
        expect(find.byType(ModelStep), findsOneWidget);
        expect(find.byType(TriggerStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(3, 5)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 3);
        await _tapNext(tester);

        // Seite 4: Autostart & Auto-Paste — auf Linux nur der
        // Autostart-Umschalter (kein Paste-Controller verdrahtet).
        expect(find.byType(OnboardingAutostartToggle), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(4, 5)), findsOneWidget);
        _expectExactlyTwoNavActions(tester, page: 4);
        await _tapNext(tester);

        // Seite 5: Ausprobieren & Los.
        expect(find.byType(TestRecordingStep), findsOneWidget);
        expect(find.byType(ReadyStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(5, 5)), findsOneWidget);
        // Der Abschluss-CTA trägt das "Los geht's"-Label statt "Weiter".
        expect(find.text(l10n.onboardingStartUsing), findsOneWidget);

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
        expect(find.text(l10n.onboardingStepOf(2, 5)), findsOneWidget);

        await tester.tap(find.byKey(kOnboardingBackButtonKey));
        await tester.pumpAndSettle();

        expect(find.text(l10n.onboardingStepOf(1, 5)), findsOneWidget);
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
        final settings = await _pumpOverlay(tester);
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
                onboardingCurrentStep: 4,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          );

          expect(find.text(l10n.onboardingStepOf(5, 5)), findsOneWidget);
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
  });

  group('Onboarding Wiederaufnahme & Ablauf-Migration', () {
    testWidgets('Neustart mit persistierter Position aus dem NEUEN Ablauf '
        '(flowVersion aktuell) setzt genau dort fort', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final settings = await _pumpOverlay(
          tester,
          initialSettings: AppSettings.defaults.copyWithSections(
            onboarding: AppSettings.defaults.onboarding.copyWith(
              onboardingCurrentStep: 2,
              onboardingFlowVersion: kOnboardingFlowVersion,
            ),
          ),
        );

        expect(find.byType(ModelStep), findsOneWidget);
        expect(find.text(l10n.onboardingStepOf(3, 5)), findsOneWidget);
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
      'gestempelt — alter Linux-Index 4 (trigger) landet auf Seite 3 '
      '(Modell & Hotkey)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          final settings = await _pumpOverlay(
            tester,
            initialSettings: AppSettings.defaults.copyWithSections(
              onboarding: AppSettings.defaults.onboarding.copyWith(
                onboardingCurrentStep: 4, // Legacy-Linux: trigger
                // onboardingFlowVersion bleibt auf dem Default 0 (Alt-Stand).
              ),
            ),
          );

          expect(find.byType(ModelStep), findsOneWidget);
          expect(find.byType(TriggerStep), findsOneWidget);
          expect(find.text(l10n.onboardingStepOf(3, 5)), findsOneWidget);

          final onboarding = settings.state.value!.onboarding;
          expect(
            onboarding.onboardingCurrentStep,
            2,
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
          final settings = await _pumpOverlay(
            tester,
            initialSettings: AppSettings.defaults.copyWithSections(
              onboarding: AppSettings.defaults.onboarding.copyWith(
                onboardingCurrentStep: 9,
              ),
            ),
          );

          expect(find.byType(WelcomeStep), findsOneWidget);
          expect(find.text(l10n.onboardingStepOf(1, 5)), findsOneWidget);
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
          final settings = await _pumpOverlay(
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
}
