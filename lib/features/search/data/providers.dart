/// Providers of the search over every area (#628).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:whispaste/core/data/content_metadata.dart' show ContentKind;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/widgets/find_reveal.dart';

import 'content_search.dart';

export 'content_search.dart';

/// Wall clock for the `date:` periods; a seam so tests can pin "now".
final contentSearchClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// The answer to one query. Recordings and notes are withheld while the
/// history PIN lock is closed ([historyContentHiddenProvider]); snippets are
/// not covered by that lock.
final contentSearchProvider = FutureProvider.autoDispose
    .family<ContentSearchResults, String>((ref, query) {
      if (query.trim().isEmpty) {
        return Future.value(ContentSearchResults.empty);
      }
      final db = ref.watch(historyDatabaseProvider);
      final hidden = ref.watch(historyContentHiddenProvider);
      return searchAllContent(
        db,
        query,
        now: ref.read(contentSearchClockProvider)(),
        includePrivate: !hidden,
      );
    });

/// Opens [hit] at its place: the recording in the Aufnahmen detail, the
/// note in the editor with the match selected, the snippet beside its list;
/// in each, the find bar opens with the matched text (#653).
/// [read] is `ref.read` of a widget or a provider.
void openContentSearchHit(
  T Function<T>(ProviderListenable<T> provider) read,
  ContentSearchHit hit,
) {
  // The editor of the entry opens its find bar with the matched text
  // (#653). Notes hand theirs over themselves: their editor folds Windows
  // line endings, so the page moves the offset along first.
  final match = hit.excerpt?.match ?? '';
  switch (hit.area) {
    case ContentSearchArea.recordings:
      WpFindReveal.request(
        (kind: ContentKind.recording, id: hit.id),
        match,
        anchor: hit.matchStart,
      );
      read(historyOpenEntryProvider.notifier).set(hit.id);
      read(activePageProvider.notifier).setPage('history');
    case ContentSearchArea.notes:
      read(
        notesRevealTargetProvider.notifier,
      ).set((noteId: hit.id, start: hit.matchStart, end: hit.matchEnd));
      read(activePageProvider.notifier).setPage('notes');
    case ContentSearchArea.snippets:
      WpFindReveal.request(
        (kind: ContentKind.snippet, id: hit.id),
        match,
        anchor: hit.matchStart,
      );
      read(snippetsOpenTargetProvider.notifier).set(hit.id);
      read(activePageProvider.notifier).setPage('snippets');
  }
}
