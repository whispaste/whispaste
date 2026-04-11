/// Riverpod providers for history data — bridges Drift streams to UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'search_query_parser.dart';
export 'search_query_parser.dart';

// Re-export base data-stream providers from core so existing feature-local
// imports continue to work without changes.
export 'package:whispaste/core/data/history_providers.dart';

/// Active filter state for the history page.
enum HistoryFilter { all, today, week, pinned, archived, trash }

class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => HistoryFilter.all;

  void set(HistoryFilter filter) => state = filter;
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilter>(
        HistoryFilterNotifier.new);

/// Search query for the history page.
class HistorySearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final historySearchProvider =
    NotifierProvider<HistorySearchNotifier, String>(HistorySearchNotifier.new);

/// Filtered and searched history entries— the main data source for the list.
final filteredHistoryProvider = Provider<AsyncValue<List<HistoryEntry>>>((ref) {
  final filter = ref.watch(historyFilterProvider);
  final rawSearch = ref.watch(historySearchProvider).trim();
  final parsed = parseSearchQuery(rawSearch);

  // For archive/trash with search, use DB-level advanced search (FTS5 + tag join)
  // instead of in-memory filtering on a capped list.
  if (filter == HistoryFilter.archived) {
    if (parsed.isEmpty) return ref.watch(archivedEntriesProvider);
    final advAsync = ref.watch(_archivedSearchProvider(rawSearch));
    if (advAsync is AsyncData<List<HistoryEntry>>) {
      return AsyncValue.data(advAsync.value);
    }
    // Fall back to in-memory while DB search loads
    final archivedAsync = ref.watch(archivedEntriesProvider);
    return archivedAsync.whenData(
        (entries) => _applyParsedSearch(entries, parsed));
  }
  if (filter == HistoryFilter.trash) {
    if (parsed.isEmpty) return ref.watch(trashEntriesProvider);
    final advAsync = ref.watch(_trashSearchProvider(rawSearch));
    if (advAsync is AsyncData<List<HistoryEntry>>) {
      return AsyncValue.data(advAsync.value);
    }
    // Fall back to in-memory while DB search loads
    final trashAsync = ref.watch(trashEntriesProvider);
    return trashAsync.whenData(
        (entries) => _applyParsedSearch(entries, parsed));
  }

  final entriesAsync = ref.watch(historyEntriesProvider);

  if (!parsed.isEmpty) {
    // Has commands (tags/lang) or free-text: prefer advanced DB search.
    final advancedAsync = ref.watch(_advancedSearchProvider(rawSearch));
    if (advancedAsync is AsyncData<List<HistoryEntry>>) {
      final results = advancedAsync.value;
      // Use DB results when non-empty, or for tag/lang-only queries where
      // empty is genuinely "no matches" (in-memory can't filter by tags).
      // For free-text + empty DB result, fall through to in-memory (also
      // covers test environments where the DB has no data).
      if (results.isNotEmpty || parsed.freeText.isEmpty) {
        return AsyncValue.data(_applyFilter(results, filter));
      }
    }
    // Fall back to in-memory search while advanced search loads/errors
    return entriesAsync.whenData((entries) =>
        _applyFilter(_applyParsedSearch(entries, parsed), filter));
  }

  return entriesAsync.whenData((entries) => _applyFilter(entries, filter));
});

/// Advanced search (FTS5 + tag filter + lang filter) — auto-disposes on query change.
final _advancedSearchProvider =
    FutureProvider.autoDispose.family<List<HistoryEntry>, String>(
  (ref, rawQuery) async {
    final db = ref.watch(historyDatabaseProvider);
    final parsed = parseSearchQuery(rawQuery);
    try {
      return await db.searchEntriesAdvanced(
        freeText: parsed.freeText,
        tagNames: parsed.tagNames,
        langCode: parsed.langCode,
      );
    } catch (_) {
      return [];
    }
  },
);

/// Advanced search for archived entries (FTS5 + tag join).
final _archivedSearchProvider =
    FutureProvider.autoDispose.family<List<HistoryEntry>, String>(
  (ref, rawQuery) async {
    final db = ref.watch(historyDatabaseProvider);
    final parsed = parseSearchQuery(rawQuery);
    try {
      final results = await db.searchEntriesAdvanced(
        freeText: parsed.freeText,
        tagNames: parsed.tagNames,
        langCode: parsed.langCode,
        includeArchived: true,
      );
      // Filter to archived-only
      return results.where((e) => e.archived && e.deletedAt == null).toList();
    } catch (_) {
      return [];
    }
  },
);

/// Advanced search for trashed entries (FTS5 + tag join).
final _trashSearchProvider =
    FutureProvider.autoDispose.family<List<HistoryEntry>, String>(
  (ref, rawQuery) async {
    final db = ref.watch(historyDatabaseProvider);
    final parsed = parseSearchQuery(rawQuery);
    try {
      final results = await db.searchEntriesAdvanced(
        freeText: parsed.freeText,
        tagNames: parsed.tagNames,
        langCode: parsed.langCode,
        includeDeleted: true,
      );
      // Filter to trashed-only
      return results.where((e) => e.deletedAt != null).toList();
    } catch (_) {
      return [];
    }
  },
);

