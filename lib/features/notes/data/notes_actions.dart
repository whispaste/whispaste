/// Stateless write-side facade for the sidebar Notizen area.
///
/// UI reads live data from `notesProvider`/`trashNotesProvider`
/// (`core/data/notes_providers.dart`) and writes exclusively through
/// [NotesActions] — one data flow, no `NotesDetailNotifier`-style duplicate
/// state (a note is a flat object; there's nothing to hold beyond what the
/// stream providers already emit).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/database.dart';
import '../../../core/data/note_asset_storage.dart';
import '../../../core/data/note_version_limits.dart';
import '../../../services/automation_api/automation_hook_dispatcher_provider.dart';
import '../../../services/path_service.dart' show appDataDir;
import 'note_asset_store.dart';
import 'note_image_inspector.dart';
import 'note_image_metadata.dart';

class NotesActions {
  NotesActions(
    this._db, {
    this.onChanged,
    this._assets,
    this._limits = NoteAssetLimits.standard,
  });

  final HistoryDatabase _db;

  /// Image files. Null in tests that only exercise the database side; image
  /// methods then refuse to run instead of writing somewhere unexpected.
  final NoteAssetStore? _assets;

  final NoteAssetLimits _limits;

  /// Called after a successful [save] with the note id and the saved
  /// content. The app wires this to the automation `note.changed` event;
  /// the automation API's own writes are built without it (loop guard).
  final void Function(String noteId, String content)? onChanged;

  Future<Note> create() => _db.createNote();

  /// A new note with [content] that remembers recording [entryId] (issue
  /// #629). Fires [onChanged] like [save], so the automation event is the same.
  Future<Note> createFromEntry(String entryId, String content) async {
    final note = await _db.createNoteFromEntry(entryId, content);
    onChanged?.call(note.id, content);
    return note;
  }

  Future<Note?> duplicate(String noteId) => _db.duplicateNote(noteId);

  /// One-shot read of a single note — the deep-link case (open exactly this
  /// note), where the id is known but the note may not be in the currently
  /// streamed list at all (wrong filter, list not emitted yet). Returns
  /// `null` when the note no longer exists.
  Future<Note?> getNote(String noteId) => _db.getNote(noteId);

  Future<void> save(String noteId, String content) async {
    await _db.updateNoteContent(noteId, content);
    onChanged?.call(noteId, content);
  }

  Future<void> togglePin(String noteId, {required bool pinned}) =>
      _db.toggleNotePin(noteId, pinned: pinned);

  /// Marks [noteId] as the exclusive quick note (the target the quick-note
  /// hotkey appends to), unmarking whichever note held the mark before.
  Future<void> markAsQuickNote(String noteId) => _db.setQuickNote(noteId);

  /// Clears the quick-note mark without marking another note.
  Future<void> clearQuickNoteMark() => _db.clearQuickNote();

  Future<void> moveToTrash(String noteId) => _db.softDeleteNote(noteId);

  Future<void> restore(String noteId) => _db.restoreNote(noteId);

  /// Moves all [noteIds] to the trash at once (multi-select, #655).
  Future<int> moveManyToTrash(List<String> noteIds) =>
      _db.softDeleteNotes(noteIds);

  /// Restores all [noteIds] from the trash at once — the undo of
  /// [moveManyToTrash].
  Future<int> restoreMany(List<String> noteIds) => _db.restoreNotes(noteIds);

  /// Pins (or unpins) all [noteIds] at once.
  Future<int> setPinnedMany(List<String> noteIds, {required bool pinned}) =>
      _db.setNotesPinned(noteIds, pinned: pinned);

  /// Merges [noteIds] in order into one new note; the sources go to the
  /// trash. See [HistoryDatabase.mergeNotes].
  Future<Note?> merge(List<String> noteIds) => _db.mergeNotes(noteIds);

  /// Undoes [merge]: removes the merged note for good and brings its sources
  /// back from the trash.
  Future<void> undoMerge(String mergedId, List<String> sourceIds) async {
    await _db.permanentDeleteNote(mergedId);
    await _db.restoreNotes(sourceIds);
  }

  Future<void> deleteForever(String noteId) async {
    final hadImages = await _hasImages(noteId);
    await _db.permanentDeleteNote(noteId);
    if (hadImages) await _removeNoteFolder(noteId);
  }

  /// Empties the notes trash, including the image files of the trashed notes.
  Future<int> emptyTrash() async {
    final removed = await _db.emptyNotesTrash();
    await sweepAssetFolders();
    return removed;
  }

  /// Meta key: when the automatic notes-trash purge first ran.
  static const trashRetentionSinceKey = 'notes_trash_retention_since';

