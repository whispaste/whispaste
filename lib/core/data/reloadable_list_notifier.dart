import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared tail for `AsyncNotifier<List<T>>` classes whose every mutation
/// (add/update/remove/replaceAll) ends by re-reading the full list from
/// persistence and republishing it as the new state — the exact pattern
/// Replacements, Automations, and Snippets each repeated once per method
/// before this was extracted.
mixin ReloadableListNotifier<T> on AsyncNotifier<List<T>> {
  /// Re-reads the full list from persistence.
  Future<List<T>> readAll();

  /// Re-reads and republishes [readAll] as the new state. Call this as the
  /// last step of every mutation.
  Future<void> reload() async {
    state = AsyncData(await readAll());
  }
}
