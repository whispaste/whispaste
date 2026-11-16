import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/content_metadata_providers.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';
import 'package:whispaste/features/notes/widgets/quick_note_hotkey_line.dart';
import 'package:whispaste/features/settings/sections/shortcuts_section.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

import '../../fixtures/test_helpers.dart';

/// `NotesPage` now also has a search `TextField` (Ticket 06) alongside the
/// editor's — scope finders to the editor panel where a test cares
/// specifically about the note body/tag input, not the search field.
Finder _editorTextFields() => find.descendant(
  of: find.byKey(const ValueKey('notes-editor-body')),
  matching: find.byType(TextField),
);

late L10n l10n;

/// Every widget test that pumps [NotesPage] must override these two alongside
/// `notesProvider`/`trashNotesProvider` — left un-overridden, they fall
/// through to real Drift `.watch()` queries (even against the in-memory test
/// db from `makeTestable`), whose stream-cleanup schedules a Timer on
/// disposal that flutter_test's pending-timer check then trips.
List<Object> get _noTagOverrides => [
  // The metadata index would start isolates; these tests are not about it.
  contentMetadataProvider.overrideWith((ref, key) => Stream.value(null)),
  contentMetadataPreviewProvider.overrideWith((ref, text) async => null),
  // The fixture notes carry their full text; no database read for search hits.
  noteTextHitsProvider.overrideWith((ref, query) async => const {}),
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

class _FailingCreateActions extends NotesActions {
  _FailingCreateActions(super.db);

  int discardCalls = 0;

  @override
  Future<Note> create() async => throw SqliteException(
    extendedResultCode: 13,
    message: 'private database error',
  );

  @override
  Future<bool> discardIfBlank(String noteId) async {
    discardCalls++;
    return true;
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

/// Switches the list to the trash view via the toolbar's filter menu.
Future<void> _showTrash(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier('notes-filter-menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsIdentifier('notes-filter-trash'));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
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
    testWidgets('failed creation preserves the selected blank note', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _FailingCreateActions(db);
      addTearDown(db.close);
      final notes = [_sampleNote(id: 'existing', content: '')];
      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          noticeBar: true,
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(notes)),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NotesListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('notes-new-note')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('notice-bar-notes-create-error')),
        findsOneWidget,
      );
      expect(find.byType(NotesListTile), findsOneWidget);
      expect(
        tester.widget<NotesListTile>(find.byType(NotesListTile)).note.id,
        'existing',
      );
      expect(_editorTextFields(), findsOneWidget);
      expect(actions.discardCalls, 0);
      // Let the error toast expire and finish its reverse animation before
      // the tree goes away, or its ticker outlives the overlay.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
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

      await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
      await tester.pumpAndSettle();

      expect(_editorTextFields(), findsOneWidget);
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
        await tester.tap(find.byKey(const ValueKey('notes-new-note')).first);
        await tester.pumpAndSettle();
        expect(_editorTextFields(), findsOneWidget);

        // Now create the SECOND note — the reported scenario.
        await tester.tap(find.byKey(const ValueKey('notes-new-note')).first);
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
              '(internal-notes §5.9) — without focus, keystrokes never reach the '
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

        await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
        await tester.pumpAndSettle();
        expect(_editorTextFields(), findsOneWidget);

        await tester.tap(find.bySemanticsIdentifier('notes-row-n2'));
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

        await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
        await tester.pumpAndSettle();
        expect(find.byType(NoteEditorPanel), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('notes-new-note')).first);
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
        await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  });

  group('NotesPage — favorite/trash/restore (Ticket 04)', () {
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

        await _showTrash(tester);
        await _hoverRow(tester, find.byType(NotesListTile).first);

        expect(find.byKey(const ValueKey('notes-restore-n1')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('notes-delete-forever-n1')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('notes-favorite-n1')), findsNothing);
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
      await _showTrash(tester);
      await _hoverRow(tester, find.byType(NotesListTile).first);

      await tester.tap(find.byKey(const ValueKey('notes-delete-forever-n1')));
      await tester.pumpAndSettle();

      const confirm = ValueKey('confirm-dialog-confirm');
      expect(find.byKey(confirm), findsOneWidget);

      // Cancel — dialog dismisses, note is untouched.
      await tester.tap(find.byKey(const ValueKey('confirm-dialog-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(confirm), findsNothing);
    });

    testWidgets(
      'duplicating a note creates a second tile with the same content',
      (tester) async {
        // Real in-memory db (notesProvider left un-overridden) — duplication
        // is a genuine db write/re-query, same rationale as the "brand-new
        // note" test above.
        await tester.pumpWidget(
          makeTestable(
            const NotesPage(),
            overrides: _noTagOverrides,
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('notes-new-note')).first);
        await tester.pumpAndSettle();
        await tester.enterText(_editorTextFields(), 'Duplicate me');
        await tester.pumpAndSettle();

        expect(find.byType(NotesListTile), findsOneWidget);

        await tapNoteHeadAction(tester, 'duplicate');

        expect(find.byType(NotesListTile), findsNWidgets(2));

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  });

  group('NotesPage — tags (Ticket 05)', () {
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

      await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
      await tester.pumpAndSettle();

      // Reveal the inline tag input, type a name, confirm with Enter.
      await tester.tap(find.byKey(const ValueKey('tag-input-add')));
      await tester.pumpAndSettle();
      // The inline tag field lives under the note's tags key, not the body.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('tags-n1')),
          matching: find.byType(TextField),
        ),
        'errands',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(actions.lastAddTag, ('n1', 'errands'));
    });

    testWidgets('a half-typed tag does not follow the editor to a new note', (
      tester,
    ) async {
      // The editor panel is updated in place across a note switch rather than
      // rebuilt from scratch (WpCollectionSplit.crossFadeDetail), so every child
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

      await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-input-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('tags-n1')),
          matching: find.byType(TextField),
        ),
        'errands',
      );
      await tester.pumpAndSettle();
      expect(find.text('errands'), findsOneWidget);

      // Ctrl/Cmd+N rather than a click on a list tile: the tag input closes
      // its own add mode on any pointer-down outside itself, so only the
      // keyboard path (deliberately not guarded by isTextFieldFocused, see
      // _buildListShortcuts) actually reaches the editor with the field open.
      if (defaultTargetPlatform == TargetPlatform.macOS) {
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
      await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.desktop());

    testWidgets(
      'removing a tag calls NotesActions.removeTag for the open note',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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

        await tester.tap(find.bySemanticsIdentifier('notes-row-n1'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Remove tag "work"',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Remove tag "work"',
          ),
        );
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

      expect(find.bySemanticsIdentifier('notes-row-n1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('notes-row-n2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'grocery');
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('notes-row-n1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('notes-row-n2'), findsNothing);
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
      expect(find.byKey(const ValueKey('notes-search-empty')), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('notes-search-empty')), findsNothing);
      expect(find.bySemanticsIdentifier('notes-row-n1'), findsOneWidget);
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

      // The shortcut binding reads the platform seam (`defaultTargetPlatform`),
      // pinned per run by the variant — match that.
      // Vorbild: settings_search_keyboard_a11y_test.dart (separate down/up
      // for the letter key, not the combined `sendKeyEvent`).
      if (defaultTargetPlatform == TargetPlatform.macOS) {
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
    }, variant: TargetPlatformVariant.desktop());
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
      double width = 320,
    }) {
      final controller = TextEditingController(text: note.content);
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      return makeTestable(
        MediaQuery(
          data: const MediaQueryData(),
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
      await tester.tap(find.byKey(const ValueKey('hotkey-recorder-save')));
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
      await tester.tap(find.byKey(const ValueKey('hotkey-recorder-save')));
      await tester.pumpAndSettle();

      expect(
        settingsOf(tester).quickNoteHotkey.quickNoteHotkeyKey,
        'Y',
        reason: 'the colliding combination must not reach the settings',
      );
      // The recorder refuses the taken combination live: Save is disabled and
      // the holder is named under the key caps, so the user sees the reason
      // before pressing anything. The notes-line notice only follows a result
      // that was actually saved, which a taken combination never produces.
      expect(
        find.byKey(const ValueKey<String>('hotkey-recorder-holder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notesQuickNoteHotkeyCollisionNotice')),
        findsNothing,
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
      expect(
        find.byKey(const Key('notesQuickNoteHotkeyEnable')),
        findsOneWidget,
      );
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

      // The page scrolls in the app; the combination sits below the fold here.
      await tester.ensureVisible(
        find.byKey(const Key('notesQuickNoteHotkeyCombo')),
      );
      await tester.tap(find.byKey(const Key('notesQuickNoteHotkeyCombo')));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hotkey-recorder-save')));
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

      await tester.ensureVisible(
        find.byKey(const Key('quickNoteHotkeyToggle')),
      );
      await tester.tap(find.byKey(const Key('quickNoteHotkeyToggle')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(NoteEditorPanel),
          matching: find.byKey(const Key('notesQuickNoteHotkeyEnable')),
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
