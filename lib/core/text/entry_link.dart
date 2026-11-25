/// Links between notes, recordings and snippets (#660).
///
/// A link lives in the Markdown source as `[[<kind>:<id>|<label>]]`, for
/// example `[[note:3f2a…|Meeting]]`. The id is what the link follows, so
/// renaming the target never breaks it; the label is only what the text
/// shows and may grow stale. The part before `|` is the target the content
/// index already records for every `[[…]]` (`parseContentMetadata`), so
/// backlinks come from that index without a table of their own.
library;

import '../data/content_metadata.dart' show ContentKey, ContentKind;

/// What a link can point at.
enum EntryLinkKind {
  note('note'),
  recording('recording'),
  snippet('snippet');

  const EntryLinkKind(this.prefix);

  /// The word before the colon in the stored target.
  final String prefix;

  /// The content-index kind of the target's text. A recording's two texts
  /// (raw and Smart Mode) are one target.
  ContentKind get contentKind => switch (this) {
    EntryLinkKind.note => ContentKind.note,
    EntryLinkKind.recording => ContentKind.recording,
    EntryLinkKind.snippet => ContentKind.snippet,
  };

  static EntryLinkKind of(ContentKind kind) => switch (kind) {
    ContentKind.note => EntryLinkKind.note,
    ContentKind.recording ||
    ContentKind.recordingEdited => EntryLinkKind.recording,
    ContentKind.snippet => EntryLinkKind.snippet,
  };

  static EntryLinkKind? byPrefix(String prefix) {
    for (final kind in values) {
      if (kind.prefix == prefix) return kind;
    }
    return null;
  }
}

/// One entry a link points at, or one entry that points somewhere.
typedef EntryRef = ({EntryLinkKind kind, String id});

/// The target string of [ref] as stored before the `|`.
String entryLinkTarget(EntryRef ref) => '${ref.kind.prefix}:${ref.id}';

/// The entry of a content-index key (a recording's edited text is the
/// recording).
EntryRef entryRefOf(ContentKey key) =>
    (kind: EntryLinkKind.of(key.kind), id: key.id);

/// Parses a stored target (`note:<id>`). Anything else, a plain `[[word]]`
/// included, is no entry link.
EntryRef? parseEntryLinkTarget(String target) {
  final colon = target.indexOf(':');
  if (colon <= 0) return null;
  final kind = EntryLinkKind.byPrefix(target.substring(0, colon));
  final id = target.substring(colon + 1).trim();
  if (kind == null || id.isEmpty || !_id.hasMatch(id)) return null;
  return (kind: kind, id: id);
}

/// The text to insert for a link to [ref] shown as [label]. Characters that
/// would end the link early (`]`, `|`) and line breaks leave the label.
String formatEntryLink(EntryRef ref, String label) {
  var clean = label
      .replaceAll(RegExp(r'[\]\[|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.length > _maxLabel) clean = '${clean.substring(0, _maxLabel)}…';
  return clean.isEmpty
      ? '[[${entryLinkTarget(ref)}]]'
      : '[[${entryLinkTarget(ref)}|$clean]]';
}

/// One entry link found in a text: where it stands and what it says.
class EntryLinkMatch {
  const EntryLinkMatch({
    required this.ref,
    required this.label,
    required this.start,
    required this.end,
  });

  final EntryRef ref;

  /// The label as written; null for `[[note:<id>]]` without one.
  final String? label;
  final int start;
  final int end;
}

/// Every entry link in [text], in order. Plain `[[words]]` are skipped.
List<EntryLinkMatch> findEntryLinks(String text) => [
  for (final m in entryLinkPattern.allMatches(text))
    if (parseEntryLinkTarget(m.group(1)!) case final ref?)
      EntryLinkMatch(ref: ref, label: m.group(2), start: m.start, end: m.end),
];

/// The entry link the caret at [offset] stands in, or null.
EntryLinkMatch? entryLinkAt(String text, int offset) {
  for (final link in findEntryLinks(text)) {
    if (offset > link.start && offset < link.end) return link;
  }
  return null;
}

/// `[[kind:id|label]]`: group 1 the target, group 2 the label.
final entryLinkPattern = RegExp(r'\[\[([a-z]+:[^\]|\s]+)(?:\|([^\]\n]*))?\]\]');

/// Whether the change from [before] to [after] was the typing of the second
/// `[` of a fresh `[[` right before the caret at [caret]. Only a single typed
/// character counts: paste, undo and dictation never open the picker.
/// Returns the offset of the first `[`, or null.
int? typedLinkTrigger(String before, String after, int caret) {
  if (after.length != before.length + 1) return null;
  if (caret < 2 || caret > after.length) return null;
  if (after.codeUnitAt(caret - 1) != _open ||
      after.codeUnitAt(caret - 2) != _open) {
    return null;
  }
  // The rest must be the old text with one character inserted at caret - 1.
  if (after.substring(0, caret - 1) != before.substring(0, caret - 1) ||
      after.substring(caret) != before.substring(caret - 1)) {
    return null;
  }
  // `[[[` is no fresh link, and neither is a `[[` that already closes.
  if (caret >= 3 && after.codeUnitAt(caret - 3) == _open) return null;
  if (caret < after.length && after.codeUnitAt(caret) == _open) return null;
  return caret - 2;
}

const _open = 0x5B; // [
const _maxLabel = 120;
final _id = RegExp(r'^[A-Za-z0-9_.:-]+$');
