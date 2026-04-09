/// Riverpod providers for history data — bridges Drift streams to UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';

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

  // For archive/trash, use dedicated streams
  if (filter == HistoryFilter.archived) {
    return ref.watch(archivedEntriesProvider);
  }
  if (filter == HistoryFilter.trash) {
    return ref.watch(trashEntriesProvider);
  }

  final search = ref.watch(historySearchProvider).trim();
  final entriesAsync = ref.watch(historyEntriesProvider);

  if (search.isNotEmpty) {
    // Try FTS5 first; fall back to in-memory search for resilience
    // (handles DB-unavailable scenarios and test environments).
    final ftsAsync = ref.watch(_ftsSearchProvider(search));
    if (ftsAsync is AsyncData<List<HistoryEntry>>) {
      final ftsEntries = ftsAsync.value;
      if (ftsEntries.isNotEmpty) {
        return AsyncValue.data(_applyFilter(ftsEntries, filter));
      }
    }

    // FTS empty / loading / error — fall back to in-memory search
    return entriesAsync.whenData((entries) {
      final lower = search.toLowerCase();
      return _applyFilter(
        entries
            .where((e) =>
                e.title.toLowerCase().contains(lower) ||
                e.content.toLowerCase().contains(lower))
            .toList(),
        filter,
      );
    });
  }

  return entriesAsync.whenData((entries) => _applyFilter(entries, filter));
});

/// FTS5 search results — auto-disposes when the query changes.
final _ftsSearchProvider =
    FutureProvider.autoDispose.family<List<HistoryEntry>, String>(
  (ref, query) async {
    final db = ref.watch(historyDatabaseProvider);
    try {
      return await db.searchEntries(query);
    } catch (_) {
      return [];
    }
  },
);

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
