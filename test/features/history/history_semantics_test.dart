/// Accessibility semantics tests for History-feature interactive widgets.
///
/// Verifies that key history widgets expose accessible names via
/// `find.bySemanticsLabel(...)` so screen readers can announce history actions.
///
/// Scope: widgets addressed in issue 02-a11y-semantics-history.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/features/history/widgets/history_filter_chip.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/features/history/widgets/history_row_action.dart';

import '../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

HistoryEntry _makeEntry({String title = 'Test entry'}) => HistoryEntry(
  id: '1',
  content: 'Some transcribed content',
  title: title,
  timestamp: DateTime(2026, 4, 14, 10, 30),
  durationSec: 30.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HistoryEntryRow — row semantics', () {
    testWidgets('exposes entry title as semantics label', (tester) async {
      final entry = _makeEntry(title: 'My important note');

      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: entry,
            isDark: true,
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The Semantics wrapper on HistoryEntryRow merges with inner content,
      // so we use a substring RegExp to verify the title is part of the label.
      expect(
        find.bySemanticsLabel(RegExp('My important note')),
        findsWidgets,
        reason:
            'HistoryEntryRow must expose its entry title as a semantics label',
      );
    });

    testWidgets('uses fallback label for untitled entry', (tester) async {
      final entry = _makeEntry(title: '');

      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: entry,
            isDark: true,
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 'Untitled recording' is the en l10n fallback.
      expect(
        find.bySemanticsLabel(RegExp('Untitled recording')),
        findsWidgets,
        reason: 'Untitled HistoryEntryRow must use l10n fallback as label',
      );
    });

    testWidgets('HistoryEntryRow semantics node carries entry title', (
      tester,
    ) async {
      final entry = _makeEntry(title: 'My important note');

      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: entry,
            isDark: true,
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // tester.getSemantics returns the merged semantics label for the widget.
      final semantics = tester.getSemantics(find.byType(HistoryEntryRow));
      expect(
        semantics.label,
        contains('My important note'),
        reason: 'HistoryEntryRow semantics label must contain the entry title',
      );
    });
  });

  group('HistoryRowAction — action button semantics', () {
    testWidgets('exposes tooltip as semantics label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryRowAction(
            icon: LucideIcons.copy,
            tooltip: 'Copy text',
            isDark: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Copy text'),
        findsOneWidget,
        reason: 'HistoryRowAction must expose its tooltip as a semantics label',
      );
    });
  });

  group('HistoryDetailAction — detail panel action semantics', () {
    testWidgets('exposes tooltip as semantics label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryDetailAction(
            icon: LucideIcons.undo2,
            tooltip: 'Restore',
            isDark: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Restore'),
        findsOneWidget,
        reason:
            'HistoryDetailAction must expose its tooltip as a semantics label',
      );
    });
  });

  group('HistoryFilterChip — filter chip semantics', () {
    testWidgets('HistoryFilterChip semantics node carries label', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryFilterChip(
            label: 'All',
            isActive: true,
            onTap: () {},
            isDark: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The Semantics wrapper merges with the inner Text("All"),
      // so tester.getSemantics is the authoritative way to assert the label.
      final semantics = tester.getSemantics(find.byType(HistoryFilterChip));
      expect(
        semantics.label,
        contains('All'),
        reason: 'HistoryFilterChip semantics label must contain the chip label',
      );
    });
  });
}
