/// Widget guards for the start page (Onboarding v6, V02): one statement, one
/// static illustration, one model line and one language line. The consent and
/// the download are covered in onboarding_speech_consent_test.dart and in the
/// start-page group of onboarding_overlay_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/onboarding_speech_consent.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';

import '../../fixtures/test_helpers.dart';

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

const _offer = WelcomeSpeechOffer(
  engine: OnDeviceEngine.whisper,
  whisperModelId: 'whisper-medium',
  sizeBytes: 1536 * 1024 * 1024,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpStart(
    WidgetTester tester, {
    FakeSettingsNotifier? settings,
    Locale locale = const Locale('en'),
    Size size = kOnboardingWindowSize,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        MediaQuery(
          // The scene loops by design; reduced motion holds it still so
          // pumpAndSettle can settle.
          data: MediaQueryData(size: size, disableAnimations: true),
          // The start page is full bleed: it fills the window it is given,
          // as the overlay gives it, and never sits in a scroll view.
          child: SizedBox.fromSize(size: size, child: const WelcomeStep()),
        ),
        size: size,
        locale: locale,
        overrides: [
          settingsProvider.overrideWith(
            () => settings ?? FakeSettingsNotifier(),
          ),
          welcomeSpeechOfferProvider.overrideWith((ref) async => _offer),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  group('WelcomeStep (start page)', () {
    testWidgets('choosing a language in the selector updates the setting', (
      tester,
    ) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(interface_: InterfaceSettings(locale: 'en')),
      );
      await pumpStart(tester, settings: notifier);

      final semantics = tester.ensureSemantics();
      await tester.tap(
        find.bySemanticsIdentifier('onboarding-welcome-app-language'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsIdentifier('onboarding-welcome-app-language-option-de'),
      );
      await tester.pumpAndSettle();
      semantics.dispose();

      expect(notifier.state.value!.locale, 'de');
    });
  });
}
