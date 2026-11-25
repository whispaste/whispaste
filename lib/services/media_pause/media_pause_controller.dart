/// Pauses or turns down running media while a dictation records and restores
/// it afterwards, but only what WhisPaste itself changed (#563, #1511).
///
/// The controller holds the state logic; each platform plugs in a
/// [MediaPauseBackend] (pause/resume) and a [MediaDuckBackend] (volume). All
/// operations run through one queue, so a stop that arrives while the pause
/// or duck call is still in flight restores only after that call has
/// finished, and the start of a recording never waits for it.
///
/// Ducking writes the previous volumes to a [DuckJournal] before it lowers
/// anything, so the next app start puts them back when the app crashed or was
/// killed during a dictation ([MediaPauseController.restoreAfterCrash]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/settings_sections.dart' show MediaWhileRecording;
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

  /// The host did not answer in time. It may still pause something after
  /// the caller gave up, so the recording's end asks it to resume anyway;
  /// the host resumes only what it paused itself.
  noAnswer,
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

/// One volume WhisPaste can turn down: an output device (macOS), an audio
/// session (Windows) or a playback stream (Linux). [id] is opaque to
/// everything but its backend; [levels] are linear volumes `0..1`, one per
/// channel where the system keeps them per channel.
class DuckTarget {
  const DuckTarget(this.id, this.levels);

  final String id;
  final List<double> levels;

  DuckTarget scaled(double factor) =>
      DuckTarget(id, [for (final l in levels) l * factor]);

  Map<String, Object> toJson() => {'id': id, 'levels': levels};

  static DuckTarget? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final levels = json['levels'];
    if (id is! String || levels is! List) return null;
    final parsed = <double>[
      for (final l in levels)
        if (l is num) l.toDouble(),
    ];
    if (parsed.isEmpty || parsed.length != levels.length) return null;
    return DuckTarget(id, parsed);
  }

  @override
  bool operator ==(Object other) =>
      other is DuckTarget &&
      other.id == id &&
      other.levels.length == levels.length &&
      Iterable<int>.generate(
        levels.length,
      ).every((i) => other.levels[i] == levels[i]);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(levels));

  @override
  String toString() => 'DuckTarget($id, $levels)';
}

/// Per-platform access to the volume of what is playing.
abstract interface class MediaDuckBackend {
  /// Whether this system lets WhisPaste turn playback down at all.
  Future<bool> isAvailable();

  /// The volumes of everything that is audible right now, never WhisPaste's
  /// own sounds. Empty when nothing plays: then nothing is touched.
  Future<List<DuckTarget>> playingTargets();

  /// Sets each target to its [DuckTarget.levels]. A target that no longer
  /// exists (the player quit) is skipped.
  Future<void> setLevels(List<DuckTarget> targets);
}

class UnavailableMediaDuckBackend implements MediaDuckBackend {
  const UnavailableMediaDuckBackend();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<DuckTarget>> playingTargets() async => const [];

  @override
  Future<void> setLevels(List<DuckTarget> targets) async {}
}

/// Where the volumes before a duck survive a crash.
abstract interface class DuckJournal {
  Future<void> save(List<DuckTarget> original);

  /// The saved volumes, empty when there are none (or the file is damaged).
  Future<List<DuckTarget>> load();

  Future<void> clear();
}

class MemoryDuckJournal implements DuckJournal {
  List<DuckTarget> saved = const [];

  @override
  Future<void> save(List<DuckTarget> original) async => saved = original;

  @override
  Future<List<DuckTarget>> load() async => saved;

  @override
  Future<void> clear() async => saved = const [];
}

/// JSON file in the app data folder (`media_duck_journal.json`).
class FileDuckJournal implements DuckJournal {
  FileDuckJournal(this.path);

  final String path;

  @override
  Future<void> save(List<DuckTarget> original) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      jsonEncode([for (final t in original) t.toJson()]),
      flush: true,
    );
    await tmp.rename(path);
  }

  @override
  Future<List<DuckTarget>> load() async {
    try {
      final file = File(path);
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return [for (final e in decoded) ?DuckTarget.fromJson(e)];
    } catch (e) {
      _log.warning('Reading the duck journal failed: $e');
      return const [];
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      _log.warning('Clearing the duck journal failed: $e');
    }
  }
}

