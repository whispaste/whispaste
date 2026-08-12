/// Ticket 21 — after a successful quick-note run the window comes forward,
/// the Notizen area opens the target note and scrolls to the end of it, and
/// the live editor (not the database) takes the append while it is open.
///
/// Deliberately drives the **real** orchestrator append
/// (`RecordingOrchestrator.appendToQuickNote`) against a real in-memory
/// database rather than re-enacting the sequence by hand: the whole point of
/// the flush pre-hook is *when* it runs relative to the database read, and a
/// hand-rolled imitation of that order in a test would keep passing after the
/// production order drifted. The only thing this file wires up itself is the
/// single registration line `WpRecordingBehavior` owns — the reaction it
/// registers is the production function [openQuickNoteInEditor].
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/notes/data/providers.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/notes/widgets/note_editor_panel.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/widgets/recording_behavior.dart';
import 'package:whispaste/widgets/wp_text_field.dart' show WpScrollToEndSignal;

/// The one line `_WpRecordingBehaviorState.initState` owns: register the
/// production reaction on the orchestrator's completion hook. Mounting the
/// whole `WpRecordingBehavior` would drag in the tray, sound feedback and the
/// STT bundle for no gain here.
class _QuickNoteReactionHost extends ConsumerStatefulWidget {
  const _QuickNoteReactionHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_QuickNoteReactionHost> createState() =>
      _QuickNoteReactionHostState();
}

