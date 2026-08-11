import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';

import '../../fixtures/test_helpers.dart';

/// `NotesPage` now also has a search `TextField` (Ticket 06) alongside the
/// editor's — scope finders to the editor panel where a test cares
/// specifically about the note body/tag input, not the search field.
Finder _editorTextFields() => find.descendant(
  of: find.byType(NoteEditorPanel),
  matching: find.byType(TextField),
);

late L10n l10n;

/// Every widget test that pumps [NotesPage] must override these two alongside
/// `notesProvider`/`trashNotesProvider` — left un-overridden, they fall
/// through to real Drift `.watch()` queries (even against the in-memory test
/// db from `makeTestable`), whose stream-cleanup schedules a Timer on
/// disposal that flutter_test's pending-timer check then trips.
List<Object> get _noTagOverrides => [
  allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
  noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
];

Tag _sampleTag(String id, String name) =>
    Tag(id: id, name: name, createdAt: DateTime(2025, 6, 1));

/// Records calls instead of hitting the DB, so a widget test can assert
/// _which_ note/tag `_NotesPageState`'s `onAddTag`/`onRemoveTag` closures were
/// invoked with — everything else (`purgeEmpty` from `initState`, etc.) still
/// needs a real, harmless backing db.
class _RecordingActions extends NotesActions {
  _RecordingActions(super.db);

  (String noteId, String tagName)? lastAddTag;
  (String noteId, String tagId)? lastRemoveTag;

  @override
  Future<void> addTag(String noteId, String tagName) async {
    lastAddTag = (noteId, tagName);
  }

  @override
  Future<void> removeTag(String noteId, String tagId) async {
    lastRemoveTag = (noteId, tagId);
  }
}

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
    isQuickNote: false,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

