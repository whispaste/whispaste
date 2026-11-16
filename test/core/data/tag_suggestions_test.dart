/// The tag suggestions of the tag inputs (#830): the most used tags while the
/// field is empty, tags starting with the typed text otherwise.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/tag_suggestions.dart';

void main() {
  late HistoryDatabase db;

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    final n1 = await db.createNote();
    final n2 = await db.createNote();
    final often = await db.createTag('projekt');
    final once = await db.createTag('privat');
    await db.createTag('unused');
    await db.tagNote(n1.id, often.id);
    await db.tagNote(n2.id, often.id);
    await db.tagNote(n2.id, once.id);
  });

  tearDown(() => db.close());

  test(
    'an empty query offers the used tags, most used first, with counts',
    () async {
      final result = await loadTagSuggestions(db, '  ');
      expect([for (final t in result.tags) t.name], ['projekt', 'privat']);
      expect(result.counts.values, [2, 1]);
    },
  );

  test('a typed prefix offers the matching tags, used or not', () async {
    final result = await loadTagSuggestions(db, 'pr');
    expect([for (final t in result.tags) t.name], ['privat', 'projekt']);
    expect(result.counts, isEmpty);
    expect(
      [for (final t in (await loadTagSuggestions(db, 'UN')).tags) t.name],
      ['unused'],
    );
  });
}
