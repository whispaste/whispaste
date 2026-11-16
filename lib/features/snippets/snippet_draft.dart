import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Key of the one draft for a snippet that does not exist yet.
const kNewSnippetDraftKey = '__new__';

/// Identity of the snippet editor beside the list (the key it mounts under)
/// for the row with [id].
///
/// A new snippet's editor keeps one identity for its whole session, also
/// after its first save created the snippet ([newSessionId]), so autosave
/// never remounts the editor under the caret (#1498). [newEditorSession]
/// counts the new editors opened ("+", Cmd/Ctrl+N, example chip) and makes
/// each one a different identity: "+" always mounts a fresh, empty editor
/// instead of reusing the one that still edits the snippet just created
/// (#1680).
String snippetDetailIdentity(
  String id, {
  required String? newSessionId,
  required int newEditorSession,
}) => id == kNewSnippetDraftKey || id == newSessionId
    ? '$kNewSnippetDraftKey#$newEditorSession'
    : id;

/// What the snippet editor holds: title, body, kind and the interactive
/// field names, as typed (untrimmed).
@immutable
class SnippetDraft {
  const SnippetDraft({
    this.title = '',
    this.body = '',
    this.kind = 'static',
    this.fields = const [],
  });

  final String title;
  final String body;
  final String kind;
  final List<String> fields;

  /// The draft as it is stored: title, body and field names trimmed, and no
  /// fields for a static snippet. Two drafts with the same stored form are
  /// the same snippet.
  SnippetDraft get stored => SnippetDraft(
    title: title.trim(),
    body: body.trim(),
    kind: kind,
    fields: kind == 'interactive'
        ? [for (final f in fields) f.trim()]
        : const [],
  );

  @override
  bool operator ==(Object other) =>
      other is SnippetDraft &&
      other.title == title &&
      other.body == body &&
      other.kind == kind &&
      listEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(title, body, kind, Object.hashAll(fields));
}

/// Unsaved edits per snippet (`id`, or [kNewSnippetDraftKey] for a new one).
///
/// Never auto-disposed, the same rule as the contact form's draft: closing
/// the editor, Esc, switching to another snippet or leaving the page keeps
/// the typed text. The editor saves valid states on its own (#1498), so a
/// draft that outlives it is mostly an invalid state (no title yet, fields
/// that do not match the template) or one whose save is still on its way.
/// A successful save of the same state or a confirmed discard clears it.
/// Memory only — a restart of the app starts without drafts.
class SnippetDraftsNotifier extends Notifier<Map<String, SnippetDraft>> {
  @override
  Map<String, SnippetDraft> build() => const {};

  void save(String key, SnippetDraft draft) {
    if (state[key] == draft) return;
    state = {...state, key: draft};
  }

  void clear(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
  }
}

final snippetDraftsProvider =
    NotifierProvider<SnippetDraftsNotifier, Map<String, SnippetDraft>>(
      SnippetDraftsNotifier.new,
    );
