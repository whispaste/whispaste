/// Riverpod providers for history data — bridges Drift streams to UI.
library;

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/content_metadata.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';

import 'package:whispaste/core/views/smart_view.dart';
import 'package:whispaste/core/views/smart_view_items.dart';
import 'package:whispaste/core/views/smart_view_providers.dart';

import 'search_query_parser.dart';
export 'search_query_parser.dart';

// Re-export base data-stream providers from core so existing feature-local
// imports continue to work without changes.
export 'package:whispaste/core/data/history_providers.dart';

/// Active filter state for the history page.
enum HistoryFilter { all, pinned, archived, trash }

class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => HistoryFilter.all;

  void set(HistoryFilter filter) => state = filter;
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilter>(
      HistoryFilterNotifier.new,
    );

/// The duration chips of the history page (#879): exactly one is active.
///
/// The bounds are inclusive in the middle: under 1 min is `< 60 s`, 1–5 min
/// is `60 s ..= 300 s`, over 5 min is `> 300 s`, so every length lands in
/// exactly one bucket.
enum HistoryDurationBucket {
  all('all'),
  short('short'),
  medium('medium'),
  long('long');

  const HistoryDurationBucket(this.token);

  /// Stable, language-independent id part (`history-duration-<token>`).
  final String token;

  static const double shortMaxSec = 60;
  static const double longMinSec = 300;

  /// Whether a recording of [durationSec] seconds belongs to this bucket.
  bool matches(double durationSec) => switch (this) {
    all => true,
    short => durationSec < shortMaxSec,
    medium => durationSec >= shortMaxSec && durationSec <= longMinSec,
    long => durationSec > longMinSec,
  };

  /// The same bounds for the database queries; null when every length counts.
  HistoryDurationBounds? get bounds => switch (this) {
    all => null,
    short => const HistoryDurationBounds(below: shortMaxSec),
    medium => const HistoryDurationBounds(
      atLeast: shortMaxSec,
      atMost: longMinSec,
    ),
    long => const HistoryDurationBounds(above: longMinSec),
  };
}

class HistoryDurationBucketNotifier extends Notifier<HistoryDurationBucket> {
  @override
  HistoryDurationBucket build() => HistoryDurationBucket.all;

  void set(HistoryDurationBucket bucket) => state = bucket;
}

final historyDurationBucketProvider =
    NotifierProvider<HistoryDurationBucketNotifier, HistoryDurationBucket>(
      HistoryDurationBucketNotifier.new,
    );

/// [entries] narrowed to [bucket]; the list itself when every length counts.
List<HistoryEntry> applyDurationBucket(
  List<HistoryEntry> entries,
  HistoryDurationBucket bucket,
) => bucket == HistoryDurationBucket.all
    ? entries
    : entries.where((e) => bucket.matches(e.durationSec)).toList();

/// Search query for the history page.
class HistorySearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final historySearchProvider = NotifierProvider<HistorySearchNotifier, String>(
  HistorySearchNotifier.new,
);

/// Sort order of the history page for the session (#1074, #1663). The lists
/// and the search read it in SQL, so it reaches every match, not only the
/// loaded page.
class HistorySortOrderNotifier extends Notifier<HistorySortOrder> {
  @override
  HistorySortOrder build() => HistorySortOrder.newest;

  void set(HistorySortOrder order) => state = order;
}

final historySortOrderProvider =
    NotifierProvider<HistorySortOrderNotifier, HistorySortOrder>(
      HistorySortOrderNotifier.new,
    );

