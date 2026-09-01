import 'dart:async';
import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/features/notes/widgets/quick_note_hotkey_line.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

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
  bool isQuickNote = false,
  DateTime? deletedAt,
  DateTime? updatedAt,
}) {
  final t = updatedAt ?? DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: pinned,
    isQuickNote: isQuickNote,
    deletedAt: deletedAt,
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

    testWidgets(
      'a brand-new note lands focus in the body field, ready to type',
      (tester) async {
        // notesProvider is deliberately NOT overridden with Stream.value here
        // (unlike every other test in this file): a synchronous stream can't
        // reproduce the real app's async gap between _actions.create()'s
        // write and db.watchNotes() re-emitting with the new row — that gap
        // is exactly what races against _createNote()'s single
        // requestFocus() call. makeTestable's default historyDatabaseProvider
        // override (a real in-memory Drift db) reproduces it.
        await tester.pumpWidget(
          makeTestable(
            const NotesPage(),
            overrides: _noTagOverrides,
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        // Seed one existing note through the real UI, matching the bug
        // report (the user already has notes before hitting this). The
        // empty state shows two "New note" buttons (header + empty-state
        // action, see the comment at its actionLabel) — `.first` picks either.
        await tester.tap(find.text(l10n.notesNewNote).first);
        await tester.pumpAndSettle();
        expect(_editorTextFields(), findsOneWidget);

        // Now create the SECOND note — the reported scenario.
        await tester.tap(find.text(l10n.notesNewNote).first);
        await tester.pumpAndSettle();

        expect(_editorTextFields(), findsOneWidget);
        final focusNode = tester
            .widget<TextField>(_editorTextFields())
            .focusNode;
        expect(
          focusNode?.hasFocus,
          isTrue,
          reason:
              'a brand-new note must land the caret in the body field '
              "immediately, same as the app's always-focused editor design "
              '(CONTEXT.md §5.9) — without focus, keystrokes never reach the '
              'field at all, which is exactly the reported "field is locked" '
              'symptom.',
        );

        // NOTE (diagnosing-bugs session, 2026-08-12): this asserts focus
        // only. An attempt to tighten this into an input-DELIVERY probe via
        // tester.testTextInput.enterText() was abandoned — a control test
        // doing the same thing on an already-working existing note also
        // failed to see the typed text land, proving that API isn't wired to
        // this app's text field in this harness (false red, not a real
        // repro). This test is therefore a NEGATIVE result only: it proves
        // focus itself isn't the broken part (see git history / session
        // notes for the live-GUI evidence — the focus ring is visibly
        // present on a genuinely stuck field), not a reproduction of the
        // reported bug. Left in as a regression guard for the focus path.

        // Unmount before the test ends and pump once more: real
        // db.watchNotes() streams (used deliberately above, unlike this
        // file's other tests) schedule a zero-duration Timer on cancel, and
        // flutter_test's pending-timer check trips if that fires only during
        // the implicit teardown after this callback returns.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'switching notes never mounts a second editor field on the shared '
      'controller',
      (tester) async {
        final notes = [
          _sampleNote(id: 'n1', content: 'First note'),
          _sampleNote(id: 'n2', content: 'Second note'),
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

        await tester.tap(find.text('First note'));
        await tester.pumpAndSettle();
        expect(_editorTextFields(), findsOneWidget);

        await tester.tap(find.text('Second note'));
        // Mid-transition on purpose — pumpAndSettle would run past the very
        // window this guards.
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          _editorTextFields(),
          findsOneWidget,
          reason:
              'the page owns ONE TextEditingController and ONE FocusNode for '
              'the note body (see _NotesPageState). A second, simultaneously '
              'mounted field bound to them fights over the platform text-input '
              'connection and over which widget owns the FocusNode\'s '
              'attachment — the field then paints a focus ring it cannot type '
              'into.',
        );

        await tester.pumpAndSettle();
        expect(_editorTextFields(), findsOneWidget);
      },
    );

    testWidgets(
      'a new note keeps the editor panel mounted while the stream catches up',
      (tester) async {
        // The notes stream is driven by hand here so the gap between
        // `_actions.create()` writing the row and `watchNotes()` re-emitting
        // with it can be held open for longer than the split view's close
        // animation. In that gap `currentNote` used to resolve to null, the
        // detail column animated shut, and the editor panel was unmounted
        // while its field held the focus — which detaches the page-owned
        // FocusNode mid-focus and leaves the remounted field unable to
        // accept a keystroke.
        final controller = StreamController<List<Note>>();
        addTearDown(controller.close);

        await tester.pumpWidget(
          makeTestable(
            const NotesPage(),
            overrides: [
              notesProvider.overrideWith((ref) => controller.stream),
              ..._noTagOverrides,
            ],
            locale: const Locale('en'),
          ),
        );
        controller.add([_sampleNote(id: 'n1', content: 'First note')]);
        await tester.pumpAndSettle();

        await tester.tap(find.text('First note'));
        await tester.pumpAndSettle();
        expect(find.byType(NoteEditorPanel), findsOneWidget);

        await tester.tap(find.text(l10n.notesNewNote).first);
        // Deliberately no emit on `controller`: the new row exists in the db
        // and nowhere else yet. Pump well past the close animation.
        await tester.pumpAndSettle();

        expect(
          find.byType(NoteEditorPanel),
          findsOneWidget,
          reason:
              'the note was created and selected — the editor must stay on '
              'screen through the stream gap, not close and reopen around the '
              'focus request',
        );
        final focusNode = tester
            .widget<TextField>(_editorTextFields())
            .focusNode;
        expect(
          focusNode?.hasFocus,
          isTrue,
          reason: 'and it must still be the focused, typable field',
        );

        // Leave the blank new note behind before tearing down: the page's
        // dispose would otherwise run the empty-discard db write against the
        // connection the provider scope closes in the same unmount pass.
        await tester.tap(find.text('First note'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'switching notes lands the body field at the caret, not at the offset '
      'the previous note was left at',
      (tester) async {
        // The panel is now updated in place instead of cross-faded, so the
        // body field's own ScrollController survives the switch. Left alone
        // it merely clamps into range, which parks the new note at an offset
        // that means nothing — the end (where _setEditorText puts the caret)
        // is the one position that does.
        final notes = [
          _sampleNote(
            id: 'n1',
            content: 'Long note\n${List.filled(200, 'line').join('\n')}',
          ),
          _sampleNote(
            id: 'n2',
            content: 'Medium note\n${List.filled(40, 'line').join('\n')}',
          ),
          _sampleNote(id: 'n3', content: 'Short note'),
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

        await tester.tap(find.text('Long note').first);
        await tester.pumpAndSettle();

        final scrollController = tester
            .widget<TextField>(_editorTextFields())
            .scrollController!;
        expect(
          scrollController.position.maxScrollExtent,
          greaterThan(0),
          reason:
              'the long note has to actually overflow for this to test '
              'anything',
        );
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pumpAndSettle();

        // Another note that still overflows: the offset above is a legal one
        // here too, so clamping alone would leave it untouched.
        await tester.tap(find.text('Medium note').first);
        await tester.pumpAndSettle();
        expect(scrollController.position.maxScrollExtent, greaterThan(0));
        expect(
          scrollController.offset,
          scrollController.position.maxScrollExtent,
        );

        // And one that does not overflow at all.
        await tester.tap(find.text('Short note').first);
        await tester.pumpAndSettle();
        expect(scrollController.offset, 0.0);
      },
    );
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

    testWidgets('a half-typed tag does not follow the editor to a new note', (
      tester,
    ) async {
      // The editor panel is updated in place across a note switch rather than
      // rebuilt from scratch (WpSplitView.crossFadeDetail), so every child
      // holding note-scoped state is keyed on the note id. This is that
      // contract for WpTagInput: without the key its typed-but-unsubmitted
      // text survives, and Enter would file it on the wrong note.
      final controller = StreamController<List<Note>>();
      addTearDown(controller.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => controller.stream),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      controller.add([_sampleNote(id: 'n1', content: 'First note')]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('First note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.notesAddTag));
      await tester.pumpAndSettle();
      await tester.enterText(_editorTextFields().first, 'errands');
      await tester.pumpAndSettle();
      expect(find.text('errands'), findsOneWidget);

      // Ctrl/Cmd+N rather than a click on a list tile: the tag input closes
      // its own add mode on any pointer-down outside itself, so only the
      // keyboard path (deliberately not guarded by isTextFieldFocused, see
      // _buildListShortcuts) actually reaches the editor with the field open.
      if (Platform.isMacOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      }
      await tester.pumpAndSettle();

      expect(
        find.text('errands'),
        findsNothing,
        reason:
            'the new note must not inherit the tag name typed for the '
            'previous one — pressing Enter would file it here',
      );

      // Leave the blank new note before teardown: the page's dispose runs the
      // empty-discard write, and the provider scope closes the db in the same
      // unmount pass.
      await tester.tap(find.text('First note'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
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

  // ---------------------------------------------------------------------------
  // Schnellnotiz-Hotkey an der Markierung (Ticket 24)
  // ---------------------------------------------------------------------------

  group('NoteEditorPanel — Schnellnotiz-Hotkey (Ticket 24)', () {
    /// Der Editor allein, ohne Seite und Datenbank: die Zeile hängt an der
    /// Markierung der offenen Notiz, und die steckt in diesem Panel.
    Widget panelSubject({
      required Note note,
      AppSettings settings = _hotkeyOn,
      double textScale = 1.0,
      double width = 320,
    }) {
      final controller = TextEditingController(text: note.content);
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      return makeTestable(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(
            child: SizedBox(
              key: const Key('probeFrame'),
              // Die Panel-Untergrenze der Split-View plus etwas Luft — die
              // Breite, bei der die Aktionsleiste historisch überlief
              // (FLUTTER_WHISPASTE-64).
              width: width,
              height: 560,
              child: NoteEditorPanel(
                note: note,
                tags: const [],
                controller: controller,
                focusNode: focusNode,
                onClose: () {},
                onDuplicate: () {},
                onToggleFavorite: () {},
                onQuickNoteSet: () {},
                onQuickNoteClear: () {},
                onMoveToTrash: () {},
                onRestore: () {},
                onDeleteForever: () {},
                onAddTag: (_) {},
                onRemoveTag: (_) {},
                onExport: () {},
                onVoiceTranscript: (_) {},
              ),
            ),
          ),
        ),
        locale: const Locale('en'),
        overrides: [
          settingsProvider.overrideWith(() => _FakeSettings(settings)),
        ],
      );
    }

    AppSettings settingsOf(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(NoteEditorPanel)),
    ).read(settingsProvider).value!;

    testWidgets('shows the stored combination on the marked note', (
      tester,
    ) async {
      await tester.pumpWidget(
        panelSubject(
          note: _sampleNote(id: 'n1', content: 'Inbox', isQuickNote: true),
          settings: const AppSettings(
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: ';',
              // Layout-abweichende Anzeige-Taste (DE-Tastatur): gespeichert
              // wird ';', angezeigt gehört 'Ö'.
              quickNoteHotkeyKeyDisplay: 'Ö',
              quickNoteHotkeyModifiers: 'ctrl+alt',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Die bestehende Darstellungsform, nicht eine zweite: dasselbe Widget,
      // das die Einstellungsseite benutzt.
      expect(
        find.descendant(
          of: find.byType(NoteEditorPanel),
          matching: find.byType(HotkeyDisplay),
        ),
        findsOneWidget,
      );
      expect(find.text('Ö'), findsOneWidget);
      expect(find.text(';'), findsNothing);
    });

    testWidgets('an unmarked note carries no hotkey line', (tester) async {
      await tester.pumpWidget(
        panelSubject(
          note: _sampleNote(id: 'n1', content: 'Just a note'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickNoteHotkeyLine), findsNothing);
    });

    testWidgets('the trash view carries no hotkey line either', (tester) async {
      // Eine Notiz im Papierkorb trägt die Markierung nicht mehr sichtbar —
      // also gibt es dort auch nichts, woneben die Einstellung stehen könnte.
      await tester.pumpWidget(
        panelSubject(
          note: _sampleNote(
            id: 'n1',
            content: 'Trashed',
            isQuickNote: true,
            deletedAt: DateTime(2025, 6, 2),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickNoteHotkeyLine), findsNothing);
    });

    testWidgets('tapping the combination records and saves a free one', (
      tester,
    ) async {
      await tester.pumpWidget(
        panelSubject(
          note: _sampleNote(id: 'n1', content: 'Inbox', isQuickNote: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notesQuickNoteHotkeyCombo')));
      await tester.pumpAndSettle();

      // Derselbe Dialog wie in den Einstellungen — kein Nachbau.
      expect(find.byType(WpHotkeyRecorderDialog), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      expect(settingsOf(tester).quickNoteHotkey.quickNoteHotkeyKey, 'K');
      expect(
        find.byKey(const Key('notesQuickNoteHotkeyCollisionNotice')),
        findsNothing,
      );
    });

    testWidgets('a combination another hotkey holds is refused here too', (
      tester,
    ) async {
      await tester.pumpWidget(
        panelSubject(
          note: _sampleNote(id: 'n1', content: 'Inbox', isQuickNote: true),
          settings: const AppSettings(
            hotkey: HotkeySettings(
              hotkeyEnabled: true,
              hotkeyKey: 'D',
              hotkeyModifiers: 'ctrl+shift',
            ),
            quickNoteHotkey: QuickNoteHotkeySettings(
              quickNoteHotkeyEnabled: true,
              quickNoteHotkeyKey: 'Y',
              quickNoteHotkeyModifiers: 'ctrl+shift',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notesQuickNoteHotkeyCombo')));
      await tester.pumpAndSettle();

      // Genau die Kombination des Haupt-Hotkeys aufzeichnen.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      expect(
        settingsOf(tester).quickNoteHotkey.quickNoteHotkeyKey,
        'Y',
        reason: 'the colliding combination must not reach the settings',
      );
      expect(
        find.byKey(const Key('notesQuickNoteHotkeyCollisionNotice')),
        findsOneWidget,
      );
      // Dieselbe Meldung wie in den Einstellungen — dieselbe Regel, ein
      // Wortlaut.
      expect(
        find.text(
          l10n.settingsQuickNoteHotkeyCollision(
            l10n.settingsHotkeyActionRecording,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a switched-off hotkey says so and can be switched on here', (
      tester,
    ) async {
      await tester.pumpWidget(
        panelSubject(
          note: _sampleNote(id: 'n1', content: 'Inbox', isQuickNote: true),
          settings: const AppSettings(),
        ),
      );
      await tester.pumpAndSettle();

      // Wer hier markiert und nichts erführe, hätte ein Feature eingerichtet,
      // das nichts tut.
      expect(find.text(l10n.notesQuickNoteHotkeyOff), findsOneWidget);
      expect(find.byKey(const Key('notesQuickNoteHotkeyCombo')), findsNothing);

      await tester.tap(find.byKey(const Key('notesQuickNoteHotkeyEnable')));
      await tester.pumpAndSettle();

      expect(
        settingsOf(tester).quickNoteHotkey.quickNoteHotkeyEnabled,
        isTrue,
        reason: 'the AC asks for switching on from here, not for a signpost',
      );
      expect(
        find.byKey(const Key('notesQuickNoteHotkeyCombo')),
        findsOneWidget,
        reason: 'switching on must reveal the combination it just enabled',
      );
    });

    testWidgets('the combination is reachable by keyboard and announced as '
        'one label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        panelSubject(
          note: _sampleNote(id: 'n1', content: 'Inbox', isQuickNote: true),
        ),
      );
      await tester.pumpAndSettle();

      final combo = find.byKey(const Key('notesQuickNoteHotkeyCombo'));
      final node = tester.widget<InkWell>(combo).focusNode!;
      node.requestFocus();
      await tester.pump();
      expect(
        node.hasFocus,
        isTrue,
        reason: 'a mouse-only entry point would not be reachable at all',
      );

      // Die Kappen selbst sind eine Row aus Einzel-Texten — ohne eigene
      // Beschriftung läse ein Screenreader „Strg", „+", „Y" als Fetzen vor.
      final settings = settingsOf(tester).quickNoteHotkey;
      expect(
        find.bySemanticsLabel(
          l10n.notesQuickNoteHotkeyChange(
            formatHotkeyShortcut(
              settings.quickNoteHotkeyModifiers,
              settings.quickNoteHotkeyKey,
              l10n: l10n,
              displayOverride: settings.quickNoteHotkeyKeyDisplay,
            ),
          ),
        ),
        findsOneWidget,
      );

      // Genau einmal: der Maus-Hinweis (Tooltip) trägt denselben Satz und
      // landete ohne `excludeFromSemantics` als zweite Eigenschaft am selben
      // Knoten — vorgelesen würde die Kombination dann doppelt.
      expect(
        tester.getSemantics(combo).tooltip,
        isEmpty,
        reason: 'label and tooltip would be announced one after the other',
      );
      handle.dispose();
    });

    for (final scale in [1.5, 2.0, 2.5]) {
      testWidgets('survives text scale $scale without clipping', (
        tester,
      ) async {
        // Erst die Kontrolle ohne die neue Zeile: was das Panel bei dieser
        // Schriftgröße ohnehin schon wirft, ist Bestand und darf die Aussage
        // über die Zeile weder tragen noch verschlucken.
        await tester.pumpWidget(
          panelSubject(
            note: _sampleNote(id: 'n1', content: 'Inbox'),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final baseline = _drainExceptions(tester);

        await tester.pumpWidget(
          panelSubject(
            note: _sampleNote(id: 'n1', content: 'Inbox', isQuickNote: true),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final marked = _drainExceptions(tester);
        expect(
          marked.length,
          lessThanOrEqualTo(baseline.length),
          reason:
              'the hotkey line must not add an overflow at scale $scale: '
              '$marked (Kontrolle: $baseline)',
        );

        final frame = tester.getRect(find.byKey(const Key('probeFrame')));
        for (final probe in <String, Finder>{
          'Beschriftung': find.text(l10n.notesQuickNoteHotkeyLabel),
          'Tastenkappen': find.byType(HotkeyDisplay),
        }.entries) {
          final rect = tester.getRect(probe.value);
          expect(
            rect.left >= frame.left - 0.5 && rect.right <= frame.right + 0.5,
            isTrue,
            reason:
                '${probe.key} ragt aus ${frame.left}..${frame.right} heraus: '
                '${rect.left}..${rect.right}',
          );
        }
      });
    }

    testWidgets('the hotkey line does not push the notes list away', (
      tester,
    ) async {
      // Die Zeile sitzt im Detail-Panel; die Liste daneben darf davon nichts
      // merken — auch nicht bei vergrößerter Systemschrift.
      Future<Rect> listRectFor(bool marked) async {
        await tester.pumpWidget(
          makeTestable(
            const MediaQuery(
              data: MediaQueryData(
                size: Size(1280, 800),
                textScaler: TextScaler.linear(2.0),
              ),
              child: NotesPage(),
            ),
            overrides: [
              notesProvider.overrideWith(
                (ref) => Stream.value([
                  _sampleNote(id: 'n1', content: 'Inbox', isQuickNote: marked),
                ]),
              ),
              settingsProvider.overrideWith(() => _FakeSettings(_hotkeyOn)),
              ..._noTagOverrides,
            ],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NotesListTile).first);
        await tester.pumpAndSettle();
        while (tester.takeException() != null) {}
        return tester.getRect(find.byType(NotesListTile).first);
      }

      final unmarked = await listRectFor(false);
      final marked = await listRectFor(true);
      expect(marked.width, closeTo(unmarked.width, 0.5));
      expect(marked.left, closeTo(unmarked.left, 0.5));
    });
  });

  // ---------------------------------------------------------------------------
  // Eine Einstellung, zwei Aufrufstellen (Ticket 24)
  // ---------------------------------------------------------------------------

  group('Notizen-Seite und Einstellungen teilen einen Zustand', () {
    Widget bothSurfaces(AppSettings settings) {
      final controller = TextEditingController(text: 'Inbox');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      return makeTestable(
        SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(width: 560, child: KeyboardShortcutSection()),
              SizedBox(
                width: 420,
                height: 420,
                child: NoteEditorPanel(
                  note: _sampleNote(
                    id: 'n1',
                    content: 'Inbox',
                    isQuickNote: true,
                  ),
                  tags: const [],
                  controller: controller,
                  focusNode: focusNode,
                  onClose: () {},
                  onDuplicate: () {},
                  onToggleFavorite: () {},
                  onQuickNoteSet: () {},
                  onQuickNoteClear: () {},
                  onMoveToTrash: () {},
                  onRestore: () {},
                  onDeleteForever: () {},
                  onAddTag: (_) {},
                  onRemoveTag: (_) {},
                  onExport: () {},
                  onVoiceTranscript: (_) {},
                ),
              ),
            ],
          ),
        ),
        locale: const Locale('en'),
        overrides: [
          settingsProvider.overrideWith(() => _FakeSettings(settings)),
        ],
      );
    }

    testWidgets('a change made in the notes editor shows up in Settings', (
      tester,
    ) async {
      // Höheres Testfenster, seit die Einstellungs-Sektion einen dritten
      // Hotkey-Eintrag trägt (Ticket 27): beide Oberflächen stehen hier
      // untereinander, und der Notiz-Editor darunter wäre sonst außerhalb des
      // Fensters — in der App scrollt die Seite, `tap` scrollt nicht.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(bothSurfaces(_hotkeyOn));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notesQuickNoteHotkeyCombo')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHotkeyRecorderSave));
      await tester.pumpAndSettle();

      // Nicht den Provider-Wert prüfen, sondern das, was die andere Oberfläche
      // *zeigt*: ein zweiter gespeicherter Zustand fiele nur hier auf.
      // 'K' ist eindeutig — der Haupt-Hotkey steht per Vorgabe auf 'D'.
      expect(
        find.descendant(
          of: find.byType(KeyboardShortcutSection),
          matching: find.text('K'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('switching the hotkey off in Settings reaches the notes '
        'editor', (tester) async {
      await tester.pumpWidget(bothSurfaces(_hotkeyOn));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notesQuickNoteHotkeyCombo')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('quickNoteHotkeyToggle')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(NoteEditorPanel),
          matching: find.text(l10n.notesQuickNoteHotkeyOff),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('notesQuickNoteHotkeyCombo')), findsNothing);
    });
  });
}

/// Der Schnellnotiz-Hotkey eingeschaltet, sonst alles auf Vorgabe.
const _hotkeyOn = AppSettings(
  quickNoteHotkey: QuickNoteHotkeySettings(quickNoteHotkeyEnabled: true),
);

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

/// Räumt die anstehenden Layout-Ausnahmen ab und meldet ihre erste Zeile.
///
/// Die Meldungen und nicht nur ihre Zahl, damit ein Fehlschlag benennt, *was*
/// übergelaufen ist — sonst steht da nur „1 statt 0".
List<String> _drainExceptions(WidgetTester tester) {
  final messages = <String>[];
  for (
    Object? e = tester.takeException();
    e != null;
    e = tester.takeException()
  ) {
    messages.add(e.toString().split('\n').first);
  }
  return messages;
}
