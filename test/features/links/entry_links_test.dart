import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/links/data/providers.dart';

void main() {
  group('resolving link targets (#660)', () {
    late HistoryDatabase db;
    setUp(() => db = HistoryDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('titles follow renames; trashed targets are not found', () async {
      final note = await db.createNote();
      await db.updateNoteContent(note.id, 'First line\nbody');
      await db.upsertSnippet(
        id: 's-1',
        title: 'Greeting',
        body: 'Hello',
        createdAt: DateTime(2026),
      );
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'r-1',
          timestamp: DateTime(2026),
          content: const Value('spoken words here'),
        ),
      );
      final refs = [
        (kind: EntryLinkKind.note, id: note.id),
        (kind: EntryLinkKind.snippet, id: 's-1'),
        (kind: EntryLinkKind.recording, id: 'r-1'),
        (kind: EntryLinkKind.note, id: 'gone'),
      ];

      var found = await resolveLinkedEntries(db, refs, includePrivate: true);
      expect(found[refs[0]]?.title, 'First line');
      expect(found[refs[1]]?.title, 'Greeting');
      expect(found[refs[2]]?.title, 'spoken words here');
      expect(found.containsKey(refs[3]), isFalse);

      await db.setNoteTitle(note.id, 'Renamed');
      await db.softDeleteEntry('r-1');
      found = await resolveLinkedEntries(db, refs, includePrivate: true);
      expect(found[refs[0]]?.title, 'Renamed');
      expect(found.containsKey(refs[2]), isFalse);

      // PIN lock closed: only snippets.
      found = await resolveLinkedEntries(db, refs, includePrivate: false);
      expect(found.keys, [refs[1]]);
    });

    test('recent targets leave out the entry being written', () async {
      final a = await db.createNote();
      await db.updateNoteContent(a.id, 'A');
      final b = await db.createNote();
      await db.updateNoteContent(b.id, 'B');
      final recent = await recentLinkTargets(
        db,
        includePrivate: true,
        except: (kind: EntryLinkKind.note, id: a.id),
      );
      final ids = recent.map((e) => e.ref.id);
      expect(ids, contains(b.id));
      expect(ids, isNot(contains(a.id)));
    });
  });

  group('back over a link', () {
    const a = (kind: EntryLinkKind.note, id: 'a');
    const b = (kind: EntryLinkKind.recording, id: 'b');
    const c = (kind: EntryLinkKind.snippet, id: 'c');

    test('a chain of jumps walks back step by step', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      followEntryLink(container.read, a, b);
      expect(container.read(historyOpenEntryProvider), 'b');
      expect(container.read(activePageProvider), 'history');
      followEntryLink(container.read, b, c);
      expect(container.read(snippetsOpenTargetProvider), 'c');

      // Only the target of the last jump offers "Back".
      final trail = container.read(entryLinkTrailProvider);
      expect(entryLinkBackTarget(trail, c), b);
      expect(entryLinkBackTarget(trail, b), isNull);

      expect(goBackOverEntryLink(container.read, c), isTrue);
      expect(container.read(historyOpenEntryProvider), 'b');
      expect(goBackOverEntryLink(container.read, b), isTrue);
      expect(container.read(notesRevealTargetProvider)?.noteId, 'a');
      expect(goBackOverEntryLink(container.read, a), isFalse);
    });

    test('a link to the entry itself goes nowhere', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      followEntryLink(container.read, a, a);
      expect(container.read(entryLinkTrailProvider), isEmpty);
    });
  });
}
