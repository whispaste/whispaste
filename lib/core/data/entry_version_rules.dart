/// Rules for the version history of a recording transcript (#635).
///
/// A version is a snapshot of the transcript text. Pure Dart: the Drift store
/// applies the plan, the tests drive it with a simulated clock.
///
/// - The first snapshot is the text as dictated, taken before the first manual
///   edit overwrites it.
/// - Consecutive typed snapshots within [EntryVersionLimits.mergeWindow] are
///   merged into one row; if the merged text is again the one before it, the
///   row is dropped.
/// - At most [EntryVersionLimits.maxCount] versions are kept, the oldest go
///   first, and the list says so (see the version list).
library;

/// How a stored text came to be.
enum EntryVersionSource {
  /// Straight from the speech engine; the state before any manual edit.
  dictated,

  /// Edited by hand in the transcript field.
  typed,

  /// Changed by something that took no snapshot of its own (Smart Mode,
  /// new transcription); noticed when the next edit starts.
  converted,

  /// Brought back from an older version.
  restored;

  /// The stored name; unknown names read back as [typed].
  static EntryVersionSource fromName(String name) => values.firstWhere(
    (s) => s.name == name,
    orElse: () => EntryVersionSource.typed,
  );
}

/// Bounds of the history of one entry. Not user-configurable.
class EntryVersionLimits {
  const EntryVersionLimits({
    this.maxCount = 50,
    this.mergeWindow = const Duration(minutes: 10),
    this.maxChars = 2 * 1000 * 1000,
  });

  /// Most versions kept per entry.
  final int maxCount;

  /// Typed snapshots closer than this to the newest typed version merge.
  final Duration mergeWindow;

  /// A longer text is not stored (the caller says so).
  final int maxChars;

  static const EntryVersionLimits standard = EntryVersionLimits();
}

/// What recording a snapshot did.
enum EntryVersionOutcome {
  /// A new version row was written.
  stored,

  /// The newest version of the same source was updated in place.
  merged,

  /// The merge brought the text back to the version before it; the row is gone.
  collapsed,

  /// The text equals the newest version; nothing changed.
  unchanged,

  /// The text exceeds [EntryVersionLimits.maxChars]; nothing was stored.
  tooLarge,
}

/// The minimum the planner needs about a stored version (text already
/// unpacked).
class EntryVersionSnapshot {
  const EntryVersionSnapshot({
    required this.id,
    required this.content,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String content;
  final EntryVersionSource source;
  final DateTime createdAt;
}

/// Where a snapshot sits in an editing session of the writing surface: one
/// session (focus in the editor until focus loss or another entry) is exactly
/// one version (#1498).
enum EditSessionStep {
  /// First snapshot of the session: always a new version.
  start,

  /// Later snapshot of the same session: updates the session's version.
  continued,
}

/// What to do with a new snapshot.
sealed class EntryVersionPlan {
  const EntryVersionPlan();
}

final class EntryVersionInsert extends EntryVersionPlan {
  const EntryVersionInsert();
}

final class EntryVersionNoop extends EntryVersionPlan {
  const EntryVersionNoop();
}

/// Overwrite the newest row with the new text (keeps its creation time, so a
/// long session still yields a version every [EntryVersionLimits.mergeWindow]).
final class EntryVersionMerge extends EntryVersionPlan {
  const EntryVersionMerge(this.id);
  final String id;
}

/// Delete the newest row: the text is back at the one before it.
final class EntryVersionCollapse extends EntryVersionPlan {
  const EntryVersionCollapse(this.id);
  final String id;
}

/// Plans a snapshot of [content]. [newest] and [previous] are the two newest
/// stored versions (null when absent).
EntryVersionPlan planEntryVersion({
  required String content,
  required EntryVersionSource source,
  required DateTime now,
  required EntryVersionSnapshot? newest,
  required EntryVersionSnapshot? previous,
  EntryVersionLimits limits = EntryVersionLimits.standard,
  EditSessionStep? session,
}) {
  if (newest == null) return const EntryVersionInsert();
  if (newest.content == content) return const EntryVersionNoop();
  // Only typing merges: a dictated, converted or restored state is a step the
  // user may want to find again by itself.
  final typing =
      source == EntryVersionSource.typed &&
      newest.source == EntryVersionSource.typed;
  // An editing session decides by itself: its first snapshot is always a new
  // version, every later one updates that version however long it takes.
  final mergeable = switch (session) {
    EditSessionStep.start => false,
    EditSessionStep.continued => typing,
    null => typing && now.difference(newest.createdAt) <= limits.mergeWindow,
  };
  if (!mergeable) return const EntryVersionInsert();
  if (previous != null && previous.content == content) {
    return EntryVersionCollapse(newest.id);
  }
  return EntryVersionMerge(newest.id);
}

/// Ids to delete so that at most [EntryVersionLimits.maxCount] remain.
/// [newestFirst] is ordered newest first.
List<String> entryVersionIdsToPrune(
  List<String> newestFirst, {
  EntryVersionLimits limits = EntryVersionLimits.standard,
}) => newestFirst.length <= limits.maxCount
    ? const []
    : newestFirst.sublist(limits.maxCount);

/// Source of the baseline snapshot taken when an edit starts: the dictated
/// text when no version exists, otherwise [EntryVersionSource.converted]
/// (the text changed without a snapshot, for example by Smart Mode).
EntryVersionSource baselineSource({required bool hasVersions}) =>
    hasVersions ? EntryVersionSource.converted : EntryVersionSource.dictated;
