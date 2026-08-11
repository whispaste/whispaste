import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';
import 'package:whispaste/features/history/widgets/tag_management_dialog.dart';

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
  colorSlot: 0,
);

void main() {
  group('WpFilterChip keyboard access', () {
    testWidgets('is focusable via Tab and activates on Enter and Space', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: WpFilterChip(
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
            child: WpFilterChip(
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
          of: find.byType(WpFilterChip),
          matching: find.byType(InkWell),
        ),
      );
      expect(inkWellSize.height, greaterThanOrEqualTo(WpLayout.minTouchTarget));
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

  group('HistoryViewModeToggle keyboard access', () {
    testWidgets('each segment is reachable by Tab and fires on Enter', (
      tester,
    ) async {
      HistoryViewMode? picked;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: HistoryViewModeToggle(
              viewMode: HistoryViewMode.list,
              isDark: true,
              onChanged: (mode) => picked = mode,
            ),
          ),
        ),
      );

      // Second stop in the Tab order is the middle segment; before the fix
      // there was no stop at all — the toggle was a bare GestureDetector.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(picked, HistoryViewMode.cards);
    });

    testWidgets('only the active segment reports selected', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: HistoryViewModeToggle(
                viewMode: HistoryViewMode.compact,
                isDark: true,
                onChanged: (_) {},
              ),
            ),
          ),
        );

        // The segments carry icons only, so without the flag all three
        // announce the same whichever view is on.
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Compact'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('List'))
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isFalse,
        );
      } finally {
        handle.dispose();
      }
    });
  });

  group('HistoryDetailAction keyboard access', () {
    testWidgets('is focusable via Tab and activates on Enter', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: HistoryDetailAction(
              icon: LucideIcons.copy,
              tooltip: 'Copy',
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

  group('Tag management — delete button reveal', () {
    testWidgets('the delete button becomes visible on focus, not just hover', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.createTag('work');

      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showTagManagementDialog(
                context: context,
                db: db,
                isDark: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('work'), findsOneWidget);

      // The dialog carries other icon buttons, so the row's delete button is
      // addressed by its own icon.
      final deleteButton = find.widgetWithIcon(IconButton, LucideIcons.trash2);
      final opacity = find
          .ancestor(of: deleteButton, matching: find.byType(AnimatedOpacity))
          .first;
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0.0);

      // Focus is requested directly rather than tabbed to: the assertion is
      // about what a focused delete button looks like, not about where it sits
      // in the dialog's tab order.
      tester.widget<IconButton>(deleteButton).focusNode!.requestFocus();
      await tester.pumpAndSettle();

      // Before the fix this stayed 0.0 — Tab parked the caret on an invisible
      // destructive control, once per tag row.
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1.0);
    });
  });
}
