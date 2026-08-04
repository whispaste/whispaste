/// Widget tests for [PrivacyStep] — the informed telemetry opt-out step.
///
/// Verifies the behaviours that matter for an *informed opt-out*, across
/// both consents (anonymous usage stats and crash reporting):
///   1. Both default to ON (switches reflect `shareUsageStats`/
///      `errorReporting == true`).
///   2. Toggling either switch persists its own consent value independently.
///
/// Navigation (Back/Next) is owned by the onboarding shell and covered in
/// `onboarding_flow_test.dart` — this step renders content only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart'
    show PrivacyStep, kPrivacyStepCrashToggleKey;

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

  testWidgets('both consents default to ON (informed opt-out)', (tester) async {
    final settings = await _pump(tester);
    expect(
      settings.state.value!.privacy.shareUsageStats,
      isTrue,
      reason: 'Default must be opt-out: consent on until the user disables it.',
    );
    expect(
      settings.state.value!.errorReporting,
      isTrue,
      reason: 'Crash-reporting consent must also default to on-by-default.',
    );
    expect(find.byType(Switch), findsNWidgets(2));
    for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(s.value, isTrue);
    }
    expect(find.text(l10n.onboardingPrivacyTitle), findsOneWidget);
  });

  testWidgets(
    'toggling the usage-stats switch off persists that consent only',
    (tester) async {
      final settings = await _pump(tester);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(settings.state.value!.privacy.shareUsageStats, isFalse);
      expect(
        settings.state.value!.errorReporting,
        isTrue,
        reason: 'The two consents must not affect each other.',
      );
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
        reason: 'The two consents must not affect each other.',
      );
      expect(tester.widget<Switch>(crashToggle).value, isFalse);
    },
  );
}
