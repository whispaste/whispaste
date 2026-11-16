/// Application order of the replacement rules (#1004): the list order the
/// cascade runs in, changed by drag & drop or the move buttons.
library;

/// [ids] with [id] moved by [delta] places. Unknown ids and moves past
/// either end leave the order unchanged.
List<String> movedReplacementIds(List<String> ids, String id, int delta) {
  final result = [...ids];
  final from = result.indexOf(id);
  if (from < 0) return result;
  final to = from + delta;
  if (to < 0 || to >= result.length) return result;
  result
    ..removeAt(from)
    ..insert(to, id);
  return result;
}

/// [ids] after dragging the item at [oldIndex] to [newIndex] (indices as
/// `ReorderableListView.onReorderItem` reports them: already adjusted).
List<String> reorderedReplacementIds(
  List<String> ids,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= ids.length) return [...ids];
  final result = [...ids];
  final id = result.removeAt(oldIndex);
  result.insert(newIndex.clamp(0, result.length), id);
  return result;
}
