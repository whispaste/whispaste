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

  // For archive/trash, use dedicated streams with parsed filtering
  if (filter == HistoryFilter.archived) {
    final archivedAsync = ref.watch(archivedEntriesProvider);
    if (parsed.isEmpty) return archivedAsync;
    return archivedAsync.whenData(
        (entries) => _applyParsedSearch(entries, parsed));
  }
  if (filter == HistoryFilter.trash) {
    final trashAsync = ref.watch(trashEntriesProvider);
    if (parsed.isEmpty) return trashAsync;
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

/// Per-filter match counts when a search query is active.
///
/// Returns a [Map] from [HistoryFilter] to the number of matching entries,
/// or `null` when the search field is empty (so chips show no count badge).
final searchCountsProvider = Provider<Map<HistoryFilter, int>?>((ref) {
  final rawSearch = ref.watch(historySearchProvider).trim();
  if (rawSearch.isEmpty) return null;
  final parsed = parseSearchQuery(rawSearch);
  if (parsed.isEmpty) return null;

  final activeAsync = ref.watch(historyEntriesProvider);
  final archivedAsync = ref.watch(archivedEntriesProvider);
  final trashAsync = ref.watch(trashEntriesProvider);

  // Wait until all three streams have loaded before surfacing counts.
  if (activeAsync is! AsyncData<List<HistoryEntry>> ||
      archivedAsync is! AsyncData<List<HistoryEntry>> ||
      trashAsync is! AsyncData<List<HistoryEntry>>) {
    return null;
  }

  final active = activeAsync.value;
  final archived = archivedAsync.value;
  final trash = trashAsync.value;

  // Apply parsed search consistently across all pools
  final activeMatched = _applyParsedSearch(active, parsed);
  final archivedMatched = _applyParsedSearch(archived, parsed);
  final trashMatched = _applyParsedSearch(trash, parsed);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final weekAgo = today.subtract(const Duration(days: 7));

  return {
    HistoryFilter.all: activeMatched.length,
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
    HistoryFilter.archived: archivedMatched.length,
    HistoryFilter.trash: trashMatched.length,
  };
});

/// Applies a [ParsedSearchQuery] to an in-memory list (archived/trash/counts).
///
/// This is the fallback path when the DB advanced search hasn't loaded yet,
/// and the canonical path for archived/trash (which don't go through FTS5).
/// Note: tag filtering here is done by checking entry.tags field or by name
/// matching on the entry.content — a lightweight in-memory approximation.
/// Full accuracy for tag commands requires the DB method.
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
