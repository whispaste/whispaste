/// Choosing an answer on the "about you" screen must not move Weiter (#1845):
/// on the Windows test laptop the hint under the button vanished, the
/// centred column jumped about 45 px and the next click missed the button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/about_answers.dart';
import 'package:whispaste/features/onboarding/steps/about_step.dart';

import '../../fixtures/test_helpers.dart';
import 'welcome_step_test.dart' show FakeSettingsNotifier;

void main() {
  testWidgets('Weiter stays where it is when an answer is chosen', (
    tester,
  ) async {
    const size = kOnboardingWindowSize;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        MediaQuery(
          data: const MediaQueryData(size: size, disableAnimations: true),
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
    await tester.pumpAndSettle();

    final next = find.bySemanticsIdentifier('onboarding-about-next');
    final before = tester.getRect(next);
    await tester.tap(
      find.bySemanticsIdentifier('onboarding-about-role-$kAboutDeclined'),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(next).top, before.top);
  });
}
