/// Tests for [PrivacyStep], the closing page of the onboarding.
///
/// Logic only (test strategy 2026-10-30): each diagnostics switch persists its
/// own consent without touching the other, and the sentence about where the
/// audio goes follows the chosen transcription mode (CONTEXT.md §6.5/§7).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show CloudProviderSettings;
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

Future<_FakeSettingsNotifier> _pump(WidgetTester tester) async {
  final settings = _FakeSettingsNotifier();
  await tester.pumpWidget(
    makeTestable(
      const PrivacyStep(),
      size: const Size(1100, 800),
      locale: const Locale('en'),
      overrides: [settingsProvider.overrideWith(() => settings)],
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

/// The switch under [key]: the usage key sits on the toggle itself, the crash
/// key on its row, so the keyed widget counts as well.
Finder _switchIn(Key key) => find.descendant(
  of: find.byKey(key),
  matching: find.byType(Switch),
  matchRoot: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('the usage-statistics switch persists that consent only', (
    tester,
  ) async {
    final settings = await _pump(tester);
    final before = settings.state.value!;
    await tester.tap(_switchIn(kPrivacyStepUsageToggleKey));
    await tester.pumpAndSettle();

    final after = settings.state.value!;
    expect(after.privacy.shareUsageStats, !before.privacy.shareUsageStats);
    expect(after.errorReporting, before.errorReporting);
    expect(after.privacy.retainRecentAudio, before.privacy.retainRecentAudio);
  });

  testWidgets('the crash-report switch persists that consent only', (
    tester,
  ) async {
    final settings = await _pump(tester);
    final before = settings.state.value!;
    await tester.tap(_switchIn(kPrivacyStepCrashToggleKey));
    await tester.pumpAndSettle();

    final after = settings.state.value!;
    expect(after.errorReporting, !before.errorReporting);
    expect(after.privacy.shareUsageStats, before.privacy.shareUsageStats);
    expect(after.privacy.retainRecentAudio, before.privacy.retainRecentAudio);
  });

  group('where the audio goes follows the transcription mode', () {
    AppSettings withProvider(SttProviderType type, {String url = ''}) {
      final s = AppSettings.defaults.copyWith(sttProvider: type.value);
      return s.copyWithSections(
        cloudProvider: CloudProviderSettings(customEndpointUrl: url),
      );
    }

    test('local mode keeps audio and text on the device', () {
      expect(
        onboardingPrivacyModeLine(l10n, withProvider(SttProviderType.onDevice)),
        l10n.onboardingPrivacyModeLocal,
      );
    });

    test('a cloud provider is named as the direct receiver', () {
      for (final type in [SttProviderType.openAI, SttProviderType.deepgram]) {
        expect(
          onboardingPrivacyModeLine(l10n, withProvider(type)),
          l10n.onboardingPrivacyModeCloud(type.value),
        );
      }
    });

    test('a custom server is named by its host only', () {
      final line = onboardingPrivacyModeLine(
        l10n,
        withProvider(
          SttProviderType.customEndpoint,
          url: 'https://user:secret@stt.example.org:8443/v1?key=abc',
        ),
      );
      expect(line, l10n.onboardingPrivacyModeCustom('stt.example.org'));
    });

    test('a custom server without a usable address gets no sentence', () {
      expect(
        onboardingPrivacyModeLine(
          l10n,
          withProvider(SttProviderType.customEndpoint),
        ),
        isNull,
      );
    });
  });
}