/// Share of the previous volume that stays while ducked (about −12 dB):
/// clearly quieter, still audible, so nobody wonders whether playback broke.
const duckFactor = 0.25;

class MediaPauseController {
  MediaPauseController({
    required this._backend,
    required this._mode,
    MediaDuckBackend duckBackend = const UnavailableMediaDuckBackend(),
    DuckJournal? journal,
  }) : _duck = duckBackend,
       _journal = journal ?? MemoryDuckJournal();

  final MediaPauseBackend _backend;
  final MediaDuckBackend _duck;
  final DuckJournal _journal;
  final MediaWhileRecording Function() _mode;

  Future<void> _tail = Future<void>.value();
  bool _holdingPause = false;
  List<DuckTarget> _ducked = const [];

  bool get _holding => _holdingPause || _ducked.isNotEmpty;

  /// A recording started. Returns at once; the pause or duck runs in the
  /// background.
  void recordingStarted() {
    final mode = _mode();
    if (mode == MediaWhileRecording.off) return;
    _enqueue(() async {
      if (_holding) return;
      switch (mode) {
        case MediaWhileRecording.off:
          return;
        case MediaWhileRecording.pause:
          await _pause();
        case MediaWhileRecording.duck:
          await _duckDown();
      }
    });
  }

  Future<void> _pause() async {
    final MediaPauseOutcome outcome;
    try {
      outcome = await _backend.pauseIfPlaying();
    } catch (e) {
      _log.warning('Pausing media failed: $e');
      return;
    }
    if (outcome == MediaPauseOutcome.noAnswer) {
      _log.warning('Pausing media did not answer in time');
    }
    if (outcome == MediaPauseOutcome.paused ||
        outcome == MediaPauseOutcome.noAnswer) {
      _holdingPause = true;
    }
  }

  Future<void> _duckDown() async {
    final List<DuckTarget> playing;
    try {
      playing = await _duck.playingTargets();
    } catch (e) {
      _log.warning('Reading playback volumes failed: $e');
      return;
    }
    if (playing.isEmpty) return;
    try {
      // Journal first: a crash after this line still finds the old volumes.
      await _journal.save(playing);
    } catch (e) {
      // Without a journal a crash could leave playback quiet for good, so
      // nothing is lowered.
      _log.warning('Saving the duck journal failed, not ducking: $e');
      return;
    }
    _ducked = playing;
    try {
      await _duck.setLevels([for (final t in playing) t.scaled(duckFactor)]);
    } catch (e) {
      _log.warning('Ducking failed: $e');
    }
  }

  /// The recording ended (stopped, cancelled or failed). Restores only what
  /// the controller changed; a no-op otherwise, also when the setting was
  /// switched meanwhile.
  Future<void> recordingEnded() => _enqueue(() async {
    if (_holdingPause) {
      _holdingPause = false;
      try {
        await _backend.resumePaused();
      } catch (e) {
        _log.warning('Resuming media failed: $e');
      }
    }
    if (_ducked.isNotEmpty) {
      final original = _ducked;
      _ducked = const [];
      await _restore(original);
    }
  });

  /// App start: puts back volumes a crashed or killed dictation left lowered.
  Future<void> restoreAfterCrash() => _enqueue(() async {
    if (_ducked.isNotEmpty) return;
    final left = await _journal.load();
    if (left.isEmpty) return;
    _log.info('Restoring ${left.length} volume(s) left ducked by a crash');
    await _restore(left);
  });

  Future<void> _restore(List<DuckTarget> original) async {
    try {
      await _duck.setLevels(original);
    } catch (e) {
      // Keep the journal: the next app start tries again.
      _log.warning('Restoring volumes failed: $e');
      return;
    }
    await _journal.clear();
  }

  Future<void> _enqueue(Future<void> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.catchError((Object _) {});
    return run;
  }
}
