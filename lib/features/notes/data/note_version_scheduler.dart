/// Decides when a note gets a version snapshot (WP-31a).
///
/// Two triggers, both funnelled through [onSnapshot]: an explicit save, which
/// snapshots at once, and an idle pause, which snapshots once no edit has come
/// in for [idleDelay]. Every edit restarts the idle timer, so a long session of
/// typing yields one snapshot after it, not one per keystroke. Pure Dart with
/// a [Timer], so the rules are testable with `fakeAsync`.
library;

import 'dart:async';

class NoteVersionScheduler {
  NoteVersionScheduler({
    required this.onSnapshot,
    this.idleDelay = const Duration(seconds: 30),
  });

  /// Stores a snapshot of the note's current state. Called with the note id.
  final Future<void> Function(String noteId) onSnapshot;

  /// Pause after the last edit before an idle snapshot is taken.
  final Duration idleDelay;

  Timer? _timer;
  String? _pendingNoteId;

  /// Whether an idle snapshot is waiting to fire.
  bool get hasPending => _pendingNoteId != null;

  /// Records an edit of [noteId]. Restarts the idle timer.
  void touch(String noteId) {
    _timer?.cancel();
    _pendingNoteId = noteId;
    _timer = Timer(idleDelay, _fire);
  }

  /// Snapshots [noteId] immediately and drops any pending idle snapshot.
  Future<void> snapshotNow(String noteId) async {
    _cancel();
    await onSnapshot(noteId);
  }

  /// Drops the pending idle snapshot without taking it. Used on teardown,
  /// after the caller has already snapshotted explicitly.
  void dispose() => _cancel();

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingNoteId = null;
  }

  void _fire() {
    final noteId = _pendingNoteId;
    _cancel();
    if (noteId != null) unawaited(onSnapshot(noteId));
  }
}
