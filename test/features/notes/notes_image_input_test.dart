/// Images reach a note by drop (desktop_drop) and by paste (Cmd/Ctrl+V) as
/// well as by the file picker: every path runs the same checks, cleaning and
/// limits, and a trashed note takes none (ticket).
library;

import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/content_metadata_providers.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/note_clipboard_image.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/pump_until.dart';

/// Complete 1x1 PNG, 45 bytes: signature, IHDR, IEND.
Uint8List _png() {
  final head = Uint8List(33);
  head.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  head.setAll(8, [0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  final d = ByteData.sublistView(head);
  d.setUint32(16, 1);
  d.setUint32(20, 1);
  return Uint8List.fromList([
    ...head,
    0,
    0,
    0,
    0,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}

void main() {
  late Directory appData;
  late HistoryDatabase db;
  late NoteAssetStore store;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('wp31a-image-input-');
    db = openInMemoryTestDatabase();
    store = NoteAssetStore(appDataDirPath: appData.path);
  });

  tearDown(() async {
    await db.close();
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  /// Real database for attachments; the list gets the note from a plain
  /// stream so no Drift watch Timer outlives the test.
  Future<Note> seedNote(WidgetTester tester, String content) async {
    final id = (await tester.runAsync(() => db.createNote()))!.id;
    await tester.runAsync(() => db.updateNoteContent(id, content));
    return (await tester.runAsync(() => db.getNote(id)))!;
  }

  File writeFile(String name, Uint8List bytes) =>
      File('${appData.path}/$name')..writeAsBytesSync(bytes);

  Future<void> pumpPage(
    WidgetTester tester, {
    required Note note,
    NoteClipboardImageReader? clipboard,
  }) async {
    await tester.pumpWidget(
      makeTestable(
        const NotesPage(),
        db: db,
        overrides: [
          noteAssetStoreProvider.overrideWithValue(store),
          // The attachment path does not depend on the metadata index; its
          // isolate work would otherwise hold the database while the test
          // awaits the drop in real time.
          contentMetadataProvider.overrideWith(
            (ref, key) => Stream.value(null),
          ),
          contentMetadataPreviewProvider.overrideWith(
            (ref, text) async => null,
          ),
          notesProvider.overrideWith((ref) => Stream.value([note])),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
          if (clipboard != null)
            noteClipboardImageReaderProvider.overrideWithValue(clipboard),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a dropped image file is attached to the open note', (
    tester,
  ) async {
    final note = await seedNote(tester, 'Drop-Test');
    await pumpPage(tester, note: note);
    await tester.tap(find.text('Drop-Test').first);
    await tester.pumpAndSettle();

    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    // The callback is typed void but returns the page's drop future. The
    // attach needs real file I/O and fake-async frames alike, so alternate the
    // two until it finishes instead of a fixed delay (#106).
    final Object? done = (target.onDragDone! as dynamic)(
      DropDoneDetails(
        files: [
          DropItemFile(writeFile('photo.png', _png()).path),
          DropItemFile(
            writeFile('notes.txt', Uint8List.fromList([1, 2, 3])).path,
          ),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    var finished = false;
    if (done is Future<void>) {
      unawaited(done.whenComplete(() => finished = true));
    } else {
      finished = true;
    }
    await pumpUntil(tester, () => finished, what: 'the drop handler to finish');
    expect(finished, isTrue, reason: 'the drop handler did not finish');

    final assets = await tester.runAsync(() => db.noteAssetsFor(note.id));
    expect(assets, hasLength(1), reason: 'only the image file is attached');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an image on the clipboard is pasted into the editor', (
    tester,
  ) async {
    final note = await seedNote(tester, 'Paste-Test');
    await pumpPage(tester, note: note, clipboard: () async => _png());
    await tester.tap(find.text('Paste-Test').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notes-editor-body')),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();

    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(modifier);
    // Wait for the attach itself, not a fixed delay that load can outrun:
    // the row comes first, the file is renamed into place last (#106), so
    // the finished file alone says the attach is done. The database is asked
    // once afterwards: a query per round, under lab load, stalled the run
    // for 20 s without a reporter event (lab/win run 2952). The attach needs
    // real I/O and fake-async frames alike: alternate them (real event-loop
    // turns, no fixed wait, #1491), bounded by a real deadline so a missing
    // attach fails here with a reason.
    final folder = Directory('${store.rootPath}/${note.id}');
    bool attached() =>
        folder.existsSync() &&
        folder.listSync().any((f) => f is File && !f.path.endsWith('.tmp'));
    await pumpUntil(tester, attached, what: 'the pasted image to be stored');
    expect(attached(), isTrue, reason: 'the pasted image was not stored');
    await tester.pump();
    final assets = await tester.runAsync(() => db.noteAssetsFor(note.id));
    expect(assets, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('paste without an image on the clipboard attaches nothing', (
    tester,
  ) async {
    final note = await seedNote(tester, 'Kein Bild');
    var clipboardRead = false;
    await pumpPage(
      tester,
      note: note,
      clipboard: () async {
        clipboardRead = true;
        return null;
      },
    );
    await tester.tap(find.text('Kein Bild').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('notes-editor-body')),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();

    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(modifier);
    // The paste ends once the empty clipboard was read: wait for that read,
    // not a fixed time (#1491).
    await pumpUntil(
      tester,
      () => clipboardRead,
      what: 'the clipboard to be read',
    );
    await tester.pump();

    final assets = await tester.runAsync(() => db.noteAssetsFor(note.id));
    expect(assets, isEmpty);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.desktop());
}
