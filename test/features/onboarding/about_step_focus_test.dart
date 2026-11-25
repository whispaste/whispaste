/// Tab walks the role chips of "About you" in the order they are read
/// (#1845): the rows overlap slightly, which made reading-order traversal
/// jump between rows.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/platform/desktop_window_geometry.dart'
    show kOnboardingWindowSize;
import 'package:whispaste/features/onboarding/about_answers.dart';
import 'package:whispaste/features/onboarding/steps/about_step.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../../fixtures/test_helpers.dart';
import 'welcome_step_test.dart' show FakeSettingsNotifier;

String? _focusedChip() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<WpFilterChip>()
    ?.testId;

void main() {
  testWidgets('Tab follows the role chips in list order', (tester) async {
    const size = kOnboardingWindowSize;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        SizedBox.fromSize(
          size: size,
          child: AboutStep(onNext: () {}),
        ),
        size: size,
        locale: const Locale('en'),
        overrides: [settingsProvider.overrideWith(FakeSettingsNotifier.new)],
      ),
    );
    await tester.pump();

    final expected = [
      for (final id in [...kOnboardingAboutRoles, kAboutDeclined])
        'onboarding-about-role-$id',
    ];
    final first = find.byWidgetPredicate(
      (w) => w is WpFilterChip && w.testId == expected.first,
    );
    // The chip's own focus node sits below the WpFilterChip widget.
    final firstNode = Focus.of(
      tester.element(
        find.descendant(of: first, matching: find.byType(Text)).first,
      ),
    );
    firstNode.requestFocus();
    await tester.pump();

    final seen = <String?>[_focusedChip()];
    for (var i = 1; i < expected.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      seen.add(_focusedChip());
    }
    expect(seen, expected);
  });
}
