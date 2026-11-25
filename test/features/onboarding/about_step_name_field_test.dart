/// The first-name field on the "About you" step names its purpose (#1927):
/// autofill knows it asks for a given name (WCAG 1.3.5), and the text field
/// node itself carries the visible label as its accessible name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/steps/about_step.dart';

import '../../fixtures/test_helpers.dart';
import 'welcome_step_test.dart' show FakeSettingsNotifier;

void main() {
  testWidgets('the name field asks for a given name under its own label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final l10n = await L10n.delegate.load(const Locale('en'));
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
    await tester.pump();

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).autofillHints, [
      AutofillHints.givenName,
    ]);

    // The field is a merge boundary: the label, the text-field flag and the
    // automation identifier are folded onto one node, which is what the
    // platform receives (#2011). Read the merged data, not the raw node.
    final node = tester
        .getSemantics(find.byType(EditableText))
        .getSemanticsData();
    expect(node.flagsCollection.isTextField, isTrue);
    expect(node.label, contains(l10n.onboardingAboutNameLabel));
    expect(node.identifier, 'onboarding-about-name');
    handle.dispose();
  });
}