/// Parks a synthetic mouse pointer on [finder]. Row actions reveal on hover
/// or focus app-wide (see WpRowAction's library comment), so a trash row's
/// restore/delete-forever buttons only exist once the row is pointed at.
Future<void> _hoverRow(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(() => gesture.removePointer());
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pumpAndSettle();
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
            ..._noTagOverrides,
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
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
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
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Meeting notes'));
      await tester.pumpAndSettle();

      expect(_editorTextFields(), findsOneWidget);
      expect(find.text('Meeting notes'), findsWidgets); // tile + editor title
    });
  });

  group('NotesPage — favorite/trash/restore (Ticket 04)', () {
    testWidgets('switching to the trash filter shows the trash empty state', (
      tester,
    ) async {
      final activeNotes = [_sampleNote(id: 'n1', content: 'Active note')];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(activeNotes)),
            trashNotesProvider.overrideWith((ref) => Stream.value(const [])),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.notesTrash));
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesTrashEmpty), findsOneWidget);
      expect(find.text(l10n.notesTrashEmptyHint), findsOneWidget);
    });

    testWidgets(
      'trash view shows restore/delete-forever, not the favorite star',
      (tester) async {
        final trashedNotes = [_sampleNote(id: 'n1', content: 'Trashed note')];

        await tester.pumpWidget(
          makeTestable(
            const NotesPage(),
            overrides: [
              notesProvider.overrideWith((ref) => Stream.value(const [])),
              trashNotesProvider.overrideWith(
                (ref) => Stream.value(trashedNotes),
              ),
              ..._noTagOverrides,
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(l10n.notesTrash));
        await tester.pumpAndSettle();
        await _hoverRow(tester, find.byType(NotesListTile).first);

        expect(find.byTooltip(l10n.notesRestore), findsOneWidget);
        expect(find.byTooltip(l10n.notesDeleteForever), findsOneWidget);
        expect(find.byTooltip(l10n.notesFavorite), findsNothing);
      },
    );

    testWidgets('deleting forever asks for confirmation before deleting', (
      tester,
    ) async {
      final trashedNotes = [_sampleNote(id: 'n1', content: 'Trashed note')];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(const [])),
            trashNotesProvider.overrideWith(
              (ref) => Stream.value(trashedNotes),
            ),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.notesTrash));
      await tester.pumpAndSettle();
      await _hoverRow(tester, find.byType(NotesListTile).first);

      await tester.tap(find.byTooltip(l10n.notesDeleteForever));
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesDeleteForeverConfirm), findsOneWidget);

      // Cancel — dialog dismisses, note is untouched.
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesDeleteForeverConfirm), findsNothing);
    });

    testWidgets('moving the open note to trash shows an undo toast', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'Some note')];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            trashNotesProvider.overrideWith((ref) => Stream.value(const [])),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Some note'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.notesMoveToTrash));
      await tester.pump();

      expect(find.text(l10n.notesMovedToTrash), findsOneWidget);
      expect(find.text(l10n.notesUndo), findsOneWidget);

      // Drain the toast's 4s auto-dismiss timer so no Timer outlives the test.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('favorite star reflects the pinned state', (tester) async {
      final notes = [
        _sampleNote(id: 'n1', content: 'Pinned note', pinned: true),
      ];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip(l10n.notesUnfavorite), findsOneWidget);
      expect(find.byTooltip(l10n.notesFavorite), findsNothing);
    });
  });

  group('NotesPage — tags (Ticket 05)', () {
    testWidgets('shows tag pills for a tagged note in the tile and editor', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];
      final workTag = _sampleTag('t1', 'work');

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            allNoteTagsProvider.overrideWith(
              (ref) => Stream.value({
                'n1': [workTag],
              }),
            ),
            noteTagsProvider.overrideWith(
              (ref, noteId) =>
                  Stream.value(noteId == 'n1' ? [workTag] : const []),
            ),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Tile shows the compact "#work" pill.
      expect(find.text('#work'), findsOneWidget);

      await tester.tap(find.text('Grocery list'));
      await tester.pumpAndSettle();

      // Editor's WpTagInput shows the plain tag name (no "#" prefix).
      expect(find.text('work'), findsOneWidget);
    });

    testWidgets('adding a tag calls NotesActions.addTag for the open note', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _RecordingActions(db);
      addTearDown(db.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grocery list'));
      await tester.pumpAndSettle();

      // Reveal the inline tag input, type a name, confirm with Enter.
      await tester.tap(find.text(l10n.notesAddTag));
      await tester.pumpAndSettle();
      // The inline tag field renders above the divider/main editor TextField
      // within NoteEditorPanel — `.first` there is the tag input, not the
      // note body (scoped to exclude the page's separate search TextField).
      await tester.enterText(_editorTextFields().first, 'errands');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(actions.lastAddTag, ('n1', 'errands'));
    });

    testWidgets(
      'removing a tag calls NotesActions.removeTag for the open note',
      (tester) async {
        final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];
        final workTag = _sampleTag('t1', 'work');
        final db = HistoryDatabase.forTesting(NativeDatabase.memory());
        final actions = _RecordingActions(db);
        addTearDown(db.close);

        await tester.pumpWidget(
          makeTestable(
            const NotesPage(),
            overrides: [
              notesProvider.overrideWith((ref) => Stream.value(notes)),
              notesActionsProvider.overrideWith((ref) => actions),
              allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
              noteTagsProvider.overrideWith(
                (ref, noteId) =>
                    Stream.value(noteId == 'n1' ? [workTag] : const []),
              ),
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Grocery list'));
        await tester.pumpAndSettle();

        await tester.tap(find.bySemanticsLabel('Remove work'));
        await tester.pumpAndSettle();

        expect(actions.lastRemoveTag, ('n1', 't1'));
      },
    );
  });

  group('NotesPage — search (Ticket 06)', () {
    testWidgets('typing in the search field filters the list by content', (
      tester,
    ) async {
      final notes = [
        _sampleNote(id: 'n1', content: 'Grocery list'),
        _sampleNote(id: 'n2', content: 'Meeting agenda'),
      ];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grocery list'), findsOneWidget);
      expect(find.text('Meeting agenda'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'grocery');
      await tester.pumpAndSettle();

      expect(find.text('Grocery list'), findsOneWidget);
      expect(find.text('Meeting agenda'), findsNothing);
    });

    testWidgets('shows the no-results empty state for a non-matching query', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesNoResults), findsOneWidget);
      expect(find.text(l10n.notesNoResultsHint('nonexistent')), findsOneWidget);
    });

    testWidgets('clearing the search restores the original list', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();
      expect(find.text(l10n.notesNoResults), findsOneWidget);

      await tester.tap(find.text(l10n.actionClearSearch));
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesNoResults), findsNothing);
      expect(find.text('Grocery list'), findsOneWidget);
    });

    testWidgets('shows a result count only while searching', (tester) async {
      final notes = [
        _sampleNote(id: 'n1', content: 'Grocery list'),
        _sampleNote(id: 'n2', content: 'Meeting agenda'),
      ];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesResultCount(1)), findsNothing);

      await tester.enterText(find.byType(TextField), 'grocery');
      await tester.pumpAndSettle();

      expect(find.text(l10n.notesResultCount(1)), findsOneWidget);
    });

    testWidgets('Ctrl/Cmd+F focuses the search field', (tester) async {
      final notes = [_sampleNote(id: 'n1', content: 'Grocery list')];

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(
        tester.widget<TextField>(searchField).focusNode!.hasFocus,
        isFalse,
        reason: 'Field must not have focus before the shortcut',
      );

      // The shortcut binding checks the real OS (`dart:io Platform.isMacOS`),
      // not Flutter's `defaultTargetPlatform` test override — match that.
      // Vorbild: settings_search_keyboard_a11y_test.dart (separate down/up
      // for the letter key, not the combined `sendKeyEvent`).
      if (Platform.isMacOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      }
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(searchField).focusNode!.hasFocus,
        isTrue,
        reason: 'Field must have focus after the shortcut',
      );
    });
  });
}
