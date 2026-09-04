/// Quick-note mark in the notes list and the note editor (ticket 22).
///
/// The mark is a *default value*, not a checkbox: at most one note carries it,
/// marking another one re-hangs it without an intermediate step, and marking
/// the note that already carries it is not offered at all. Removing it is a
/// separate, separately named control in a separate place — no screen position
/// ever carries both meanings, which is what keeps it from feeling like the
/// favourite star sitting next to it.
///
/// These tests pin exactly that: which control exists in which state, that the
/// write path is reached with a flushed autosave, and that neither control
/// appears in the trash view.
library;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/features/notes/widgets/notes_list_tile.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

List<Object> get _noTagOverrides => [
  allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
  noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
];

Note _note({
  String id = 'n1',
  String content = 'Hello',
  bool isQuickNote = false,
  DateTime? deletedAt,
}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: false,
    isQuickNote: isQuickNote,
    deletedAt: deletedAt,
    createdAt: t,
    updatedAt: t,
  );
}

/// Records the quick-note writes and the autosave saves in call order, so a
/// test can assert not just *that* the write happened but that the pending
/// draft was flushed *before* it.
class _RecordingActions extends NotesActions {
  _RecordingActions(super.db);

  final List<String> calls = [];

  @override
  Future<void> save(String noteId, String content) async {
    calls.add('save:$noteId:$content');
  }

  @override
  Future<void> markAsQuickNote(String noteId) async {
    calls.add('mark:$noteId');
  }

  @override
  Future<void> clearQuickNoteMark() async {
    calls.add('clear');
  }
}

Widget _tile({
  bool isQuickNote = false,
  bool trashView = false,
  bool isFocused = false,
  VoidCallback? onSet,
  VoidCallback? onClear,
}) => NotesListTile(
  note: _note(
    isQuickNote: isQuickNote,
    deletedAt: trashView ? DateTime(2025, 6, 2) : null,
  ),
  tags: const [],
  isTrashView: trashView,
  isSelected: false,
  isFocused: isFocused,
  onTap: () {},
  onCopy: () {},
  onDuplicate: () {},
  onFavoriteToggle: () {},
  onQuickNoteSet: onSet ?? () {},
  onQuickNoteClear: onClear ?? () {},
  onRestore: () {},
  onDeleteForever: () {},
);

Widget _panel({
  bool isQuickNote = false,
  bool trashed = false,
  VoidCallback? onSet,
  VoidCallback? onClear,
}) {
  final controller = TextEditingController(text: 'Hello');
  final focusNode = FocusNode();
  return NoteEditorPanel(
    note: _note(
      isQuickNote: isQuickNote,
      deletedAt: trashed ? DateTime(2025, 6, 2) : null,
    ),
    tags: const [],
    controller: controller,
    focusNode: focusNode,
    onClose: () {},
    onToggleFavorite: () {},
    onQuickNoteSet: onSet ?? () {},
    onQuickNoteClear: onClear ?? () {},
    onMoveToTrash: () {},
    onRestore: () {},
    onDeleteForever: () {},
    onAddTag: (_) {},
    onRemoveTag: (_) {},
    onExport: () {},
    onVoiceTranscript: (_) {},
  );
}

