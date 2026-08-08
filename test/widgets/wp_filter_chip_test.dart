import 'dart:io';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';

import '../fixtures/test_helpers.dart';

/// Anchors [WpFilterChip] as the app's single selectable filter chip. History
/// and Notes each carried their own copy of this pill — same padding, same
/// radius, same three state colors, same focus/touch-target scaffolding — and
/// the Notes copy said so in its own header comment. The tests below pin the
/// parts that would drift first if a third copy ever appeared: the three state
/// colors, the pill silhouette, the 48px tap surface and the semantics.

/// The pill's declared decoration (the AnimatedContainer's target values).
BoxDecoration _pillDecoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(WpFilterChip),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return container.decoration! as BoxDecoration;
}

Color _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!.color!;

/// Moves a mouse pointer onto the chip and settles the hover animation.
Future<void> _hover(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(find.byType(WpFilterChip)));
  await tester.pumpAndSettle();
}

Widget _chip({
  bool isActive = false,
  bool isDark = true,
  int? count,
  IconData? icon,
  VoidCallback? onTap,
}) => Center(
  child: WpFilterChip(
    label: 'All',
    icon: icon,
    isActive: isActive,
    isDark: isDark,
    count: count,
    onTap: onTap ?? () {},
  ),
);

void main() {
  group('WpFilterChip — the three states', () {
    testWidgets('resting uses the surface-variant fill and secondary label', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_chip()));
      await tester.pumpAndSettle();

      expect(_pillDecoration(tester).color, WpColorsDark.surfaceVariant);
      expect(_labelColor(tester, 'All'), WpColorsDark.textSecondary);
      expect(
        _pillDecoration(tester).border,
        isNull,
        reason: 'only the selected state carries an outline',
      );
    });

    testWidgets('hover lifts the fill to the hover surface and the label to '
        'primary text', (tester) async {
      await tester.pumpWidget(makeTestable(_chip()));
      await tester.pumpAndSettle();
      await _hover(tester);

      expect(_pillDecoration(tester).color, WpColorsDark.hover);
      expect(_labelColor(tester, 'All'), WpColorsDark.textPrimary);
    });

    testWidgets('selected uses the accent tint, the 30% accent outline and a '
        'heavier label', (tester) async {
      await tester.pumpWidget(makeTestable(_chip(isActive: true)));
      await tester.pumpAndSettle();

      expect(_pillDecoration(tester).color, WpColorsDark.accentSubtle);
      expect(
        (_pillDecoration(tester).border! as Border).top.color,
        WpColorsDark.accentBorder30,
      );
      expect(_labelColor(tester, 'All'), WpColorsDark.accent);
      expect(
        tester.widget<Text>(find.text('All')).style!.fontWeight,
        FontWeight.w600,
      );
    });

    testWidgets('the light theme resolves the same three states through its '
        'own token pair', (tester) async {
      await tester.pumpWidget(
        makeTestable(_chip(isDark: false), brightness: Brightness.light),
      );
      await tester.pumpAndSettle();
      expect(_pillDecoration(tester).color, WpColorsLight.surfaceVariant);
      expect(_labelColor(tester, 'All'), WpColorsLight.textSecondary);

      await _hover(tester);
      expect(_pillDecoration(tester).color, WpColorsLight.hover);
      expect(_labelColor(tester, 'All'), WpColorsLight.textPrimary);

      await tester.pumpWidget(
        makeTestable(
          _chip(isActive: true, isDark: false),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();
      expect(_pillDecoration(tester).color, WpColorsLight.accentSubtle);
      expect(_labelColor(tester, 'All'), WpColorsLight.accent);
    });
  });

  group('WpFilterChip — anatomy', () {
    testWidgets('stays a pill: the fully-round radius, not a card corner', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_chip()));
      await tester.pumpAndSettle();

      expect(_pillDecoration(tester).borderRadius, WpRadius.borderFull);
    });

    testWidgets('the tap surface is at least minTouchTarget tall while the '
        'pill itself stays compact', (tester) async {
      await tester.pumpWidget(makeTestable(_chip()));
      await tester.pumpAndSettle();

      final inkWell = tester.getSize(
        find.descendant(
          of: find.byType(WpFilterChip),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWell.height, greaterThanOrEqualTo(WpLayout.minTouchTarget));

      final pill = tester.getSize(
        find.descendant(
          of: find.byType(WpFilterChip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        pill.height,
        lessThan(WpLayout.minTouchTarget),
        reason: 'the visual pill must not inflate to the touch target',
      );
    });

    testWidgets('focus visuals belong to WpFocusRing, not to the InkWell', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_chip()));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(WpFilterChip),
          matching: find.byType(WpFocusRing),
        ),
        findsOneWidget,
      );

      final inkWell = tester.widget<InkWell>(
        find.descendant(
          of: find.byType(WpFilterChip),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWell.focusColor, Colors.transparent);
      expect(inkWell.hoverColor, Colors.transparent);
      expect(inkWell.splashColor, Colors.transparent);
      expect(inkWell.highlightColor, Colors.transparent);
    });

    testWidgets('is reachable by Tab and fires on Enter and Space', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(makeTestable(_chip(onTap: () => taps++)));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('carries label, button and selected in its semantics node', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_chip(isActive: true)));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(WpFilterChip));
      expect(node.label, contains('All'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
    });
  });

  group('WpFilterChip — optional count badge', () {
    testWidgets('renders no badge when count is null', (tester) async {
      await tester.pumpWidget(makeTestable(_chip()));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(WpFilterChip),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders the count beside the label when given', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_chip(count: 12)));
      await tester.pumpAndSettle();

      expect(find.text('12'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('12')).style!.fontSize,
        WpTypography.caption,
      );
    });

    testWidgets('a non-zero count on an unselected chip is accented, a zero '
        'one is not', (tester) async {
      await tester.pumpWidget(makeTestable(_chip(count: 3)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('3')).style!.color,
        WpColorsDark.accent,
      );

      await tester.pumpWidget(makeTestable(_chip(count: 0)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('0')).style!.color,
        isNot(WpColorsDark.accent),
      );
    });
  });

  group('WpFilterChip — enlarged system font', () {
    testWidgets('grows without overflowing at accessibility text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.0)),
              child: _chip(icon: LucideIcons.star, count: 42),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final pill = tester.getSize(
        find.descendant(
          of: find.byType(WpFilterChip),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        pill.height,
        greaterThan(WpLayout.minTouchTarget),
        reason:
            'given unbounded height, the pill scales with the text instead '
            'of clipping. This is a statement about the component only: a call '
            'site that caps its row (history wraps its filter list in a fixed '
            'SizedBox(height: minTouchTarget)) squeezes the pill back to 48 and '
            'the label spills silently — no exception, so no test catches it.',
      );
    });
  });

  group('WpFilterChip — single-source guard', () {
    test('no source file outside wp_filter_chip.dart declares its own filter '
        'chip class', () {
      // The pattern targets the class *declaration*: a widget whose name ends
      // in "FilterChip" is by definition another member of this family. Both
      // previous members (HistoryFilterChip, _NotesFilterChip) would have
      // matched it.
      final declaration = RegExp(r'class\s+\w*FilterChip\b');
      final offenders = <String>[];

      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'lib/ must exist');

      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path.endsWith('lib/widgets/wp_filter_chip.dart')) continue;
        if (declaration.hasMatch(entity.readAsStringSync())) {
          offenders.add(path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Filter chips belong to WpFilterChip (lib/widgets/wp_filter_chip'
            '.dart). It already takes an optional icon and an optional count '
            '— extend it rather than growing a second copy.',
      );
    });
  });
}
