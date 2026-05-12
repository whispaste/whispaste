/// HistoryDetailNotifier unit tests (Phase 4B).
///
/// Tests the centralized mutation boundary for the detail panel:
/// content/title edits, notes CRUD, tag mutations, entry actions.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/history_detail_provider.dart';

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;

  const entryId = 'detail-test-1';

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());

    // Seed an entry for the notifier to load.
    await db.upsertEntry(
      HistoryEntriesCompanion.insert(
        id: entryId,
        timestamp: DateTime(2025, 6, 1, 12, 0),
        content: const Value('Original transcript content'),
        title: const Value('Original Title'),
        model: const Value('whisper-small'),
        isLocal: const Value(true),
        durationSec: const Value(10.0),
      ),
    );

    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// Reads the notifier and waits for the initial load.
  /// Keeps a listener active so the autoDispose provider stays alive
  /// across multiple async calls within a test.
  Future<HistoryDetailNotifier> loadNotifier() async {
    // Keep the provider alive for the duration of the test.
    container.listen(historyDetailProvider(entryId), (_, _) {});
    final state = await container.read(historyDetailProvider(entryId).future);
    expect(state.entry.id, entryId);
    return container.read(historyDetailProvider(entryId).notifier);
  }

  // =========================================================================
  // Initial load
  // =========================================================================

  group('Initial load', () {
    test('loads entry, empty tags, and empty notes', () async {
      final state = await container.read(historyDetailProvider(entryId).future);

      expect(state.entry.id, entryId);
      expect(state.entry.content, 'Original transcript content');
      expect(state.entry.title, 'Original Title');
      expect(state.tags, isEmpty);
      expect(state.notes, isEmpty);
    });

    test('throws StateError for non-existent entry', () async {
      expect(
        container.read(historyDetailProvider('nonexistent').future),
        throwsStateError,
      );
    });
  });

  // =========================================================================
  // Content editing
  // =========================================================================

  group('updateContent', () {
    test('updates content via partial update and refreshes state', () async {
      final notifier = await loadNotifier();

      await notifier.updateContent('Updated content text');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.entry.content, 'Updated content text');

      final dbEntry = await db.getEntry(entryId);
      expect(dbEntry!.content, 'Updated content text');
    });
  });

  // =========================================================================
  // Title editing
  // =========================================================================

  group('updateTitle', () {
    test('updates title and sets titleEdited flag', () async {
      final notifier = await loadNotifier();

      await notifier.updateTitle('My Custom Title');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.entry.title, 'My Custom Title');
      expect(state.value!.entry.titleEdited, isTrue);

      final dbEntry = await db.getEntry(entryId);
      expect(dbEntry!.title, 'My Custom Title');
      expect(dbEntry.titleEdited, isTrue);
    });
  });

  // =========================================================================
  // Notes CRUD
  // =========================================================================

  group('Notes', () {
    test('addNote creates note and updates state', () async {
      final notifier = await loadNotifier();

      await notifier.addNote('My first note');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.notes, hasLength(1));
      expect(state.value!.notes.first.content, 'My first note');

      final dbNotes = await db.notesForEntry(entryId);
      expect(dbNotes, hasLength(1));
    });

    test('addNote trims whitespace', () async {
      final notifier = await loadNotifier();

      await notifier.addNote('  Trimmed note  ');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.notes.first.content, 'Trimmed note');
    });

    test('addNote ignores empty or whitespace-only content', () async {
      final notifier = await loadNotifier();

      await notifier.addNote('   ');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.notes, isEmpty);
    });

    test('deleteNote removes note from state and DB', () async {
      final notifier = await loadNotifier();

      await notifier.addNote('To be deleted');
      var state = container.read(historyDetailProvider(entryId));
      final noteId = state.value!.notes.first.id;

      await notifier.deleteNote(noteId);

      state = container.read(historyDetailProvider(entryId));
      expect(state.value!.notes, isEmpty);
      expect(await db.notesForEntry(entryId), isEmpty);
    });

    test('updateNote changes note content', () async {
      final notifier = await loadNotifier();

      await notifier.addNote('Draft note');
      final state = container.read(historyDetailProvider(entryId));
      final noteId = state.value!.notes.first.id;

      await notifier.updateNote(noteId, 'Final note');

      final updated = container.read(historyDetailProvider(entryId));
      expect(updated.value!.notes.first.content, 'Final note');
    });

    test('multiple notes are returned ordered by createdAt desc', () async {
      // Insert notes directly with explicit timestamps to avoid
      // Windows DateTime.now() resolution issues (~16ms granularity).
      await db.upsertNote(
        EntryNotesCompanion(
          id: const Value('note-old'),
          entryId: const Value(entryId),
          content: const Value('First note'),
          createdAt: Value(DateTime(2025, 6, 1, 10, 0)),
          updatedAt: Value(DateTime(2025, 6, 1, 10, 0)),
        ),
      );
      await db.upsertNote(
        EntryNotesCompanion(
          id: const Value('note-new'),
          entryId: const Value(entryId),
          content: const Value('Second note'),
          createdAt: Value(DateTime(2025, 6, 1, 11, 0)),
          updatedAt: Value(DateTime(2025, 6, 1, 11, 0)),
        ),
      );

      await loadNotifier();
      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.notes, hasLength(2));
      // Newest first (desc order from DB).
      expect(state.value!.notes.first.content, 'Second note');
      expect(state.value!.notes.last.content, 'First note');
    });
  });

  // =========================================================================
  // Tags
  // =========================================================================

  group('Tags', () {
    test('addTag creates and links a new tag', () async {
      final notifier = await loadNotifier();

      await notifier.addTag('important');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.tags, hasLength(1));
      expect(state.value!.tags.first.name, 'important');
    });

    test('addTag normalizes to lowercase', () async {
      final notifier = await loadNotifier();

      await notifier.addTag('URGENT');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.tags.first.name, 'urgent');
    });

    test('addTag ignores empty or whitespace-only input', () async {
      final notifier = await loadNotifier();

      await notifier.addTag('   ');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.tags, isEmpty);
    });

    test('addTag reuses existing tag instead of creating duplicate', () async {
      // Pre-create a tag in the DB.
      await db.createTag('existing');

      final notifier = await loadNotifier();
      await notifier.addTag('existing');

      final allTags = await db.allTags();
      expect(allTags, hasLength(1)); // Not duplicated.

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.tags, hasLength(1));
      expect(state.value!.tags.first.name, 'existing');
    });

    test('removeTag unlinks tag from entry', () async {
      final notifier = await loadNotifier();

      await notifier.addTag('removable');
      var state = container.read(historyDetailProvider(entryId));
      final tagId = state.value!.tags.first.id;

      await notifier.removeTag(tagId);

      state = container.read(historyDetailProvider(entryId));
      expect(state.value!.tags, isEmpty);

      // Tag still exists globally, just unlinked.
      final allTags = await db.allTags();
      expect(allTags, hasLength(1));
    });

    test('multiple tags appear alphabetically', () async {
      final notifier = await loadNotifier();

      await notifier.addTag('zebra');
      await notifier.addTag('alpha');
      await notifier.addTag('middle');

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.tags.map((t) => t.name).toList(), [
        'alpha',
        'middle',
        'zebra',
      ]);
    });
  });

  // =========================================================================
  // Entry actions
  // =========================================================================

  group('togglePin', () {
    test('flips pinned state', () async {
      final notifier = await loadNotifier();

      expect(
        container.read(historyDetailProvider(entryId)).value!.entry.pinned,
        isFalse,
      );

      await notifier.togglePin();
      expect(
        container.read(historyDetailProvider(entryId)).value!.entry.pinned,
        isTrue,
      );

      await notifier.togglePin();
      expect(
        container.read(historyDetailProvider(entryId)).value!.entry.pinned,
        isFalse,
      );
    });
  });

  group('toggleArchive', () {
    test('flips archived state', () async {
      final notifier = await loadNotifier();

      expect(
        container.read(historyDetailProvider(entryId)).value!.entry.archived,
        isFalse,
      );

      await notifier.toggleArchive();
      expect(
        container.read(historyDetailProvider(entryId)).value!.entry.archived,
        isTrue,
      );

      await notifier.toggleArchive();
      expect(
        container.read(historyDetailProvider(entryId)).value!.entry.archived,
        isFalse,
      );
    });
  });

  group('softDelete', () {
    test('marks entry as deleted in DB', () async {
      final notifier = await loadNotifier();

      await notifier.softDelete();

      final dbEntry = await db.getEntry(entryId);
      expect(dbEntry!.deletedAt, isNotNull);
    });
  });

  group('restore', () {
    test('clears deletedAt and updates state', () async {
      // Soft-delete first.
      await db.softDeleteEntry(entryId);

      final notifier = await loadNotifier();
      await notifier.restore();

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.entry.deletedAt, isNull);

      final dbEntry = await db.getEntry(entryId);
      expect(dbEntry!.deletedAt, isNull);
    });
  });

  group('permanentDelete', () {
    test('removes entry from DB entirely', () async {
      final notifier = await loadNotifier();

      await notifier.permanentDelete();

      final dbEntry = await db.getEntry(entryId);
      expect(dbEntry, isNull);
    });
  });

  group('duplicate', () {
    test('creates copy with "(copy)" suffix and new ID', () async {
      final notifier = await loadNotifier();

      final copy = await notifier.duplicate();

      expect(copy, isNotNull);
      expect(copy!.id, isNot(entryId));
      expect(copy.title, 'Original Title (copy)');
      expect(copy.content, 'Original transcript content');
      expect(copy.pinned, isFalse);
      expect(copy.archived, isFalse);

      // Both entries exist in DB.
      final entries = await db.allEntries();
      expect(entries, hasLength(2));
    });
  });

  // =========================================================================
  // Refresh
  // =========================================================================

  group('refresh', () {
    test('reloads state from DB after external mutation', () async {
      await loadNotifier();

      // External mutation using full companion (required for upsert).
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: entryId,
          timestamp: DateTime(2025, 6, 1, 12, 0),
          content: const Value('Externally updated'),
        ),
      );

      final notifier = container.read(historyDetailProvider(entryId).notifier);
      await notifier.refresh();

      final state = container.read(historyDetailProvider(entryId));
      expect(state.value!.entry.content, 'Externally updated');
    });
  });
}
