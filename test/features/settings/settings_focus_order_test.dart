import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('SettingsPage focus traversal', () {
    testWidgets('Tab traversal moves focus in reading order (never jumps upward)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Locate the content Column inside the SingleChildScrollView as a
      // scroll-invariant reference ancestor.
      final columnFinder = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Column),
      );
      // There may be nested Columns — use the first one (the outermost child
      // of the scroll view, which is the section layout column).
      final columnElement = columnFinder.evaluate().first;
      final columnRO = columnElement.renderObject as RenderBox;

      // Seed focus into the widget tree so primaryFocus is non-null.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final List<double> dyValues = [];
      final Set<int> seenFocusIds = {};

      const maxTabs =
          30; // safety ceiling — stops the loop from running forever

      for (int i = 0; i < maxTabs; i++) {
        final focus = tester.binding.focusManager.primaryFocus;
        if (focus == null) break;

        final id = focus.hashCode;
        if (seenFocusIds.contains(id)) {
          // Focus wrapped around — we've completed the traversal cycle.
          break;
        }
        seenFocusIds.add(id);

        final context = focus.context;
        if (context != null) {
          final ro = context.findRenderObject();
          if (ro is RenderBox && ro.hasSize && columnRO.hasSize) {
            final dy =
                (ro.localToGlobal(Offset.zero) -
                        columnRO.localToGlobal(Offset.zero))
                    .dy;
            dyValues.add(dy);
          }
        }

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }

      // We need at least a few focusable controls to make the test meaningful.
      expect(
        dyValues.length,
        greaterThanOrEqualTo(4),
        reason:
            'Expected at least 4 focusable controls in SettingsPage, got ${dyValues.length}.',
      );

      // Assert monotonically non-decreasing — allow 1px of sub-pixel rounding.
      const epsilon = 1.0;
      for (int i = 1; i < dyValues.length; i++) {
        expect(
          dyValues[i],
          greaterThanOrEqualTo(dyValues[i - 1] - epsilon),
          reason:
              'Tab focus jumped upward at step $i: dy went from '
              '${dyValues[i - 1].toStringAsFixed(1)} → ${dyValues[i].toStringAsFixed(1)}.',
        );
      }

      // Also confirm no FocusTraversalOrder widgets exist (would indicate
      // manual ordering that could hide bugs).
      expect(
        find.byType(FocusTraversalOrder),
        findsNothing,
        reason:
            'Found FocusTraversalOrder widget(s) — manual ordering present, '
            'test assumptions may not hold.',
      );
    });
  });
}
