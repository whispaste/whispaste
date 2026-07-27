import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/history/widgets/history_filter_chip.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/features/history/widgets/history_row_action.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry({String tags = '[]'}) => HistoryEntry(
  id: '1',
  content: 'Test content',
  title: 'Test title',
  timestamp: DateTime(2026, 4, 14),
  durationSec: 30.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: tags,
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
);

void main() {
  group('HistoryFilterChip keyboard access', () {
    testWidgets('is focusable via Tab and activates on Enter and Space', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: HistoryFilterChip(
              label: 'Pinned',
              icon: LucideIcons.star,
              isActive: false,
              isDark: true,
              onTap: () => taps++,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('tap/focus surface is at least minTouchTarget tall', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: HistoryFilterChip(
              label: 'All',
              isActive: true,
              isDark: true,
              onTap: () {},
            ),
          ),
        ),
      );

      final inkWellSize = tester.getSize(
        find.descendant(
          of: find.byType(HistoryFilterChip),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWellSize.height, greaterThanOrEqualTo(WpLayout.minTouchTarget));
    });
  });

  group('HistoryRowAction keyboard access', () {
    testWidgets('is focusable via Tab and activates on Enter', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: HistoryRowAction(
              icon: LucideIcons.star,
              tooltip: 'Pin to top',
              isDark: true,
              onTap: () => taps++,
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('Entry tag chips keyboard access', () {
    testWidgets('tag chip is focusable and activates onTagTap via Enter', (
      tester,
    ) async {
      String? tappedTag;
      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: _entry(tags: '["work"]'),
            isDark: true,
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onTagTap: (tag) => tappedTag = tag,
          ),
        ),
      );

      expect(find.text('#work'), findsOneWidget);

      // Row is neither hovered nor focused → the tag chip is the only
      // focusable element inside the row.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tappedTag, 'work');
    });

    testWidgets('tag chip without onTagTap is not focusable', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: _entry(tags: '["work"]'),
            isDark: true,
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.text('#work'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HistoryEntryRow),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });
  });
}
