/// Providers and navigation of links between entries (#660).
library;

import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:whispaste/core/data/content_metadata_providers.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/history/data/history_lock.dart';

import 'entry_links.dart';

export 'entry_links.dart';

/// One link of an entry: where it points and, while the target lives, how
/// it is called now. [entry] null means the target is in the trash or gone.
typedef OutgoingLink = ({EntryRef ref, LinkedEntry? entry});

/// Every entry whose text links to [ref], with current titles, newest
/// change first. Read from the content index, so a text counts once the
/// index has parsed it; the entry itself never lists itself.
final entryBacklinksProvider = StreamProvider.autoDispose
    .family<List<LinkedEntry>, EntryRef>((ref, target) {
      final db = ref.watch(historyDatabaseProvider);
      final includePrivate = !ref.watch(historyContentHiddenProvider);
      return db.contentIndex.watchBacklinks(entryLinkTarget(target)).asyncMap((
        keys,
      ) async {
        final sources = {for (final key in keys) entryRefOf(key)}
          ..remove(target);
        final found = await resolveLinkedEntries(
          db,
          sources,
          includePrivate: includePrivate,
        );
        return found.values.toList()
          ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
      });
    });

/// The links in the saved text of [key], in text order without repeats,
/// each with its target's current title. Follows renames and the trash of
/// the targets while the editor is open.
final entryOutgoingLinksProvider = StreamProvider.autoDispose
    .family<List<OutgoingLink>, ContentKey>((ref, key) {
      final db = ref.watch(historyDatabaseProvider);
      final includePrivate = !ref.watch(historyContentHiddenProvider);
      final metadata = ref.watch(contentMetadataProvider(key)).value;
      final self = entryRefOf(key);
      final refs = <EntryRef>[];
      for (final link in metadata?.links ?? const <ContentLink>[]) {
        final target = parseEntryLinkTarget(link.target);
        if (target == null || target == self || refs.contains(target)) {
          continue;
        }
        refs.add(target);
      }
      if (refs.isEmpty) return Stream.value(const []);
      Future<List<OutgoingLink>> resolve() async {
        final found = await resolveLinkedEntries(
          db,
          refs,
          includePrivate: includePrivate,
        );
        return [for (final r in refs) (ref: r, entry: found[r])];
      }

      return Stream.multi((sink) {
        Future<void> emit() async {
          try {
            sink.add(await resolve());
          } on Object catch (error, stack) {
            sink.addError(error, stack);
          }
        }

        final sub = db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                db.notes,
                db.historyEntries,
                db.snippets,
              ]),
            )
            .listen((_) => unawaited(emit()));
        unawaited(emit());
        sink.onCancel = sub.cancel;
      });
    });

/// One jump over a link: from the entry that holds it to its target.
typedef EntryJump = ({EntryRef from, EntryRef to});

/// The jumps made over links in this session, last one last. The target of
/// the last jump offers "Back to …" ([EntryLinkTrailNotifier.back]); going
/// back pops it, so a chain of jumps can be walked back step by step.
class EntryLinkTrailNotifier extends Notifier<List<EntryJump>> {
  /// Long chains keep only their recent part.
  static const maxDepth = 50;

  @override
  List<EntryJump> build() => const [];

  void push(EntryJump jump) {
    final next = [...state, jump];
    state = next.length > maxDepth
        ? next.sublist(next.length - maxDepth)
        : next;
  }

  /// Removes the last jump and returns it, or null when there is none.
  EntryJump? pop() {
    if (state.isEmpty) return null;
    final last = state.last;
    state = state.sublist(0, state.length - 1);
    return last;
  }
}

final entryLinkTrailProvider =
    NotifierProvider<EntryLinkTrailNotifier, List<EntryJump>>(
      EntryLinkTrailNotifier.new,
    );

/// The entry "Back" returns to while [current] is open: the start of the
/// last jump, but only when that jump ended at [current].
EntryRef? entryLinkBackTarget(List<EntryJump> trail, EntryRef current) {
  if (trail.isEmpty) return null;
  final last = trail.last;
  return last.to == current ? last.from : null;
}

/// Opens [target] in its own area: a note in the notes editor, a recording
/// in the Aufnahmen detail, a snippet beside its list. [read] is `ref.read`
/// of a widget or a provider.
void openLinkedEntry(
  T Function<T>(ProviderListenable<T> provider) read,
  EntryRef target,
) {
  switch (target.kind) {
    case EntryLinkKind.note:
      // The search's jump, without a range: it also lands in the archive
      // view for an archived note.
      read(
        notesRevealTargetProvider.notifier,
      ).set((noteId: target.id, start: null, end: null));
      read(activePageProvider.notifier).setPage('notes');
    case EntryLinkKind.recording:
      read(historyOpenEntryProvider.notifier).set(target.id);
      read(activePageProvider.notifier).setPage('history');
    case EntryLinkKind.snippet:
      read(snippetsOpenTargetProvider.notifier).set(target.id);
      read(activePageProvider.notifier).setPage('snippets');
  }
}

/// Follows a link from [from] to [to] and remembers the jump for "Back".
void followEntryLink(
  T Function<T>(ProviderListenable<T> provider) read,
  EntryRef from,
  EntryRef to,
) {
  if (from == to) return;
  read(entryLinkTrailProvider.notifier).push((from: from, to: to));
  openLinkedEntry(read, to);
}

/// Goes back over the last jump while [current] is its target. Returns
/// whether it went anywhere.
bool goBackOverEntryLink(
  T Function<T>(ProviderListenable<T> provider) read,
  EntryRef current,
) {
  final back = entryLinkBackTarget(read(entryLinkTrailProvider), current);
  if (back == null) return false;
  read(entryLinkTrailProvider.notifier).pop();
  openLinkedEntry(read, back);
  return true;
}

/// One entry with its current title, null while it is in the trash or gone
/// (or hidden behind the history PIN lock). For "Back to …".
final linkedEntryProvider = FutureProvider.autoDispose
    .family<LinkedEntry?, EntryRef>((ref, target) async {
      final db = ref.watch(historyDatabaseProvider);
      final includePrivate = !ref.watch(historyContentHiddenProvider);
      final found = await resolveLinkedEntries(db, [
        target,
      ], includePrivate: includePrivate);
      return found[target];
    });
