import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/widgets/settings_scroll_affordance.dart';

const _fadeKey = ValueKey('settings-scroll-fade');

Future<void> _pump(WidgetTester tester, {required double height}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: SettingsScrollAffordance(
            child: SizedBox(height: height, width: double.infinity),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the bottom fade only while more content lies below', (
    tester,
  ) async {
    await _pump(tester, height: 900);
    expect(find.byKey(_fadeKey), findsOneWidget, reason: 'overflowing content');

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_fadeKey), findsNothing, reason: 'scrolled to the end');

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_fadeKey), findsOneWidget, reason: 'back at the top');
  });

  testWidgets('no fade and no scroll when the content fits', (tester) async {
    await _pump(tester, height: 120);
    expect(find.byKey(_fadeKey), findsNothing);
  });

  testWidgets('the scrollbar thumb is always visible on overflow', (
    tester,
  ) async {
    await _pump(tester, height: 900);
    final bar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(bar.thumbVisibility, isTrue);
  });
}
