import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_status_dot.dart';

import '../fixtures/test_helpers.dart';

Color _colorOf(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(WpStatusDot),
      matching: find.byType(Container),
    ),
  );
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('success is green, the only tone that paints the success role', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const WpStatusDot(tone: WpStatusTone.success)),
    );
    expect(_colorOf(tester), WpColors.success);
  });

  testWidgets('ready is accent, busy amber, error red, idle muted', (
    tester,
  ) async {
    final cases = {
      WpStatusTone.ready: WpColors.accent,
      WpStatusTone.busy: WpColors.warning,
      WpStatusTone.error: WpColors.error,
      WpStatusTone.idle: WpColors.textMuted,
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(makeTestable(WpStatusDot(tone: entry.key)));
      expect(_colorOf(tester), entry.value, reason: entry.key.name);
    }
  });

  testWidgets('is hidden from semantics when no label is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const WpStatusDot(tone: WpStatusTone.ready)),
    );

    expect(
      find.descendant(
        of: find.byType(WpStatusDot),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets('announces its label when one is given', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        const WpStatusDot(
          tone: WpStatusTone.ready,
          semanticsLabel: 'Engine ready',
        ),
      ),
    );

    expect(find.bySemanticsLabel('Engine ready'), findsOneWidget);
    handle.dispose();
  });
}
