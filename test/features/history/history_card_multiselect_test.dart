/// Regression guard for a silent multi-select hole in the card view.
///
/// `HistoryEntryCard` accepted `multiSelectMode` and the per-entry checked
/// flag but its `build` referenced neither, so the card grid was the one view
/// mode where batch selection was completely invisible: Ctrl+A filled the
/// action bar with "n selected" while every card kept its resting look, and
/// the Delete that followed hit a set the user had no way to see.
///
/// `flutter analyze` does not flag an unused *widget field*, which is why this
/// needs a test rather than a lint.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_card_view.dart';
import 'package:whispaste/widgets/wp_row_action.dart';
import 'package:whispaste/widgets/wp_row_checkbox.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry({String id = '1', String title = 'Kartentitel'}) {
  return HistoryEntry(
    id: id,
    content: 'Inhalt der Aufnahme',
    title: title,
    timestamp: DateTime(2026, 4, 14),
    durationSec: 30.0,
    processingDurationSec: 1.0,
    language: 'de',
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
    colorSlot: 0,
  );
}

void main() {
  group('HistoryEntryCard multi-select', () {
    testWidgets('renders no checkbox outside multi-select', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryEntryCard(
            entry: _entry(),
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            multiSelectMode: false,
            isChecked: false,
          ),
        ),
      );

      expect(find.byType(WpRowCheckbox), findsNothing);
    });

    testWidgets('shows a checked checkbox for a selected card', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryEntryCard(
            entry:
                _entry(), // The prop is overloaded exactly like the list/compact views: in
            // multi-select it means "checked", not "open in the detail panel".
            isSelected: true,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            multiSelectMode: true,
            isChecked: true,
          ),
        ),
      );

      final checkbox = tester.widget<WpRowCheckbox>(find.byType(WpRowCheckbox));
      expect(checkbox.value, isTrue);
    });

    testWidgets('hides the per-card row actions while multi-selecting', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          HistoryEntryCard(
            entry: _entry(),
            isSelected: true,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            multiSelectMode: true,
            isChecked: true,
          ),
        ),
      );

      // A per-card Delete sitting next to a live batch selection is an easy
      // misfire, so the reveal is suppressed the same way it is in the list
      // and compact views.
      final actions = tester.widget<WpRowActions>(find.byType(WpRowActions));
      expect(actions.visible, isFalse);
    });
  });
}
