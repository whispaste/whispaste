/// Accessibility semantics tests for History-feature interactive widgets.
///
/// Verifies that key history widgets expose accessible names via
/// `find.bySemanticsLabel(...)` so screen readers can announce history actions.
///
/// Scope: widgets addressed in issue 02-a11y-semantics-history.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/providers.dart'
    show HistoryFilter;
import 'package:whispaste/features/history/widgets/history_date_header.dart';
import 'package:whispaste/features/history/widgets/history_helpers.dart';
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

  group('HistoryEntryRow — title announced once', () {
    testWidgets('the title appears exactly once in the merged label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            HistoryEntryRow(
              entry: _makeEntry(title: 'Quartalsbericht'),
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

        // The wrapper's `label:` is prepended to the subtree's own text, so
        // before the fix the rendered title contributed a second copy and the
        // row read "Quartalsbericht, Quartalsbericht, <preview>…". The preview
        // stays in the label on purpose — it is content, not a duplicate.
        final label = tester.getSemantics(find.byType(HistoryEntryRow)).label;
        expect('Quartalsbericht'.allMatches(label).length, 1);
      } finally {
        handle.dispose();
      }
    });
  });

  group('HistoryEntryRow — selected follows the arrow cursor', () {
    Future<SemanticsNode> pumpRow(
      WidgetTester tester, {
      required bool isSelected,
      required bool isFocused,
      bool multiSelectMode = false,
    }) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: _makeEntry(),
            isDark: true,
            isSelected: isSelected,
            isFocused: isFocused,
            multiSelectMode: multiSelectMode,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSemantics(find.byType(HistoryEntryRow));
    }

    testWidgets('the arrow-cursor row reports selected', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        // The list holds a single Focus node and the arrow keys move only an
        // optical highlight. Without this flag a screen reader reported no
        // change at all while arrowing — the row Enter/Delete would act on was
        // simply not announced.
        final node = await pumpRow(tester, isSelected: false, isFocused: true);
        expect(
          node.getSemanticsData().flagsCollection.isSelected,
          Tristate.isTrue,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a row the cursor has left does not also report selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        // Click row A (detail panel opens, isSelected), then arrow to row B.
        // Exactly one row may claim selected in single-select mode, so the
        // row the cursor left must drop the flag even though it is still the
        // entry shown in the detail panel.
        final node = await pumpRow(tester, isSelected: true, isFocused: false);
        expect(
          node.getSemanticsData().flagsCollection.isSelected,
          Tristate.isFalse,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('inside multi-select the flag reports the checked state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        // The cursor is suppressed in multi-select (history_list_view.dart:72)
        // and `isSelected` carries the checked state instead. Several rows
        // reporting selected is correct for a multi-selection.
        final node = await pumpRow(
          tester,
          isSelected: true,
          isFocused: false,
          multiSelectMode: true,
        );
        expect(
          node.getSemanticsData().flagsCollection.isSelected,
          Tristate.isTrue,
        );
      } finally {
        handle.dispose();
      }
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

  group('Empty-trash button — announced once', () {
    testWidgets('the caption is not repeated by a tooltip', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      try {
        await tester.pumpWidget(
          makeTestable(
            HistorySearchFilterBar(
              controller: controller,
              activeFilter: HistoryFilter.trash,
              isDark: true,
              onFilterChanged: (_) {},
              onSearchChanged: () {},
              resultCount: 3,
              viewMode: HistoryViewMode.list,
              onViewModeChanged: (_) {},
              multiSelectMode: false,
              onToggleMultiSelect: () {},
              sortOrder: HistorySortOrder.newest,
              onSortOrderChanged: (_) {},
              onEmptyTrash: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The caption is already on screen, so the tooltip that repeated it
        // word for word taught nothing and made the button announce itself
        // twice (label plus tooltip). House rule 1: fold, don't label.
        final semantics = tester.getSemantics(find.text('Empty Trash'));
        final data = semantics.getSemanticsData();
        expect(semantics.label, 'Empty Trash');
        expect(data.tooltip, isEmpty);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      } finally {
        handle.dispose();
      }
    });
  });

  group('HistoryDateHeader — group structure', () {
    testWidgets('both date headers are exposed as headers', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        // Both headers pumped at once, told apart by their labels: the compact
        // one upper-cases its text, so the two nodes stay addressable.
        await tester.pumpWidget(
          makeTestable(
            const Column(
              children: [
                HistoryDateHeader(label: 'Yesterday', isDark: true),
                HistoryCompactDateHeader(label: 'Today', isDark: true),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Without the flag the date reads as one more line of body text
        // between two entries, and header navigation cannot jump the groups.
        for (final label in ['Yesterday', 'TODAY']) {
          expect(
            tester
                .getSemantics(find.text(label))
                .getSemanticsData()
                .flagsCollection
                .isHeader,
            isTrue,
            reason: '"$label" must be exposed as a semantics header',
          );
        }
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
