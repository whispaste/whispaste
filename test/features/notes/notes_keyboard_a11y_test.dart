/// Keyboard accessibility tests for the Notizen page (Ticket 09). Vorbild
/// `history_keyboard_a11y_test.dart` + `keyboard_navigation_test.dart`.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// Records whether `create()` was invoked instead of hitting the DB — the
/// static `Stream.value` fixture used everywhere in this file never reflects
/// a newly created note, so asserting on `NoteEditorPanel` appearing after
/// Ctrl/Cmd+N isn't possible; asserting the action fired is.
class _RecordingActions extends NotesActions {
  _RecordingActions(super.db);

  bool createCalled = false;

  @override
  Future<Note> create() {
    createCalled = true;
    return super.create();
  }
}

List<Object> get _noTagOverrides => [
  allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
  noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
];

Note _sampleNote({
  required String id,
  required String content,
  bool pinned = false,
}) {
  final t = DateTime(2025, 6, 1);
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

Finder _editorTextField() => find.descendant(
  of: find.byType(NoteEditorPanel),
  matching: find.byType(TextField),
);

/// Pump enough frames for widgets to build + animations to run, without
/// waiting for Drift stream timers to settle (Vorbild
/// `keyboard_navigation_test.dart`).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('list keyboard navigation', () {
    testWidgets(
      'Arrow Down/Up move the virtual cursor without opening a note',
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
        await _settle(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await _settle(tester);

        // Arrow keys move the list's virtual cursor only — no editor opens.
        expect(find.byType(NoteEditorPanel), findsNothing);
        expect(find.byType(NotesPage), findsOneWidget);
      },
    );

    testWidgets('Enter opens the focused note in the editor', (tester) async {
      final notes = [_sampleNote(id: 'n1', content: 'First note')];
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
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);

      expect(find.byType(NoteEditorPanel), findsOneWidget);
    });

    testWidgets('Delete moves the focused note to trash (active view)', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'First note')];
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
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await _settle(tester);

      expect(find.text(l10n.notesMovedToTrash), findsOneWidget);

      // Drain the toast's 4s auto-dismiss timer so no Timer outlives the test.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets(
      'Backspace on the focused note also moves it to trash (active view)',
      (tester) async {
        final notes = [_sampleNote(id: 'n1', content: 'First note')];
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
        await _settle(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await _settle(tester);

        expect(find.text(l10n.notesMovedToTrash), findsOneWidget);
        await tester.pumpAndSettle(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'Delete on a focused trashed note opens the delete-forever confirm '
      'dialog',
      (tester) async {
        final trashed = [_sampleNote(id: 'n1', content: 'Trashed note')];
        await tester.pumpWidget(
          makeTestable(
            const NotesPage(),
            overrides: [
              notesProvider.overrideWith((ref) => Stream.value(const [])),
              trashNotesProvider.overrideWith((ref) => Stream.value(trashed)),
              ..._noTagOverrides,
            ],
            locale: const Locale('en'),
          ),
        );
        await _settle(tester);

        await tester.tap(find.text(l10n.notesTrash));
        await _settle(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await _settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await _settle(tester);

        expect(find.text(l10n.notesDeleteForeverConfirm), findsOneWidget);

        // Cancel — dialog dismisses, note is untouched.
        await tester.tap(find.text(l10n.actionCancel));
        await _settle(tester);
        expect(find.text(l10n.notesDeleteForeverConfirm), findsNothing);
      },
    );

    testWidgets('F does not crash and does not open the note (active view)', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'First note')];
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
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await _settle(tester);

      expect(find.byType(NotesPage), findsOneWidget);
      expect(find.byType(NoteEditorPanel), findsNothing);
    });

    testWidgets('Escape clears the virtual cursor without crashing', (
      tester,
    ) async {
      final notes = [_sampleNote(id: 'n1', content: 'First note')];
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
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);

      expect(find.byType(NotesPage), findsOneWidget);
    });

    testWidgets('Escape closes the open editor', (tester) async {
      final notes = [_sampleNote(id: 'n1', content: 'First note')];
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
      await _settle(tester);

      await tester.tap(find.text('First note'));
      await _settle(tester);
      expect(find.byType(NoteEditorPanel), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);

      expect(find.byType(NoteEditorPanel), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Bare-key guard when the editor text field has focus — Pflichtfall
  // ---------------------------------------------------------------------------
  group('bare-key guard — editor text field focused', () {
    testWidgets(
      'Backspace deletes a character in the open editor, not the note '
      '(Pflichtfall)',
      (tester) async {
        final notes = [_sampleNote(id: 'n1', content: 'Hello')];
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
        await _settle(tester);

        await tester.tap(find.text('Hello'));
        await _settle(tester);
        expect(find.byType(NoteEditorPanel), findsOneWidget);

        // Focus the editor's text field explicitly (cursor lands at the end,
        // see _setEditorText) so isTextFieldFocused() is true.
        await tester.tap(_editorTextField());
        await _settle(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await _settle(tester);

        final field = tester.widget<TextField>(_editorTextField());
        expect(
          field.controller!.text,
          'Hell',
          reason:
              'Backspace must edit the text, not fall through to the '
              "list's move-to-trash bare-key handler",
        );
        expect(find.byType(NoteEditorPanel), findsOneWidget);
        expect(find.text(l10n.notesMovedToTrash), findsNothing);
      },
    );

    testWidgets(
      'Delete does not move the note to trash while the editor is focused',
      (tester) async {
        final notes = [_sampleNote(id: 'n1', content: 'Hello')];
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
        await _settle(tester);

        await tester.tap(find.text('Hello'));
        await _settle(tester);
        await tester.tap(_editorTextField());
        await _settle(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await _settle(tester);

        expect(find.byType(NoteEditorPanel), findsOneWidget);
        expect(find.text(l10n.notesMovedToTrash), findsNothing);
      },
    );

    testWidgets(
      'F does not toggle favourite or navigate while the editor is focused',
      (tester) async {
        // flutter_test's sendKeyEvent does not simulate real IME text input
        // for plain character keys (only DefaultTextEditingShortcuts' bound
        // editing keys like Backspace/Delete produce an observable effect —
        // see the two tests above), so this asserts the guard's actual
        // contract: the list's bare-key handler must not fire (no crash, no
        // navigation away from the still-open editor) rather than asserting
        // a keystroke landed in the field.
        final notes = [_sampleNote(id: 'n1', content: 'Hello', pinned: false)];
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
        await _settle(tester);

        await tester.tap(find.text('Hello'));
        await _settle(tester);
        await tester.tap(_editorTextField());
        await _settle(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await _settle(tester);

        expect(find.byType(NoteEditorPanel), findsOneWidget);
        expect(find.text(l10n.notesMovedToTrash), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Modifier shortcuts (list focused, no text field)
  // ---------------------------------------------------------------------------
  group('modifier shortcuts', () {
    testWidgets('Ctrl/Cmd+N creates a new note', (tester) async {
      final notes = [_sampleNote(id: 'n1', content: 'First note')];
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
      await _settle(tester);

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
      await _settle(tester);

      expect(actions.createCalled, isTrue);
    });

    testWidgets('Ctrl/Cmd+N creates a note even while the editor is focused', (
      tester,
    ) async {
      // This used to assert the opposite: an isTextFieldFocused() guard sat
      // on Ctrl/Cmd+N, grouped with the bare-key guards (Backspace, Delete,
      // F) by analogy. The analogy does not hold — those are bare keys that
      // genuinely collide with typing, while Ctrl/Cmd+N collides with
      // nothing (Flutter binds keyN in its macOS Emacs set only, as Ctrl+N,
      // and on macOS we send Cmd+N). The guard therefore bought no safety
      // and cost the shortcut outright: this page's editor is an
      // always-focused text field that grabs focus after every create, so
      // from the second note onwards Ctrl+N was inert — in the one area of
      // the app whose audience is defined by never reaching for the mouse.
      final notes = [_sampleNote(id: 'n1', content: 'Hello')];
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
      await _settle(tester);

      await tester.tap(find.text('Hello'));
      await _settle(tester);
      await tester.tap(_editorTextField());
      await _settle(tester);

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
      await _settle(tester);

      expect(actions.createCalled, isTrue);
    });

    testWidgets('Ctrl/Cmd+N creates a new note from the empty state', (
      tester,
    ) async {
      // Regression pin: the shortcut+focus layer used to live only inside
      // the populated data branch, leaving Ctrl/Cmd+N (and Ctrl/Cmd+F,
      // since nothing held focus for it to bubble up from) dead exactly
      // when a first-time user needed "create a note" most.
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _RecordingActions(db);
      addTearDown(db.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          overrides: [
            notesProvider.overrideWith((ref) => Stream.value(const [])),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await _settle(tester);

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
      await _settle(tester);

      expect(actions.createCalled, isTrue);
    });

    testWidgets('Ctrl/Cmd+C copies the focused note\'s content', (
      tester,
    ) async {
      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final args = Map<String, dynamic>.from(call.arguments as Map);
              clipboardText = args['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final notes = [_sampleNote(id: 'n1', content: 'Copy me please')];
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
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);

      if (Platform.isMacOS) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      } else {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      }
      await tester.pump();

      expect(clipboardText, 'Copy me please');
      expect(find.text(l10n.notesCopied), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });
}
