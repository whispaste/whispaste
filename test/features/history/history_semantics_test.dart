/// Accessibility semantics tests for History-feature interactive widgets.
///
/// Verifies that key history widgets expose accessible names via
/// `find.bySemanticsLabel(...)` so screen readers can announce history actions.
///
/// Scope: widgets addressed in issue 02-a11y-semantics-history.
library;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';
import 'package:whispaste/widgets/wp_filter_chip.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';

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

  group('HistoryMultiSelectAction — batch action semantics', () {
    testWidgets('announces its caption exactly once', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            HistoryMultiSelectAction(
              icon: LucideIcons.merge,
              label: 'Merge',
              isDark: true,
              onTap: () {},
              shortcutHint: 'Ctrl+M',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Before the fix the wrapper carried `label: widget.label` while the
        // subtree still rendered `Text(widget.label)`. A wrapper label is
        // prepended to the subtree's text rather than replacing it, so the
        // batch bar announced every action twice ("Merge, Merge"). Asserting
        // equality — not `contains` — is the point of this test.
        final semantics = tester.getSemantics(
          find.byType(HistoryMultiSelectAction),
        );
        expect(semantics.label, 'Merge');
        // The fold must not cost the control its role or its tap action, and
        // the shortcut hint has to survive as the tooltip — that hint is how
        // the keyboard-first audience learns the accelerator at all.
        final data = semantics.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.tooltip, 'Merge (Ctrl+M)');
      } finally {
        handle.dispose();
      }
    });
  });

  group('WpFilterChip — filter chip semantics', () {
    testWidgets('WpFilterChip semantics node carries label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpFilterChip(
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
      final semantics = tester.getSemantics(find.byType(WpFilterChip));
      expect(
        semantics.label,
        contains('All'),
        reason: 'WpFilterChip semantics label must contain the chip label',
      );
    });
  });
}
