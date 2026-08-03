import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

Note _sampleNote({
  required String id,
  required String content,
  bool pinned = false,
  DateTime? updatedAt,
}) {
  final t = updatedAt ?? DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: pinned,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('NotesPage — static fixtures (rendering)', () {
    testWidgets('shows the empty state when there are no notes', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesEmptyTitle), findsOneWidget);
      expect(find.text(l10n.notesEmptyHint), findsOneWidget);
    });

    testWidgets('renders a derived title and preview for each note', (
      tester,
    ) async {
      final notes = [
        _sampleNote(id: 'n1', content: 'Grocery list\nMilk, eggs, bread'),
        _sampleNote(id: 'n2', content: ''),
      ];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [notesProvider.overrideWith((ref) => Stream.value(notes))],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grocery list'), findsOneWidget);
      expect(find.text(l10n.notesUntitled), findsOneWidget);
    });

    testWidgets('tapping a note opens it in the editor', (tester) async {
      final notes = [_sampleNote(id: 'n1', content: 'Meeting notes')];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [notesProvider.overrideWith((ref) => Stream.value(notes))],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Meeting notes'), findsWidgets); // tile + editor title
    });
  });
}