/// Parks a synthetic mouse pointer on [finder] — trailing row actions reveal
/// on hover or focus (see WpRowAction's library comment).
Future<void> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(() => gesture.removePointer());
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _setAction() => find.byIcon(LucideIcons.zap);
// `.data` because FaIcon overrides Icon.icon with the wrapped IconData —
// find.byIcon compares against that, not against the FaIconData wrapper.
Finder _markGlyph() => find.byIcon(FontAwesomeIcons.bolt.data);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('list tile — which control exists in which state', () {
    testWidgets('an unmarked note offers "set" on hover, and no mark glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(_tile(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(_markGlyph(), findsNothing);
      expect(_setAction(), findsNothing);

      await _hover(tester, find.byType(NotesListTile));
      expect(_setAction(), findsOneWidget);
    });

    testWidgets('the marked note shows the mark without hovering', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(_tile(isQuickNote: true), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(
        _markGlyph(),
        findsOneWidget,
        reason: 'which note is the quick note must be readable at a glance',
      );
      expect(
        tester.widget<FaIcon>(_markGlyph()).color,
        WpColors.accent,
        reason:
            'the mark carries the generic interaction accent, never the '
            'favourite star amber (WpSharedColors.pinnedAccent)',
      );
    });

    testWidgets('the marked note offers no way to mark it again', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(_tile(isQuickNote: true), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      await _hover(tester, find.byType(NotesListTile));

      expect(
        _setAction(),
        findsNothing,
        reason:
            'a default value does not get re-chosen — the control is absent, '
            'not a silent no-op',
      );
    });

    testWidgets('set and clear are two controls in two places', (tester) async {
      var setCalls = 0;
      var clearCalls = 0;
      await tester.pumpWidget(
        makeTestable(
          _tile(
            isQuickNote: true,
            onSet: () => setCalls++,
            onClear: () => clearCalls++,
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_markGlyph());
      await tester.pump();
      expect(clearCalls, 1);
      expect(
        setCalls,
        0,
        reason: 'the mark glyph clears; it never re-marks the same note',
      );
    });

    testWidgets('the trash view has neither control', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          _tile(isQuickNote: true, trashView: true),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _hover(tester, find.byType(NotesListTile));

      expect(_markGlyph(), findsNothing);
      expect(_setAction(), findsNothing);
    });

    testWidgets('keyboard focus alone reveals the set action', (tester) async {
      await tester.pumpWidget(
        makeTestable(_tile(isFocused: true), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(
        _setAction(),
        findsOneWidget,
        reason: 'the list cursor must reach the action without a mouse',
      );
    });

    testWidgets('revealing the set action does not change the row height', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(_tile(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      final atRest = tester.getSize(find.byType(NotesListTile)).height;

      await _hover(tester, find.byType(NotesListTile));
      expect(
        tester.getSize(find.byType(NotesListTile)).height,
        atRest,
        reason: 'the row must not get restless when the mark action appears',
      );
    });
  });

  group('list tile — keyboard and screen reader', () {
    testWidgets('both controls announce what they do, in domain language', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(_tile(isQuickNote: true), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(l10n.notesQuickNoteClear), findsOneWidget);

        await tester.pumpWidget(
          makeTestable(_tile(isFocused: true), locale: const Locale('en')),
        );
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(l10n.notesQuickNoteSet), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the mark can be removed with the keyboard alone', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _RecordingActions(db);
      addTearDown(db.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          size: const Size(1800, 900),
          overrides: [
            notesProvider.overrideWith(
              (ref) => Stream.value([_note(isQuickNote: true)]),
            ),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // The mark is the *only* way to drop it from the list, so it has to sit
      // in the tab order — the list's arrow-key cursor moves a selection, not
      // real focus, and would never reach it.
      final clearButton = find
          .descendant(
            of: find.byType(NotesListTile),
            matching: find.ancestor(
              of: _markGlyph(),
              matching: find.byType(InkWell),
            ),
          )
          .first;
      bool hasFocus() =>
          tester.widget<InkWell>(clearButton).focusNode?.hasFocus ?? false;

      var tabs = 0;
      while (!hasFocus() && tabs < 12) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        tabs++;
      }
      expect(hasFocus(), isTrue, reason: 'tab traversal must reach the mark');

      // Space, not Enter: the list's own `Focus.onKeyEvent` claims bare Enter
      // to open the focused note and never lets it reach a button inside the
      // list — the favourite star has lived with that since it shipped, and
      // widening that guard is not this ticket's to make.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(actions.calls, ['clear']);
    });
  });

  group('editor toolbar', () {
    testWidgets('an unmarked note offers "set" in the action cluster', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(_panel(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(_setAction(), findsOneWidget);
      expect(_markGlyph(), findsNothing);
    });

    testWidgets('the marked note shows the mark and drops the set button', (
      tester,
    ) async {
      var clearCalls = 0;
      await tester.pumpWidget(
        makeTestable(
          _panel(isQuickNote: true, onClear: () => clearCalls++),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_markGlyph(), findsOneWidget);
      expect(_setAction(), findsNothing);

      await tester.tap(_markGlyph());
      await tester.pump();
      expect(clearCalls, 1);
    });

    testWidgets('a trashed note has neither control', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          _panel(isQuickNote: true, trashed: true),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_markGlyph(), findsNothing);
      expect(_setAction(), findsNothing);
    });
  });

  // Narrow panels and enlarged system font are deliberately *not* retested
  // here: the marked list row is a case of its own in
  // `test/widgets/row_actions_consistency_test.dart` (240 dp, and 360 dp at
  // 1.5x), and the marked editor toolbar one in
  // `note_editor_toolbar_overflow_test.dart` (240/280/320/640 dp, and 280 dp
  // at 1.5x). Both are the canonical homes for that guard; duplicating them
  // would only give the next person two places to update.

  group('wired into NotesPage', () {
    testWidgets('marking flushes the pending draft before it writes', (
      tester,
    ) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _RecordingActions(db);
      addTearDown(db.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          size: const Size(1800, 900),
          overrides: [
            notesProvider.overrideWith(
              (ref) => Stream.value([_note(content: 'Hello')]),
            ),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hello'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(NoteEditorPanel),
              matching: find.byType(TextField),
            )
            .first,
        'Hello world',
      );
      // Deliberately no pump past the 400ms debounce — only the mark's own
      // flush may fire this save.
      await tester.pump();
      expect(actions.calls, isEmpty);

      // The open note offers "set" twice — once in its list row, once in the
      // editor toolbar. This is the list row's copy.
      await tester.tap(
        find.descendant(of: find.byType(NotesListTile), matching: _setAction()),
      );
      await tester.pump();

      expect(
        actions.calls,
        ['save:n1:Hello world', 'mark:n1'],
        reason:
            'without the flush the stream would re-emit the stale pre-flush '
            'content over the fresh draft',
      );
    });

    testWidgets('clearing flushes the pending draft too', (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      final actions = _RecordingActions(db);
      addTearDown(db.close);

      await tester.pumpWidget(
        makeTestable(
          const NotesPage(),
          size: const Size(1800, 900),
          overrides: [
            notesProvider.overrideWith(
              (ref) =>
                  Stream.value([_note(content: 'Hello', isQuickNote: true)]),
            ),
            notesActionsProvider.overrideWith((ref) => actions),
            ..._noTagOverrides,
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hello'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(NoteEditorPanel),
              matching: find.byType(TextField),
            )
            .first,
        'Hello world',
      );
      await tester.pump();
      expect(actions.calls, isEmpty);

      // The editor toolbar's mark glyph — the list row carries one too.
      await tester.tap(
        find.descendant(
          of: find.byType(NoteEditorPanel),
          matching: _markGlyph(),
        ),
      );
      await tester.pump();

      expect(actions.calls, ['save:n1:Hello world', 'clear']);
    });
  });
}
