/// The favourites section of the note list folds and unfolds (#830): the
/// toggle head carries a stable key, hides the pinned rows, and the choice is
/// kept.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/notes_list_view.dart';

import '../../fixtures/test_helpers.dart';

Note _note(String id, {bool pinned = false}) => Note(
  id: id,
  content: 'Inhalt $id',
  pinned: pinned,
  isQuickNote: false,
  createdAt: DateTime(2026, 4, 14),
  updatedAt: DateTime(2026, 4, 14, 9),
);

NotesListView _list(List<Note> notes, {bool isSearch = false}) => NotesListView(
  notes: notes,
  tagsByNoteId: const {},
  isTrashView: false,
  isSearch: isSearch,
  selectedId: null,
  focusedId: null,
  onNoteTap: (_) {},
  onCopy: (_) {},
  onDuplicate: (_) {},
  onFavoriteToggle: (_) {},
  onQuickNoteSet: (_) {},
  onQuickNoteClear: () {},
  onRestore: (_) {},
  onDeleteForever: (_) {},
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await L10n.delegate.load(const Locale('en'));
  });

  final notes = [_note('p', pinned: true), _note('a')];
  const toggle = ValueKey('notes-favorites-toggle');

  testWidgets('the toggle hides and shows the pinned rows', (tester) async {
    await tester.pumpWidget(
      makeTestable(_list(notes), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('p')), findsOneWidget);
    expect(find.byKey(const ValueKey('a')), findsOneWidget);

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('p')), findsNothing);
    expect(find.byKey(const ValueKey('a')), findsOneWidget);

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('p')), findsOneWidget);
  });

  testWidgets('a hit list has no favourites head and nothing folds', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(_list(notes, isSearch: true), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(toggle), findsNothing);
    expect(find.byKey(const ValueKey('p')), findsOneWidget);
  });

  testWidgets('no pinned note, no favourites head', (tester) async {
    await tester.pumpWidget(
      makeTestable(_list([_note('a')]), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(toggle), findsNothing);
  });
}
