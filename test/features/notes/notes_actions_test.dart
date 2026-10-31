/// [NotesActions] facade tests — no widget tree, [ProviderContainer] +
/// in-memory drift DB only (Vorbild: `store_thank_you_service_test.dart`).
///
/// Widget-level interaction (create/autosave/empty-discard via the actual
/// UI) is intentionally NOT covered here with a real db + widget tree: doing
/// so ties a live `NotesPage`'s fire-and-forget `dispose()` write to
/// flutter_test's FakeAsync zone and pending-timer/guard invariants, which is
/// fragile across sequential tests in one file. `notes_page_test.dart`
/// covers rendering/selection via `Stream.value` fixtures instead (Vorbild:
/// `history_page_test.dart`); this file covers what the facade actually does
/// against a real database.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;
  late NotesActions actions;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );
    actions = container.read(notesActionsProvider);
  });

  tearDown(() => container.dispose());

  group('create', () {
    test('creates an empty, unpinned, non-deleted note', () async {
      final note = await actions.create();

      expect(note.content, isEmpty);
      expect(note.pinned, isFalse);
      expect(note.deletedAt, isNull);
      expect(await db.getNote(note.id), isNotNull);
    });
  });

  group('save', () {
    test('overwrites the note content', () async {
      final note = await actions.create();

      await actions.save(note.id, 'Grocery list');

      expect((await db.getNote(note.id))?.content, 'Grocery list');
    });
  });

  group('togglePin', () {
    test('sets and unsets the favourite flag', () async {
      final note = await actions.create();

      await actions.togglePin(note.id, pinned: true);
      expect((await db.getNote(note.id))?.pinned, isTrue);

      await actions.togglePin(note.id, pinned: false);
      expect((await db.getNote(note.id))?.pinned, isFalse);
    });
  });

  group('moveToTrash / restore', () {
    test(
      'moveToTrash soft-deletes — the row survives with deletedAt set',
      () async {
        final note = await actions.create();

        await actions.moveToTrash(note.id);

        final trashed = await db.getNote(note.id);
        expect(trashed, isNotNull);
        expect(trashed!.deletedAt, isNotNull);
      },
    );

    test('restore clears deletedAt', () async {
      final note = await actions.create();
      await actions.moveToTrash(note.id);

      await actions.restore(note.id);

      expect((await db.getNote(note.id))?.deletedAt, isNull);
    });
  });

  group('deleteForever', () {
    test('permanently removes the row (not a soft-delete)', () async {
      final note = await actions.create();

      await actions.deleteForever(note.id);

      expect(await db.getNote(note.id), isNull);
    });
  });

  group('empty-discard contract', () {
    test(
      'discardIfBlank permanently deletes a blank note, never moveToTrash '
      '(the empty-discard rule: leaving an empty note deletes it outright)',
      () async {
        final note = await actions.create();
        expect(note.content.trim(), isEmpty);

        // This is exactly what NotesPage._leaveCurrentNote/dispose do when
        // the content is blank — verify the facade call they rely on.
        final deleted = await actions.discardIfBlank(note.id);

        expect(deleted, isTrue);
        final result = await db.getNote(note.id);
        expect(result, isNull); // gone entirely, not sitting in trash
      },
    );

    test(
      'discardIfBlank exempts the marked quick note even while blank',
      () async {
        final note = await actions.create();
        await actions.markAsQuickNote(note.id);

        final deleted = await actions.discardIfBlank(note.id);

        expect(deleted, isFalse);
        expect(await db.getNote(note.id), isNotNull);
      },
    );

    test('discardIfBlank leaves a non-blank note untouched', () async {
      final note = await actions.create();
      await actions.save(note.id, 'keep me');

      final deleted = await actions.discardIfBlank(note.id);

      expect(deleted, isFalse);
      expect(await db.getNote(note.id), isNotNull);
    });
  });

  group('purgeEmpty', () {
    test('deletes active notes with blank content, keeps the rest', () async {
      final empty = await actions.create();
      final kept = await actions.create();
      await actions.save(kept.id, 'keep me');

      final purged = await actions.purgeEmpty();

      expect(purged, 1);
      expect(await db.getNote(empty.id), isNull);
      expect(await db.getNote(kept.id), isNotNull);
    });
  });

  group('addTag / removeTag (find-or-create, Ticket 05)', () {
    test('addTag creates a new tag when none exists', () async {
      final note = await actions.create();

      await actions.addTag(note.id, '  Groceries  ');

      final tags = await db.tagsForNote(note.id);
      expect(tags, hasLength(1));
      expect(tags.first.name, 'groceries');
    });

    test('addTag reuses an existing tag (case-insensitive)', () async {
      await db.createTag('errands');
      final note = await actions.create();

      await actions.addTag(note.id, 'ERRANDS');

      expect(await db.allTags(), hasLength(1));
      expect(await db.tagsForNote(note.id), hasLength(1));
    });

    test('addTag is a no-op for a blank name', () async {
      final note = await actions.create();

      await actions.addTag(note.id, '   ');

      expect(await db.tagsForNote(note.id), isEmpty);
      expect(await db.allTags(), isEmpty);
    });

    test('removeTag unlinks without deleting the tag', () async {
      final note = await actions.create();
      await actions.addTag(note.id, 'keep-tag');
      final tag = (await db.tagsForNote(note.id)).single;

      await actions.removeTag(note.id, tag.id);

      expect(await db.tagsForNote(note.id), isEmpty);
      expect(await db.allTags(), hasLength(1));
    });
  });
}
