import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_preview.dart';

/// Lists read a stored preview, never the full text (#639).
void main() {
  late HistoryDatabase db;

  setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  final longText = List.generate(20000, (i) => 'wort$i').join(' ');

  test('preview is cut at a word end and bounded', () {
    final p = notePreview('  \n$longText');
    expect(p.length, lessThanOrEqualTo(kNotePreviewLength));
    expect(p, startsWith('wort0 wort1'));
    expect(longText.startsWith(p), isTrue);
    expect(longText.substring(p.length), startsWith(' '));
    expect(notePreview('   '), '');
    expect(notePreview('short'), 'short');
  });

  test('saving a long note updates the list preview, list rows carry no '
      'full text', () async {
    final note = await db.createNote();
    await db.updateNoteContent(note.id, 'Titel\n$longText');

    final list = await db.watchNotes().first;
    expect(list, hasLength(1));
    expect(list.single.content, startsWith('Titel\nwort0'));
    expect(list.single.content.length, lessThanOrEqualTo(kNotePreviewLength));
    expect(list.single.preview, list.single.content);

    // The full text is read only for the single open note.
    expect((await db.getNote(note.id))!.content, 'Titel\n$longText');
  });

  test('a new preview reaches a running list without full texts', () async {
    final note = await db.createNote();
    final emissions = <String>[];
    // Waits for the emissions themselves, not a fixed time (#1491).
    final listed = Completer<void>();
    final updated = Completer<void>();
    final sub = db.watchNotes().listen((l) {
      emissions.add(l.single.content);
      if (!listed.isCompleted) listed.complete();
      if (l.single.content.startsWith('neue Vorschau') &&
          !updated.isCompleted) {
        updated.complete();
      }
    });
    await listed.future;
    await db.updateNoteContent(note.id, 'neue Vorschau $longText');
    await updated.future.timeout(const Duration(seconds: 10));
    await sub.cancel();
    expect(emissions.last, startsWith('neue Vorschau wort0'));
    expect(emissions.last.length, lessThanOrEqualTo(kNotePreviewLength));
  });

  test('rows without a stored preview are cut in SQL and backfilled', () async {
    final note = await db.createNote();
    await db.updateNoteContent(note.id, longText);
    await db.customStatement('UPDATE notes SET preview = NULL');

    final list = await db.watchNotes().first;
    expect(list.single.content.length, kNotePreviewLength);

    await db.customStatement('UPDATE notes SET preview = NULL');
    // Same step as the v42 migration.
    await db.backfillNotePreviewsForTesting();
    final row = await db.getNote(note.id);
    expect(row!.preview, notePreview(longText));
  });

  test('search reads full texts only on demand', () async {
    final note = await db.createNote();
    await db.updateNoteContent(note.id, '$longText ENDMARKE');
    final hits = await db.noteTextsMatching('endmarke');
    expect(hits.keys, [note.id]);
    expect(await db.noteTextsMatching('gibtsnicht'), isEmpty);
  });
}
