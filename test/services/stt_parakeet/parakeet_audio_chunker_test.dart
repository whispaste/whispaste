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
      expect(chunks.single.samples.length, samples.length);
    });

    test('splits a 10-minute recording into chunks within the limit', () {
      // Sentry 150092299: ~624 s of audio in one encoder pass overflowed the
      // relative-position embedding and ORT threw out of the FFI call.
      final samples = _tone(624);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(
          c.samples.length,
          lessThanOrEqualTo(parakeetMaxChunkSeconds * _rate),
        );
      }
      // Every sample is covered; no sample is lost between two chunks.
      final ends = [
        for (final c in chunks) c.samples.offsetInBytes ~/ 4 + c.samples.length,
      ];
      expect(ends.last, samples.length);
    });

    test('cuts at the quietest point near the end of a chunk', () {
      // Speech, a 0.5 s pause at 22 s, then more speech: the cut must land
      // inside the pause instead of hard at the limit (mid-word).
      final samples = _concat([_tone(22), Float32List(_rate ~/ 2), _tone(20)]);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      final firstEnd = chunks.first.samples.length / _rate;
      expect(firstEnd, inInclusiveRange(22.0, 22.5));
    });

    test('a hard cut overlaps the next chunk by 2 s within the limit', () {
      // Loud speech everywhere: no pause, so every cut is a hard cut.
      final samples = _tone(60);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      expect(chunks.length, greaterThan(2));
      final starts = [for (final c in chunks) c.samples.offsetInBytes ~/ 4];
      final ends = [
        for (var i = 0; i < chunks.length; i++)
          starts[i] + chunks[i].samples.length,
      ];
      expect(ends.last, samples.length);
      for (var i = 0; i < chunks.length; i++) {
        expect(
          chunks[i].samples.length,
          lessThanOrEqualTo(parakeetMaxChunkSeconds * _rate),
        );
        if (i == 0) {
          expect(chunks[i].overlapsPrevious, isFalse);
          continue;
        }
        expect(chunks[i].overlapsPrevious, isTrue);
        expect(starts[i], ends[i - 1] - 2 * _rate);
      }
    });

    test('a cut in a pause adds no overlap', () {
      final samples = _concat([_tone(22), Float32List(_rate ~/ 2), _tone(20)]);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      expect(chunks.length, 2);
      expect(chunks[1].overlapsPrevious, isFalse);
      expect(chunks[1].samples.offsetInBytes ~/ 4, chunks.first.samples.length);
    });

    test('never leaves a sliver chunk at the end', () {
      final samples = _tone(parakeetMaxChunkSeconds + 0.2);
      final chunks = splitForParakeet(samples, sampleRate: _rate);
      for (final c in chunks) {
        expect(c.samples.length, greaterThanOrEqualTo(_rate));
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
