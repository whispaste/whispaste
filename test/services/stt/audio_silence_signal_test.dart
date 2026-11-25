import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/audio_silence_signal.dart';
import 'package:whispaste/services/stt/transcript_hallucination_filter.dart';

/// A 16 kHz mono WAV of [parts]: (milliseconds, peak amplitude 0–1) of a
/// 200 Hz tone; amplitude 0 is digital silence.
Uint8List _wav(List<(int, double)> parts) {
  final samples = <int>[];
  for (final (ms, amp) in parts) {
    final n = ms * 16;
    for (var i = 0; i < n; i++) {
      samples.add(
        (math.sin(2 * math.pi * 200 * i / 16000) * amp * 32767).round(),
      );
    }
  }
  final bytes = ByteData(44 + samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test('speech followed by silence reports the silent tail', () {
    final s = audioSilenceSignalOfWav(_wav([(1000, 0.3), (2000, 0)]));
    expect(s.silentAudio, isFalse);
    expect(s.trailingSilenceMs, 2000);
    expect(s.fillerNotSpoken, isTrue);
    // A silent tail alone is no evidence for stock phrases.
    expect(s.tailNotSpoken, isFalse);
  });

  test('speech up to the end reports no silent tail', () {
    final s = audioSilenceSignalOfWav(_wav([(500, 0), (1500, 0.3)]));
    expect(s.silentAudio, isFalse);
    expect(s.trailingSilenceMs, 0);
    expect(s.fillerNotSpoken, isFalse);
  });

  test('a recording without any voice level is strong evidence', () {
    final s = audioSilenceSignalOfWav(_wav([(3000, 0.001)]));
    expect(s.silentAudio, isTrue);
    expect(s.trailingSilenceMs, 3000);
    expect(s.strong, isTrue);
  });

  test('quiet speech below the pause level is still voice', () {
    // About -40 dBFS peak: below the pause RMS, above the voice peak.
    final s = audioSilenceSignalOfWav(_wav([(2000, 0.01)]));
    expect(s.silentAudio, isFalse);
    expect(s.strong, isFalse);
  });

  test('an empty or unreadable recording carries no evidence', () {
    expect(audioSilenceSignalOfWav(Uint8List(44)).strong, isFalse);
    expect(audioSilenceSignalOfWav(const []).fillerNotSpoken, isFalse);
  });

  test('a silent end of a dictation drops a filler there (#2013)', () {
    final signal = audioSilenceSignalOfWav(_wav([(1500, 0.3), (1500, 0)]));
    expect(
      dropInventedText('Wir sehen uns morgen. Ähm.', signal),
      'Wir sehen uns morgen.',
    );
    expect(
      dropInventedText('Wir sehen uns morgen. Vielen Dank.', signal),
      'Wir sehen uns morgen. Vielen Dank.',
    );
  });
}
