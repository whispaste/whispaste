/// WhisPaste history database — drift schema definitions.
///
/// Tables: history_entries, daily_stats, entry_notes, entry_attachments,
/// text_replacements, tags, entry_tags. FTS5 is handled separately via raw
/// SQL.
///
/// History note: a `projects` table and `history_entries.project_id` column
/// existed in the Go-era schema (≤ v9) but were never wired to any UI and
/// have been dropped destructively in schema v10 (see [HistoryDatabase] in
/// `database.dart`).
library;

import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/// Core transcription history entries.
@DataClassName('HistoryEntry')
class HistoryEntries extends Table {
  TextColumn get id => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get timestamp => dateTime()();
  RealColumn get durationSec => real().withDefault(const Constant(0.0))();
  RealColumn get processingDurationSec =>
      real().withDefault(const Constant(0.0))();
  TextColumn get language => text().withDefault(const Constant(''))();

  /// Language the engine detected for an `auto` recording (DEV-132); empty
  /// when unknown. Read by retroactive Smart Mode for the fact guard's name
  /// rule. Stored in this existing column, so no migration was needed.
  TextColumn get languageHint => text().withDefault(const Constant(''))();
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get source => text().withDefault(const Constant('dictation'))();
  TextColumn get model => text().withDefault(const Constant(''))();
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();
  RealColumn get costUsd => real().withDefault(const Constant(0.0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get titleEdited => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Decorative color slot (v18) — an index into the 8 rotating category
  /// hues (`WpCategorySlot.categories`, index 0–7). Assigned once at real
  /// creation time in [DriftRecordingStore.save] and never touched again;
  /// see `insertHistoryEntry` in `database.dart`. Purely decorative, not a
  /// content category — the 9th slot, `WpCategorySlot.neutral`, is never a
  /// value here because there is no "uncategorized" case for this rotation.
  IntColumn get colorSlot => integer().withDefault(const Constant(0))();

  /// Smart Mode's "current edited version" (v22, Smart-Mode-v2 ticket 05) —
  /// overwritten in place by every preset application (live or retroactive),
  /// never a version stack. `null` means no preset has ever been applied to
  /// this entry; [content] (the raw transcript) is never touched by Smart
  /// Mode and stays the source of truth for the "raw" view.
  TextColumn get smartModeEditedContent => text().nullable()();

  /// Original transcript before live Smart-Mode refinement / text
  /// replacements were applied (v24, ticket 12). `null` for entries where
  /// no transform changed the transcript, or for pre-v24 entries — never
  /// backfilled. [content] stays the final, post-transform text; this
  /// column only exists so the detail panel can show what was originally
  /// dictated when it actually differs from [content].
  TextColumn get originalTranscript => text().nullable()();

  /// Bundle ID (macOS) / process identifier (Windows) of the app the
  /// dictation was pasted into, captured via the same auto-paste target
  /// lookup the blocklist uses (v24, ticket 12). `null` when unavailable
  /// (Linux, no target captured, permission missing, or pre-v24 entries).
  TextColumn get targetApp => text().nullable()();

  /// Exact input of the Smart-Mode run that produced [content] (v27). `null`
  /// when that input equals [originalTranscript], which is then the input
  /// (BIZ-25: the raw text is stored once).
  TextColumn get smartModeInput => text().nullable()();

  /// Result of that Smart-Mode run while an undo is in effect (v27): the
  /// content holds the input, and this holds the result for a restore. `null`
  /// when the entry shows the result.
  TextColumn get smartModeOutput => text().nullable()();

  /// Whether a Smart-Mode run changed this entry and no manual edit or
  /// re-transcription has happened since (v27). This marker is what makes an
  /// entry undoable; without it, a manual edit could be mistaken for a run.
  BoolColumn get smartModeApplied => boolean().nullable()();

  /// List preview (schema v43, #1324): the start of [content], computed on
  /// every save (see `notePreview`). Lists read this instead of the full text.
  /// NULL = not filled yet (an older row); readers then cut it from [content].
  TextColumn get preview => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pre-aggregated daily statistics for fast analytics.
@DataClassName('DailyStat')
class DailyStats extends Table {
  TextColumn get date => text()();
  TextColumn get model => text()();
  BoolColumn get isLocal => boolean()();
  IntColumn get count => integer().withDefault(const Constant(0))();
  RealColumn get totalDurationSec => real().withDefault(const Constant(0.0))();
  RealColumn get totalProcessingSec =>
      real().withDefault(const Constant(0.0))();
  IntColumn get totalWords => integer().withDefault(const Constant(0))();
  RealColumn get totalCostUsd => real().withDefault(const Constant(0.0))();
  IntColumn get durUnder15s => integer().withDefault(const Constant(0))();
  IntColumn get dur15To30s => integer().withDefault(const Constant(0))();
  IntColumn get dur30To60s => integer().withDefault(const Constant(0))();
  IntColumn get dur1To3m => integer().withDefault(const Constant(0))();
  IntColumn get durOver3m => integer().withDefault(const Constant(0))();

  /// Words as spoken, before a transform action changed the text (schema
  /// v40, issue #887). Equals [totalWords] for untransformed recordings.
  IntColumn get rawWords => integer().withDefault(const Constant(0))();

  /// Recordings whose text a transform action (smart mode or LLM) changed.
  IntColumn get actionCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {date, model, isLocal};
}

/// Rich-text notes attached to history entries.
@DataClassName('EntryNote')
class EntryNotes extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text().references(HistoryEntries, #id)();
  TextColumn get content => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// File attachments for history entries (audio, screenshots, etc.).
@DataClassName('EntryAttachment')
class EntryAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text().references(HistoryEntries, #id)();
  TextColumn get filename => text()();
  TextColumn get filepath => text()();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Replacements — auto-replace trigger words during dictation.
///
/// `trigger` is kept as a legacy, schema-additive mirror of the first entry
/// in [TextReplacementTriggers] for this row (written on every save, never
/// read by app logic) — see [TextReplacementTriggers] for the source of
/// truth on which trigger phrases fire this replacement.
@DataClassName('TextReplacement')
class TextReplacements extends Table {
  TextColumn get id => text()();
  TextColumn get trigger => text()();
  TextColumn get replacement => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Last time the content changed (triggers, result, mode, threshold), schema
  /// v32. `null` for rows written before v32 — readers fall back to
  /// [createdAt]. Never set by usage counts or the favourite flag.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// Match algorithm — `exact` (word-boundary regex, unchanged pre-v20
  /// behavior) or `fuzzy` (similarity scoring, vocabulary-fuzzy-replacements
  /// PRD, schema v20). Stored as text rather than an int enum so a raw
  /// `SELECT` stays human-readable in the DB browser, consistent with other
  /// text-backed enum-ish columns in this file (e.g. `source` on
  /// `HistoryEntries`).
  TextColumn get matchMode => text().withDefault(const Constant('exact'))();

  /// Similarity threshold (0.0-1.0) for `matchMode == fuzzy`; unused and left
  /// `null` for `exact` rows. The UI only ever offers three named steps
  /// (Streng 0.92 / Standard 0.85 / Tolerant 0.75), not a free slider — see
  /// PRD.md.
  RealColumn get fuzzyThreshold => real().nullable()();

  /// `manual` (default, user-authored) or `imported` (vocabulary-import
  /// scan) — display-only distinction (PRD User Story 11), no behavioral
  /// difference in matching.
  TextColumn get origin => text().withDefault(const Constant('manual'))();

  /// How often this entry changed a dictation (schema v26). Written after
  /// each save, off the matching path; matching never reads it.
  IntColumn get usageCount => integer().withDefault(const Constant(0))();

  /// Former dictionary favourite (schema v26). Unused since #2166: the star
  /// only reordered the display. Kept because migrations are additive only.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  /// Place in the user's application order (schema v41, #1004): the cascade
  /// runs the rules in this order. `null` until the user first reorders;
  /// such rows follow all ordered ones in creation order.
  IntColumn get sortPosition => integer().nullable()();

  /// The contact-name group that brought this entry in (schema v48, #2036),
  /// a [ContactNameGroups] id. `null` for every other entry and for an
  /// imported name the user has since edited: it then belongs to the user
  /// and stays when the group is removed or refreshed.
  TextColumn get importGroupId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A removable import of contact names (schema v48, #2036). One row per
/// source the user agreed to read: [sourceKind] names the kind of source
/// (`file` for a vCard or CSV file, later a system address book),
/// [sourceLabel] what the user picked (a file name). [consentedAt] records
/// the consent; revoking it deletes the row and the untouched names it
/// brought in.
@DataClassName('ContactNameGroup')
class ContactNameGroups extends Table {
  TextColumn get id => text()();
  TextColumn get sourceKind => text()();
  TextColumn get sourceLabel => text()();
  DateTimeColumn get consentedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Trigger phrases for a [TextReplacements] row — normalized N:1 so a single
/// replacement can fire on multiple trigger phrases (schema v13). Every
/// replacement has at least one row here; each is matched independently
/// with the existing word-boundary regex (`DriftRecordingStore.save()`).
@DataClassName('TextReplacementTrigger')
class TextReplacementTriggers extends Table {
  TextColumn get id => text()();
  TextColumn get replacementId => text().references(TextReplacements, #id)();
  TextColumn get trigger => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Normalized tags for categorizing history entries.
@DataClassName('Tag')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Many-to-many link between history entries and tags.
@DataClassName('EntryTag')
class EntryTags extends Table {
  TextColumn get entryId => text().references(HistoryEntries, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {entryId, tagId};
}

/// User-defined text snippets (dictation-automations ticket 05) — named,
/// multi-line reusable text blocks, deliberately a separate table/data type
/// from [TextReplacements] (no trigger phrase, no auto-fire during a
/// recording cycle; snippets are inserted on explicit user action via a
/// picker, tickets 06/07/08). The trigger-phrase-driven "automation" feature
/// this table's doc comment used to reference alongside it (open URL/run
/// shell command/run script, tickets 02-04) was shipped and then retired —
/// full feature parity between the sandboxed Mac App Store build and the
/// Direct-Download build turned out unreachable within Apple's sandbox
/// rules, and maintaining two divergent action-type sets wasn't worth it.
@DataClassName('Snippet')
class Snippets extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// Last content change (title, body, fields, kind), schema v32. `null` for
  /// rows written before v32 — readers fall back to [createdAt].
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// `static` (default, today's only behavior — [body] is inserted verbatim)
  /// or `interactive` (schema v21, `interactive-snippets` PRD; template
  /// authoring added in schema v23): for `interactive`, [body] holds the
  /// user-authored template ([interactiveSnippetPlaceholder] tokens mark
  /// where each [SnippetFields] entry's dictated text is substituted at
  /// trigger time, see `interactive_snippet_composer.dart`) rather than
  /// text inserted verbatim.
  TextColumn get kind => text().withDefault(const Constant('static'))();

  /// The note this Textbaustein was created from ("Als Textbaustein", schema
  /// v29). Informational link back; NULL for snippets authored directly.
  TextColumn get sourceNoteId => text().nullable()();

  /// Starred by the user (schema v36). Favourites sort first in the list.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  /// Moment the snippet was moved to the trash (schema v36); `null` while it
  /// is active. Trashed snippets are invisible to the picker, the automation
  /// API and the settings export; the retention sweep removes them for good.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// How often the snippet was inserted, from the picker or the page (schema
  /// v39). Local only: never exported, never sent anywhere.
  IntColumn get useCount => integer().withDefault(const Constant(0))();

  /// When the snippet was last inserted (schema v39); `null` until its first
  /// use.
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Named fields of an `interactive`-[Snippets.kind] snippet (schema v21),
/// N:1 to [Snippets] — analogous to [TextReplacementTriggers]. Unused for a
/// `static` snippet. [sortOrder] fixes the strictly sequential field order
/// the guided recording walks through (PRD: "kein Zurückspringen, kein
/// Überspringen").
@DataClassName('SnippetField')
class SnippetFields extends Table {
  TextColumn get id => text()();
  TextColumn get snippetId => text().references(Snippets, #id)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Standalone notes for the sidebar Notizen area (schema v17) — distinct
/// from [EntryNotes], which back the per-history-entry "Anmerkung" section
/// and are a different feature entirely. No title column: the list/editor
/// derive a display title from [content] (see `deriveNoteTitle`).
@DataClassName('Note')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  // Explicit title (schema v29). NULL = no title set: list, editor and search
  // then fall back to the first non-blank line of [content].
  TextColumn get title => text().nullable()();
  // List preview (schema v42, #639): the start of [content], computed on every
  // save (see `notePreview`). Lists read this instead of the full text. NULL =
  // not filled yet (an older row); readers then cut it from [content].
  TextColumn get preview => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  // Exclusive "quick note" mark (schema v19): at most one note carries it at
  // any time, enforced by a partial unique index (see _ensureNotesIndexes).
  // Deliberately its own column, not a reuse of [pinned] — pinned is
  // multi-valued and sort-affecting, this is exclusive and sort-neutral.
  BoolColumn get isQuickNote => boolean().withDefault(const Constant(false))();
  // The recording this note was taken from with "Als Notiz übernehmen"
  // (schema v35). Soft link, no foreign key: a deleted recording leaves a
  // dangling id that readers treat as "no link".
  TextColumn get sourceEntryId => text().nullable()();
  // Archive (schema v45, #656): set aside, out of the active list, but not
  // headed for deletion like [deletedAt]. Independent of [deletedAt]: a
  // trashed archived note comes back archived when restored.
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  // Folder (schema v47, #659): the [NoteFolders] row the note sits in, NULL
  // for the top level. Soft link, no foreign key: an id whose folder is gone
  // reads as top level. Independent of trash and archive.
  TextColumn get folderId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Folders for notes (schema v47, #659). Optional: as long as no row exists,
/// the notes area shows no folder at all. At most two levels: a folder with a
/// [parentId] is a subfolder, and a subfolder never has children (enforced by
/// the database methods, see `HistoryDatabase.createNoteFolder`). A note sits
/// in at most one folder ([Notes.folderId]).
@DataClassName('NoteFolder')
class NoteFolders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local version history of a recording transcript (schema v37, #635). A row
/// is a snapshot of the transcript text after manual editing; [source] says
/// how that text came to be (`dictated`, `typed`, `restored`). Merge, count
/// cap and the unpacking of long texts live in `entry_version_rules.dart`, not
/// in the schema. Deleted together with its entry.
@DataClassName('EntryVersion')
class EntryVersions extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text()();
  TextColumn get content => text()();
  TextColumn get source => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Results of reprocessing a recording with another mode (schema v44, #680).
/// A row is one result of a Smart Mode preset run over the raw transcript;
/// [instruction] is the stored order (`cleanup`, `concise`, `translate:<code>`,
/// null for a result from before this table). The newest row whose text is
/// the entry's edited version is the shown result; undoing it drops the row
/// and brings the one before it back. The raw transcript is never changed.
/// Deleted together with its entry.
@DataClassName('ReprocessedVersion')
class ReprocessedVersions extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text()();
  TextColumn get content => text()();
  TextColumn get instruction => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local version history of a note (schema v29). A row is a snapshot of
/// title and body taken on an explicit save or after an idle pause; the
/// bounds (count per note, bytes per note) are enforced by the version store,
/// not by the schema. Deleted together with its note.
@DataClassName('NoteVersion')
class NoteVersions extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get title => text().nullable()();
  TextColumn get content => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Image attached to a note (schema v29). The bytes live in the app data
/// directory, `note_assets/<noteId>/<id>.<ext>`; [relativePath] is that path
/// below the app data directory. The body references the image as
/// `![](wp-asset:<id>)`. Rows are removed together with their note.
@DataClassName('NoteAsset')
class NoteAssets extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get relativePath => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// When a dictation was appended to a note by the quick-note hotkey (schema
/// v38, #803). The note text stays clean; the editor shows each row as a mark
/// in its margin. [anchor] is the start of the appended text, used to find the
/// spot again after the user edited the note; a mark whose anchor is gone is
/// simply not shown. Deleted together with its note.
@DataClassName('NoteAppend')
class NoteAppends extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  DateTimeColumn get appendedAt => dateTime()();
  TextColumn get anchor => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Many-to-many link between [Notes] and [Tags] — mirrors [EntryTags], reuses
/// the same [Tags] table so a tag can be shared between history entries and
/// notes.
@DataClassName('NoteTag')
class NoteTags extends Table {
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

/// Many-to-many link between [Snippets] and [Tags] (schema v46, #662) —
/// mirrors [NoteTags] and reuses the same [Tags] table, so a tag is shared
/// between recordings, notes and Textbausteine and managed in one place.
@DataClassName('SnippetTag')
class SnippetTags extends Table {
  TextColumn get snippetId => text().references(Snippets, #id)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {snippetId, tagId};
}

/// Per-recording end-to-end hotkey→text latency — local-only performance KPI.
///
/// A different privacy domain than the outgoing (bucketed) telemetry latency
/// counter in `recording_orchestrator.dart` (`_latencyBucketSeconds`) /
/// `telemetry_service.dart`: rows here are never read by anything that
/// leaves the device.
@DataClassName('HotkeyLatencyEntry')
class HotkeyLatencyEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get recordedAt => dateTime()();
  IntColumn get latencyMs => integer()();

  /// Recording stop → text delivered, without the speaking time (XP-6-09).
  /// `null` for samples recorded before schema v30.
  IntColumn get stopToTextMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One persisted correction observation for vocabulary-learning-from-
/// corrections — the
/// Drift-shape counterpart of the pure `CorrectionObservation` in
/// `services/replacements/correction_candidate_detector.dart`.
///
/// `normalizedKey` is the case-insensitive, whitespace-collapsed grouping key
/// (`normalizeCorrectionKey`) that decides whether two [CorrectionSignal]s
/// are "the same correction"; `sourceText`/`targetText` keep the most
/// recently observed original casing for display and for the eventual
/// replacement entry. A row only ever leaves `pending` for `accepted` or
/// `rejected` (never back). A rejected correction is not suggested again
/// while its row stays in the learning log; deleting the row forgets the
/// decision, so the same correction can be counted and suggested anew.
@DataClassName('CorrectionObservationRow')
class CorrectionObservations extends Table {
  TextColumn get id => text()();
  TextColumn get normalizedKey => text().unique()();
  TextColumn get sourceText => text()();
  TextColumn get targetText => text()();
  IntColumn get occurrenceCount => integer().withDefault(const Constant(1))();

  /// `pending` / `accepted` / `acceptedTerm` / `rejected` — see [CorrectionObservationStatus]
  /// in `correction_candidate_detector.dart`. Text-backed like other
  /// enum-ish columns in this file (e.g. `TextReplacements.origin`).
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// `voiceCommand` / `manualEdit` / `targetAppEdit` / `selectionHotkey`
  /// (#934) — see `CorrectionSignalSource` in
  /// `correction_signal.dart`.
  TextColumn get source => text()();
  DateTimeColumn get firstSeenAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime()();

  /// `word` for a word-level candidate (issue #144, schema v33). `text` marked
  /// the whole-text rows of v25, which schema v34 deleted (issue #350); every
  /// writer passes `word`, the default only keeps the v33 column definition.
  TextColumn get unit => text().withDefault(const Constant('text'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One app profile (ticket, `services/app_profiles/app_profile.dart`).
///
/// Optional columns are nullable and mean "keep the global setting" when
/// empty. `smart_mode` and `context_source` hold the `storageValue` of their
/// enum; unknown values fall back to `standard` / `none` on read.
/// `position` is the explicit order used for rule ties (DEV-239).
@DataClassName('AppProfileRow')
class AppProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get smartMode => text().withDefault(const Constant('standard'))();
  TextColumn get asrLanguage => text().nullable()();
  TextColumn get modelId => text().nullable()();
  TextColumn get contextSource => text().withDefault(const Constant('none'))();
  // Optional hotkey (key label and modifier string, as the settings store
  // them); null means the profile has no hotkey.
  TextColumn get hotkeyKey => text().nullable()();
  TextColumn get hotkeyModifiers => text().nullable()();
  // Fields a profile applies when it becomes active; null keeps the current
  // value ("unverändert").
  TextColumn get afterTranscription => text().nullable()();
  TextColumn get microphone => text().nullable()();
  // Consent (BIZ Art. 7(1)): all null until the user confirms. Stored in UTC.
  TextColumn get consentProvider => text().nullable()();
  BoolColumn get consentSelection =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get consentClipboard =>
      boolean().withDefault(const Constant(false))();
  TextColumn get consentTextVersion => text().nullable()();
  DateTimeColumn get consentGivenAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One matching rule of an [AppProfiles] row. `profile_id` is the owning
/// profile; rows are replaced together with their profile.
@DataClassName('AppProfileRuleRow')
class AppProfileRules extends Table {
  TextColumn get id => text()();
  TextColumn get profileId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get identifier => text()();

  /// macOS code-signing team identifier; null when not recorded.
  TextColumn get teamId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
