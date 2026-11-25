/// A search hit's query on its way to the editor of its entry (#653).
///
/// Opening a hit from "Überall suchen" switches page, loads the entry and
/// only then mounts its editor, so the query cannot be handed over directly.
/// The search leaves it here, keyed by the entry; the [WpTextEditor] showing
/// that entry takes it once it is on screen and opens its find bar with it:
/// every hit tinted, the first one selected and in view, F3 / Shift+F3 for
/// the others.
library;

import 'package:flutter/foundation.dart';

import '../core/data/content_metadata.dart' show ContentKey, ContentKind;

/// What the find bar opens with: the matched text, and the offset from which
/// the hit to start on is chosen (the first one at or after it).
typedef WpFindRevealRequest = ({String query, int? anchor});

abstract final class WpFindReveal {
  /// A request no editor took within this time is dropped: the entry never
  /// came on screen (a closed PIN lock, a read-only version), and opening the
  /// same entry later by hand must not bring up a stale search.
  static const maxAge = Duration(seconds: 5);

  /// Notifies the mounted editors that a request is waiting.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static ContentKey? _entry;
  static WpFindRevealRequest? _request;
  static DateTime? _at;

  /// Leaves [query] for the editor of [entry]; replaces any earlier request.
  /// A blank query clears instead (a hit that matched only the title or a
  /// tag has nothing to find in the text).
  static void request(
    ContentKey entry,
    String query, {
    int? anchor,
    DateTime? now,
  }) {
    if (query.trim().isEmpty) {
      clear();
      return;
    }
    _entry = entry;
    _request = (query: query, anchor: anchor);
    _at = now ?? DateTime.now();
    changes.value++;
  }

  /// The request for [entry], removed on the way out; null when there is
  /// none, it is for another entry or it has expired.
  ///
  /// A recording matches in either of its versions: the search reads the
  /// one text, the detail shows whichever version is chosen.
  static WpFindRevealRequest? take(ContentKey entry, {DateTime? now}) {
    final request = peek(entry, now: now);
    if (request != null) clear();
    return request;
  }

  /// Like [take], but leaves the request in place: the editor waits with it
  /// while the entry's text is still loading.
  static WpFindRevealRequest? peek(ContentKey entry, {DateTime? now}) {
    final pending = _entry;
    final request = _request;
    final at = _at;
    if (pending == null || request == null || at == null) return null;
    if ((now ?? DateTime.now()).difference(at) > maxAge) {
      clear();
      return null;
    }
    if (pending.id != entry.id ||
        _family(pending.kind) != _family(entry.kind)) {
      return null;
    }
    return request;
  }

  static void clear() {
    _entry = null;
    _request = null;
    _at = null;
  }

  static ContentKind _family(ContentKind kind) =>
      kind == ContentKind.recordingEdited ? ContentKind.recording : kind;
}
