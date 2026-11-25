/// Sort order of the user-maintained lists (Replacements, Snippets).
///
/// Pure Dart: the comparator and the sort state are testable without
/// widgets or a database. The display order is a view concern only. The
/// replacement cascade runs in the user's application order (`sort_position`,
/// set in the "Change order" dialog) and never reads these sorts, see
/// `readAllReplacements` in `database.dart`.
library;

import '../utils/search_fold.dart';

/// Fields a list can be sorted by. A list offers a subset, see [ListSort.decode].
enum ListSortField {
  title,
  trigger,
  result,
  added,
  changed,
  used,

  /// The list's own order (replacements: the order the rules apply in,
  /// #1969). Lists with it keep their stored order and do not sort.
  order,
}

/// What the comparator needs from one list entry. Text fields compare
/// [sortTitle] (title, or first trigger) and [sortResult]; date fields use
/// [sortCreatedAt] and [sortChangedAt].
abstract interface class ListSortable {
  /// Stable identity, the last tie-break of the order.
  String get sortId;

  /// The text the A–Z order and every tie is decided on.
  String get sortTitle;

  /// Result text of an entry, or `''` for lists without one.
  String get sortResult;

  DateTime get sortCreatedAt;

  /// Last content change, falling back to the creation time for rows written
  /// before the column existed.
  DateTime get sortChangedAt;
}

/// A [ListSortable] that records how it is used (snippets). Lists of entries
/// without usage do not implement it and never offer [ListSortField.used].
abstract interface class UsageSortable implements ListSortable {
  /// When the entry was last used, or `null` if it never was.
  DateTime? get sortUsedAt;
}

/// The chosen order of one list: a field plus a direction.
///
/// Natural direction is A–Z for text fields and newest first for dates.
/// [reversed] flips only the primary key, so the tie rules stay the same.
class ListSort {
  const ListSort(this.field, {this.reversed = false});

  final ListSortField field;
  final bool reversed;

  /// Persisted form: `trigger`, or `trigger:reversed`.
  String encode() => reversed ? '${field.name}:reversed' : field.name;

  /// Reads a persisted value. Null for a missing, malformed or unknown value,
  /// and for a field that [allowed] does not offer, so the caller falls back
  /// to its default.
  static ListSort? decode(String? raw, {required Set<ListSortField> allowed}) {
    if (raw == null) return null;
    final parts = raw.split(':');
    ListSortField? field;
    for (final candidate in ListSortField.values) {
      if (candidate.name == parts.first) field = candidate;
    }
    if (field == null || !allowed.contains(field)) return null;
    if (parts.length == 1) return ListSort(field);
    if (parts.length == 2 && parts[1] == 'reversed') {
      return ListSort(field, reversed: true);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ListSort && other.field == field && other.reversed == reversed;

  @override
  int get hashCode => Object.hash(field, reversed);

  @override
  String toString() => 'ListSort(${encode()})';
}

/// Sorts [items] by [sort]. Every comparison is total, so the result does not
/// depend on the input order.
List<T> sortListItems<T extends ListSortable>(
  Iterable<T> items,
  ListSort sort,
) {
  final sorted = items.toList()..sort((a, b) => compareListItems(a, b, sort));
  return sorted;
}

/// Orders two entries: primary key by [sort], then A–Z on the text key, then
/// creation time (earliest first), then [ListSortable.sortId].
int compareListItems(ListSortable a, ListSortable b, ListSort sort) {
  var primary = switch (sort.field) {
    ListSortField.title ||
    ListSortField.trigger => compareListText(a.sortTitle, b.sortTitle),
    ListSortField.result => compareListText(a.sortResult, b.sortResult),
    // Dates: natural order is newest first.
    ListSortField.added => b.sortCreatedAt.compareTo(a.sortCreatedAt),
    ListSortField.changed => b.sortChangedAt.compareTo(a.sortChangedAt),
    // Most recently used first; entries never used follow all used ones.
    ListSortField.used => _compareUsed(a, b),
    // Not sorted: the caller keeps the stored order (see the field).
    ListSortField.order => 0,
  };
  if (sort.reversed) primary = -primary;
  if (primary != 0) return primary;

  final byText = compareListText(a.sortTitle, b.sortTitle);
  if (byText != 0) return byText;
  final byCreated = a.sortCreatedAt.compareTo(b.sortCreatedAt);
  if (byCreated != 0) return byCreated;
  return a.sortId.compareTo(b.sortId);
}

int _compareUsed(ListSortable a, ListSortable b) {
  final usedA = a is UsageSortable ? a.sortUsedAt : null;
  final usedB = b is UsageSortable ? b.sortUsedAt : null;
  if (usedA == null || usedB == null) {
    if (usedA == null && usedB == null) return 0;
    return usedA == null ? 1 : -1;
  }
  return usedB.compareTo(usedA);
}

/// Orders [items] A–Z by [textOf] with [compareListText], for callers that
/// have no sort state, e.g. the snippet picker's title order without a search
/// term.
List<T> sortedByText<T>(Iterable<T> items, String Function(T) textOf) {
  final sorted = items.toList()
    ..sort((a, b) => compareListText(textOf(a), textOf(b)));
  return sorted;
}

/// Language-aware A–Z for list labels.
///
/// Compares case-insensitively and diacritic-insensitively (`ä` ≈ `a`,
/// via [foldForSearch]). Leading characters that are neither letters nor
/// digits (spaces, punctuation) are skipped. Digit runs compare by value, so
/// `2` sorts before `10`. Ties on that key fall back to the raw strings, so
/// two different strings never compare equal.
int compareListText(String a, String b) {
  final byKey = _naturalCompare(_sortKey(a), _sortKey(b));
  if (byKey != 0) return byKey;
  return a.compareTo(b);
}

final _firstLetterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The folded text from its first letter or digit on.
String _sortKey(String text) {
  final folded = foldForSearch(text);
  final match = _firstLetterOrDigit.firstMatch(folded);
  return match == null ? '' : folded.substring(match.start);
}

bool _isAsciiDigit(int unit) => unit >= 0x30 && unit <= 0x39;

int _naturalCompare(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    if (_isAsciiDigit(ca) && _isAsciiDigit(cb)) {
      var endA = i;
      while (endA < a.length && _isAsciiDigit(a.codeUnitAt(endA))) {
        endA++;
      }
      var endB = j;
      while (endB < b.length && _isAsciiDigit(b.codeUnitAt(endB))) {
        endB++;
      }
      final numA = a.substring(i, endA).replaceFirst(RegExp('^0+'), '');
      final numB = b.substring(j, endB).replaceFirst(RegExp('^0+'), '');
      if (numA.length != numB.length) {
        return numA.length.compareTo(numB.length);
      }
      final byValue = numA.compareTo(numB);
      if (byValue != 0) return byValue;
      i = endA;
      j = endB;
    } else {
      if (ca != cb) return ca.compareTo(cb);
      i++;
      j++;
    }
  }
  return (a.length - i).compareTo(b.length - j);
}
