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

  /// Stores a version snapshot of [noteId] unless it repeats the newest one.
  Future<bool> snapshot(
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
    final name = tagName.trim().toLowerCase();
    if (name.isEmpty) return;

    final existing = await _db.searchTags(name);
    final tag = existing.any((t) => t.name == name)
        ? existing.firstWhere((t) => t.name == name)
        : await _db.createTag(name);

    await _db.tagNote(noteId, tag.id);
  }

  /// Remove a tag from a note (does not delete the tag itself).
  Future<void> removeTag(String noteId, String tagId) =>
      _db.untagNote(noteId, tagId);
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