  /// Removes notes that have been in the trash longer than [days] (the same
  /// period and the same setting as the recordings trash, `0` = never).
  ///
  /// Notes trashed before this rule existed were promised to stay until
  /// deleted by hand, so the first run only records its date and no trashed
  /// note disappears before a full period after that date. [now] is injected
  /// so tests use a simulated clock. Returns the number of notes removed.
  Future<int> purgeExpiredTrash({
    required int days,
    required DateTime now,
  }) async {
    if (days <= 0) return 0;
    final stored = await _db.readAppMeta(trashRetentionSinceKey);
    var since = stored == null ? null : DateTime.tryParse(stored);
    if (since == null) {
      since = now;
      await _db.writeAppMeta(trashRetentionSinceKey, now.toIso8601String());
    }
    final cutoff = now.subtract(Duration(days: days));
    if (cutoff.isBefore(since)) return 0;
    final removed = await _db.purgeNotesTrashBefore(cutoff);
    if (removed > 0) await sweepAssetFolders();
    return removed;
  }

  /// Deletes active notes whose content is blank — the empty-discard
  /// safety-net sweep run once when the Notizen page mounts.
  Future<int> purgeEmpty() async {
    final removed = await _db.purgeEmptyNotes();
    await sweepAssetFolders();
    return removed;
  }

  /// Empty-discard for a single note (leaving it, closing the page): deletes
  /// [noteId] only if it is still blank and not the marked quick note.
  Future<bool> discardIfBlank(String noteId) async {
    final hadImages = await _hasImages(noteId);
    final removed = await _db.discardNoteIfBlank(noteId);
    if (removed && hadImages) await _removeNoteFolder(noteId);
    return removed;
  }

  /// Whether [noteId] has image rows, read before its rows are deleted. The
  /// check keeps the common case (no images) free of file access.
  Future<bool> _hasImages(String noteId) async {
    if (_assets == null) return false;
    return (await _db.noteAssetsFor(noteId)).isNotEmpty;
  }

  Future<void> _removeNoteFolder(String noteId) async {
    final assets = _assets;
    if (assets != null) await assets.deleteNoteFolder(noteId);
  }

  /// Sets (or with a blank value clears) the explicit title of [noteId].
  Future<void> saveTitle(String noteId, String? title) =>
      _db.setNoteTitle(noteId, title);

  /// Stores a version snapshot of [noteId] unless it repeats the newest one;
  /// the outcome also says when the text is too long to keep a version of.
  Future<NoteVersionOutcome> snapshot(
    String noteId, {
    required String? title,
    required String content,
  }) => _db.recordNoteVersionIfChanged(noteId, title: title, content: content);

  /// Restores [versionId] as the current state. The state it replaces is kept
  /// as a version, so the restore can be undone.
  Future<bool> restoreVersion(String versionId) =>
      _db.restoreNoteVersion(versionId);

  Future<int> deleteVersion(String versionId) =>
      _db.deleteNoteVersion(versionId);

  /// Stores [bytes] as an image of [noteId]. The bytes are checked from their
  /// header first; a rejected file is never written. Throws
  /// [NoteImageRejectedException] for a refused file.
  Future<NoteAsset> addImage(String noteId, Uint8List bytes) async {
    final assets = _requireAssets();
    final check = inspectNoteImage(bytes);
    final info = check.info;
    if (info == null) {
      throw NoteImageRejectedException(check.rejection!);
    }
    // The stored copy has its metadata (GPS, camera data) removed. Pixels are
    // not decoded, so the size and dimensions read above still hold.
    final Uint8List clean;
    try {
      clean = stripImageMetadata(bytes, info.type);
    } on NoteImageMetadataException {
      throw const NoteImageRejectedException(
        NoteImageRejection.unreadableStructure,
      );
    }
    final assetId = generateV4Uuid();
    final relativePath = NoteAssetStore.relativePathFor(
      noteId,
      assetId,
      info.type,
    );
    // The row goes in first, inside the limit check, so a refused import
    // writes neither a row nor a file. The file follows; if writing it fails,
    // the row is taken back again.
    await _db.insertNoteAssetWithinLimits(
      NoteAssetsCompanion.insert(
        id: assetId,
        noteId: noteId,
        relativePath: relativePath,
        mimeType: info.type.mimeType,
        sizeBytes: clean.length,
        width: info.width,
        height: info.height,
        createdAt: DateTime.now(),
      ),
      _limits,
    );
    try {
      await assets.write(relativePath, clean);
    } catch (_) {
      await _db.deleteNoteAsset(assetId);
      rethrow;
    }
    final asset = await _db.getNoteAsset(assetId);
    if (asset == null) {
      throw StateError('note asset $assetId vanished after insert');
    }
    return asset;
  }

