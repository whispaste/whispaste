/// Centralized mutation boundary for history detail panel.
///
/// Owns all read/write operations for a single history entry:
/// transcript edits, tag mutations, note mutations, entry actions.
/// UI widgets become pure consumers — no direct DB calls.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable snapshot of everything the detail panel needs for one entry.
class HistoryDetailState {
  const HistoryDetailState({
    required this.entry,
    required this.tags,
    required this.notes,
  });

  final HistoryEntry entry;
  final List<Tag> tags;
  final List<EntryNote> notes;

  HistoryDetailState copyWith({
    HistoryEntry? entry,
    List<Tag>? tags,
    List<EntryNote>? notes,
  }) =>
      HistoryDetailState(
        entry: entry ?? this.entry,
        tags: tags ?? this.tags,
        notes: notes ?? this.notes,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class HistoryDetailNotifier extends AsyncNotifier<HistoryDetailState> {
  HistoryDetailNotifier(this._entryId);
  final String _entryId;

  HistoryDatabase get _db => ref.read(historyDatabaseProvider);

  @override
  Future<HistoryDetailState> build() async {
    final entry = await _db.getEntry(_entryId);
    if (entry == null) {
      throw StateError('Entry $_entryId not found');
    }
    final tags = await _db.tagsForEntry(_entryId);
    final notes = await _db.notesForEntry(_entryId);
    return HistoryDetailState(entry: entry, tags: tags, notes: notes);
  }

  /// Reload all data from DB (e.g. after external mutation).
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }

  // ── Transcript / content ──────────────────────────────────────────────

  Future<void> updateContent(String newContent) async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.upsertEntry(HistoryEntriesCompanion(
      id: Value(_entryId),
      content: Value(newContent),
    ));
    state = AsyncValue.data(current.copyWith(
      entry: await _db.getEntry(_entryId) ?? current.entry,
    ));
  }

  Future<void> updateTitle(String newTitle) async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.upsertEntry(HistoryEntriesCompanion(
      id: Value(_entryId),
      title: Value(newTitle),
      titleEdited: const Value(true),
    ));
    state = AsyncValue.data(current.copyWith(
      entry: await _db.getEntry(_entryId) ?? current.entry,
    ));
  }

  // ── Notes ─────────────────────────────────────────────────────────────

  Future<void> addNote(String content) async {
    final current = state.asData?.value;
    if (current == null || content.trim().isEmpty) return;
    final now = DateTime.now();
    await _db.upsertNote(EntryNotesCompanion(
      id: Value(now.millisecondsSinceEpoch.toString()),
      entryId: Value(_entryId),
      content: Value(content.trim()),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    final notes = await _db.notesForEntry(_entryId);
    state = AsyncValue.data(current.copyWith(notes: notes));
  }

  Future<void> deleteNote(String noteId) async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.deleteNote(noteId);
    final notes = await _db.notesForEntry(_entryId);
    state = AsyncValue.data(current.copyWith(notes: notes));
  }

  Future<void> updateNote(String noteId, String newContent) async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.upsertNote(EntryNotesCompanion(
      id: Value(noteId),
      entryId: Value(_entryId),
      content: Value(newContent.trim()),
      updatedAt: Value(DateTime.now()),
    ));
    final notes = await _db.notesForEntry(_entryId);
    state = AsyncValue.data(current.copyWith(notes: notes));
  }

  // ── Tags ──────────────────────────────────────────────────────────────

  /// Add an existing or new tag to this entry.
  Future<void> addTag(String tagName) async {
    final current = state.asData?.value;
    if (current == null || tagName.trim().isEmpty) return;
    final name = tagName.trim().toLowerCase();

    // Find or create the tag
    final existing = await _db.searchTags(name);
    Tag tag;
    if (existing.any((t) => t.name == name)) {
      tag = existing.firstWhere((t) => t.name == name);
    } else {
      tag = await _db.createTag(name);
    }

    await _db.tagEntry(_entryId, tag.id);
    final tags = await _db.tagsForEntry(_entryId);
    state = AsyncValue.data(current.copyWith(tags: tags));
  }

  /// Remove a tag from this entry (does not delete the tag itself).
  Future<void> removeTag(String tagId) async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.untagEntry(_entryId, tagId);
    final tags = await _db.tagsForEntry(_entryId);
    state = AsyncValue.data(current.copyWith(tags: tags));
  }

  // ── Entry actions ─────────────────────────────────────────────────────

  Future<void> togglePin() async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.togglePin(_entryId);
    final entry = await _db.getEntry(_entryId);
    if (entry != null) {
      state = AsyncValue.data(current.copyWith(entry: entry));
    }
  }

  Future<void> toggleArchive() async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.toggleArchive(_entryId);
    final entry = await _db.getEntry(_entryId);
    if (entry != null) {
      state = AsyncValue.data(current.copyWith(entry: entry));
    }
  }

  Future<void> softDelete() async {
    await _db.softDeleteEntry(_entryId);
  }

  Future<void> restore() async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.restoreEntry(_entryId);
    final entry = await _db.getEntry(_entryId);
    if (entry != null) {
      state = AsyncValue.data(current.copyWith(entry: entry));
    }
  }

  Future<void> permanentDelete() async {
    await _db.permanentDeleteEntry(_entryId);
  }

  Future<HistoryEntry?> duplicate() async {
    return _db.duplicateEntry(_entryId);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Family provider keyed by entry ID. Auto-disposes when the detail panel
/// is closed (no listeners).
final historyDetailProvider = AsyncNotifierProvider.autoDispose
    .family<HistoryDetailNotifier, HistoryDetailState, String>(
  HistoryDetailNotifier.new,
);
