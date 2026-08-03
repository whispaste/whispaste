/// Feature-local providers for the Notizen sidebar area — filter/search UI
/// state layered on top of the core data-stream providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

// Re-export the core data-stream providers so feature-local imports don't
// need to reach into `core/data/` directly (mirrors
// `features/history/data/providers.dart`).
export 'package:whispaste/core/data/notes_providers.dart';

/// Active/trash filter for the Notizen page.
enum NotesFilter { active, trash }

class NotesFilterNotifier extends Notifier<NotesFilter> {
  @override
  NotesFilter build() => NotesFilter.active;

  void set(NotesFilter filter) => state = filter;
}

final notesFilterProvider = NotifierProvider<NotesFilterNotifier, NotesFilter>(
  NotesFilterNotifier.new,
);
