/// Widget tests for [PrivacyStep] — the informed telemetry opt-out step.
///
/// Verifies the three behaviours that matter for an *informed opt-out*:
///   1. Consent defaults to ON (the switch reflects `shareUsageStats == true`).
///   2. Toggling the switch persists the new consent value.
///   3. "Next" is always enabled (continuing never depends on the choice);
///      "Back" and "Next" invoke their callbacks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart';

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

Future<_FakeSettingsNotifier> _pump(
  WidgetTester tester, {
  VoidCallback? onNext,
  VoidCallback? onBack,
}) async {
  final settings = _FakeSettingsNotifier();
  await tester.pumpWidget(
    makeTestable(
      PrivacyStep(onNext: onNext ?? () {}, onBack: onBack ?? () {}),
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

  testWidgets('consent defaults to ON (informed opt-out)', (tester) async {
    final settings = await _pump(tester);
    expect(
      settings.state.value!.privacy.shareUsageStats,
      isTrue,
      reason: 'Default must be opt-out: consent on until the user disables it.',
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text(l10n.onboardingPrivacyTitle), findsOneWidget);
  });

  testWidgets('toggling the switch off persists the new consent', (
    tester,
  ) async {
    final settings = await _pump(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(settings.state.value!.privacy.shareUsageStats, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets(
    'Next is always enabled and invokes onNext; Back invokes onBack',
    (tester) async {
      var nextCalls = 0;
      var backCalls = 0;
      await _pump(tester, onNext: () => nextCalls++, onBack: () => backCalls++);

      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
      expect(nextCalls, 1);

      await tester.tap(find.text(l10n.onboardingBack));
      await tester.pumpAndSettle();
      expect(backCalls, 1);
    },
  );
}
