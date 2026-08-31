/// Centralized mutation boundary for history detail panel.
///
/// Owns all read/write operations for a single history entry:
/// transcript edits, tag mutations, note mutations, entry actions.
/// UI widgets become pure consumers — no direct DB calls.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/services/smart_mode/smart_mode_retroactive_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable snapshot of everything the detail panel needs for one entry.
class HistoryDetailState {
  const HistoryDetailState({
    required this.entry,
    required this.tags,
    required this.notes,
    this.viewingEditedVersion = false,
    this.applyingPreset = false,
  });

  final HistoryEntry entry;
  final List<Tag> tags;
  final List<EntryNote> notes;

  /// Which text the detail panel currently shows for the transcript area —
  /// `true` selects [HistoryEntry.smartModeEditedContent] over the raw
  /// [HistoryEntry.content] (ticket 05). Defaults to raw/`false` whenever the
  /// entry is (re)loaded; not persisted.
  final bool viewingEditedVersion;

  /// Whether a retroactive preset application is currently in flight — lets
  /// the UI show a spinner and disable the action while it runs.
  final bool applyingPreset;

  /// The text currently selected for display per [viewingEditedVersion] —
  /// falls back to the raw [content][HistoryEntry.content] whenever no
  /// edited version exists yet, even if [viewingEditedVersion] is `true`
  /// (e.g. right after loading an entry that was never edited).
  String get displayedContent {
    if (!viewingEditedVersion) return entry.content;
    return entry.smartModeEditedContent ?? entry.content;
  }

  /// Whether this entry has an edited version to toggle to at all.
  bool get hasEditedVersion => entry.smartModeEditedContent != null;

  HistoryDetailState copyWith({
    HistoryEntry? entry,
    List<Tag>? tags,
    List<EntryNote>? notes,
    bool? viewingEditedVersion,
    bool? applyingPreset,
  }) => HistoryDetailState(
    entry: entry ?? this.entry,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    viewingEditedVersion: viewingEditedVersion ?? this.viewingEditedVersion,
    applyingPreset: applyingPreset ?? this.applyingPreset,
  );
}

/// Outcome of [HistoryDetailNotifier.applyPreset], surfaced to the UI so it
/// can show a tailored message (ticket 05: failures must not fail silently
/// the way the live pipeline does — there is no paste to protect here).
sealed class HistoryPresetApplicationResult {
  const HistoryPresetApplicationResult();
}

final class HistoryPresetApplicationSuccess
    extends HistoryPresetApplicationResult {
  const HistoryPresetApplicationSuccess();
}

final class HistoryPresetApplicationFailure
    extends HistoryPresetApplicationResult {
  const HistoryPresetApplicationFailure(this.reason);

  final SmartModeRetroactiveFailureReason reason;
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
    await _db.updateEntry(
      _entryId,
      HistoryEntriesCompanion(content: Value(newContent)),
    );
    state = AsyncValue.data(
      current.copyWith(entry: await _db.getEntry(_entryId) ?? current.entry),
    );
  }

  /// Switches the detail panel's transcript view between raw and edited
  /// (ticket 05) — pure UI state, not persisted.
  void setViewingEditedVersion(bool viewingEdited) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(viewingEditedVersion: viewingEdited),
    );
  }

  /// Applies [preset] to this entry's raw content and overwrites its
  /// "current edited version" on success (ticket 05). The raw content is
  /// never touched. On failure the existing edited version (if any) is left
  /// exactly as it was — no silent data loss — and the returned result
  /// tells the caller why, for a tailored error message.
  Future<HistoryPresetApplicationResult> applyPreset(
    SmartModePreset preset, {
    SmartModeTargetLanguage? targetLanguage,
  }) async {
    final current = state.asData?.value;
    if (current == null) {
      return const HistoryPresetApplicationFailure(
        SmartModeRetroactiveFailureReason.engineError,
      );
    }

    state = AsyncValue.data(current.copyWith(applyingPreset: true));
    final result = await ref
        .read(smartModeRetroactiveServiceProvider)
        .apply(
          rawText: current.entry.content,
          preset: preset,
          targetLanguage: targetLanguage,
        );

    switch (result) {
      case SmartModeRetroactiveSuccess(:final editedContent):
        await _db.updateEntry(
          _entryId,
          HistoryEntriesCompanion(smartModeEditedContent: Value(editedContent)),
        );
        final entry = await _db.getEntry(_entryId);
        state = AsyncValue.data(
          (current.copyWith(applyingPreset: false)).copyWith(
            entry: entry ?? current.entry,
            viewingEditedVersion: true,
          ),
        );
        return const HistoryPresetApplicationSuccess();
      case SmartModeRetroactiveFailure(:final reason):
        state = AsyncValue.data(current.copyWith(applyingPreset: false));
        return HistoryPresetApplicationFailure(reason);
    }
  }

  Future<void> updateTitle(String newTitle) async {
    final current = state.asData?.value;
    if (current == null) return;
    await _db.updateEntry(
      _entryId,
      HistoryEntriesCompanion(
        title: Value(newTitle),
        titleEdited: const Value(true),
      ),
    );
    state = AsyncValue.data(
      current.copyWith(entry: await _db.getEntry(_entryId) ?? current.entry),
    );
  }

  // ── Notes ─────────────────────────────────────────────────────────────

  Future<void> addNote(String content) async {
    final current = state.asData?.value;
    if (current == null || content.trim().isEmpty) return;
    final now = DateTime.now();
    await _db.upsertNote(
      EntryNotesCompanion(
        id: Value(generateV4Uuid()),
        entryId: Value(_entryId),
        content: Value(content.trim()),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
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
    await _db.updateNoteFields(
      noteId,
      EntryNotesCompanion(
        content: Value(newContent.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
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

  Future<void> _applyEntryAction(Future<void> Function() action) async {
    final current = state.asData?.value;
    if (current == null) return;
    await action();
    final entry = await _db.getEntry(_entryId);
    if (entry != null) {
      state = AsyncValue.data(current.copyWith(entry: entry));
    }
  }

  Future<void> togglePin() => _applyEntryAction(() => _db.togglePin(_entryId));

  Future<void> toggleArchive() =>
      _applyEntryAction(() => _db.toggleArchive(_entryId));

  Future<void> softDelete() async {
    await _db.softDeleteEntry(_entryId);
  }

  Future<void> restore() => _applyEntryAction(() => _db.restoreEntry(_entryId));

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
