import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/pcm16_pause_finder.dart';

const _rate = 16000;

/// Builds 16 kHz mono PCM from `[seconds, amplitude]` segments. Amplitude 0 is
/// digital silence; a square wave of amplitude `a` has RMS `a / 32768`.
ByteData _pcm(List<(double, int)> segments) {
  final samples = <int>[];
  for (final (seconds, amplitude) in segments) {
    final count = (seconds * _rate).round();
    for (var i = 0; i < count; i++) {
      samples.add(
        amplitude == 0
            ? 0
            : (i ~/ 8).isEven
            ? amplitude
            : -amplitude,
      );
    }
  }
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data;
}

const _loud = 8000; // RMS about 0.24, well above the 0.015 threshold.
const _quiet = 200; // RMS about 0.0043, below the threshold.

void main() {
  group('findLatestPauseMidByte', () {
    test('cuts in the middle of a one-second pause', () {
      final pcm = _pcm([(1, _loud), (1, 0), (1, _loud)]);
      final cut = findLatestPauseMidByte(pcm, 0, pcm.lengthInBytes);
      // The pause spans 1.0 s to 2.0 s; its middle is 1.5 s = 24000 samples.
      expect(cut, 24000 * 2);
    });

    test('treats quiet-but-not-silent audio as a pause', () {
      final pcm = _pcm([(1, _loud), (1, _quiet), (1, _loud)]);
      expect(findLatestPauseMidByte(pcm, 0, pcm.lengthInBytes), isNotNull);
    });

    test('ignores a pause shorter than 700 ms', () {
      final pcm = _pcm([(1, _loud), (0.6, 0), (1, _loud)]);
      expect(findLatestPauseMidByte(pcm, 0, pcm.lengthInBytes), isNull);
    });

    test('returns no cut for loud speech', () {
      final pcm = _pcm([(3, _loud)]);
      expect(findLatestPauseMidByte(pcm, 0, pcm.lengthInBytes), isNull);
    });

    test('prefers the latest pause in the range', () {
      final pcm = _pcm([
        (1, _loud),
        (1, 0), // pause 1.0 s to 2.0 s
        (2, _loud),
        (1, 0), // pause 4.0 s to 5.0 s
        (1, _loud),
      ]);
      final cut = findLatestPauseMidByte(pcm, 0, pcm.lengthInBytes);
      // Second pause 4.0 s to 5.0 s, middle at 4.5 s = 72000 samples.
      expect(cut, 72000 * 2);
    });

    test('counts only pauses lying wholly inside the range', () {
      final pcm = _pcm([(1, _loud), (1, 0), (1, _loud)]);
      // The range ends 0.5 s into the pause, which is then too short.
      expect(findLatestPauseMidByte(pcm, 0, 24000 * 2), isNull);
    });

    test('works on a range that does not start at zero', () {
      final pcm = _pcm([(2, _loud), (1, 0), (1, _loud)]);
      final cut = findLatestPauseMidByte(pcm, 16000 * 2, pcm.lengthInBytes);
      // Pause 2.0 s to 3.0 s, middle at 2.5 s.
      expect(cut, 40000 * 2);
    });

    test('returns null for an empty range', () {
      final pcm = _pcm([(1, 0)]);
      expect(findLatestPauseMidByte(pcm, 0, 0), isNull);
    });

    test('never returns an odd byte offset', () {
      final pcm = _pcm([(1, _loud), (1.3, 0), (1, _loud)]);
      final cut = findLatestPauseMidByte(pcm, 0, pcm.lengthInBytes);
      expect(cut, isNotNull);
      expect(cut!.isEven, isTrue);
    });
  });
}
