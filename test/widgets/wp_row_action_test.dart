import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';
import 'package:whispaste/widgets/wp_row_action.dart';
import 'package:whispaste/widgets/wp_row_checkbox.dart';

import '../fixtures/test_helpers.dart';

/// Moves a synthetic mouse onto [finder] and leaves it there for the rest of
/// the test. Returns once the hover transition has run.
Future<void> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(() => gesture.removePointer());
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Color _iconColor(WidgetTester tester) =>
    tester.widget<Icon>(find.byType(Icon).first).color!;

void main() {
  group('WpRowAction — semantics and keyboard', () {
    testWidgets('exposes its tooltip as the semantics label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpRowAction(
            icon: LucideIcons.copy,
            tooltip: 'Copy text',
            isDark: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Copy text'), findsOneWidget);
    });

    testWidgets(
      'is focusable via Tab, activates on Enter, shows a focus ring',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: WpRowAction(
                icon: LucideIcons.star,
                tooltip: 'Pin to top',
                isDark: true,
                onTap: () => taps++,
              ),
            ),
          ),
        );

        expect(
          find.byType(WpFocusRing),
          findsOneWidget,
          reason:
              'focus must be drawn by WpFocusRing — one highlight per state',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(taps, 1);
      },
    );
  });

  group('WpRowAction — destructive colour follows the theme', () {
    for (final isDark in [true, false]) {
      final label = isDark ? 'dark' : 'light';
      testWidgets('destructive action turns error-red on hover ($label)', (
        tester,
      ) async {
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: WpRowAction(
                icon: LucideIcons.trash2,
                tooltip: 'Delete',
                isDark: isDark,
                isDestructive: true,
                onTap: () {},
              ),
            ),
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
        );

        final muted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
        expect(
          _iconColor(tester),
          muted,
          reason: 'at rest a destructive action is as quiet as any other',
        );

        await _hover(tester, find.byType(WpRowAction));

        expect(
          _iconColor(tester),
          isDark ? WpColorsDark.error : WpColorsLight.error,
          reason: 'each theme must contribute its own error colour',
        );
      });
    }
  });

  group('WpRowActions — reveal without reflow', () {
    Widget group({required bool visible, bool dense = false}) => Center(
      child: SizedBox(
        width: 200,
        child: Row(
          children: [
            const Expanded(child: Text('Title')),
            WpRowActions(
              visible: visible,
              dense: dense,
              children: [
                WpRowAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Copy',
                  isDark: true,
                  onTap: () {},
                  dense: dense,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    for (final dense in [false, true]) {
      testWidgets('keeps its height while hidden (dense: $dense)', (
        tester,
      ) async {
        await tester.pumpWidget(
          makeTestable(group(visible: false, dense: dense)),
        );
        await tester.pumpAndSettle();
        final hidden = tester.getSize(find.byType(WpRowActions));

        await tester.pumpWidget(
          makeTestable(group(visible: true, dense: dense)),
        );
        await tester.pumpAndSettle();
        final shown = tester.getSize(find.byType(WpRowActions));

        expect(
          hidden.height,
          shown.height,
          reason: 'revealing actions must never change the row height',
        );
        expect(
          shown.height,
          WpRowAction.extentFor(dense: dense),
          reason: 'the reserved height is the action extent',
        );
        expect(
          hidden.width,
          0,
          reason: 'hidden actions give their width back to the title',
        );
        expect(shown.width, greaterThan(0));
      });
    }

    testWidgets('renders no action button while hidden', (tester) async {
      await tester.pumpWidget(makeTestable(group(visible: false)));
      await tester.pumpAndSettle();
      expect(find.byType(WpRowAction), findsNothing);
    });

    testWidgets('stays revealed while one of its actions holds focus', (
      tester,
    ) async {
      // Revealed by hover first, then the pointer state drops away while a
      // button still owns keyboard focus — the group must not collapse.
      await tester.pumpWidget(makeTestable(group(visible: true)));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byType(WpRowAction), findsOneWidget);

      await tester.pumpWidget(makeTestable(group(visible: false)));
      await tester.pumpAndSettle();

      expect(
        find.byType(WpRowAction),
        findsOneWidget,
        reason: 'collapsing under a focused button would strand the focus',
      );
    });
  });

  group('WpRowCheckbox', () {
    testWidgets('is 24x24 and reports taps', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: WpRowCheckbox(
              value: false,
              isDark: true,
              onChanged: () => toggles++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(WpRowCheckbox)),
        const Size(WpRowCheckbox.extent, WpRowCheckbox.extent),
      );

      await tester.tap(find.byType(WpRowCheckbox));
      await tester.pump();
      expect(toggles, 1);
    });
  });
}