/// [a] before [b] in [order], the same as [historyOrderBy] does in SQL. For
/// rows that are put together in Dart (bulk copy and export of selected
/// entries that were not loaded).
int compareHistoryEntries(
  HistorySortOrder order,
  HistoryEntry a,
  HistoryEntry b,
) {
  int newerFirst() {
    final byTime = b.timestamp.compareTo(a.timestamp);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  switch (order) {
    case HistorySortOrder.newest:
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return newerFirst();
    case HistorySortOrder.oldest:
      return -newerFirst();
    case HistorySortOrder.longest:
      final byLength = b.durationSec.compareTo(a.durationSec);
      return byLength != 0 ? byLength : newerFirst();
  }
}

/// Archive and trash load whole (no paging), newest first by their own
/// clock (the trash by deletion). The other orders apply in Dart.
List<HistoryEntry> _sortStored(
  List<HistoryEntry> entries,
  HistorySortOrder order,
) => switch (order) {
  HistorySortOrder.newest => entries,
  HistorySortOrder.oldest => entries.reversed.toList(),
  HistorySortOrder.longest => [
    ...entries,
  ]..sort((a, b) => compareHistoryEntries(order, a, b)),
};

/// A bounded live window keeps mutations atomic across page boundaries. The
/// existing rows remain visible while the window grows, including on undo.
/// Every list of the Aufnahmen page loads in these pages, with and without a
/// search, so no view holds the whole history in memory (#1643).
const historyPageSize = 50;

class HistoryPageLimit extends Notifier<int> {
  @override
  int build() {
    ref.watch(historyFilterProvider);
    ref.watch(historySearchProvider);
    ref.watch(historyDurationBucketProvider);
    ref.watch(historySortOrderProvider);
    return historyPageSize;
  }

  /// Grows the window by one page. Callers guard with [historyHasMoreProvider]
  /// (true only once the current window has loaded), so this never runs ahead
  /// of the data and needs no read of the paged stream itself.
  void loadMore() => state += historyPageSize;
}

final historyPageLimitProvider = NotifierProvider<HistoryPageLimit, int>(
  HistoryPageLimit.new,
);

/// The live window of the "all" or "pinned" list: one row more than the page
/// limit, so [historyHasMoreProvider] knows whether another page follows. The
/// pinned filter and the duration chip narrow it in SQL, so a page is always
/// a full page of matches.
final pagedHistoryProvider = StreamProvider.autoDispose<List<HistoryEntry>>((
  ref,
) {
  final limit = ref.watch(historyPageLimitProvider);
  final pinnedOnly = ref.watch(historyFilterProvider) == HistoryFilter.pinned;
  final bucket = ref.watch(historyDurationBucketProvider);
  return ref
      .watch(historyDatabaseProvider)
      .watchEntries(
        limit: limit + 1,
        pinnedOnly: pinnedOnly,
        duration: bucket.bounds,
        sort: ref.watch(historySortOrderProvider),
      );
});

final historyHasMoreProvider = Provider<bool>((ref) {
  final filter = ref.watch(historyFilterProvider);
  final rawSearch = ref.watch(historySearchProvider).trim();
  if (!parseSearchQuery(rawSearch).isEmpty) {
    final page = ref.watch(historySearchPageProvider).value;
    return page != null &&
        page.matches(
          rawSearch,
          filter,
          ref.watch(historyDurationBucketProvider),
          ref.watch(historySortOrderProvider),
        ) &&
        page.rows.length > page.limit;
  }
  // Archive and trash are not paged.
  if (filter == HistoryFilter.archived || filter == HistoryFilter.trash) {
    return false;
  }
  final limit = ref.watch(historyPageLimitProvider);
  return (ref.watch(pagedHistoryProvider).value?.length ?? 0) > limit;
});

/// Filtered and searched history entries— the main data source for the list.
///
/// The duration chip narrows whatever the filter and the search return, so
/// all three combine. A saved view (#658) narrows the loaded rows of the
/// live list on top; "Mehr laden" reads further rows into it.
final filteredHistoryProvider = Provider<AsyncValue<List<HistoryEntry>>>((ref) {
  final bucket = ref.watch(historyDurationBucketProvider);
  final view = _shownHistoryView(ref);
  final checklists = view != null && smartViewNeedsChecklists(view)
      ? ref.watch(checklistDocumentsProvider).value ?? const <ContentKey>{}
      : const <ContentKey>{};
  final now = clock.now();
  return _filteredBySearch(ref).whenData((entries) {
    final narrowed = applyDurationBucket(entries, bucket);
    if (view == null) return narrowed;
    return [
      for (final e in narrowed)
        if (smartViewMatches(
          view,
          recordingSmartViewItem(
            e,
            hasChecklist:
                checklists.contains((kind: ContentKind.recording, id: e.id)) ||
                checklists.contains((
                  kind: ContentKind.recordingEdited,
                  id: e.id,
                )),
          ),
          now,
        ))
          e,
    ];
  });
});

/// The view the Aufnahmen page shows now; views narrow only the live list,
/// not the archive or the trash.
final shownHistorySmartViewProvider = Provider<SmartView?>((ref) {
  final filter = ref.watch(historyFilterProvider);
  if (filter == HistoryFilter.archived || filter == HistoryFilter.trash) {
    return null;
  }
  return ref.watch(shownSmartViewProvider(SmartViewScope.recordings));
});

SmartView? _shownHistoryView(Ref ref) =>
    ref.watch(shownHistorySmartViewProvider);

AsyncValue<List<HistoryEntry>> _filteredBySearch(Ref ref) {
  final filter = ref.watch(historyFilterProvider);
  final rawSearch = ref.watch(historySearchProvider).trim();
  final parsed = parseSearchQuery(rawSearch);

  if (parsed.isEmpty) {
    if (filter == HistoryFilter.archived || filter == HistoryFilter.trash) {
      return _storedList(ref, filter);
    }
    return _pagedWindow(ref);
  }

  // A database search, one page at a time (FTS5 + tag join + operators).
  final pageAsync = ref.watch(historySearchPageProvider);
  if (pageAsync case AsyncError(:final error, :final stackTrace)) {
    // Errors surface so the page can show a failure, not "No results"
    // (UIA-HIS-10).
    return AsyncValue.error(error, stackTrace);
  }
  final page = pageAsync.value;
  final archiveOrTrash =
      filter == HistoryFilter.archived || filter == HistoryFilter.trash;
  if (page != null &&
      page.matches(
        rawSearch,
        filter,
        ref.watch(historyDurationBucketProvider),
        ref.watch(historySortOrderProvider),
      )) {
    final rows = page.rows.take(page.limit).toList();
    // An empty free-text result of the active list falls through to the
    // in-memory search below (test environments without data).
    if (rows.isNotEmpty || parsed.freeText.isEmpty || archiveOrTrash) {
      return AsyncValue.data(_applyFilter(rows, filter));
    }
  }

  // In-memory search on the loaded rows while the database search loads.
  final AsyncValue<List<HistoryEntry>> loaded = switch (filter) {
    HistoryFilter.archived || HistoryFilter.trash => _storedList(ref, filter),
    _ => _pagedWindow(ref),
  };
  return loaded.whenData(
    (entries) => _applyFilter(_applyParsedSearch(entries, parsed), filter),
  );
}

/// The loaded page of the "all" or "pinned" list. The pinned filter is
/// applied again in Dart: it costs nothing and keeps a stream that is not
/// narrowed in SQL correct.
AsyncValue<List<HistoryEntry>> _pagedWindow(Ref ref) {
  final filter = ref.watch(historyFilterProvider);
  final limit = ref.watch(historyPageLimitProvider);
  return ref
      .watch(pagedHistoryProvider)
      .whenData(
        (entries) => _applyFilter(entries.take(limit).toList(), filter),
      );
}

/// Archive or trash, whole, in the chosen order.
AsyncValue<List<HistoryEntry>> _storedList(Ref ref, HistoryFilter filter) {
  final order = ref.watch(historySortOrderProvider);
  final stored = filter == HistoryFilter.archived
      ? ref.watch(archivedEntriesProvider)
      : ref.watch(trashEntriesProvider);
  return stored.whenData((entries) => _sortStored(entries, order));
}

/// One window of a search on the Aufnahmen page: up to [limit] + 1 [rows]
/// for the [query], list, duration chip and order it was read for. [spec]
/// is the query that found them (with or without the substring pass).
class HistorySearchPage {
  const HistorySearchPage({
    required this.query,
    required this.filter,
    required this.bucket,
    required this.sort,
    required this.limit,
    required this.rows,
    required this.spec,
  });

  final String query;
  final HistoryFilter filter;
  final HistoryDurationBucket bucket;
  final HistorySortOrder sort;
  final int limit;
  final List<HistoryEntry> rows;
  final HistorySearchSpec spec;

  /// Whether this window answers the search shown now. While the next page
  /// loads the previous window of the same search stays visible; a window
  /// of another search or order never does.
  bool matches(
    String rawSearch,
    HistoryFilter filter,
    HistoryDurationBucket bucket,
    HistorySortOrder sort,
  ) =>
      query == rawSearch &&
      this.filter == filter &&
      this.bucket == bucket &&
      this.sort == sort;
}

/// The search of the current list, one page more each time the user scrolls
/// to its end (#1643). Rebuilt on every change of query, list, chip or page
/// limit; the previous window stays readable while the next one loads.
final historySearchPageProvider =
    FutureProvider.autoDispose<HistorySearchPage?>((ref) async {
      final rawSearch = ref.watch(historySearchProvider).trim();
      final parsed = parseSearchQuery(rawSearch);
      if (parsed.isEmpty) return null;
      final filter = ref.watch(historyFilterProvider);
      final bucket = ref.watch(historyDurationBucketProvider);
      final sort = ref.watch(historySortOrderProvider);
      final limit = ref.watch(historyPageLimitProvider);
      final db = ref.watch(historyDatabaseProvider);

      var spec = _searchSpec(parsed, filter: filter, bucket: bucket);
      var rows = await db.searchHistory(spec, sort: sort, limit: limit + 1);
      final activeList =
          filter == HistoryFilter.all || filter == HistoryFilter.pinned;
      if (rows.isEmpty && parsed.freeText.isNotEmpty && activeList) {
        // The index matches word beginnings only: a part from the middle of a
        // word is looked up in titles and previews of the active list instead.
        spec = spec.copyWith(substring: true, archived: false, deleted: false);
        rows = await db.searchHistory(spec, sort: sort, limit: limit + 1);
      }
      return HistorySearchPage(
        query: rawSearch,
        filter: filter,
        bucket: bucket,
        sort: sort,
        limit: limit,
        rows: rows,
        spec: spec,
      );
    });

/// The database search of [parsed] on the list of [filter], narrowed to the
/// duration chip [bucket].
HistorySearchSpec _searchSpec(
  ParsedSearchQuery parsed, {
  required HistoryFilter filter,
  required HistoryDurationBucket bucket,
}) {
  final range = _range(parsed);
  return HistorySearchSpec(
    freeText: parsed.freeText,
    tagNames: parsed.tagNames,
    langCode: parsed.langCode,
    from: range?.from,
    to: range?.to,
    longerThanSec: parsed.longerThanSec,
    shorterThanSec: parsed.shorterThanSec,
    duration: bucket.bounds,
    pinnedOnly: filter == HistoryFilter.pinned,
    includeArchived: filter == HistoryFilter.archived,
    includeDeleted: filter == HistoryFilter.trash,
    archived: filter == HistoryFilter.archived ? true : null,
    deleted: switch (filter) {
      HistoryFilter.archived => false,
      HistoryFilter.trash => true,
      _ => null,
    },
  );
}

/// The query behind the list shown now (#1663): list, duration chip and
/// search, as the database reads them. Null while a search has not answered
/// yet. "Alle auswählen" reads the ids of every match through it, and a
/// selection keeps the matches that are not loaded yet.
final historyListSpecProvider = Provider.autoDispose<HistorySearchSpec?>((ref) {
  // A saved view is applied in Dart (#658): no query reads exactly its
  // rows, so "Alle auswählen" and the count stay with the loaded rows.
  if (_shownHistoryView(ref) != null) return null;
  final rawSearch = ref.watch(historySearchProvider).trim();
  final filter = ref.watch(historyFilterProvider);
  final bucket = ref.watch(historyDurationBucketProvider);
  if (parseSearchQuery(rawSearch).isEmpty) {
    return HistorySearchSpec(
      duration: bucket.bounds,
      pinnedOnly: filter == HistoryFilter.pinned,
      // The trash holds archived entries too.
      includeArchived: filter == HistoryFilter.trash,
      includeDeleted: filter == HistoryFilter.trash,
      archived: filter == HistoryFilter.archived ? true : null,
      deleted: switch (filter) {
        HistoryFilter.trash => true,
        HistoryFilter.archived => false,
        _ => null,
      },
    );
  }
  final page = ref.watch(historySearchPageProvider).value;
  final sort = ref.watch(historySortOrderProvider);
  return page != null && page.matches(rawSearch, filter, bucket, sort)
      ? page.spec
      : null;
});

/// How many recordings the list shown now holds in all, loaded or not
/// (#1663); null while unknown. Counted in SQL and read again after every
/// write to the recordings.
final historyListCountProvider = FutureProvider.autoDispose<int?>((ref) async {
  ref.watch(historyRevisionProvider);
  final spec = ref.watch(historyListSpecProvider);
  if (spec == null) return null;
  return ref.watch(historyDatabaseProvider).countHistory(spec);
});

/// Per-filter match counts when a search query is active.
///
/// Returns a [Map] from [HistoryFilter] to the number of matching entries,
/// or `null` when the search field is empty (so chips show no count badge).
///
/// Counted in SQL with the same conditions as the list (#1643), so a period
/// or length operator narrows the badges as it narrows the list. A failed
/// search throws (UIA-HIS-10); the chips then show no count instead of a
/// misleading 0.
final searchCountsProvider = FutureProvider<Map<HistoryFilter, int>?>((
  ref,
) async {
  final rawSearch = ref.watch(historySearchProvider).trim();
  if (rawSearch.isEmpty) return null;
  final parsed = parseSearchQuery(rawSearch);
  if (parsed.isEmpty) return null;

  final db = ref.watch(historyDatabaseProvider);
  final bucket = ref.watch(historyDurationBucketProvider);
  HistorySearchSpec spec(HistoryFilter filter) =>
      _searchSpec(parsed, filter: filter, bucket: bucket);

  final counts = await Future.wait([
    // The badge of "all" counts only active entries, also when a free-text
    // match reaches archived ones.
    db.countHistory(spec(HistoryFilter.all).copyWith(archived: false)),
    db.countHistory(spec(HistoryFilter.pinned).copyWith(archived: false)),
    db.countHistory(spec(HistoryFilter.archived)),
    db.countHistory(spec(HistoryFilter.trash)),
  ]);
  return {
    HistoryFilter.all: counts[0],
    HistoryFilter.pinned: counts[1],
    HistoryFilter.archived: counts[2],
    HistoryFilter.trash: counts[3],
  };
});

/// The period of a `date:` operator as of now, or `null` without one.
({DateTime from, DateTime to})? _range(ParsedSearchQuery parsed) {
  final range = parsed.dateRange;
  return range == null ? null : resolveDateRange(range, clock.now());
}

/// Applies a [ParsedSearchQuery] to an in-memory list (fallback path).
///
/// This is the fallback path when the DB advanced search hasn't loaded yet.
/// Checks title, content, AND entry.tags JSON field for tag name matches.
List<HistoryEntry> _applyParsedSearch(
  List<HistoryEntry> entries,
  ParsedSearchQuery parsed,
) {
  // Pre-compile regexes outside the loop to avoid allocating a new lowercased
  // string per entry per filter — caseSensitive:false also fixes the two
  // filters below comparing a lowercased field against a non-lowercased term.
  final freeTextRegex = parsed.freeText.isNotEmpty
      ? RegExp(RegExp.escape(parsed.freeText), caseSensitive: false)
      : null;

  final langRegex = parsed.langCode != null && parsed.langCode!.isNotEmpty
      ? RegExp('^${RegExp.escape(parsed.langCode!)}', caseSensitive: false)
      : null;

  final tagRegexes = parsed.tagNames.isNotEmpty
      ? parsed.tagNames
            .map((t) => RegExp(RegExp.escape(t), caseSensitive: false))
            .toList()
      : null;

  final range = _range(parsed);
  return entries.where((e) {
    if (range != null &&
        (e.timestamp.isBefore(range.from) || !e.timestamp.isBefore(range.to))) {
      return false;
    }
    if (parsed.longerThanSec != null &&
        e.durationSec <= parsed.longerThanSec!) {
      return false;
    }
    if (parsed.shorterThanSec != null &&
        e.durationSec >= parsed.shorterThanSec!) {
      return false;
    }
    // Free-text match
    if (freeTextRegex != null) {
      if (!freeTextRegex.hasMatch(e.title) &&
          !freeTextRegex.hasMatch(e.content)) {
        return false;
      }
    }
    // Language filter
    if (langRegex != null) {
      if (!langRegex.hasMatch(e.language)) {
        return false;
      }
    }
    // Tag filter — check the JSON tags field on the entry
    if (tagRegexes != null) {
      for (final tagRegex in tagRegexes) {
        if (!tagRegex.hasMatch(e.tags)) return false;
      }
    }
    return true;
  }).toList();
}

/// Applies date/pin filter predicates to a list of entries.
List<HistoryEntry> _applyFilter(
  List<HistoryEntry> entries,
  HistoryFilter filter,
) {
  switch (filter) {
    case HistoryFilter.pinned:
      return entries.where((e) => e.pinned).toList();
    case HistoryFilter.all:
    case HistoryFilter.archived:
    case HistoryFilter.trash:
      return entries;
  }
}

/// Groups entries by relative date for section headers.
///
/// [label] uses l10n key IDs (e.g. 'today', 'yesterday') — the UI resolves
/// them via [DateGroup.resolve] or directly from [L10n].
class DateGroup {
  const DateGroup({required this.labelKey, required this.entries});

  /// Key identifier: 'today', 'yesterday', 'thisWeek', 'older'.
  final String labelKey;
  final List<HistoryEntry> entries;
}

/// Groups filtered entries into date sections (Today, Yesterday, This Week, Older).
///
/// The rows arrive in the chosen order (#1663). "Älteste" shows the sections
/// from Older to Today; "Längste" has one section, since length and day do
/// not go together.
final groupedHistoryProvider = Provider<AsyncValue<List<DateGroup>>>((ref) {
  final filteredAsync = ref.watch(filteredHistoryProvider);
  final order = ref.watch(historySortOrderProvider);

  return filteredAsync.whenData((entries) {
    if (entries.isEmpty) return [];
    if (order == HistorySortOrder.longest) {
      return [DateGroup(labelKey: 'all', entries: entries)];
    }

    final now = clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sixDaysAgo = today.subtract(const Duration(days: 6));

    final todayEntries = <HistoryEntry>[];
    final yesterdayEntries = <HistoryEntry>[];
    final weekEntries = <HistoryEntry>[];
    final olderEntries = <HistoryEntry>[];

    for (final e in entries) {
      // PERF (Bolt): Avoiding `DateTime(y, m, d)` allocation per entry.
      // Using integer property comparisons for exact days, and comparing
      // the original timestamp against a shifted threshold (`sixDaysAgo`)
      // instead of truncating `e.timestamp` and checking `.isAfter(weekAgo)`.
      // Reduces GC pressure significantly during search filtering.
      if (e.timestamp.year == today.year &&
          e.timestamp.month == today.month &&
          e.timestamp.day == today.day) {
        todayEntries.add(e);
      } else if (e.timestamp.year == yesterday.year &&
          e.timestamp.month == yesterday.month &&
          e.timestamp.day == yesterday.day) {
        yesterdayEntries.add(e);
      } else if (e.timestamp.compareTo(sixDaysAgo) >= 0) {
        weekEntries.add(e);
      } else {
        olderEntries.add(e);
      }
    }

    final groups = [
      if (todayEntries.isNotEmpty)
        DateGroup(labelKey: 'today', entries: todayEntries),
      if (yesterdayEntries.isNotEmpty)
        DateGroup(labelKey: 'yesterday', entries: yesterdayEntries),
      if (weekEntries.isNotEmpty)
        DateGroup(labelKey: 'thisWeek', entries: weekEntries),
      if (olderEntries.isNotEmpty)
        DateGroup(labelKey: 'older', entries: olderEntries),
    ];
    return order == HistorySortOrder.oldest ? groups.reversed.toList() : groups;
  });
});
