/// Accessibility semantics tests for Notizen-feature interactive widgets
/// (Ticket 09). Vorbild `history_semantics_test.dart`.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/providers.dart' show NotesFilter;
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/features/notes/widgets/notes_search_bar.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

Note _note({
  String content = 'Grocery list\nMilk, eggs',
  bool pinned = false,
  DateTime? deletedAt,
}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: 'n1',
    content: content,
    pinned: pinned,
    deletedAt: deletedAt,
    createdAt: t,
    updatedAt: t,
  );
}

Widget _buildTile({
  bool trashView = false,
  bool isFocused = false,
  bool pinned = false,
}) {
  return NotesListTile(
    note: _note(
      pinned: pinned,
      deletedAt: trashView ? DateTime(2025, 6, 2) : null,
    ),
    tags: const [],
    isDark: true,
    isTrashView: trashView,
    isSelected: false,
    isFocused: isFocused,
    onTap: () {},
    onFavoriteToggle: () {},
    onRestore: () {},
    onDeleteForever: () {},
  );
}

Widget _buildPanel({bool trashed = false}) {
  final controller = TextEditingController(text: 'Some content');
  final focusNode = FocusNode();
  return NoteEditorPanel(
    note: _note(deletedAt: trashed ? DateTime(2025, 6, 2) : null),
    tags: const [],
    isDark: true,
    controller: controller,
    focusNode: focusNode,
    onClose: () {},
    onToggleFavorite: () {},
    onMoveToTrash: () {},
    onRestore: () {},
    onDeleteForever: () {},
    onAddTag: (_) {},
    onRemoveTag: (_) {},
    onExport: () {},
    onVoiceTranscript: (_) {},
  );
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('NotesListTile — tile semantics', () {
    testWidgets('exposes the derived title as a semantics label', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_buildTile()));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('Grocery list')),
        findsWidgets,
        reason: 'NotesListTile must expose its derived title as a label',
      );
    });

    testWidgets('uses the notesUntitled fallback label for blank content', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          NotesListTile(
            note: _note(content: '   '),
            tags: const [],
            isDark: true,
            isTrashView: false,
            isSelected: false,
            isFocused: false,
            onTap: () {},
            onFavoriteToggle: () {},
            onRestore: () {},
            onDeleteForever: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(RegExp(l10n.notesUntitled)), findsWidgets);
    });

    testWidgets('exposes SemanticsFlag.isFocused when isFocused is true', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_buildTile(isFocused: true)));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(NotesListTile));
      expect(semantics.flagsCollection.isFocused, Tristate.isTrue);
    });

    testWidgets('does not expose the focused flag otherwise', (tester) async {
      await tester.pumpWidget(makeTestable(_buildTile()));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(NotesListTile));
      expect(semantics.flagsCollection.isFocused, isNot(Tristate.isTrue));
    });

    testWidgets('favourite toggle exposes its tooltip as a semantics label', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_buildTile()));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(l10n.notesFavorite), findsOneWidget);
    });

    testWidgets(
      'trash view exposes restore/delete-forever as semantics labels',
      (tester) async {
        await tester.pumpWidget(makeTestable(_buildTile(trashView: true)));
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel(l10n.notesRestore), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.notesDeleteForever), findsOneWidget);
      },
    );
  });

  group('NoteEditorPanel — toolbar action semantics', () {
    testWidgets(
      'exposes copy/export/mic/favourite/trash/close as semantics labels',
      (tester) async {
        await tester.pumpWidget(makeTestable(_buildPanel()));
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel(l10n.notesCopy), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.notesExport), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.voiceNoteButton), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.notesFavorite), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.notesMoveToTrash), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.historyClose), findsOneWidget);
      },
    );

    testWidgets(
      'trash view exposes restore/delete-forever as semantics labels',
      (tester) async {
        await tester.pumpWidget(makeTestable(_buildPanel(trashed: true)));
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel(l10n.notesRestore), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.notesDeleteForever), findsOneWidget);
      },
    );
  });

  group('NotesSearchBar — clear button semantics', () {
    testWidgets('exposes its tooltip as a semantics label, not just a hint', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          NotesSearchBar(
            currentFilter: NotesFilter.active,
            onFilterChanged: (_) {},
            isDark: true,
            searchController: TextEditingController(text: 'grocery'),
            searchFocusNode: FocusNode(),
            onSearchChanged: () {},
            resultCount: 1,
            showResultCount: true,
            onCreate: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(l10n.notesClearSearch), findsOneWidget);
    });
  });
}
