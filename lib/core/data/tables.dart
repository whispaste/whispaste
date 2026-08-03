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

/// Voice shortcuts — auto-replace trigger words during dictation.
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

/// User-defined dictation automations (dictation-automations ticket 02).
///
/// If the *entire* transcription exactly matches [trigger] (after
/// normalization — see `normalizeForExactMatch` in
/// `automation_dispatch_service.dart`), the action described by
/// [actionType]/[payload] runs instead of the normal insert/history pipeline.
///
/// [actionType]/[payload] deliberately separate "what kind of action" from
/// "the action's parameters" so further action types (shell command, script,
/// snippet-picker — tickets 03/04/06) can be added without a schema change:
/// [payload] is a free-form JSON blob whose shape is defined by [actionType]
/// alone. The only action type today is `open_url`, whose payload is
/// `{"url": "..."}`.
@DataClassName('Automation')
class Automations extends Table {
  TextColumn get id => text()();
  TextColumn get trigger => text()();
  TextColumn get actionType => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User-defined text snippets (dictation-automations ticket 05) — named,
/// multi-line reusable text blocks, deliberately a separate table/data type
/// from [TextReplacements] (no trigger phrase, no auto-fire during a
/// recording cycle; snippets are inserted on explicit user action via a
/// picker, tickets 06/07/08).
@DataClassName('Snippet')
class Snippets extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-recording end-to-end hotkey→text latency — local-only performance KPI.
///
/// A different privacy domain than the outgoing (bucketed) telemetry latency
/// counter in `recording_orchestrator.dart` (`_latencyBucketSeconds`) /
/// `telemetry_service.dart`: rows here are never read by anything that
/// leaves the device. See
/// `.scratch/experience-perf-polish/issues/07-latenz-kpi-erfassung.md`.
@DataClassName('HotkeyLatencyEntry')
class HotkeyLatencyEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get recordedAt => dateTime()();
  IntColumn get latencyMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
