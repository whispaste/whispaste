/// Widget tests for [PrivacyStep] — the informed telemetry opt-out step.
///
/// Verifies the behaviours that matter for an *informed opt-out*, across all
/// three toggles (crash reporting, anonymous usage stats, keep recent
/// recordings — in that order, mirroring Settings → Privacy):
///   1. Crash reporting and usage stats default to ON; keep recent
///      recordings defaults to OFF.
///   2. Toggling any switch persists its own value independently of the
///      other two.
///   3. The wording follows CONTEXT.md §6.5/§7 — never an absolute "no
///      tracking" claim; instead the correct promise: audio & text stay
///      local, the statistics are anonymous, self-hosted, and can be
///      switched off.
///   4. Layout: the step fits the fixed onboarding window (1100×720,
///      [kOnboardingWindowSize]) without scrolling, and stays reachable via
///      the shell's scroll fallback at enlarged system text.
///
/// Navigation (Back/Next) is owned by the onboarding shell and covered in
/// `onboarding_flow_test.dart` — this step renders content only; the layout
/// tests below mount the real shell to measure the step in its true frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart'
    show PrivacyStep, kPrivacyStepCrashToggleKey;
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

import '../../fixtures/test_helpers.dart';

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

/// Inert platform truth — the shell's page-1 mic chip checks on mount and
/// leaving page 1 may request; neither call may reach the real audio plugin.
class _FakeMicPermissionChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => false;
}

/// Mounts the real onboarding shell and navigates to page 2 (this step) so
/// layout is measured in the step's true frame: shell chrome, content
/// padding, and the shell-owned scroll fallback all included.
Future<void> _pumpShellOnPrivacyPage(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: const OnboardingOverlay(),
      ),
      size: size,
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(_FakeSettingsNotifier.new),
        micPermissionCheckerProvider.overrideWithValue(
          _FakeMicPermissionChecker(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(kOnboardingNextButtonKey));
  await tester.pumpAndSettle();
  expect(
    find.byType(PrivacyStep),
    findsOneWidget,
    reason: 'Page 2 of the shell must be the privacy step.',
  );
}

