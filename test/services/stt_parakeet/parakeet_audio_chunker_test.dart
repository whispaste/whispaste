import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_audio_chunker.dart';

const _rate = 16000;

Float32List _tone(double seconds, {double amplitude = 0.5}) {
  final n = (seconds * _rate).round();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = (i.isEven ? amplitude : -amplitude);
  }
  return out;
}

Float32List _concat(List<Float32List> parts) {
  final total = parts.fold<int>(0, (s, p) => s + p.length);
  final out = Float32List(total);
  var o = 0;
  for (final p in parts) {
    out.setAll(o, p);
    o += p.length;
  }
  return out;
}

void main() {
  group('splitForParakeet', () {
    test('keeps audio up to the chunk limit as a single chunk', () {
      final samples = _tone(parakeetMaxChunkSeconds.toDouble());
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      expect(chunks, hasLength(1));
      expect(chunks.single.length, samples.length);
    });

    test('splits a 10-minute recording into chunks within the limit', () {
      // Sentry 150092299: ~624 s of audio in one encoder pass overflowed the
      // relative-position embedding and ORT threw out of the FFI call.
      final samples = _tone(624);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(parakeetMaxChunkSeconds * _rate));
      }
      expect(
        chunks.fold<int>(0, (s, c) => s + c.length),
        samples.length,
        reason: 'no audio may be dropped or duplicated',
      );
    });

    test('cuts at the quietest point near the end of a chunk', () {
      // Speech, a 0.5 s pause at 22 s, then more speech: the cut must land
      // inside the pause instead of hard at the limit (mid-word).
      final samples = _concat([_tone(22), Float32List(_rate ~/ 2), _tone(20)]);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      final firstEnd = chunks.first.length / _rate;
      expect(firstEnd, inInclusiveRange(22.0, 22.5));
    });

    test('never leaves a sliver chunk at the end', () {
      final samples = _tone(parakeetMaxChunkSeconds + 0.2);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      for (final c in chunks) {
        expect(c.length, greaterThanOrEqualTo(_rate));
      }
    });
  });

  group('parakeetTranscribeTimeout', () {
    test('keeps the 30 s floor for short dictations', () {
      expect(
        parakeetTranscribeTimeout(const Duration(seconds: 5)),
        const Duration(seconds: 30),
      );
    });

    test('grows with the audio length for long recordings', () {
      expect(
        parakeetTranscribeTimeout(const Duration(minutes: 10)),
        greaterThan(const Duration(minutes: 10)),
      );
    });
  });
}
