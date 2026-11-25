/// The note row's archive handover (#656): an active row offers "Archive" in
/// its context menu, an archived row offers "Unarchive" and no favourite
/// star, and the trash offers neither.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';

import '../../fixtures/test_helpers.dart';

Note _note({required bool archived}) => Note(
  archived: archived,
  id: 'n1',
  content: 'Einkaufsliste',
  pinned: true,
  isQuickNote: false,
  createdAt: DateTime(2026, 4, 14),
  updatedAt: DateTime(2026, 4, 14, 9, 41),
);

Future<void> _pump(
  WidgetTester tester, {
  required bool archived,
  bool isTrashView = false,
  VoidCallback? onToggleArchive,
}) async {
  await tester.pumpWidget(
    makeTestable(
      SizedBox(
        width: 480,
        child: NotesListTile(
          note: _note(archived: archived),
          tags: const [],
          isTrashView: isTrashView,
          isSelected: false,
          isFocused: true,
          onTap: () {},
          onCopy: () {},
          onDuplicate: () {},
          onFavoriteToggle: () {},
          onQuickNoteSet: () {},
          onQuickNoteClear: () {},
          onRestore: () {},
          onDeleteForever: () {},
          onMoveToTrash: () {},
          onToggleArchive: isTrashView ? null : onToggleArchive ?? () {},
        ),
      ),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('notes-row-title-n1')),
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('an active row archives from its context menu', (tester) async {
    var toggled = 0;
    await _pump(tester, archived: false, onToggleArchive: () => toggled++);

    await _openMenu(tester);
    expect(find.byKey(const ValueKey('notes-unarchive-n1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notes-archive-n1')));
    await tester.pumpAndSettle();
    expect(toggled, 1);
  });

  testWidgets('an archived row unarchives and carries no favourite', (
    tester,
  ) async {
    var toggled = 0;
    await _pump(tester, archived: true, onToggleArchive: () => toggled++);

    expect(find.byKey(const ValueKey('notes-favorite-n1')), findsNothing);
    expect(find.byKey(const ValueKey('notes-favourite-mark-n1')), findsNothing);
    await _openMenu(tester);
    expect(find.byKey(const ValueKey('notes-archive-n1')), findsNothing);
    expect(find.byKey(const ValueKey('notes-quick-note-set-n1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notes-unarchive-n1')));
    await tester.pumpAndSettle();
    expect(toggled, 1);
  });

  testWidgets('the trash offers no archive action', (tester) async {
    await _pump(tester, archived: true, isTrashView: true);

    await _openMenu(tester);
    expect(find.byKey(const ValueKey('notes-archive-n1')), findsNothing);
    expect(find.byKey(const ValueKey('notes-unarchive-n1')), findsNothing);
  });
}
