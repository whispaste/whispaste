/// WhisPaste history database — drift schema definitions.
///
/// Mirrors the Go SQLite schema (v9) for full compatibility.
/// Tables: history_entries, projects, daily_stats, entry_notes,
/// entry_attachments. FTS5 is handled separately via raw SQL.
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
  TextColumn get source =>
      text().withDefault(const Constant('dictation'))();
  TextColumn get model => text().withDefault(const Constant(''))();
  BoolColumn get isLocal => boolean().withDefault(const Constant(false))();
  RealColumn get costUsd => real().withDefault(const Constant(0.0))();
  TextColumn get projectId => text().withDefault(const Constant(''))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get titleEdited =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User-defined projects for grouping entries.
@DataClassName('Project')
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  DateTimeColumn get createdAt => dateTime()();

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
  RealColumn get totalDurationSec =>
      real().withDefault(const Constant(0.0))();
  RealColumn get totalProcessingSec =>
      real().withDefault(const Constant(0.0))();
  IntColumn get totalWords => integer().withDefault(const Constant(0))();
  RealColumn get totalCostUsd =>
      real().withDefault(const Constant(0.0))();
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
@DataClassName('TextReplacement')
class TextReplacements extends Table {
  TextColumn get id => text()();
  TextColumn get trigger => text()();
  TextColumn get replacement => text()();
  DateTimeColumn get createdAt => dateTime()();

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
