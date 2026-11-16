/// Bounds and pruning rules for the local version history of a note
/// (schema v29, ticket). Pure Dart: the Drift store applies the result.
///
/// A version is a snapshot of title and body. Snapshots are taken on an
/// explicit save (Cmd/Ctrl+S) or after an idle pause following edits; an
/// identical snapshot to the newest one is never stored. Storage stays
/// bounded per note by a count cap and a byte budget. The oldest versions go
/// first; the newest [NoteVersionLimits.minKeep] versions are never pruned for
/// bytes, so a long text keeps its recent history (#636).
///
/// Long bodies are stored compressed ([encodeNoteVersionBody]); the byte
/// budget counts the stored size. A snapshot that still cannot be stored is
/// reported ([NoteVersionOutcome.tooLarge]), never dropped silently.
library;

import 'dart:convert';
import 'dart:io' show gzip;

/// Retention of note versions, amount-based: at most [maxCount] versions per
/// note and a byte budget ([maxTotalBytes]) for each note. There is no time
/// limit, so an old version is only dropped when the amount or the budget
/// requires it. Not user-configurable (see the open question in the ticket
/// report about a retention setting).
class NoteVersionLimits {
  const NoteVersionLimits({
    this.maxCount = 50,
    this.maxTotalBytes = 4 * 1024 * 1024,
    this.maxVersionChars = 2 * 1000 * 1000,
    this.minKeep = 20,
    this.hardMaxTotalBytes = 16 * 1024 * 1024,
  });

  /// Most versions kept per note.
  final int maxCount;

  /// Byte budget for all versions of one note (title + stored body). The
  /// newest [minKeep] versions are exempt, see [noteVersionIdsToPrune].
  final int maxTotalBytes;

  /// A snapshot with a longer body (UTF-16 code units, about 300,000 words)
  /// is not stored; the caller says so.
  final int maxVersionChars;

  /// The newest versions that survive the byte budget, so even a very long
  /// text keeps its last stages. Still bounded by [maxCount].
  final int minKeep;

  /// Ceiling for all versions of one note, also for the protected newest
  /// [minKeep]: beyond it even those go, oldest first.
  final int hardMaxTotalBytes;

  static const NoteVersionLimits standard = NoteVersionLimits();
}

/// What recording a snapshot did.
enum NoteVersionOutcome {
  /// A new version was stored.
  stored,

  /// The text equals the newest version; nothing to store.
  unchanged,

  /// The body is longer than [NoteVersionLimits.maxVersionChars]; no version
  /// was stored and the user is told.
  tooLarge,
}

/// The minimum a pruning decision needs about one stored version.
class NoteVersionSize {
  const NoteVersionSize({required this.id, required this.sizeBytes});

  final String id;
  final int sizeBytes;
}

/// Marks a body stored compressed. A plain body that happens to start with
/// it is compressed too, so a stored body without the marker is always plain.
const String kNoteVersionGzipMarker = 'wp-gzip-v1:';

/// Bodies from this length on are stored compressed.
const int kNoteVersionCompressFrom = 2048;

/// The body as stored: plain when short, otherwise gzip as base64 behind
/// [kNoteVersionGzipMarker]. A text of 40,000 words shrinks to about a third.
String encodeNoteVersionBody(String content) {
  if (content.length < kNoteVersionCompressFrom &&
      !content.startsWith(kNoteVersionGzipMarker)) {
    return content;
  }
  final packed = gzip.encode(utf8.encode(content));
  return '$kNoteVersionGzipMarker${base64.encode(packed)}';
}

/// The text of a stored body, or null when a packed body cannot be unpacked.
/// A plain body (no marker) is returned as it is.
String? tryDecodeNoteVersionBody(String stored) {
  if (!stored.startsWith(kNoteVersionGzipMarker)) return stored;
  try {
    final packed = base64.decode(
      stored.substring(kNoteVersionGzipMarker.length),
    );
    return utf8.decode(gzip.decode(packed));
  } on Exception {
    return null;
  }
}

/// The text of a stored body; inverse of [encodeNoteVersionBody]. A body that
/// cannot be unpacked is returned as it is, so an unexpected row never throws
/// in the version list; restoring uses [tryDecodeNoteVersionBody] instead.
String decodeNoteVersionBody(String stored) =>
    tryDecodeNoteVersionBody(stored) ?? stored;

/// Byte size of a snapshot of [title] and the stored body [storedContent].
///
/// Approximate on purpose: a plain body counts two bytes per UTF-16 code
/// unit, which over-counts ASCII and is close for most CJK text; a compressed
/// body is ASCII and counts its length. It drives the byte budget only, so a
/// few percent of error is harmless.
int noteVersionSizeBytes(String? title, String storedContent) {
  final titleBytes = title == null ? 0 : title.length * 2;
  final bodyBytes = storedContent.startsWith(kNoteVersionGzipMarker)
      ? storedContent.length
      : storedContent.length * 2;
  return titleBytes + bodyBytes;
}

/// Ids to delete so that the history respects [limits].
///
/// [newestFirst] must be ordered by creation time, newest first. The newest
/// [NoteVersionLimits.minKeep] versions are kept (within
/// [NoteVersionLimits.maxCount]) even above the byte budget, but never above
/// [NoteVersionLimits.hardMaxTotalBytes]; older ones go when the count or the
/// budget requires it.
List<String> noteVersionIdsToPrune(
  List<NoteVersionSize> newestFirst, {
  NoteVersionLimits limits = NoteVersionLimits.standard,
}) {
  final drop = <String>[];
  var kept = 0;
  var keptBytes = 0;
  for (final version in newestFirst) {
    final fitsCount = kept < limits.maxCount;
    final total = keptBytes + version.sizeBytes;
    final fitsBytes =
        kept == 0 ||
        (kept < limits.minKeep
            ? total <= limits.hardMaxTotalBytes
            : total <= limits.maxTotalBytes);
    if (fitsCount && fitsBytes) {
      kept++;
      keptBytes += version.sizeBytes;
    } else {
      drop.add(version.id);
    }
  }
  return drop;
}

/// What recording a snapshot should do: [NoteVersionOutcome.tooLarge] when the
/// body exceeds the per-version limit, [NoteVersionOutcome.unchanged] when it
/// equals the newest stored version, otherwise [NoteVersionOutcome.stored].
/// The newest version is given as plain text (already decoded).
NoteVersionOutcome decideNoteVersion({
  required String? title,
  required String content,
  required String? newestTitle,
  required String? newestContent,
  required bool hasNewest,
  NoteVersionLimits limits = NoteVersionLimits.standard,
}) {
  if (content.length > limits.maxVersionChars) {
    return NoteVersionOutcome.tooLarge;
  }
  if (hasNewest && newestTitle == title && newestContent == content) {
    return NoteVersionOutcome.unchanged;
  }
  return NoteVersionOutcome.stored;
}
