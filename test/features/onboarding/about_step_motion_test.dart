/// Screen 2's preview pulse is bounded so the setup window goes idle (#1709):
/// a few breaths, then the bars rest; reduced motion never starts them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/steps/about_step.dart';

import '../../fixtures/test_helpers.dart';
import 'welcome_step_test.dart' show FakeSettingsNotifier;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAbout(
    WidgetTester tester, {
    required bool reduceMotion,
  }) async {
    const size = kOnboardingWindowSize;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: reduceMotion),
          child: SizedBox.fromSize(
            size: size,
            child: AboutStep(onNext: () {}),
          ),
        ),
        size: size,
        locale: const Locale('en'),
        overrides: [settingsProvider.overrideWith(FakeSettingsNotifier.new)],
      ),
    );
    await tester.pump();
  }

  /// Advances the fake clock in frame-sized steps.
  Future<void> advance(WidgetTester tester, Duration total) async {
    const step = Duration(milliseconds: 100);
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  int ticking() => SchedulerBinding.instance.transientCallbackCount;

  // One beat of the pulse; mirrors _kAboutWavePeriod.
  const beat = Duration(milliseconds: 1400);

  testWidgets('the pulse stops after its breaths and the window goes idle', (
    tester,
  ) async {
    await pumpAbout(tester, reduceMotion: false);
    await advance(tester, beat * (kAboutWaveHalfBeats - 1));
    expect(ticking(), greaterThan(0), reason: 'still breathing');

    await advance(tester, beat * 2);
    expect(ticking(), 0, reason: 'no ticker left once the bars rest');
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion never starts the pulse', (tester) async {
    await pumpAbout(tester, reduceMotion: true);
    await advance(tester, beat * 3);
    expect(ticking(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
