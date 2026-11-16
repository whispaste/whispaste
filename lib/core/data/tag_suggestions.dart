/// Tag suggestions for the tag inputs of the history detail and the note
/// editor (#830): one loader, so both offer the same tags in the same order.
library;

import 'database.dart';

/// Suggested tags and, for the unfiltered case, how often each is used.
typedef TagSuggestions = ({List<Tag> tags, Map<String, int> counts});

/// The tags to offer for the typed [query]: the most used ones while it is
/// empty (with their counts), else the tags starting with it.
Future<TagSuggestions> loadTagSuggestions(
  HistoryDatabase db,
  String query,
) async {
  if (query.trim().isEmpty) {
    final results = await db.frequentTagsWithCount(limit: 8);
    return (
      tags: [for (final r in results) r.$1],
      counts: {for (final r in results) r.$1.id: r.$2},
    );
  }
  return (tags: await db.searchTags(query), counts: const <String, int>{});
}
