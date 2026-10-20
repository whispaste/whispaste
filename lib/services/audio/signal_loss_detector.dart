/// Notices when a microphone that was delivering signal stops doing so in the
/// middle of a recording (XP-5-08).
///
/// None of the platforms reports this as an error: PipeWire silently moves
/// the stream to another source (often the null sink's monitor, which carries
/// digital zeros), the Windows plugin stops its reader without telling the
/// stream, and macOS simply stops delivering buffers. What they share is that
/// the level turns into exact digital silence or no data at all, which
/// [AmplitudeFromPcm] reports as `-inf` dBFS. A working analogue microphone
/// never does that: even a quiet room leaves a noise floor above zero, so a
/// thinking pause stays finite and does not trip this detector.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Turns the per-tick dBFS values of one recording into "signal lost" and
/// "signal back" transitions.
///
/// Arms only after the first finite value: the start of a recording is the
/// dead-mic guard's job, which already warns and stops there.
class SignalLossDetector {
  SignalLossDetector({
    required this.samplesPerSecond,
    this.lostAfter = const Duration(seconds: 3),
  });

  /// Rate at which [observe] is called (one call per amplitude tick).
  final int samplesPerSecond;

  /// How long the input has to stay dead before it counts as lost. Three
  /// seconds, so a noise gate or a mute button that zeroes the input for a
  /// moment does not raise an alarm while the microphone is fine.
  final Duration lostAfter;

  bool _armed = false;
  bool _lost = false;
  int _deadTicks = 0;

  int get _threshold => (samplesPerSecond * lostAfter.inMilliseconds / 1000)
      .ceil()
      .clamp(1, 1 << 30);

  /// Feeds one dBFS value. Returns `true` when the signal was just lost,
  /// `false` when it just came back, and `null` when nothing changed.
  bool? observe(double dbFs) {
    if (dbFs.isFinite) {
      _armed = true;
      _deadTicks = 0;
      if (!_lost) return null;
      _lost = false;
      return false;
    }
    if (!_armed || _lost) return null;
    _deadTicks++;
    if (_deadTicks < _threshold) return null;
    _lost = true;
    return true;
  }
}

/// Whether the current recording's microphone has stopped delivering signal.
/// Written by the audio service, read by the overlay and the orchestrator.
class MicSignalLostController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool lost) {
    state = lost;
  }
}

final micSignalLostProvider = NotifierProvider<MicSignalLostController, bool>(
  MicSignalLostController.new,
);
