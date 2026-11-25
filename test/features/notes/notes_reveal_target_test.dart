/// #628: a hit of the search over every area opens its note with the match
/// selected, also when the Notizen area mounts with the target already set
/// (the normal case: the search runs from another page).
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/content_metadata_providers.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/editor_view_state.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/data/providers.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/services/hardware_info_service.dart';

class _PresetReveal extends NotesRevealTargetNotifier {
  _PresetReveal(this.initial);

  final NoteRevealTarget initial;

  @override
  NoteRevealTarget? build() => initial;
}

TextField _editor(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(const ValueKey('notes-editor-body')),
    matching: find.byType(TextField),
  ),
);

void main() {
  late HistoryDatabase db;
  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> pumpNotes(
    WidgetTester tester,
    List<Note> notes, {
    List<Note> archived = const [],
    NoteRevealTarget? onMount,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) => db),
          gpuInfoProvider.overrideWith(
            (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
          ),
          notesProvider.overrideWith((ref) => Stream.value(notes)),
          archivedNotesProvider.overrideWith((ref) => Stream.value(archived)),
          trashNotesProvider.overrideWith((ref) => Stream.value(const [])),
          noteAssetsProvider.overrideWith(
            (ref, noteId) => Stream.value(const <NoteAsset>[]),
          ),
          noteAppendsProvider.overrideWith(
            (ref, noteId) => Stream.value(const <NoteAppend>[]),
          ),
          contentMetadataProvider.overrideWith(
            (ref, key) => Stream.value(null),
          ),
          contentMetadataPreviewProvider.overrideWith(
            (ref, text) async => null,
          ),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
          if (onMount != null)
            notesRevealTargetProvider.overrideWith(
              () => _PresetReveal(onMount),
            ),
        ],
        child: MaterialApp(
          theme: wpDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const MediaQuery(
            data: MediaQueryData(size: Size(1800, 900)),
            child: Scaffold(body: NotesPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Note> note(String text) async {
    final n = await db.createNote();
    await db.updateNoteContent(n.id, text);
    return (await db.getNote(n.id))!;
  }

  testWidgets('a target set before the page mounts selects the match', (
    tester,
  ) async {
    const text = 'Milk, eggs and bread for the weekend.';
    final n = await tester.runAsync(() => note(text));
    final start = text.indexOf('weekend');
    await pumpNotes(
      tester,
      [n!],
      onMount: (noteId: n.id, start: start, end: start + 7),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final editor = _editor(tester);
    expect(editor.controller!.text, text);
    expect(
      editor.controller!.selection,
      TextSelection(baseOffset: start, extentOffset: start + 7),
    );
    expect(editor.focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('a target while the page is open selects the match', (
    tester,
  ) async {
    const text = 'First line\r\nSecond line with the budget.';
    final n = await tester.runAsync(() => note(text));
    await pumpNotes(tester, [n!]);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesPage)),
    );
    final start = text.indexOf('budget');
    container.read(notesRevealTargetProvider.notifier).set((
      noteId: n.id,
      start: start,
      end: start + 6,
    ));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final editor = _editor(tester);
    final sel = editor.controller!.selection;
    // The editor folds Windows line endings: one character less before it.
    expect(editor.controller!.text.substring(sel.start, sel.end), 'budget');
    expect(editor.focusNode!.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('the place the note was left at does not move the match', (
    tester,
  ) async {
    // Seen on macOS: the editor's view memory read the remembered caret
    // (here: the start) after the match was selected and put it back.
    const text = 'Milk, eggs and bread for the weekend.';
    final n = await tester.runAsync(() async {
      final n = await note(text);
      await db.viewStates.save((
        kind: ContentKind.note,
        id: n.id,
      ), const EditorViewState());
      return n;
    });
    final start = text.indexOf('weekend');
    await pumpNotes(
      tester,
      [n!],
      onMount: (noteId: n.id, start: start, end: start + 7),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }

    expect(
      _editor(tester).controller!.selection,
      TextSelection(baseOffset: start, extentOffset: start + 7),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('an archived match opens in the archive view (#656)', (
    tester,
  ) async {
    const text = 'Old minutes about the budget.';
    final n = await tester.runAsync(() async {
      final n = await note(text);
      await db.setNoteArchived(n.id, archived: true);
      return (await db.getNote(n.id))!;
    });
    final start = text.indexOf('budget');
    await pumpNotes(
      tester,
      const [],
      archived: [n!],
      onMount: (noteId: n.id, start: start, end: start + 6),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesPage)),
    );
    expect(container.read(notesFilterProvider), NotesFilter.archive);
    final editor = _editor(tester);
    expect(editor.controller!.text, text);
    expect(
      editor.controller!.selection,
      TextSelection(baseOffset: start, extentOffset: start + 6),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
