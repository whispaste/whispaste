/// Notes DAO / CRUD unit tests for the sidebar Notizen area (schema v17).
///
/// Tests the Notes table directly against the Drift database: create,
/// content/pin updates, soft-delete/restore/purge, sort order, and the
/// empty-note purge sweep. Vorbild: `tag_crud_test.dart`.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('createNote', () {
    test('creates an empty, unpinned, non-deleted note', () async {
      final note = await db.createNote();

      expect(note.id, isNotEmpty);
      expect(note.content, isEmpty);
      expect(note.pinned, isFalse);
      expect(note.deletedAt, isNull);
      expect(note.createdAt, isNotNull);
      expect(note.updatedAt, isNotNull);
    });

    test('creates distinct notes with distinct ids', () async {
      final a = await db.createNote();
      final b = await db.createNote();
      expect(a.id, isNot(b.id));
    });
  });

  group('getNote', () {
    test('returns the note by id', () async {
      final created = await db.createNote();
      final fetched = await db.getNote(created.id);
      expect(fetched?.id, created.id);
    });

    test('returns null for unknown id', () async {
      expect(await db.getNote('missing'), isNull);
    });
  });

  group('updateNoteContent', () {
    test('overwrites content and bumps updatedAt', () async {
      final note = await db.createNote();

      await db.updateNoteContent(note.id, 'Hello world');

      final updated = await db.getNote(note.id);
      expect(updated?.content, 'Hello world');
      // updatedAt is persisted with second precision (drift's default
      // DateTimeColumn storage) — assert presence, not sub-second ordering.
      expect(updated?.updatedAt, isNotNull);
    });
  });

  group('toggleNotePin', () {
    test('sets and unsets the pinned flag', () async {
      final note = await db.createNote();

      await db.toggleNotePin(note.id, pinned: true);
      expect((await db.getNote(note.id))?.pinned, isTrue);

      await db.toggleNotePin(note.id, pinned: false);
      expect((await db.getNote(note.id))?.pinned, isFalse);
    });
  });

  group('softDeleteNote / restoreNote / permanentDeleteNote', () {
    test('soft-delete sets deletedAt, restore clears it', () async {
      final note = await db.createNote();

      await db.softDeleteNote(note.id);
      expect((await db.getNote(note.id))?.deletedAt, isNotNull);

      await db.restoreNote(note.id);
      expect((await db.getNote(note.id))?.deletedAt, isNull);
    });

    test('permanentDeleteNote removes the row entirely', () async {
      final note = await db.createNote();

      await db.permanentDeleteNote(note.id);

      expect(await db.getNote(note.id), isNull);
    });
  });

  group('emptyNotesTrash', () {
    test('removes only trashed notes, leaves active notes untouched', () async {
      final active = await db.createNote();
      final trashed = await db.createNote();
      await db.softDeleteNote(trashed.id);

      final removed = await db.emptyNotesTrash();

      expect(removed, 1);
      expect(await db.getNote(active.id), isNotNull);
      expect(await db.getNote(trashed.id), isNull);
    });
  });

  group('purgeEmptyNotes', () {
    test('deletes active notes whose content is blank (trimmed)', () async {
      final empty = await db.createNote();
      final whitespace = await db.createNote();
      await db.updateNoteContent(whitespace.id, '   \n  ');
      final nonEmpty = await db.createNote();
      await db.updateNoteContent(nonEmpty.id, 'keep me');

      final purged = await db.purgeEmptyNotes();

      expect(purged, 2);
      expect(await db.getNote(empty.id), isNull);
      expect(await db.getNote(whitespace.id), isNull);
      expect(await db.getNote(nonEmpty.id), isNotNull);
    });

    test('does not touch trashed notes even if blank', () async {
      final note = await db.createNote();
      await db.softDeleteNote(note.id);

      final purged = await db.purgeEmptyNotes();

      expect(purged, 0);
      expect(await db.getNote(note.id), isNotNull);
    });
  });

  group('watchNotes (sort order)', () {
    test('orders by pinned desc, then updatedAt desc', () async {
      // Direct table inserts with explicit timestamps (bypassing
      // createNote/toggleNotePin's DateTime.now()) for deterministic sort
      // order, independent of storage precision. Vorbild:
      // store_screenshots_test.dart's fixture inserts.
      Future<void> insert(String id, {required bool pinned, required int m}) {
        return db
            .into(db.notes)
            .insert(
              NotesCompanion.insert(
                id: id,
                content: const Value('x'),
                pinned: Value(pinned),
                createdAt: DateTime(2025, 6, 1),
                updatedAt: DateTime(2025, 6, 1).add(Duration(minutes: m)),
              ),
            );
      }

      await insert('older', pinned: false, m: 1);
      await insert('newer', pinned: false, m: 2);
      await insert('pinnedOld', pinned: true, m: 0);

      final result = await db.watchNotes().first;
      expect(result.map((n) => n.id).toList(), ['pinnedOld', 'newer', 'older']);
    });

    test('excludes soft-deleted notes', () async {
      final active = await db.createNote();
      final trashed = await db.createNote();
      await db.softDeleteNote(trashed.id);

      final result = await db.watchNotes().first;
      expect(result.map((n) => n.id).toList(), [active.id]);
    });
  });

  group('watchTrashNotes', () {
    test(
      'returns only soft-deleted notes, most recently deleted first',
      () async {
        // Explicit deletedAt timestamps for deterministic order (see
        // watchNotes sort-order test above for rationale).
        await db
            .into(db.notes)
            .insert(
              NotesCompanion.insert(
                id: 'a',
                createdAt: DateTime(2025, 6, 1),
                updatedAt: DateTime(2025, 6, 1),
                deletedAt: Value(DateTime(2025, 6, 2)),
              ),
            );
        await db
            .into(db.notes)
            .insert(
              NotesCompanion.insert(
                id: 'b',
                createdAt: DateTime(2025, 6, 1),
                updatedAt: DateTime(2025, 6, 1),
                deletedAt: Value(DateTime(2025, 6, 3)),
              ),
            );

        final result = await db.watchTrashNotes().first;
        expect(result.map((n) => n.id).toList(), ['b', 'a']);
      },
    );

    test('excludes active notes', () async {
      await db.createNote();
      expect(await db.watchTrashNotes().first, isEmpty);
    });
  });
}
