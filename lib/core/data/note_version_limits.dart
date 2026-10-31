/// Bounds and pruning rules for the local version history of a note
/// (schema v29, WP-31a). Pure Dart: the Drift store applies the result.
///
/// A version is a snapshot of title and body. Snapshots are taken on an
/// explicit save (Cmd/Ctrl+S) or after an idle pause following edits; an
/// identical snapshot to the newest one is never stored. Storage stays
/// bounded per note by a count cap and a byte budget. The oldest versions go
/// first; the newest version is never pruned.
library;

/// Retention of note versions, amount-based: at most [maxCount] versions per
/// note and a byte budget ([maxTotalBytes]) for each note. There is no time
/// limit, so an old version is only dropped when the amount or the budget
/// requires it. Not user-configurable (see the open question in the WP-31a
/// report about a retention setting).
class NoteVersionLimits {
  const NoteVersionLimits({
    this.maxCount = 50,
    this.maxTotalBytes = 4 * 1024 * 1024,
    this.maxVersionBytes = 512 * 1024,
  });

  /// Most versions kept per note.
  final int maxCount;

  /// Byte budget for all versions of one note (title + body, UTF-8).
  final int maxTotalBytes;

  /// A snapshot larger than this is not stored at all.
  final int maxVersionBytes;

  static const NoteVersionLimits standard = NoteVersionLimits();
}

/// The minimum a pruning decision needs about one stored version.
class NoteVersionSize {
  const NoteVersionSize({required this.id, required this.sizeBytes});

  final String id;
  final int sizeBytes;
}

/// Byte size of a snapshot of [title] and [content] as stored.
///
/// Approximate on purpose: it counts two bytes per UTF-16 code unit, which
/// over-counts ASCII and is close for most CJK text. It drives the byte budget
/// only, so a few percent of error is harmless, and an exact UTF-8 count would
/// mean encoding every snapshot twice on each save.
int noteVersionSizeBytes(String? title, String content) {
  final titleBytes = title == null ? 0 : title.length * 2;
  return titleBytes + content.length * 2;
}

/// Ids to delete so that the history respects [limits].
///
/// [newestFirst] must be ordered by creation time, newest first. The newest
/// version is always kept, even if it alone exceeds the byte budget (it can
/// only do so when it is still under [NoteVersionLimits.maxVersionBytes]).
List<String> noteVersionIdsToPrune(
  List<NoteVersionSize> newestFirst, {
  NoteVersionLimits limits = NoteVersionLimits.standard,
}) {
  final drop = <String>[];
  var kept = 0;
  var keptBytes = 0;
  for (final version in newestFirst) {
    final fitsCount = kept < limits.maxCount;
    final fitsBytes =
        kept == 0 || keptBytes + version.sizeBytes <= limits.maxTotalBytes;
    if (fitsCount && fitsBytes) {
      kept++;
      keptBytes += version.sizeBytes;
    } else {
      drop.add(version.id);
    }
  }
  return drop;
}

/// Whether a snapshot should be stored. False when it equals the newest
/// stored version (no change) or exceeds the per-version size limit.
bool shouldStoreNoteVersion({
  required String? title,
  required String content,
  required String? newestTitle,
  required String? newestContent,
  required bool hasNewest,
  NoteVersionLimits limits = NoteVersionLimits.standard,
}) {
  if (noteVersionSizeBytes(title, content) > limits.maxVersionBytes) {
    return false;
  }
  if (hasNewest && newestTitle == title && newestContent == content) {
    return false;
  }
  return true;
}