Future<_FakeSettingsNotifier> _pump(WidgetTester tester) async {
  final settings = _FakeSettingsNotifier();
  await tester.pumpWidget(
    makeTestable(
      const PrivacyStep(),
      size: const Size(800, 1000),
      locale: const Locale('en'),
      overrides: [settingsProvider.overrideWith(() => settings)],
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'crash reporting and usage stats default to ON, keep recent recordings '
    'defaults to OFF',
    (tester) async {
      final settings = await _pump(tester);
      expect(
        settings.state.value!.errorReporting,
        isTrue,
        reason: 'Crash-reporting consent must default to on-by-default.',
      );
      expect(
        settings.state.value!.privacy.shareUsageStats,
        isTrue,
        reason:
            'Default must be opt-out: consent on until the user disables it.',
      );
      expect(
        settings.state.value!.privacy.retainRecentAudio,
        isFalse,
        reason:
            'Keeping recent recordings defaults to off, unlike the other '
            'two toggles.',
      );
      expect(find.byType(Switch), findsNWidgets(3));
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches[0].value, isTrue, reason: 'Crash reporting, first row.');
      expect(switches[1].value, isTrue, reason: 'Usage stats, second row.');
      expect(
        switches[2].value,
        isFalse,
        reason: 'Keep recent recordings, third row.',
      );
      expect(find.text(l10n.onboardingPrivacyTitle), findsOneWidget);
    },
  );

  testWidgets(
    'toggling the usage-stats switch off persists that consent only',
    (tester) async {
      final settings = await _pump(tester);
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();

      expect(settings.state.value!.privacy.shareUsageStats, isFalse);
      expect(
        settings.state.value!.errorReporting,
        isTrue,
        reason: 'The three toggles must not affect each other.',
      );
      expect(settings.state.value!.privacy.retainRecentAudio, isFalse);
    },
  );

  testWidgets(
    'toggling the crash-reporting switch off persists that consent only',
    (tester) async {
      final settings = await _pump(tester);
      final crashToggle = find.descendant(
        of: find.byKey(kPrivacyStepCrashToggleKey),
        matching: find.byType(Switch),
      );
      expect(crashToggle, findsOneWidget);

      await tester.tap(crashToggle);
      await tester.pumpAndSettle();

      expect(settings.state.value!.errorReporting, isFalse);
      expect(
        settings.state.value!.privacy.shareUsageStats,
        isTrue,
        reason: 'The three toggles must not affect each other.',
      );
      expect(settings.state.value!.privacy.retainRecentAudio, isFalse);
      expect(tester.widget<Switch>(crashToggle).value, isFalse);
    },
  );

  testWidgets(
    'toggling the keep-recent-recordings switch on persists that value only',
    (tester) async {
      final settings = await _pump(tester);
      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();

      expect(settings.state.value!.privacy.retainRecentAudio, isTrue);
      expect(
        settings.state.value!.errorReporting,
        isTrue,
        reason: 'The three toggles must not affect each other.',
      );
      expect(settings.state.value!.privacy.shareUsageStats, isTrue);
    },
  );

  // ── Wording — CONTEXT.md §6.5/§7 ──────────────────────────────────────────
  //
  // Never an absolute "no tracking" claim; instead the correct promise:
  // audio & text stay local; anonymous, self-hosted statistics — can be
  // switched off. Substring checks against the l10n getters, not full-text
  // comparisons, so minor copy tweaks don't break the contract.

  group('wording follows CONTEXT.md §6.5/§7', () {
    testWidgets('the rendered hint is the l10n privacy hint', (tester) async {
      await _pump(tester);
      expect(find.text(l10n.onboardingPrivacyHint), findsOneWidget);
    });

    test('EN hint promises local audio/text and self-hosted statistics', () {
      final hint = l10n.onboardingPrivacyHint.toLowerCase();
      expect(hint, contains('local'));
      expect(hint, contains('self-hosted'));
      expect(hint, contains('anonymous'));
      expect(
        hint,
        isNot(contains('no tracking')),
        reason: 'CONTEXT.md §7 forbids the absolute "no tracking" claim.',
      );
    });

    test('DE hint promises local audio/text and self-hosted statistics '
        '(reference wording)', () async {
      final de = await L10n.delegate.load(const Locale('de'));
      final hint = de.onboardingPrivacyHint.toLowerCase();
      expect(hint, contains('lokal'));
      expect(hint, contains('selbst gehostet'));
      expect(hint, contains('anonym'));
      expect(
        hint,
        isNot(contains('kein tracking')),
        reason: 'CONTEXT.md §7 forbids the absolute "no tracking" claim.',
      );
    });
  });

  // ── Layout — fixed onboarding window & enlarged system text ──────────────

  group('layout in the onboarding shell', () {
    testWidgets(
      'fits the fixed onboarding window size (1100×720) without scrolling',
      (tester) async {
        await _pumpShellOnPrivacyPage(tester, size: kOnboardingWindowSize);

        expect(tester.takeException(), isNull);
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(
          scrollable.position.maxScrollExtent,
          0,
          reason:
              'At the fixed onboarding window size the privacy step must be '
              'fully visible without scrolling.',
        );
      },
    );

    testWidgets('at enlarged system text (textScaler 1.5) all three rows stay '
        'reachable and operable — the shell scroll fallback may kick in, but '
        'nothing is clipped away', (tester) async {
      await _pumpShellOnPrivacyPage(
        tester,
        size: kOnboardingWindowSize,
        textScaler: const TextScaler.linear(1.5),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'Enlarged text must scroll, never overflow-clip.',
      );
      expect(find.byType(Switch), findsNWidgets(3));

      // The third row (keep recent recordings) sits lowest — prove it can
      // be brought into view and actually operated, not just that it
      // exists in the tree.
      final retainToggle = find.byType(Switch).at(2);
      await tester.ensureVisible(retainToggle);
      await tester.pumpAndSettle();
      await tester.tap(retainToggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(retainToggle).value, isTrue);
    });
  });
}
