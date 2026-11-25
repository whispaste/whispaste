/// The one app-wide player for retained recordings (#170): any screen that
/// offers "Listen" toggles it here, so at most one recording plays at a time.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sound_feedback_service.dart';
import '../encryption/recording_vault.dart';

/// Plays one audio file at a time. The seam the playback logic is tested
/// through; the app plays through the shared SoLoud engine.
abstract interface class RecordingPlayer {
  /// Starts [path] at [from], stopping whatever played before. False when it
  /// could not start; otherwise [onEnd] runs once when playback ends.
  Future<bool> play(
    String path, {
    required void Function() onEnd,
    Duration from = Duration.zero,
  });

  /// Moves the current playback to [to]. False when nothing plays.
  bool seek(Duration to);

  /// Where the current playback is, or null when nothing plays.
  Duration? get position;

  /// Stops the current playback, if any.
  void stop();
}

final class _SoLoudRecordingPlayer implements RecordingPlayer {
  _SoLoudRecordingPlayer(this._sounds, this._vault);

  final SoundFeedbackService _sounds;
  final RecordingVault _vault;

  /// Reads through the vault, so encrypted recordings (#1021) play too.
  @override
  Future<bool> play(
    String path, {
    required void Function() onEnd,
    Duration from = Duration.zero,
  }) => _sounds.playFile(path, onEnd: onEnd, read: _vault.read, from: from);

  @override
  bool seek(Duration to) => _sounds.seekFile(to);

  @override
  Duration? get position => _sounds.filePosition;

  @override
  void stop() => _sounds.stopFile();
}

final recordingPlayerProvider = Provider<RecordingPlayer>(
  (ref) => _SoLoudRecordingPlayer(
    ref.read(soundFeedbackProvider.notifier),
    ref.read(recordingVaultProvider),
  ),
);

/// The key (a history entry id) of the recording playing now, or null.
/// Not auto-disposed: leaving a screen does not cut the playback.
class RecordingPlaybackNotifier extends Notifier<String?> {
  /// Bumped by every start and stop, so the end of an older playback never
  /// clears the state of a newer one.
  int _generation = 0;

  RecordingPlayer get _player => ref.read(recordingPlayerProvider);

  @override
  String? build() => null;

  /// Plays [path] for [key], or stops it when [key] is the one playing.
  Future<void> toggle(String key, String path) async {
    if (state == key) {
      stop();
      return;
    }
    await _start(key, path, Duration.zero);
  }

  /// Plays [path] for [key] from [from] (#672: a sentence of the transcript).
  /// When [key] already plays, it jumps there instead of loading again.
  Future<void> playFrom(String key, String path, Duration from) async {
    if (state == key && _player.seek(from)) return;
    await _start(key, path, from);
  }

  /// Where the recording of [key] is now; null unless [key] plays.
  Duration? positionOf(String key) => state == key ? _player.position : null;

  Future<void> _start(String key, String path, Duration from) async {
    final generation = ++_generation;
    state = key;
    final started = await _player.play(
      path,
      from: from,
      onEnd: () {
        if (generation == _generation) state = null;
      },
    );
    if (!started && generation == _generation) state = null;
  }

  /// Stops the playback, if any.
  void stop() {
    _generation++;
    _player.stop();
    state = null;
  }
}

final recordingPlaybackProvider =
    NotifierProvider<RecordingPlaybackNotifier, String?>(
      RecordingPlaybackNotifier.new,
    );
