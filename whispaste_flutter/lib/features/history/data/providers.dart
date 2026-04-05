/// Riverpod providers for history data — bridges Drift streams to UI.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Live stream of all non-deleted, non-archived history entries, newest first.
final historyEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchEntries(limit: 500);
});

/// Live stream of archived entries.
final archivedEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchArchived(limit: 500);
});

/// Live stream of trashed entries.
final trashEntriesProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final db = ref.watch(historyDatabaseProvider);
  return db.watchTrash(limit: 500);
});

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

/// Multi-select state — set of selected entry IDs.
class MultiSelectNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void toggle(String id) {
    if (state.contains(id)) {
      state = {...state}..remove(id);
    } else {
      state = {...state, id};
    }
  }

  void clear() => state = {};

  void selectAll(List<String> ids) => state = {...ids};
}

final multiSelectProvider =
    NotifierProvider<MultiSelectNotifier, Set<String>>(
        MultiSelectNotifier.new);

/// Whether multi-select mode is active.
final multiSelectActiveProvider = Provider<bool>((ref) {
  return ref.watch(multiSelectProvider).isNotEmpty;
});

/// Filtered and searched history entries — the main data source for the list.
final filteredHistoryProvider = Provider<AsyncValue<List<HistoryEntry>>>((ref) {
  final filter = ref.watch(historyFilterProvider);

  // For archive/trash, use dedicated streams
  if (filter == HistoryFilter.archived) {
    return ref.watch(archivedEntriesProvider);
  }
  if (filter == HistoryFilter.trash) {
    return ref.watch(trashEntriesProvider);
  }

  final entriesAsync = ref.watch(historyEntriesProvider);
  final search = ref.watch(historySearchProvider).toLowerCase().trim();

  return entriesAsync.whenData((entries) {
    var result = entries;

    // Apply filter
    final now = DateTime.now();
    switch (filter) {
      case HistoryFilter.today:
        result = result
            .where((e) =>
                e.timestamp.year == now.year &&
                e.timestamp.month == now.month &&
                e.timestamp.day == now.day)
            .toList();
      case HistoryFilter.week:
        final weekAgo = now.subtract(const Duration(days: 7));
        result = result.where((e) => e.timestamp.isAfter(weekAgo)).toList();
      case HistoryFilter.pinned:
        result = result.where((e) => e.pinned).toList();
      case HistoryFilter.all:
        break;
      case HistoryFilter.archived:
      case HistoryFilter.trash:
        break; // Handled above
    }

    // Apply search
    if (search.isNotEmpty) {
      result = result
          .where((e) =>
              e.title.toLowerCase().contains(search) ||
              e.content.toLowerCase().contains(search))
          .toList();
    }

    return result;
  });
});

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
