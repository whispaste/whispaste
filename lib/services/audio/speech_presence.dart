/// The one definition of "speech" on the recording path.
///
/// Speech is a meter level ([SpeechLevelMapper] over the peak dBFS of one
/// 40 ms window) at or above [speechLevelThreshold] (about -49 dBFS peak),
/// held for at least [speechMinDuration] with dips no longer than
/// [speechMaxGap]. The safety guard (dead mic, silence auto-stop) and the
/// live preview's skip of silent ticks both read it, so a quiet microphone
/// that the guard accepts also gets a preview.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'speech_level_mapper.dart';

/// Meter level below which a window counts as silent: about -49 dBFS peak.
/// Room tone (about -50 dBFS) stays below it.
const double speechLevelThreshold = 0.097;

/// How long the level must stay at or above [speechLevelThreshold] to count
/// as speech. A click or a noise spike is loud for a window or two only.
const Duration speechMinDuration = Duration(milliseconds: 300);

/// Longest silent dip that does not restart the [speechMinDuration] count.
/// Speech dips briefly between syllables; noise spikes are further apart.
const Duration speechMaxGap = Duration(milliseconds: 80);

/// Counts loud windows towards [speechMinDuration], forgiving dips up to
/// [speechMaxGap]. Both limits are in windows of the caller's meter rate.
class SpeechRun {
  SpeechRun({required this.minWindows, required this.maxGapWindows});

  final int minWindows;
  final int maxGapWindows;
  int _loud = 0;
  int _gap = 0;

  /// Returns true once the run is long enough to count as speech, and on
  /// every further loud window of the same run.
  bool addLoud() {
    _gap = 0;
    return ++_loud >= minWindows;
  }

  void addSilent() {
    if (++_gap > maxGapWindows) _loud = 0;
  }

  void reset() {
    _loud = 0;
    _gap = 0;
  }
}

/// Applies the definition to raw 16-bit mono little-endian PCM that arrives
/// in chunks of any size: a window may span two chunks.
class Pcm16SpeechDetector {
  Pcm16SpeechDetector({int sampleRate = 16000})
    : _windowSamples = sampleRate * _windowMs ~/ 1000,
      _run = SpeechRun(
        minWindows: (speechMinDuration.inMilliseconds / _windowMs).ceil(),
        maxGapWindows: (speechMaxGap.inMilliseconds / _windowMs).ceil(),
      );

  /// Same window as the level meter (`AmplitudeFromPcm`, 40 ms).
  static const _windowMs = 40;
  static const _mapper = SpeechLevelMapper();

  final int _windowSamples;
  final SpeechRun _run;
  int _peak = 0;
  int _filled = 0;

  /// Feeds [pcm]; true when a window completed in it belongs to speech.
  bool add(Uint8List pcm) {
    final view = ByteData.sublistView(pcm, 0, pcm.length ~/ 2 * 2);
    var speech = false;
    for (var i = 0; i < view.lengthInBytes; i += 2) {
      final v = view.getInt16(i, Endian.little).abs();
      if (v > _peak) _peak = v;
      if (++_filled < _windowSamples) continue;
      if (_levelOf(_peak) >= speechLevelThreshold) {
        if (_run.addLoud()) speech = true;
      } else {
        _run.addSilent();
      }
      _peak = 0;
      _filled = 0;
    }
    return speech;
  }

  void reset() {
    _run.reset();
    _peak = 0;
    _filled = 0;
  }

  static double _levelOf(int peak) =>
      peak <= 0 ? 0.0 : _mapper.map(20 * math.log(peak / 32768) / math.ln10);
}