class _QuickNoteReactionHostState
    extends ConsumerState<_QuickNoteReactionHost> {
  RecordingOrchestrator? _orchestrator;

  @override
  void initState() {
    super.initState();
    _orchestrator = ref.read(recordingOrchestratorProvider.notifier);
    _orchestrator!.onQuickNoteAppended = (noteId) =>
        openQuickNoteInEditor(ref, noteId);
  }

  @override
  void dispose() {
    _orchestrator?.onQuickNoteAppended = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A target that is already set when [NotesPage] mounts — the production-normal
/// case: the hotkey is pressed from another app while the Notizen area is not
/// even built, so `ref.listen` never sees a change and only the `initState`
/// post-frame read can pick the target up.
class _PresetEditorTarget extends NotesEditorTargetNotifier {
  _PresetEditorTarget(this.initial);

  final String initial;

  @override
  String? build() => initial;
}

/// The scroll controller of the editor's body field. Each [WpTextField] owns
/// its own (see [WpScrollToEndSignal]); it reaches the [EditableText]
/// unchanged, which is the only place a test can read it back from.
ScrollController _editorScroll(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byType(NoteEditorPanel),
        matching: find.byType(EditableText),
      ),
    )
    .scrollController!;

Finder _editorTextField() => find.descendant(
  of: find.byType(NoteEditorPanel),
  matching: find.byType(TextField),
);

void main() {
  late HistoryDatabase db;
  late int activations;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    activations = 0;
  });

  tearDown(() async => db.close());

  /// Pumps the Notizen area over [db] with the quick-note reaction attached,
  /// and returns the orchestrator the page registered its hooks on.
  Future<RecordingOrchestrator> pumpNotes(
    WidgetTester tester, {
    required List<Note> notes,
    List<Note> trashed = const [],
    double textScale = 1.0,
    Size size = const Size(1800, 900),
    String? editorTargetOnMount,
  }) async {
    // Built here rather than through `makeTestable`, which installs its own
    // in-memory database — this file needs the one it seeded itself, and a
    // provider cannot be overridden twice in the same container.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) => db),
          gpuInfoProvider.overrideWith(
            (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
          ),
          notesProvider.overrideWith((ref) => Stream.value(notes)),
          trashNotesProvider.overrideWith((ref) => Stream.value(trashed)),
          windowActivatorProvider.overrideWithValue(() async => activations++),
          // Left un-overridden these fall through to real Drift `.watch()`
          // queries, whose stream cleanup schedules a Timer on disposal that
          // flutter_test's pending-timer check then trips.
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
          if (editorTargetOnMount != null)
            notesEditorTargetProvider.overrideWith(
              () => _PresetEditorTarget(editorTargetOnMount),
            ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: wpDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Scaffold(
              body: _QuickNoteReactionHost(child: NotesPage()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(NotesPage)),
    ).read(recordingOrchestratorProvider.notifier);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(NotesPage)));

  Future<Note> makeQuickNote(String content) async {
    final note = await db.createNote();
    await db.updateNoteContent(note.id, content);
    await db.setQuickNote(note.id);
    return (await db.getNote(note.id))!;
  }

  group('live-editor takeover', () {
    testWidgets(
      'unsaved keystrokes plus an incoming append leave BOTH in the note',
      (tester) async {
        final note = await makeQuickNote('Saved line');
        final orch = await pumpNotes(tester, notes: [note]);

        await tester.tap(find.byKey(ValueKey(note.id)));
        await tester.pumpAndSettle();

        // Typed, not yet persisted: the 400 ms autosave debounce is running.
        await tester.enterText(_editorTextField(), 'Saved line\nStill typing');
        await tester.pump();

        await orch.appendToQuickNote('Dictated');
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextField>(_editorTextField()).controller!.text,
          'Saved line\nStill typing\n\nDictated',
        );

        // …and it reaches the database once the re-scheduled autosave lands.
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          (await db.getNote(note.id))?.content,
          'Saved line\nStill typing\n\nDictated',
        );
      },
    );

    testWidgets('two appends back to back keep both texts — neither overwrites '
        'the other', (tester) async {
      final note = await makeQuickNote('Start');
      final orch = await pumpNotes(tester, notes: [note]);

      await tester.tap(find.byKey(ValueKey(note.id)));
      await tester.pumpAndSettle();

      await orch.appendToQuickNote('First');
      await tester.pumpAndSettle();
      await orch.appendToQuickNote('Second');
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(_editorTextField()).controller!.text,
        'Start\n\nFirst\n\nSecond',
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect((await db.getNote(note.id))?.content, 'Start\n\nFirst\n\nSecond');
    });

    testWidgets('the hooks are released again when the area is left', (
      tester,
    ) async {
      final note = await makeQuickNote('Anything');
      final orch = await pumpNotes(tester, notes: [note]);

      expect(orch.quickNoteLiveEditorOverride, isNotNull);
      expect(orch.quickNoteEditorFlush, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(orch.quickNoteLiveEditorOverride, isNull);
      expect(orch.quickNoteEditorFlush, isNull);
    });
  });

  group('window + navigation reaction', () {
    testWidgets('a successful append activates the window and switches to the '
        'Notizen area', (tester) async {
      final note = await makeQuickNote('Start');
      final orch = await pumpNotes(tester, notes: [note]);
      final container = containerOf(tester);
      container.read(activePageProvider.notifier).setPage('history');

      await orch.appendToQuickNote('Dictated');
      await tester.pumpAndSettle();

      expect(activations, 1);
      expect(container.read(activePageProvider), 'notes');
    });

    testWidgets('the target provider is emptied on consumption, so a later '
        'manual visit does not jump again', (tester) async {
      final note = await makeQuickNote('Start');
      final orch = await pumpNotes(tester, notes: [note]);
      final container = containerOf(tester);

      await orch.appendToQuickNote('Dictated');
      await tester.pumpAndSettle();

      expect(container.read(notesEditorTargetProvider), isNull);
    });

    testWidgets('nothing is activated when no append happened', (tester) async {
      final note = await makeQuickNote('Start');
      await pumpNotes(tester, notes: [note]);
      await tester.pumpAndSettle();

      expect(
        activations,
        0,
        reason:
            'Only a completed append fires onQuickNoteAppended — merely '
            'being on the page must never move the window.',
      );
    });

    testWidgets('a note that was not open is opened by the deep link', (
      tester,
    ) async {
      final quick = await makeQuickNote('Quick note body');
      final other = await db.createNote();
      await db.updateNoteContent(other.id, 'Some other note');
      final otherNote = (await db.getNote(other.id))!;

      final orch = await pumpNotes(tester, notes: [quick, otherNote]);
      await tester.tap(find.byKey(ValueKey(otherNote.id)));
      await tester.pumpAndSettle();

      await orch.appendToQuickNote('Dictated');
      await tester.pumpAndSettle();

      // The override declined (a different note was open) → the append went
      // to the database, and the deep link then loaded it from there.
      expect(
        tester.widget<TextField>(_editorTextField()).controller!.text,
        'Quick note body\n\nDictated',
      );
      expect(
        (await db.getNote(quick.id))?.content,
        'Quick note body\n\nDictated',
      );
      expect(activations, 1);
    });

    testWidgets('a target set before the area is even built is still picked up '
        'on mount', (tester) async {
      // The path users hit most: window hidden, some other area last active.
      // `openQuickNoteInEditor` sets the target *before* switching pages, so
      // NotesPage is built with it already in place and nothing ever changes
      // afterwards — only the initState post-frame read can catch that.
      final body = List.generate(120, (i) => 'line $i').join('\n');
      final note = await makeQuickNote('$body\n\nDictated');

      await pumpNotes(tester, notes: [note], editorTargetOnMount: note.id);

      expect(
        tester.widget<TextField>(_editorTextField()).controller!.text,
        '$body\n\nDictated',
      );
      expect(containerOf(tester).read(notesEditorTargetProvider), isNull);

      final scroll = _editorScroll(tester);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.offset, scroll.position.maxScrollExtent);
    });

    testWidgets('coming from the trash view lands in the normal notes view', (
      tester,
    ) async {
      final quick = await makeQuickNote('Quick note body');
      final trashed = await db.createNote();
      await db.updateNoteContent(trashed.id, 'Trashed note');
      await db.softDeleteNote(trashed.id);
      final trashedNote = (await db.getNote(trashed.id))!;

      final orch = await pumpNotes(
        tester,
        notes: [quick],
        trashed: [trashedNote],
      );
      final container = containerOf(tester);
      container.read(notesFilterProvider.notifier).set(NotesFilter.trash);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(trashedNote.id)));
      await tester.pumpAndSettle();

      await orch.appendToQuickNote('Dictated');
      await tester.pumpAndSettle();

      expect(container.read(notesFilterProvider), NotesFilter.active);
      expect(
        tester.widget<TextField>(_editorTextField()).controller!.text,
        'Quick note body\n\nDictated',
      );
    });
  });

  group('scrolled to the end', () {
    /// Long enough to overflow the editor at both text scales below.
    final longBody = List.generate(120, (i) => 'line $i').join('\n');

    testWidgets('the editor sits at the end of the note after an append', (
      tester,
    ) async {
      final note = await makeQuickNote(longBody);
      final orch = await pumpNotes(tester, notes: [note]);

      await tester.tap(find.byKey(ValueKey(note.id)));
      await tester.pumpAndSettle();

      await orch.appendToQuickNote('The freshly dictated tail');
      await tester.pumpAndSettle();

      final scroll = _editorScroll(tester);
      expect(scroll.hasClients, isTrue);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.offset, scroll.position.maxScrollExtent);
    });

    testWidgets('…also at an accessibility text size', (tester) async {
      final note = await makeQuickNote(longBody);
      final orch = await pumpNotes(tester, notes: [note], textScale: 2.0);

      await tester.tap(find.byKey(ValueKey(note.id)));
      await tester.pumpAndSettle();

      await orch.appendToQuickNote('The freshly dictated tail');
      await tester.pumpAndSettle();

      final scroll = _editorScroll(tester);
      expect(scroll.hasClients, isTrue);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(
        scroll.offset,
        scroll.position.maxScrollExtent,
        reason:
            'maxScrollExtent is the measured layout height, so the jump '
            'holds at any text scale.',
      );
    });
  });
}
