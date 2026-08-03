/// Debounced autosave for the note editor — reine Dart, no Widget/BuildContext
/// dependency, so it's testable with `fakeAsync` (see `note_autosave_test.dart`).
///
/// Debounces 400ms from the last keystroke ([schedule]). Callers must call
/// [flush] to save immediately and cancel the pending timer on: note
/// switch in the list, editor blur, `NotesPage.dispose()`, and immediately
/// before `togglePin`/`moveToTrash`/`deleteForever`.
library;

import 'dart:async';

class NoteAutosave {
  NoteAutosave({
    required this.onSave,
    this.debounce = const Duration(milliseconds: 400),
  });

  final Future<void> Function(String noteId, String content) onSave;
  final Duration debounce;

  Timer? _timer;
  String? _pendingNoteId;
  String? _pendingContent;

  /// Schedules [content] to be saved for [noteId] after [debounce], cancelling
  /// any previously scheduled save for a different note or older content.
  void schedule(String noteId, String content) {
    _timer?.cancel();
    _pendingNoteId = noteId;
    _pendingContent = content;
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_flushPending());
    });
  }

  /// Cancels any pending debounce timer and saves immediately, if there is
  /// a pending write.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await _flushPending();
  }

  Future<void> _flushPending() async {
    final noteId = _pendingNoteId;
    final content = _pendingContent;
    if (noteId == null || content == null) return;
    _pendingNoteId = null;
    _pendingContent = null;
    await onSave(noteId, content);
  }

  /// Cancels any pending debounce timer without saving — call when the
  /// autosave instance itself is being torn down after an explicit [flush].
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