  /// Removes an image row and its file. The caller removes the reference from
  /// the note body.
  Future<void> removeImage(NoteAsset asset) async {
    final assets = _requireAssets();
    await _db.deleteNoteAsset(asset.id);
    await assets.delete(asset.relativePath);
  }

  /// Removes image folders whose note no longer exists. Runs on page entry, so
  /// a crash or an "all data" delete never leaves images behind for good.
  Future<void> sweepAssetFolders() async {
    final assets = _assets;
    if (assets == null) return;
    await assets.sweep(
      loadLiveNoteIds: _db.allNoteIds,
      loadLiveRelativePaths: _db.allNoteAssetPaths,
    );
  }

  /// Creates a Textbaustein from a note (or a selection in it) and records the
  /// note as its source. Returns the new snippet id.
  Future<String> createSnippetFromNote({
    required String noteId,
    required String title,
    required String body,
  }) async {
    final id = generateV4Uuid();
    await _db.upsertSnippet(
      id: id,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      sourceNoteId: noteId,
    );
    return id;
  }

  NoteAssetStore _requireAssets() {
    final assets = _assets;
    if (assets == null) {
      throw StateError('NotesActions has no NoteAssetStore');
    }
    return assets;
  }

  /// Add an existing or new tag to a note (find-or-create by name), mirrors
  /// `HistoryDetailNotifier.addTag`.
  Future<void> addTag(String noteId, String tagName) async {
    final tag = await _findOrCreateTag(tagName);
    if (tag == null) return;
    await _db.tagNote(noteId, tag.id);
  }

  /// The tag named [tagName] (trimmed, lower-cased), created when missing;
  /// `null` for a blank name.
  Future<Tag?> _findOrCreateTag(String tagName) async {
    final name = tagName.trim().toLowerCase();
    if (name.isEmpty) return null;
    final existing = await _db.searchTags(name);
    return existing.any((t) => t.name == name)
        ? existing.firstWhere((t) => t.name == name)
        : await _db.createTag(name);
  }

  /// Remove a tag from a note (does not delete the tag itself).
  Future<void> removeTag(String noteId, String tagId) =>
      _db.untagNote(noteId, tagId);

  /// Adds tag [tagName] (find-or-create) to all [noteIds]. Returns the tag
  /// id and the notes that did not carry it before — exactly the links the
  /// undo ([removeTagFromMany]) has to take away again. `null` for a blank
  /// name.
  Future<({String tagId, List<String> added})?> addTagToMany(
    List<String> noteIds,
    String tagName,
  ) async {
    final tag = await _findOrCreateTag(tagName);
    if (tag == null) return null;
    final added = <String>[];
    for (final id in noteIds) {
      final had = (await _db.tagsForNote(id)).any((t) => t.id == tag.id);
      if (had) continue;
      await _db.tagNote(id, tag.id);
      added.add(id);
    }
    return (tagId: tag.id, added: added);
  }

  /// Removes tag [tagId] from all [noteIds].
  Future<void> removeTagFromMany(List<String> noteIds, String tagId) async {
    for (final id in noteIds) {
      await _db.untagNote(id, tagId);
    }
  }
}

/// Image files of the notes, under the app data directory. Overridable in
/// tests that must not touch the real app data folder.
final noteAssetStoreProvider = Provider<NoteAssetStore>(
  (ref) => NoteAssetStore(appDataDirPath: appDataDir()),
);

final notesActionsProvider = Provider<NotesActions>((ref) {
  // Watched, not read inside the callback: a save can run after this provider
  // is disposed, and a disposed Ref must not be used.
  final dispatcher = ref.watch(automationHookDispatcherProvider);
  return NotesActions(
    ref.watch(historyDatabaseProvider),
    assets: ref.watch(noteAssetStoreProvider),
    onChanged: (noteId, content) => unawaited(
      dispatcher.dispatch(
        event: 'note.changed',
        data: {'note_id': noteId, 'content': content},
      ),
    ),
  );
});

/// Version history of one note, newest first, live.
final noteVersionsProvider = StreamProvider.autoDispose
    .family<List<NoteVersion>, String>(
      (ref, noteId) =>
          ref.watch(historyDatabaseProvider).watchNoteVersions(noteId),
    );

/// Image attachments of one note, in insertion order, live.
final noteAssetsProvider = StreamProvider.autoDispose
    .family<List<NoteAsset>, String>(
      (ref, noteId) =>
          ref.watch(historyDatabaseProvider).watchNoteAssets(noteId),
    );

/// When each quick-note dictation was appended to one note, oldest first,
/// live (#803). Feeds the margin marks beside the editor.
final noteAppendsProvider = StreamProvider.autoDispose
    .family<List<NoteAppend>, String>(
      (ref, noteId) =>
          ref.watch(historyDatabaseProvider).watchNoteAppends(noteId),
    );
