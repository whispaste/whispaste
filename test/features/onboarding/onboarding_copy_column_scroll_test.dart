/// Overflowing onboarding copy shows a visible scroll bar (#1845): the
/// privacy page hid its key choices below the edge without any cue.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_split_page.dart';

void main() {
  testWidgets('one scroll bar, always visible, on overflowing copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: OnboardingCopyColumn(
              insetStart: 0,
              copy: Column(
                children: [for (var i = 0; i < 30; i++) Text('line $i')],
              ),
              actions: const Text('Next'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final bars = tester.widgetList<RawScrollbar>(
      find.byWidgetPredicate((w) => w is RawScrollbar),
    );
    expect(bars, hasLength(1), reason: 'no second, fading default bar');
    expect(bars.single.thumbVisibility, isTrue);
    expect(find.text('Next'), findsOneWidget);
  });
}
