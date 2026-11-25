/// Tags, favourites and the list filter of the Textbausteine page (#662).
/// The logic is pure, so it is tested without a widget; the page and the
/// providers below only wire it up.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/database.dart';
import '../../core/sorting/list_sort.dart';
import 'snippet_item.dart';

/// What the page shows: the active library, only its favourites, or the
/// trash. The same view choice as on Recordings (all, favourites, trash).
enum SnippetsView { active, favourites, trash }

/// Every snippet→tags link, grouped by snippet id, tags by name. The list
/// rows, the tag filter and the editor's tag field all read this one map.
final allSnippetTagsProvider = StreamProvider<Map<String, List<Tag>>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchAllSnippetTags();
});

/// The tags at least one of [items] carries, by name. A chosen tag that no
/// active snippet carries any more is not offered and does not filter.
List<Tag> snippetTagsInUse(
  List<SnippetItem> items,
  Map<String, List<Tag>> tagsBySnippetId,
) {
  final unique = <String, Tag>{
    for (final s in items)
      for (final tag in tagsBySnippetId[s.id] ?? const <Tag>[]) tag.id: tag,
  };
  return unique.values.toList()
    ..sort((a, b) => compareListText(a.name, b.name));
}

/// [items] narrowed to favourites ([favouritesOnly]) and to snippets that
/// carry every tag of [tagIds]. Order stays as given. Tag ids that no item
/// carries are ignored by the caller ([snippetTagsInUse]), not here.
List<SnippetItem> filterSnippets(
  List<SnippetItem> items, {
  bool favouritesOnly = false,
  Set<String> tagIds = const {},
  Map<String, List<Tag>> tagsBySnippetId = const {},
}) {
  if (!favouritesOnly && tagIds.isEmpty) return items;
  return [
    for (final s in items)
      if ((!favouritesOnly || s.isFavorite) &&
          _carriesAll(tagsBySnippetId[s.id], tagIds))
        s,
  ];
}

bool _carriesAll(List<Tag>? tags, Set<String> tagIds) {
  if (tagIds.isEmpty) return true;
  if (tags == null || tags.isEmpty) return false;
  final carried = {for (final t in tags) t.id};
  return carried.containsAll(tagIds);
}
