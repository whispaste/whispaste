/// Autosave of the note and recording editors — a thin adapter onto the one
/// text write path, [TextWriter] (#676).
///
/// [schedule] hands each keystroke's text to the writer, which saves after
/// its quiet pause (2 s, longer for long texts), journals in between and
/// merges changes made elsewhere. Callers still call [flush] to save at
/// once on: note switch in the list, editor blur, `dispose()`, and right
/// before `togglePin`/`moveToTrash`/`deleteForever`. Pure Dart, testable
/// with `fakeAsync`.
library;

import 'dart:async';

import '../../../core/data/text_writer/text_writer.dart';

class NoteAutosave {
  NoteAutosave({
    required this.onSave,
    this.load,
    this.kind = 'note',
    this._writer,
  });

  final Future<void> Function(String noteId, String content) onSave;

  /// Reads the stored content of a document — enables the paragraph merge
  /// with a change made outside this editor.
  final Future<String?> Function(String noteId)? load;

  /// Document kind in the writer's journal ('note', 'recording').
  final String kind;

  final TextWriter? _writer;
  TextWriter get writer => _writer ?? TextWriter.shared;

  final Set<String> _scheduled = {};

  TextDocKey keyOf(String noteId) => TextDocKey(kind, noteId);

  /// The editor shows [content] of [noteId] as stored.
  void opened(String noteId, String content) =>
      writer.opened(keyOf(noteId), content);

  /// Schedules [content] to be saved for [noteId] after the quiet pause.
  void schedule(String noteId, String content) {
    _scheduled.add(noteId);
    final read = load;
    writer.schedule(
      keyOf(noteId),
      content,
      save: (text) => onSave(noteId, text),
      load: read == null ? null : () => read(noteId),
    );
  }

  /// Saves every pending text of this editor now. Never throws: a failure
  /// keeps the text pending, writes a backup and is reported by the writer.
  /// True when nothing is left pending.
  Future<bool> flush() async {
    var ok = true;
    for (final id in [..._scheduled]) {
      final saved = await writer.flush(keyOf(id));
      if (saved) _scheduled.remove(id);
      ok = ok && saved;
    }
    return ok;
  }

  /// Drops the pending edit of [noteId] (the document was deleted).
  Future<void> discard(String noteId) {
    _scheduled.remove(noteId);
    return writer.discard(keyOf(noteId));
  }

  /// Drops every pending edit of this editor (the edit was written another
  /// way or abandoned).
  Future<void> discardAll() async {
    for (final id in [..._scheduled]) {
      await discard(id);
    }
  }

  /// Nothing to tear down: pending text stays with the writer, which the
  /// app flushes on blur, pause and quit.
  void dispose() {}
}
