import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:whispaste/features/history/data/database.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('HistoryDatabase', () {
    test('creates tables without error', () async {
      final entries = await db.allEntries();
      expect(entries, isEmpty);
    });

    test('inserts and retrieves an entry', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'test-1',
        timestamp: DateTime(2025, 1, 15, 10, 30),
        content: const Value('Hello world transcription'),
        title: const Value('Test Entry'),
        model: const Value('whisper-large-v3'),
        isLocal: const Value(true),
        durationSec: const Value(12.5),
      ));

      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.id, 'test-1');
      expect(entries.first.content, 'Hello world transcription');
      expect(entries.first.title, 'Test Entry');
      expect(entries.first.isLocal, true);
    });

    test('soft-delete moves entry to trash', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'del-1',
        timestamp: DateTime(2025, 1, 15),
      ));

      expect(await db.allEntries(), hasLength(1));

      await db.softDeleteEntry('del-1');

      expect(await db.allEntries(), isEmpty);
    });

    test('togglePin flips pin state', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'pin-1',
        timestamp: DateTime(2025, 1, 15),
      ));

      var entries = await db.allEntries();
      expect(entries.first.pinned, false);

      await db.togglePin('pin-1');
      entries = await db.allEntries();
      expect(entries.first.pinned, true);

      await db.togglePin('pin-1');
      entries = await db.allEntries();
      expect(entries.first.pinned, false);
    });

    test('pinnedEntries returns only pinned', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'a',
        timestamp: DateTime(2025, 1, 15),
        pinned: const Value(true),
      ));
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'b',
        timestamp: DateTime(2025, 1, 16),
      ));

      final pinned = await db.pinnedEntries();
      expect(pinned, hasLength(1));
      expect(pinned.first.id, 'a');
    });

    test('entriesByProject filters correctly', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'p1',
        timestamp: DateTime(2025, 1, 15),
        projectId: const Value('proj-a'),
      ));
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'p2',
        timestamp: DateTime(2025, 1, 16),
        projectId: const Value('proj-b'),
      ));

      final results = await db.entriesByProject('proj-a');
      expect(results, hasLength(1));
      expect(results.first.id, 'p1');
    });

    test('upsertEntry updates existing entry', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'up-1',
        timestamp: DateTime(2025, 1, 15),
        title: const Value('Original'),
      ));

      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'up-1',
        timestamp: DateTime(2025, 1, 15),
        title: const Value('Updated'),
      ));

      final entries = await db.allEntries();
      expect(entries, hasLength(1));
      expect(entries.first.title, 'Updated');
    });

    test('orders by timestamp descending', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'old',
        timestamp: DateTime(2025, 1, 10),
      ));
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'new',
        timestamp: DateTime(2025, 1, 20),
      ));

      final entries = await db.allEntries();
      expect(entries.first.id, 'new');
      expect(entries.last.id, 'old');
    });
  });

  group('Projects', () {
    test('CRUD operations work', () async {
      await db.upsertProject(ProjectsCompanion.insert(
        id: 'proj-1',
        name: 'My Project',
        createdAt: DateTime(2025, 1, 1),
      ));

      final projects = await db.allProjects();
      expect(projects, hasLength(1));
      expect(projects.first.name, 'My Project');

      await db.deleteProject('proj-1');
      expect(await db.allProjects(), isEmpty);
    });
  });

  group('Notes', () {
    test('CRUD operations work', () async {
      await db.upsertEntry(HistoryEntriesCompanion.insert(
        id: 'entry-1',
        timestamp: DateTime(2025, 1, 15),
      ));

      await db.upsertNote(EntryNotesCompanion.insert(
        id: 'note-1',
        entryId: 'entry-1',
        content: const Value('A detailed note'),
        createdAt: DateTime(2025, 1, 15),
        updatedAt: DateTime(2025, 1, 15),
      ));

      final notes = await db.notesForEntry('entry-1');
      expect(notes, hasLength(1));
      expect(notes.first.content, 'A detailed note');

      await db.deleteNote('note-1');
      expect(await db.notesForEntry('entry-1'), isEmpty);
    });
  });
}
