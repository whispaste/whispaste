/// Favourites-only and the tag filter of the Textbausteine list (#662).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippet_filters.dart';
import 'package:whispaste/features/snippets/snippet_item.dart';

void main() {
  SnippetItem item(String id, {bool favourite = false}) => SnippetItem(
    id: id,
    title: id,
    body: 'body',
    createdAt: DateTime(2026),
    isFavorite: favourite,
  );
  Tag tag(String id, String name) =>
      Tag(id: id, name: name, createdAt: DateTime(2026));

  final work = tag('t1', 'work');
  final mail = tag('t2', 'mail');
  final items = [item('a', favourite: true), item('b'), item('c')];
  final byId = {
    'a': [mail, work],
    'b': [work],
  };

  test('without a filter the list stays as given', () {
    expect(filterSnippets(items), same(items));
  });

  test('favourites only keeps the starred snippets', () {
    expect(filterSnippets(items, favouritesOnly: true).map((s) => s.id), ['a']);
  });

  test('a snippet must carry every chosen tag', () {
    List<String> ids(Set<String> tags) => [
      for (final s in filterSnippets(
        items,
        tagIds: tags,
        tagsBySnippetId: byId,
      ))
        s.id,
    ];
    expect(ids({'t1'}), ['a', 'b']);
    expect(ids({'t1', 't2'}), ['a']);
  });

  test('favourites and tags combine', () {
    final result = filterSnippets(
      [item('a', favourite: true), item('b', favourite: true)],
      favouritesOnly: true,
      tagIds: {'t2'},
      tagsBySnippetId: byId,
    );
    expect(result.map((s) => s.id), ['a']);
  });

  test('tags in use: only those the given snippets carry, by name', () {
    final inUse = snippetTagsInUse([item('b'), item('c')], byId);
    expect(inUse.map((t) => t.name), ['work']);
    expect(snippetTagsInUse(items, byId).map((t) => t.name), ['mail', 'work']);
  });
}
