/// Every note row action carries a stable, language-independent key in the
/// `notes-<action>-<id>` scheme (DEV-41), so UI flows and agents can address
/// it without its localized tooltip. Duplicate and setting the quick-note
/// mark have no button (one action set per row: Copy, Star, Delete; #1498);
/// they keep their keys as context-menu items.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';

import '../../fixtures/test_helpers.dart';

Note _note({required bool isQuickNote}) => Note(
  archived: false,
  id: 'n1',
  content: 'Einkaufsliste',
  pinned: false,
  isQuickNote: isQuickNote,
  createdAt: DateTime(2026, 4, 14),
  updatedAt: DateTime(2026, 4, 14, 9, 41),
);

NotesListTile _tile({
  required bool isQuickNote,
  required bool isTrashView,
  VoidCallback? onDuplicate,
}) => NotesListTile(
  note: _note(isQuickNote: isQuickNote),
  tags: const [],
  isTrashView: isTrashView,
  isSelected: false,
  // Focus reveals the row actions without a pointer.
  isFocused: true,
  onTap: () {},
  onCopy: () {},
  onDuplicate: onDuplicate ?? () {},
  onFavoriteToggle: () {},
  onQuickNoteSet: () {},
  onQuickNoteClear: () {},
  onRestore: () {},
  onDeleteForever: () {},
  onMoveToTrash: () {},
);

Future<void> _pump(WidgetTester tester, Widget row) async {
  await tester.pumpWidget(
    makeTestable(SizedBox(width: 480, child: row), locale: const Locale('en')),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('active note row shows copy, star and delete only', (
    tester,
  ) async {
    await _pump(tester, _tile(isQuickNote: false, isTrashView: false));

    expect(find.byKey(const ValueKey('notes-favorite-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-copy-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-delete-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('notes-duplicate-n1')), findsNothing);
    expect(find.byKey(const ValueKey('notes-quick-note-set-n1')), findsNothing);
    expect(
      find.byKey(const ValueKey('notes-quick-note-clear-n1')),
      findsNothing,
    );
  });

  testWidgets('context menu offers duplicate and quick-note set', (
    tester,
  ) async {
    var duplicated = 0;
    await _pump(
      tester,
      _tile(
        isQuickNote: false,
        isTrashView: false,
        onDuplicate: () => duplicated++,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('notes-row-title-n1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('notes-quick-note-set-n1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('notes-duplicate-n1')));
    await tester.pumpAndSettle();
    expect(duplicated, 1);
  });

  testWidgets('quick note row exposes the clear mark instead of set', (
    tester,
  ) async {
    await _pump(tester, _tile(isQuickNote: true, isTrashView: false));

    expect(
      find.byKey(const ValueKey('notes-quick-note-clear-n1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('notes-quick-note-set-n1')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('notes-row-title-n1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notes-quick-note-set-n1')), findsNothing);
  });

  testWidgets('trash row exposes restore and delete forever', (tester) async {
    await _pump(tester, _tile(isQuickNote: false, isTrashView: true));

    expect(find.byKey(const ValueKey('notes-restore-n1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notes-delete-forever-n1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('notes-favorite-n1')), findsNothing);
    expect(find.byKey(const ValueKey('notes-delete-n1')), findsNothing);
  });
}
