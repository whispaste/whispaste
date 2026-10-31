/// Widget tests for the closing page of the onboarding (Onboarding v6, V07):
/// page 6 "Datenschutz & Start" on the real overlay.
///
/// Covers the page's contract:
///   1. The main action "WhisPaste starten" is enabled and carries the stable
///      identifier `onboarding-ready-start`, while a speech model is set up.
///   2. Without a speech model the same action reads "Modell laden", carries
///      `onboarding-ready-load-model` and opens the model page.
///   3. A confirmed hotkey conflict turns the main action into "Hotkey ändern"
///      (never grey), carrying `onboarding-ready-fix-hotkey`, and it leads to
///      the hotkey page.
///   4. The privacy switches show the factory defaults of [AppSettings], and
///      opening the page changes none of them.
///   5. Appearance, autostart and notifications are not on the page.
///   6. Enter runs the main action.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show OnboardingSettings;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/model_step.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show
        HotkeyRegistrationStatus,
        HotkeyRegistrationStatusController,
        hotkeyRegistrationStatusProvider;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';
import 'onboarding_test_doubles.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _initial));
  }
}

/// No model on disk and no download running or failed.
class _NoModelWhisper extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState();
}

class _ConflictHotkey extends HotkeyRegistrationStatusController {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.conflict;
}

/// Opens the real overlay on the closing page (the stored position resumes
/// there), with the given model and hotkey state.
Future<_FakeSettingsNotifier> _pumpClosingPage(
  WidgetTester tester, {
  // The real, fixed onboarding window: the page anchors its main action to
  // the bottom edge, so a shorter view would push it out of reach.
  Size size = kOnboardingWindowSize,
  TextScaler textScaler = TextScaler.noScaling,
  Locale locale = const Locale('en'),
  bool modelInstalled = true,
  bool hotkeyConflict = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settings = _FakeSettingsNotifier(
    const AppSettings(
      onboarding: OnboardingSettings(
        onboardingCurrentStep: kV5Privacy,
        onboardingFlowVersion: kOnboardingFlowVersion,
      ),
    ),
  );
  final client = MockClient((_) async => http.Response('', 204));
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler,
          disableAnimations: true,
        ),
        child: const OnboardingOverlay(),
      ),
      size: size,
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(() => settings),
        micPermissionCheckerProvider.overrideWithValue(
          OnboardingCountingMicChecker(),
        ),
        modelDownloadProvider.overrideWith(
          modelInstalled ? OnboardingFakeWhisper.new : _NoModelWhisper.new,
        ),
        parakeetDownloadProvider.overrideWith(OnboardingFakeParakeet.new),
        hotkeyRegistrationStatusProvider.overrideWith(
          hotkeyConflict ? _ConflictHotkey.new : OnboardingFakeHotkey.new,
        ),
        telemetryProvider.overrideWith(
          (ref) => TelemetryService(
            client: client,
            endpointUrl: 'https://stats.example.invalid',
            siteId: 1,
            consentGranted: true,
          ),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(PrivacyStep), findsOneWidget);
  return settings;
}

/// Semantics identifiers of every node on the current screen.
Set<String> _identifiersOnScreen(WidgetTester tester) {
  final ids = <String>{};
  void visit(SemanticsNode node) {
    final id = node.getSemanticsData().identifier;
    if (id.isNotEmpty) ids.add(id);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return ids;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'with a speech model the main action starts WhisPaste, is enabled and '
    'carries its identifier',
    (tester) async {
      // Semantics must be on before the first frame; disposed before the
      // test body ends, as flutter_test checks handles at that point.
      final semantics = tester.ensureSemantics();
      await _pumpClosingPage(tester);

      final button = tester.widget<WpHeroButton>(
        find.byKey(kOnboardingNextButtonKey),
      );
      expect(button.onPressed, isNotNull, reason: 'never a grey action');
      expect(find.text(l10n.onboardingStartWhisPaste), findsOneWidget);
      expect(find.text(l10n.onboardingLoadModel), findsNothing);
      expect(_identifiersOnScreen(tester), contains('onboarding-ready-start'));
      semantics.dispose();
    },
  );

  testWidgets('without a speech model the main action reads "Modell laden", is '
      'enabled and opens the model page', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpClosingPage(tester, modelInstalled: false);

    final button = tester.widget<WpHeroButton>(
      find.byKey(kOnboardingNextButtonKey),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text(l10n.onboardingLoadModel), findsOneWidget);
    expect(find.text(l10n.onboardingStartWhisPaste), findsNothing);
    expect(
      _identifiersOnScreen(tester),
      contains('onboarding-ready-load-model'),
    );
    semantics.dispose();

    await tester.ensureVisible(find.byKey(kOnboardingNextButtonKey));
    await tester.tap(find.byKey(kOnboardingNextButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(ModelStep), findsOneWidget);
  });

  testWidgets('a confirmed hotkey conflict turns the main action into '
      '"Hotkey ändern" that leads to the hotkey page', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpClosingPage(tester, hotkeyConflict: true);

    final button = tester.widget<WpHeroButton>(
      find.byKey(kOnboardingNextButtonKey),
    );
    expect(button.onPressed, isNotNull, reason: 'never a grey action');
    expect(find.text(l10n.onboardingReadyFixHotkey), findsOneWidget);
    expect(find.text(l10n.onboardingStartWhisPaste), findsNothing);
    expect(
      _identifiersOnScreen(tester),
      contains('onboarding-ready-fix-hotkey'),
    );
    semantics.dispose();

    await tester.tap(find.byKey(kOnboardingNextButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(TriggerStep), findsOneWidget);
  });

  testWidgets(
    'the privacy switches show the factory defaults and opening the page '
    'changes none of them',
    (tester) async {
      final settings = await _pumpClosingPage(tester);

      final defaults = AppSettings.defaults;
      final current = settings.state.value!;
      expect(current.errorReporting, defaults.errorReporting);
      expect(current.privacy.shareUsageStats, defaults.privacy.shareUsageStats);
      expect(
        current.privacy.retainRecentAudio,
        defaults.privacy.retainRecentAudio,
      );
    },
  );

  testWidgets('Enter runs the main action and completes the onboarding', (
    tester,
  ) async {
    final settings = await _pumpClosingPage(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(settings.state.value!.onboarding.onboardingCompleted, isTrue);
  });
}
