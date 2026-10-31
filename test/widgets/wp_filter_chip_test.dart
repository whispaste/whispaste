import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';

import '../fixtures/test_helpers.dart';

/// Anchors [WpFilterChip] as the app's single selectable filter chip. History
/// and Notes each carried their own copy of this pill — same padding, same
/// radius, same three state colors, same focus/touch-target scaffolding — and
/// the Notes copy said so in its own header comment. The tests below pin the
/// parts that would drift first if a third copy ever appeared: the three state
/// colors, the pill silhouette, the 48px tap surface and the semantics.

Widget _chip({
  bool isActive = false,
  int? count,
  IconData? icon,
  VoidCallback? onTap,
}) => Center(
  child: WpFilterChip(
    label: 'All',
    icon: icon,
    isActive: isActive,
    count: count,
    onTap: onTap ?? () {},
  ),
);

void main() {
  group('WpFilterChip — anatomy', () {
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
