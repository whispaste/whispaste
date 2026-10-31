/// Centralized mutation boundary for history detail panel.
///
/// Owns all read/write operations for a single history entry:
/// transcript edits, tag mutations, note mutations, entry actions.
/// UI widgets become pure consumers — no direct DB calls.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/logging/app_logger.dart';
import 'package:whispaste/features/history/data/history_title.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/services/smart_mode/smart_mode_retroactive_service.dart';
import 'package:whispaste/services/pending_audio/pending_audio_providers.dart';

final _log = AppLogger('HistoryDetail');

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

/// Another Smart-Mode write (an undo, a restore or a preset) holds the entry's
/// lock. Not a failure: nothing was applied and the user may simply retry
/// (DEV-175).
final class HistoryPresetApplicationBusy
    extends HistoryPresetApplicationResult {
  const HistoryPresetApplicationBusy();
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
    final derivedTitle = deriveHistoryTitle(newContent);
    await _db.updateEntry(
      _entryId,
      HistoryEntriesCompanion(
        content: Value(newContent),
        // The title starts as a pure derivation of the content (see
        // `DriftRecordingStore.save`) and stays that way until the user
        // explicitly renames it (`titleEdited` flips true via
        // [updateTitle]). Recompute it on every content save so editing a
        // transcript's body doesn't leave the list row / detail-header
        // title stuck on the pre-edit text (issue 02) — but never overwrite
        // a title the user chose on purpose, and never blank it out: if the
        // edit clears the transcript entirely, keep the last non-empty
        // title rather than showing an untitled/empty row.
        title: current.entry.titleEdited || derivedTitle.isEmpty
            ? const Value.absent()
            : Value(derivedTitle),
      ),
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
    final lock = ref.read(smartModeBusyProvider.notifier);
    // Shared with undo/restore (DEV-155): neither may start while the other
    // writes to this entry.
    if (!lock.tryAcquire(_entryId)) {
      return const HistoryPresetApplicationBusy();
    }
    try {
      return await _applyPresetLocked(preset, targetLanguage: targetLanguage);
    } finally {
      lock.release(_entryId);
    }
  }

  Future<HistoryPresetApplicationResult> _applyPresetLocked(
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
    final SmartModeRetroactiveResult result;
    try {
      result = await ref
          .read(smartModeRetroactiveServiceProvider)
          .apply(
            rawText: current.entry.content,
            preset: preset,
            targetLanguage: targetLanguage,
            languageCode: current.entry.language,
            detectedLanguage: current.entry.languageHint,
          );
    } on Object catch (error) {
      // Fail closed: the stored versions stay as they were, and the busy flag
      // is cleared on every path (DEV-141). Only the class is logged.
      _log.warning('Retroactive Smart Mode failed (${error.runtimeType})');
      _clearApplyingPreset();
      return const HistoryPresetApplicationFailure(
        SmartModeRetroactiveFailureReason.engineError,
      );
    }

    switch (result) {
      case SmartModeRetroactiveSuccess(:final editedContent):
        await _db.updateEntry(
          _entryId,
          HistoryEntriesCompanion(smartModeEditedContent: Value(editedContent)),
        );
        final entry = await _db.getEntry(_entryId);
        final latest = state.asData?.value ?? current;
        state = AsyncValue.data(
          latest.copyWith(
            applyingPreset: false,
            entry: entry ?? latest.entry,
            viewingEditedVersion: true,
          ),
        );
        return const HistoryPresetApplicationSuccess();
      case SmartModeRetroactiveFailure(:final reason):
        _clearApplyingPreset();
        return HistoryPresetApplicationFailure(reason);
    }
  }

  void _clearApplyingPreset() {
    final latest = state.asData?.value;
    if (latest == null) return;
    state = AsyncValue.data(latest.copyWith(applyingPreset: false));
  }

  /// Smart-Mode undo (Block C): the raw input becomes the content again and
  /// the result is kept for [restoreSmartMode]. Returns false when no undo is
  /// in effect (for example after a manual edit cleared it).
  Future<bool> undoSmartMode() =>
      _writeSmartModeUndo(() => _db.undoSmartMode(_entryId));

  /// Reverses [undoSmartMode] and brings the stored result back.
  Future<bool> restoreSmartMode() =>
      _writeSmartModeUndo(() => _db.restoreSmartModeOutput(_entryId));

  /// Runs one undo/restore write. Refused while a preset is being applied
  /// (DEV-155). The state is re-read after the await, so a snapshot taken
  /// before the write never overwrites newer state.
  Future<bool> _writeSmartModeUndo(Future<bool> Function() write) async {
    final current = state.asData?.value;
    if (current == null || current.applyingPreset) return false;
    final lock = ref.read(smartModeBusyProvider.notifier);
    if (!lock.tryAcquire(_entryId)) return false;
    try {
      final changed = await write();
      final entry = await _db.getEntry(_entryId);
      final latest = state.asData?.value ?? current;
      state = AsyncValue.data(latest.copyWith(entry: entry ?? latest.entry));
      return changed;
    } finally {
      lock.release(_entryId);
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
    await ref.read(pendingAudioQueueProvider).discard(_entryId);
  }

  Future<void> restore() => _applyEntryAction(() => _db.restoreEntry(_entryId));

  Future<void> permanentDelete() async {
    await _db.permanentDeleteEntry(_entryId);
    await ref.read(pendingAudioQueueProvider).discard(_entryId);
  }

  Future<HistoryEntry?> duplicate() async {
    return _db.duplicateEntry(_entryId);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Entry IDs with a Smart-Mode write in flight (a preset apply or an
/// undo/restore). Each entry takes the lock at most once at a time, whichever
/// path (detail panel or toast) starts the write (DEV-155).
final smartModeBusyProvider =
    NotifierProvider<SmartModeBusyNotifier, Set<String>>(
      SmartModeBusyNotifier.new,
    );

class SmartModeBusyNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Returns false when [entryId] is already locked.
  bool tryAcquire(String entryId) {
    if (state.contains(entryId)) return false;
    state = {...state, entryId};
    return true;
  }

  void release(String entryId) {
    state = {...state}..remove(entryId);
  }
}

/// Family provider keyed by entry ID. Auto-disposes when the detail panel
/// is closed (no listeners).
final historyDetailProvider = AsyncNotifierProvider.autoDispose
    .family<HistoryDetailNotifier, HistoryDetailState, String>(
      HistoryDetailNotifier.new,
    );
