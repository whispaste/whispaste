/// [filteredNotesProvider] filter-logic tests (Ticket 06) — pure
/// [ProviderContainer], `Stream.value` fixtures for `notesProvider`/
/// `trashNotesProvider`/`allNoteTagsProvider`. No FTS/DB search for
/// Notizen (per the Ticket-02 plan): matching is in-memory only, so this
/// stays at the provider layer rather than needing a widget tree.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/providers.dart';

Note _sampleNote({
  required String id,
  required String content,
  DateTime? updatedAt,
}) {
  final t = updatedAt ?? DateTime(2025, 6, 1);
  return Note(
    id: id,
    content: content,
    pinned: false,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

Tag _sampleTag(String id, String name) =>
    Tag(id: id, name: name, createdAt: DateTime(2025, 6, 1));

void main() {
  late List<Note> activeNotes;
  late List<Note> trashNotes;
  late Map<String, List<Tag>> tagsByNoteId;
  late ProviderContainer container;

  setUp(() {
    activeNotes = [
      _sampleNote(id: 'n1', content: 'Grocery list: milk, eggs'),
      _sampleNote(id: 'n2', content: 'Meeting agenda for Monday'),
    ];
    trashNotes = [_sampleNote(id: 'n3', content: 'Old grocery list')];
    tagsByNoteId = {
      'n2': [_sampleTag('t1', 'work')],
    };

    container = ProviderContainer(
      overrides: [
        notesProvider.overrideWith((ref) => Stream.value(activeNotes)),
        trashNotesProvider.overrideWith((ref) => Stream.value(trashNotes)),
        allNoteTagsProvider.overrideWith((ref) => Stream.value(tagsByNoteId)),
      ],
    );
    // Prime the underlying stream providers before reading the derived one.
    container.listen(notesProvider, (_, _) {});
    container.listen(trashNotesProvider, (_, _) {});
    container.listen(allNoteTagsProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  List<Note> read() => container.read(filteredNotesProvider).value ?? const [];

  group('empty query', () {
    test('passes the active-filter stream through unchanged', () {
      expect(read().map((n) => n.id).toList(), ['n1', 'n2']);
    });

    test('passes the trash-filter stream through unchanged', () {
      container.read(notesFilterProvider.notifier).set(NotesFilter.trash);
      expect(read().map((n) => n.id).toList(), ['n3']);
    });
  });

  group('non-empty query', () {
    test('matches by content substring, case-insensitively', () {
      container.read(notesSearchProvider.notifier).set('GROCERY');
      expect(read().map((n) => n.id).toList(), ['n1']);
    });

    test('matches by linked tag name', () {
      container.read(notesSearchProvider.notifier).set('work');
      expect(read().map((n) => n.id).toList(), ['n2']);
    });

    test('excludes notes matching neither content nor tags', () {
      container.read(notesSearchProvider.notifier).set('nonexistent');
      expect(read(), isEmpty);
    });

    test('only searches the currently active filter (trash)', () {
      container.read(notesFilterProvider.notifier).set(NotesFilter.trash);
      container.read(notesSearchProvider.notifier).set('grocery');
      expect(read().map((n) => n.id).toList(), ['n3']);
    });

    test('trash notes never leak into the active-filter results', () {
      container.read(notesSearchProvider.notifier).set('grocery');
      expect(read().map((n) => n.id).toList(), ['n1']);
    });
  });
}
