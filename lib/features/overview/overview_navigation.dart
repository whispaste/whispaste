import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/page_state.dart';

/// Opens a target of the overview: a nav page id, or `settings:<row>` for a
/// Settings row (the row is scrolled to and highlighted there).
void overviewOpenTarget(WidgetRef ref, String target) {
  const prefix = 'settings:';
  if (target.startsWith(prefix)) {
    ref
        .read(settingsScrollTargetProvider.notifier)
        .set(target.substring(prefix.length));
    ref.read(activePageProvider.notifier).setPage('settings');
    return;
  }
  ref.read(activePageProvider.notifier).setPage(target);
}

/// Opens one recording in the Aufnahmen page, with its detail shown.
void overviewOpenRecording(WidgetRef ref, String entryId) {
  ref.read(historyOpenEntryProvider.notifier).set(entryId);
  ref.read(activePageProvider.notifier).setPage('history');
}
