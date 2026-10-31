/// Budget guards for the motion clip of a fill page (MOTION-POLISH).
///
/// A clip that the page budget leaves out must build no image at all, so no
/// still is decoded for a box of 0x0 (UX-088).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/steps/onboarding_headings.dart';
import 'package:whispaste/features/onboarding/steps/onboarding_motion_clip.dart';
import 'package:whispaste/features/onboarding/steps/onboarding_page_fill.dart';

import '../../fixtures/test_helpers.dart';

const String _kClipId = 'onboarding-speech-motion';

Finder _clipOf(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

/// Pumps one fill page of [availableHeight] whose body is [body], inside a
/// column of the 640 px reading measure the onboarding overlay uses.
Future<void> _pumpFillPage(
  WidgetTester tester, {
  required double availableHeight,
  required Widget body,
  List overrides = const [],
}) async {
  const width = 1100.0;
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: _readingMeasure,
          child: OnboardingPageFill(
            availableHeight: availableHeight,
            child: OnboardingPage(
              header: const OnboardingPageHeading(title: 'Title'),
              body: body,
            ),
          ),
        ),
      ),
      size: const Size(width, 900),
      locale: const Locale('en'),
      overrides: overrides,
    ),
  );
  await tester.pump();
}

/// The onboarding overlay's reading measure (`_readingMeasure`).
const double _readingMeasure = 640;

void main() {
  group('Motion clip budget (MOTION-POLISH)', () {
    testWidgets('UX-088: a clip the budget leaves out builds no Image', (
      tester,
    ) async {
      // 300 px of page, a 400 px body: no room for a clip (below the minimum).
      await _pumpFillPage(
        tester,
        availableHeight: 300,
        body: const OnboardingMotionStep(
          beat: 2,
          testId: _kClipId,
          child: SizedBox(height: 400),
        ),
      );

      expect(_clipOf(_kClipId), findsOneWidget);
      expect(tester.getSize(_clipOf(_kClipId)).height, 0);
      expect(
        find.descendant(of: _clipOf(_kClipId), matching: find.byType(Image)),
        findsNothing,
      );
    });

    testWidgets('a clip with room builds exactly one Image', (tester) async {
      await _pumpFillPage(
        tester,
        availableHeight: 600,
        body: const OnboardingMotionStep(
          beat: 2,
          testId: _kClipId,
          child: SizedBox(height: 50),
        ),
      );

      expect(
        find.descendant(of: _clipOf(_kClipId), matching: find.byType(Image)),
        findsOneWidget,
      );
    });
  });
}