/// Per-filter match counts when a search query is active.
///
/// Returns a [Map] from [HistoryFilter] to the number of matching entries,
/// or `null` when the search field is empty (so chips show no count badge).
///
/// Uses SQL COUNT queries instead of in-memory filtering to avoid the O(n)
/// per-keystroke overhead and 500-entry cap inaccuracy.
final searchCountsProvider =
    FutureProvider<Map<HistoryFilter, int>?>((ref) async {
  final rawSearch = ref.watch(historySearchProvider).trim();
  if (rawSearch.isEmpty) return null;
  final parsed = parseSearchQuery(rawSearch);
  if (parsed.isEmpty) return null;

  final db = ref.watch(historyDatabaseProvider);

  // Run all count queries in parallel for responsiveness.
  final results = await Future.wait([
    db.countSearchMatches(rawSearch, pool: 'active'),
    db.countSearchMatches(rawSearch, pool: 'archived'),
    db.countSearchMatches(rawSearch, pool: 'trash'),
  ]);

  final activeCount = results[0];
  final archivedCount = results[1];
  final trashCount = results[2];

  // For sub-filters (today, week, pinned) we still need the active results
  // to apply date/pin predicates. Use the advanced search for active pool.
  List<HistoryEntry> activeMatched;
  try {
    final all = await db.searchEntriesAdvanced(
      freeText: parsed.freeText,
      tagNames: parsed.tagNames,
      langCode: parsed.langCode,
    );
    activeMatched = all.where((e) => !e.archived && e.deletedAt == null).toList();
  } catch (_) {
    activeMatched = [];
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekAgo = today.subtract(const Duration(days: 7));

  return {
    HistoryFilter.all: activeCount,
    HistoryFilter.today: activeMatched
        .where((e) {
          final d =
              DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
          return d == today;
        })
        .length,
    HistoryFilter.week: activeMatched
        .where((e) => e.timestamp.isAfter(weekAgo))
        .length,
    HistoryFilter.pinned: activeMatched.where((e) => e.pinned).length,
    HistoryFilter.archived: archivedCount,
    HistoryFilter.trash: trashCount,
  };
});

/// Applies a [ParsedSearchQuery] to an in-memory list (fallback path).
///
/// This is the fallback path when the DB advanced search hasn't loaded yet.
/// Checks title, content, AND entry.tags JSON field for tag name matches.
List<HistoryEntry> _applyParsedSearch(
    List<HistoryEntry> entries, ParsedSearchQuery parsed) {
  return entries.where((e) {
    // Free-text match
    if (parsed.freeText.isNotEmpty) {
      final lower = parsed.freeText.toLowerCase();
      if (!e.title.toLowerCase().contains(lower) &&
          !e.content.toLowerCase().contains(lower)) {
        return false;
      }
    }
    // Language filter
    if (parsed.langCode != null && parsed.langCode!.isNotEmpty) {
      if (!e.language.toLowerCase().startsWith(parsed.langCode!)) {
        return false;
      }
    }
    // Tag filter — check the JSON tags field on the entry
    if (parsed.tagNames.isNotEmpty) {
      final entryTags = e.tags.toLowerCase();
      for (final tag in parsed.tagNames) {
        if (!entryTags.contains(tag)) return false;
      }
    }
    return true;
  }).toList();
}

/// Applies date/pin filter predicates to a list of entries.
List<HistoryEntry> _applyFilter(
    List<HistoryEntry> entries, HistoryFilter filter) {
  final now = DateTime.now();
  switch (filter) {
    case HistoryFilter.today:
      return entries
          .where((e) =>
              e.timestamp.year == now.year &&
              e.timestamp.month == now.month &&
              e.timestamp.day == now.day)
          .toList();
    case HistoryFilter.week:
      final weekAgo = now.subtract(const Duration(days: 7));
      return entries.where((e) => e.timestamp.isAfter(weekAgo)).toList();
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
final groupedHistoryProvider = Provider<AsyncValue<List<DateGroup>>>((ref) {
  final filteredAsync = ref.watch(filteredHistoryProvider);

  return filteredAsync.whenData((entries) {
    if (entries.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayEntries = <HistoryEntry>[];
    final yesterdayEntries = <HistoryEntry>[];
    final weekEntries = <HistoryEntry>[];
    final olderEntries = <HistoryEntry>[];

    for (final e in entries) {
      final d = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      if (d == today) {
        todayEntries.add(e);
      } else if (d == yesterday) {
        yesterdayEntries.add(e);
      } else if (d.isAfter(weekAgo)) {
        weekEntries.add(e);
      } else {
        olderEntries.add(e);
      }
    }

    return [
      if (todayEntries.isNotEmpty)
        DateGroup(labelKey: 'today', entries: todayEntries),
      if (yesterdayEntries.isNotEmpty)
        DateGroup(labelKey: 'yesterday', entries: yesterdayEntries),
      if (weekEntries.isNotEmpty)
        DateGroup(labelKey: 'thisWeek', entries: weekEntries),
      if (olderEntries.isNotEmpty)
        DateGroup(labelKey: 'older', entries: olderEntries),
    ];
  });
});
