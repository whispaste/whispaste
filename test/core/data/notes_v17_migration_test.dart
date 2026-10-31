/// Upgrade from schema v17 (the release that introduced notes) to v29 (WP-31a).
///
/// The fixture is a real v17 database written by the v17 code, with notes, a
/// pinned note, a trashed note and a tag link. Opening a copy runs the whole
/// upgrade chain, and every note must come out with the same content, flags,
/// tags and timestamps.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp31a_v17_');
    dbFile = File(p.join(tempDir.path, 'history.sqlite'));
    File('test/fixtures/notes/history_v17.sqlite').copySync(dbFile.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'a v17 database with notes opens at v31 with every note intact',
    () async {
      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      addTearDown(db.close);

      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(version, 31);

      final plain = await db.getNote('note-plain');
      expect(plain, isNotNull);
      expect(plain!.content, '# Einkaufsliste\n\n- Milch\n- Brot');
      expect(plain.pinned, isFalse);
      expect(plain.deletedAt, isNull);
      expect(plain.title, isNull, reason: 'titles are new and start empty');
      expect(plain.isQuickNote, isFalse);
      expect(plain.createdAt.toUtc(), DateTime.utc(2026, 3, 1, 10, 0));
      expect(plain.updatedAt.toUtc(), DateTime.utc(2026, 3, 2, 9, 30));

      final pinned = await db.getNote('note-pinned');
      expect(pinned!.pinned, isTrue);
      expect(
        pinned.content,
        'Umlaute: äöü ß — Zeile zwei\nund ein Emoji 🎙',
        reason: 'non-ASCII text survives unchanged',
      );

      final trashed = await db.getNote('note-trashed');
      expect(trashed!.deletedAt, isNotNull);
      expect(trashed.content, 'Alter Entwurf');

      final links = await db.select(db.noteTags).get();
      expect(links.map((l) => l.noteId), ['note-plain']);

      expect(await db.noteVersionsFor('note-plain'), isEmpty);
      expect(await db.noteAssetsFor('note-plain'), isEmpty);
    },
  );
}
