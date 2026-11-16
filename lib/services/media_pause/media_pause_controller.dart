/// Pauses running media while a dictation records and resumes it afterwards,
/// but only what WhisPaste itself paused (#563).
///
/// The controller holds the state logic; each platform plugs in a
/// [MediaPauseBackend]. All operations run through one queue, so a stop that
/// arrives while the pause call is still in flight resumes only after the
/// pause has finished, and the start of a recording never waits for it.
library;

import 'dart:async';

import '../../core/logging/app_logger.dart';

final _log = AppLogger('MediaPause');

/// What one pause attempt found.
enum MediaPauseOutcome {
  /// Something was playing and the backend paused it.
  paused,

  /// Nothing was playing (or it was already paused): nothing to resume later.
  nothingPlaying,

  /// The system does not allow it (no API, permission missing, no player bus).
  unavailable,
}

/// Per-platform access to the system media session.
abstract interface class MediaPauseBackend {
  /// Whether this system lets WhisPaste pause media at all.
  Future<bool> isAvailable();

  /// Pauses everything that is playing right now and remembers exactly what it
  /// paused. Never touches players that were already paused.
  Future<MediaPauseOutcome> pauseIfPlaying();

  /// Resumes the players the last [pauseIfPlaying] paused, then forgets them.
  Future<void> resumePaused();
}

/// Backend for a platform without any media control: always "unavailable".
class UnavailableMediaPauseBackend implements MediaPauseBackend {
  const UnavailableMediaPauseBackend();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<MediaPauseOutcome> pauseIfPlaying() async =>
      MediaPauseOutcome.unavailable;

  @override
  Future<void> resumePaused() async {}
}

class MediaPauseController {
  MediaPauseController({required this._backend, required this._isEnabled});

  final MediaPauseBackend _backend;
  final bool Function() _isEnabled;

  Future<void> _tail = Future<void>.value();
  bool _holding = false;

  /// A recording started. Returns at once; the pause runs in the background.
  void recordingStarted() {
    if (!_isEnabled()) return;
    _enqueue(() async {
      if (_holding) return;
      final MediaPauseOutcome outcome;
      try {
        outcome = await _backend.pauseIfPlaying();
      } catch (e) {
        _log.warning('Pausing media failed: $e');
        return;
      }
      if (outcome == MediaPauseOutcome.paused) _holding = true;
    });
  }

  /// The recording ended (stopped, cancelled or failed). Resumes only what the
  /// controller paused; a no-op otherwise, also when the setting was switched
  /// off meanwhile.
  Future<void> recordingEnded() => _enqueue(() async {
    if (!_holding) return;
    _holding = false;
    try {
      await _backend.resumePaused();
    } catch (e) {
      _log.warning('Resuming media failed: $e');
    }
  });

  Future<void> _enqueue(Future<void> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.catchError((Object _) {});
    return run;
  }
}
