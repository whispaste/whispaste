import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import 'list_sort.dart';

/// The remembered sort of one list. A view preference, so it lives in the raw
/// `app_settings` key-value table (like `last_page`), not in [AppSettings]:
/// it stays out of the settings export and import.
abstract class ListSortPreferenceNotifier extends AsyncNotifier<ListSort> {
  /// `app_settings` key the choice is stored under.
  String get settingKey;

  /// Fields this list offers; a stored field outside this set is ignored.
  Set<ListSortField> get allowedFields;

  /// Order used before the user has chosen one, or when the stored value is
  /// missing or unknown.
  ListSort get defaultSort;

  @override
  Future<ListSort> build() async {
    final db = ref.read(historyDatabaseProvider);
    final raw = await db.readAppSetting(settingKey);
    return ListSort.decode(raw, allowed: allowedFields) ?? defaultSort;
  }

  /// Shows [sort] at once and stores it for the next visit.
  Future<void> choose(ListSort sort) async {
    state = AsyncData(sort);
    final db = ref.read(historyDatabaseProvider);
    await db.writeAppSetting(settingKey, sort.encode());
  }
}

/// Replacements: by first trigger, A–Z.
const kReplacementsDefaultSort = ListSort(ListSortField.trigger);

/// Snippets: by title, A–Z.
const kSnippetsDefaultSort = ListSort(ListSortField.title);

/// Notes: most recently edited first, as before the choice existed.
const kNotesDefaultSort = ListSort(ListSortField.changed);

class ReplacementsSortNotifier extends ListSortPreferenceNotifier {
  @override
  String get settingKey => 'replacements_sort';

  @override
  Set<ListSortField> get allowedFields => const {
    ListSortField.trigger,
    ListSortField.result,
    ListSortField.added,
    ListSortField.changed,
  };

  @override
  ListSort get defaultSort => kReplacementsDefaultSort;
}

class SnippetsSortNotifier extends ListSortPreferenceNotifier {
  @override
  String get settingKey => 'snippets_sort';

  @override
  Set<ListSortField> get allowedFields => const {
    ListSortField.title,
    ListSortField.added,
    ListSortField.changed,
    ListSortField.used,
  };

  @override
  ListSort get defaultSort => kSnippetsDefaultSort;
}

class NotesSortNotifier extends ListSortPreferenceNotifier {
  @override
  String get settingKey => 'notes_sort';

  @override
  Set<ListSortField> get allowedFields => const {
    ListSortField.title,
    ListSortField.added,
    ListSortField.changed,
  };

  @override
  ListSort get defaultSort => kNotesDefaultSort;
}

final replacementsSortProvider =
    AsyncNotifierProvider<ReplacementsSortNotifier, ListSort>(
      ReplacementsSortNotifier.new,
    );

final snippetsSortProvider =
    AsyncNotifierProvider<SnippetsSortNotifier, ListSort>(
      SnippetsSortNotifier.new,
    );

final notesSortProvider = AsyncNotifierProvider<NotesSortNotifier, ListSort>(
  NotesSortNotifier.new,
);
