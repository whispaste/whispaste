/// Widget guards for the start page (Onboarding v6, V02): one statement, one
/// static illustration, one model line and one language line. The consent and
/// the download are covered in onboarding_speech_consent_test.dart and in the
/// start-page group of onboarding_overlay_test.dart. The scene's motion is
/// bounded so the setup window goes idle (#1709).
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
    bool reduceMotion = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        MediaQuery(
          // Reduced motion holds the scene still so pumpAndSettle settles
          // at once; the motion group below runs it.
          data: MediaQueryData(size: size, disableAnimations: reduceMotion),
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
    if (reduceMotion) await tester.pumpAndSettle();
  }

  /// Advances the fake clock in frame-sized steps, so the intro hands over
  /// to the loop the way it does on screen.
  Future<void> advance(WidgetTester tester, Duration total) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  int ticking() => SchedulerBinding.instance.transientCallbackCount;

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

  group('WelcomeStep scene motion (#1709)', () {
    setUp(resetWelcomeIntro);

    testWidgets('the loop stops after its bound and the window goes idle', (
      tester,
    ) async {
      await pumpStart(tester, reduceMotion: false);

      await advance(
        tester,
        kWelcomeMotionDuration - const Duration(seconds: 1),
      );
      expect(ticking(), greaterThan(0), reason: 'still looping before the end');

      await advance(tester, const Duration(seconds: 2));
      expect(ticking(), 0, reason: 'no ticker left once the scene rests');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('reduced motion never starts the loop', (tester) async {
      await pumpStart(tester);

      expect(ticking(), 0);
      await advance(tester, const Duration(seconds: 10));
      expect(ticking(), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
