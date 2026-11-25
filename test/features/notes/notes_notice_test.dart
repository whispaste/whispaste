/// What a note action has to say stays at the editor as a notice instead of a
/// toast (#450): it names the cause, stays until closed and is found by id.
library;

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';
import 'package:whispaste/core/data/content_metadata_providers.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/export_service.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/notes/notes_exporter.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/pump_until.dart';

Finder _notice(String id) => find.byKey(ValueKey('page-notice-notes-$id'));

/// A short confirmation stands in the notice bar at the bottom (#1903).
Finder _confirmation(String id) => find.byKey(ValueKey('notice-bar-notes-$id'));

void main() {
  late Directory appData;
  late HistoryDatabase db;
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    appData = Directory.systemTemp.createTempSync('wp450-notice-');
    db = openInMemoryTestDatabase();
  });

  tearDown(() async {
    await db.close();
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  Future<List<Note>> openNotes(WidgetTester tester, List<String> texts) async {
    final notes = <Note>[];
    for (final text in texts) {
      final id = (await tester.runAsync(() => db.createNote()))!.id;
      await tester.runAsync(() => db.updateNoteContent(id, text));
      final loaded = await tester.runAsync<Note?>(() => db.getNote(id));
      notes.add(loaded!);
    }
    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        db: db,
        noticeBar: true,
        overrides: [
          noteAssetStoreProvider.overrideWithValue(
            NoteAssetStore(appDataDirPath: appData.path),
          ),
          notesProvider.overrideWith((ref) => Stream.value(notes)),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
          // The notices do not depend on the metadata index; its isolate
          // work would keep pumpAndSettle from settling.
          contentMetadataProvider.overrideWith(
            (ref, key) => Stream.value(null),
          ),
          contentMetadataPreviewProvider.overrideWith(
            (ref, text) async => null,
          ),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(texts.first).first);
    await tester.pumpAndSettle();
    return notes;
  }

  Future<Note> openNote(WidgetTester tester, String content) async {
    final id = (await tester.runAsync(() => db.createNote()))!.id;
    await tester.runAsync(() => db.updateNoteContent(id, content));
    final note = (await tester.runAsync(() => db.getNote(id)))!;
    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        db: db,
        noticeBar: true,
        overrides: [
          noteAssetStoreProvider.overrideWithValue(
            NoteAssetStore(appDataDirPath: appData.path),
          ),
          notesProvider.overrideWith((ref) => Stream.value([note])),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
          // The notices do not depend on the metadata index; its isolate
          // work would keep pumpAndSettle from settling.
          contentMetadataProvider.overrideWith(
            (ref, key) => Stream.value(null),
          ),
          contentMetadataPreviewProvider.overrideWith(
            (ref, text) async => null,
          ),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(content.trim().split('\n').first).first);
    await tester.pumpAndSettle();
    return note;
  }

  Future<void> pickMenuEntry(WidgetTester tester, String testId) async {
    await tester.tap(find.byTooltip(l10n.notesMoreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(testId)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'marking without a selection says so at the editor until closed',
    (tester) async {
      await openNote(tester, 'Marker');
      await pickMenuEntry(tester, 'notes-editor-menu-mark');

      expect(_notice('mark-needs-selection'), findsOneWidget);
      expect(find.text(l10n.notesMarkNeedsSelection), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('page-notice-dismiss-notes')));
      await tester.pumpAndSettle();
      expect(_notice('mark-needs-selection'), findsNothing);
    },
  );

  testWidgets('a snippet from an empty note is refused with a notice', (
    tester,
  ) async {
    await openNote(tester, '   x');
    // Empty the editor text so there is nothing to save.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('notes-editor-body')),
        matching: find.byType(TextField),
      ),
      '   ',
    );
    await tester.pump();
    await pickMenuEntry(tester, 'notes-editor-menu-snippet');

    expect(_notice('snippet-nothing'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a snippet from a note confirms in the notice bar', (
    tester,
  ) async {
    await openNote(tester, 'Snippet body');
    await pickMenuEntry(tester, 'notes-editor-menu-snippet');
    // The snippet is written asynchronously. Yield to the event loop until the
    // confirmation shows; bounded, and no wall-clock wait.
    for (
      var i = 0;
      i < 1000 && _confirmation('snippet-created').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    expect(_confirmation('snippet-created'), findsOneWidget);
    expect(_notice('snippet-created'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the toolbar saves a snippet, confirms it and refreshes the snippet list',
    (tester) async {
      await openNote(tester, 'Toolbar body');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotesPage)),
      );
      // The list is already loaded, as after a visit to the Textbausteine
      // page or an opened insert chooser: it must not stay stale (#664).
      final before = await tester.runAsync(
        () => container.read(snippetsProvider.future),
      );
      expect(before, isEmpty);

      // On a narrow panel the button sits under "More" (#1845).
      final saveSnippet = find.bySemanticsIdentifier(
        'notes-editor-toolbar-save-snippet',
      );
      if (saveSnippet.evaluate().isEmpty) {
        await tester.tap(
          find.bySemanticsIdentifier('notes-editor-toolbar-more'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('notes-editor-toolbar-more-save-snippet')),
        );
      } else {
        await tester.tap(saveSnippet);
      }
      await tester.pump();
      for (
        var i = 0;
        i < 1000 && _confirmation('snippet-created').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      expect(_confirmation('snippet-created'), findsOneWidget);

      final after = await tester.runAsync(
        () => container.read(snippetsProvider.future),
      );
      expect(after!.map((s) => s.body), ['Toolbar body']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a refused image file is reported at the editor', (tester) async {
    await openNote(tester, 'Drop-Test');
    final bad = File('${appData.path}/fake.png')
      ..writeAsBytesSync([1, 2, 3, 4]);

    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    // The drop reads the file (real I/O) and then the database, which the
    // page also queries from fake time. Awaiting the whole drop inside one
    // runAsync deadlocked on the database in some orders (#1492): the drop
    // runs in the test zone instead, with real event-loop turns in between.
    (target.onDragDone! as dynamic)(
      DropDoneDetails(
        files: [DropItemFile(bad.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    for (
      var i = 0;
      i < 500 && _notice('image-rejected').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(_notice('image-rejected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the default export notice lands in the notes slot', (
    tester,
  ) async {
    final note = await openNote(tester, 'Exported');
    final context = tester.element(find.byType(NotesPage));
    final exporter = NotesExporter(
      pickerFn: (_) async => ExportFormat.txt,
      exporter: (entries, format, path) async => throw Exception('disk full'),
      saveLocationFn: ({required format, required suggestedName}) async =>
          '/x/y.txt',
    );
    await exporter.exportNote(context, note, const []);
    await tester.pumpAndSettle();

    expect(_notice('export-failed'), findsOneWidget);
    expect(find.text(l10n.historyExportFailed), findsOneWidget);
    expect(
      ProviderScope.containerOf(
        context,
      ).read(wpPageNoticeProvider('notes'))?.area,
      note.id,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the note clears its notice', (tester) async {
    final note = await openNote(tester, 'Marker');
    await pickMenuEntry(tester, 'notes-editor-menu-mark');
    expect(_notice('mark-needs-selection'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('notes-editor-close-${note.id}')));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NotesPage));
    expect(
      ProviderScope.containerOf(context).read(wpPageNoticeProvider('notes')),
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('switching to another note clears the notice of the first', (
    tester,
  ) async {
    await openNotes(tester, ['First note', 'Second note']);
    await pickMenuEntry(tester, 'notes-editor-menu-mark');
    expect(_notice('mark-needs-selection'), findsOneWidget);

    await tester.tap(find.text('Second note').first);
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NotesPage));
    expect(
      ProviderScope.containerOf(context).read(wpPageNoticeProvider('notes')),
      isNull,
    );
    expect(_notice('mark-needs-selection'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a saved and a restored version are announced, not shown', (
    tester,
  ) async {
    await openNote(tester, 'Versioned');
    tester.takeAnnouncements();

    await pickMenuEntry(tester, 'notes-editor-menu-save-version');
    // The version is written in real time: collect announcements until it
    // is confirmed, no fixed wait (#1491).
    final announced = <String>[];
    bool announcedYet(String message) {
      announced.addAll(tester.takeAnnouncements().map((a) => a.message));
      return announced.contains(message);
    }

    await pumpUntil(
      tester,
      () => announcedYet(l10n.notesVersionSaved),
      what: 'the saved version to be announced',
    );
    await tester.pumpAndSettle();
    expect(announced, contains(l10n.notesVersionSaved));
    expect(find.text(l10n.notesVersionSaved), findsNothing);

    // The version list streams from the database, which answers in real
    // time. Until it does, the dialog shows a spinner that never settles in
    // fake time, so the test waits in real time for the list instead of
    // pumpAndSettle.
    final restoreButtons = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'notes-version-restore-',
          ),
    );
    await tester.tap(find.byTooltip(l10n.notesMoreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-editor-menu-versions')));
    // One real event-loop turn per round (Duration.zero): the database
    // answers within a few turns, without a fixed wait.
    for (var i = 0; i < 500 && restoreButtons.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    await tester.tap(restoreButtons.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();
    announced.clear();
    await pumpUntil(
      tester,
      () => announcedYet(l10n.notesVersionRestored),
      what: 'the restored version to be announced',
    );
    await tester.pumpAndSettle();
    expect(announced, contains(l10n.notesVersionRestored));
    await tester.pumpWidget(const SizedBox());
  });
}
