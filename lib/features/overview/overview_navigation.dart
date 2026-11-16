import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/page_state.dart';
import '../../core/overview/overview_logic.dart' show kOverviewCustomizeTarget;

/// Opens a target of the overview: a nav page id, `settings:<row>` for a
/// Settings row (the row is scrolled to and highlighted there), or
/// [kOverviewCustomizeTarget] for the "Customise overview" menu.
void overviewOpenTarget(WidgetRef ref, String target) {
  if (target == kOverviewCustomizeTarget) {
    ref.read(activePageProvider.notifier).setPage('overview');
    ref.read(overviewCustomizeRequestProvider.notifier).request();
    return;
  }
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

/// Opens one note in the Notizen page, in its editor (#630).
void overviewOpenNote(WidgetRef ref, String noteId) {
  ref.read(notesEditorTargetProvider.notifier).set(noteId);
  ref.read(activePageProvider.notifier).setPage('notes');
}

/// Asks the "Customise overview" menu in the page head to open (#1576). Each
/// request bumps the value; the menu listens and opens itself.
final overviewCustomizeRequestProvider =
    NotifierProvider<OverviewCustomizeRequest, int>(
      OverviewCustomizeRequest.new,
    );

class OverviewCustomizeRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}
