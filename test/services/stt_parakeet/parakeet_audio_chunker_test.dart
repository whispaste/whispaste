import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/pcm_wav_codec.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_audio_chunker.dart';
import 'package:whispaste/services/transcription/transcript_seam.dart';

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
    test('is the shared local budget: 60 s + 3 x audio when unmeasured', () {
      expect(
        parakeetTranscribeTimeout(const Duration(seconds: 5)),
        const Duration(seconds: 75),
      );
    });

    test('follows the measured speed and the overrun boost', () {
      // RTF 0.1 -> factor max(1, 0.3) = 1.
      expect(
        parakeetTranscribeTimeout(
          const Duration(minutes: 10),
          measuredRtf: 0.1,
        ),
        const Duration(minutes: 11),
      );
      expect(
        parakeetTranscribeTimeout(
          const Duration(minutes: 10),
          measuredRtf: 0.1,
          boost: 2,
        ),
        const Duration(minutes: 21),
      );
    });

    test('grows with the audio length for long recordings', () {
      expect(
        parakeetTranscribeTimeout(const Duration(minutes: 10)),
        greaterThan(const Duration(minutes: 10)),
      );
    });
  });

  group('chunked from PCM (#1665, never float32 as a whole)', () {
    /// A canonical WAV around int16 [pcm] (only the header length matters).
    Uint8List wavOf(List<int> pcm) {
      final data = ByteData(pcm16WavHeaderBytes + pcm.length * 2);
      for (var i = 0; i < pcm.length; i++) {
        data.setInt16(pcm16WavHeaderBytes + i * 2, pcm[i], Endian.little);
      }
      return data.buffer.asUint8List();
    }

    List<int> seconds(double s, int Function(int i) sample) => [
      for (var i = 0; i < (s * _rate).round(); i++) sample(i),
    ];

    // Speech, a pause, a long unbroken stretch (hard cuts with overlap) and
    // a short tail: every branch of the cut rule.
    final pcm = [
      ...seconds(22, (i) => (i * 7919 % 16001) - 8000),
      ...seconds(0.6, (i) => i.isEven ? 30 : -30),
      ...seconds(70, (i) => (i * 104729 % 20001) - 10000),
      ...seconds(0.4, (i) => 0),
      ...seconds(12.3, (i) => (i * 31 % 4001) - 2000),
    ];
    final wav = wavOf(pcm);

    /// A stand-in decoder whose text depends on every sample it got.
    String decode(Float32List chunk) {
      var sum = 0.0;
      for (final s in chunk) {
        sum += s.abs();
      }
      return 'n${chunk.length} s${sum.toStringAsFixed(3)}';
    }

    test('the ranges from the WAV file are the cuts of splitForParakeet', () {
      final dir = Directory.systemTemp.createTempSync('wp1665_chunks_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/r.wav')..writeAsBytesSync(wav);
      final view = Pcm16WavView.file(file.path);

      final ranges = parakeetChunkRanges(
        view.sampleCount,
        sampleRate: _rate,
        read: (start, end) => view.toFloat32(start, end),
      );
      final floats = pcm16WavBytesToFloat32(wav);
      final chunks = splitForParakeet(floats, sampleRate: _rate);

      expect(ranges.length, greaterThan(3));
      expect(ranges.any((r) => r.overlapsPrevious), isTrue);
      expect(ranges.skip(1).any((r) => !r.overlapsPrevious), isTrue);
      expect(
        [for (final r in ranges) (r.end - r.start, r.overlapsPrevious)],
        [for (final c in chunks) (c.samples.length, c.overlapsPrevious)],
      );
      expect(ranges.last.end, floats.length);
    });

    test('path in gives the transcript of the whole float decode', () {
      final dir = Directory.systemTemp.createTempSync('wp1665_chunks_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/r.wav')..writeAsBytesSync(wav);

      final fromFile = transcribePcmInParakeetChunks(
        Pcm16WavSource.file(file.path).open(),
        sampleRate: _rate,
        decode: decode,
      );
      final fromBytes = transcribePcmInParakeetChunks(
        Pcm16WavSource.bytes(wav).open(),
        sampleRate: _rate,
        decode: decode,
      );
      // The way the worker decoded before #1665.
      final chunks = splitForParakeet(
        pcm16WavBytesToFloat32(wav),
        sampleRate: _rate,
      );
      final before = joinSeamTexts(
        [for (final c in chunks) decode(c.samples).trim()],
        [for (final c in chunks) c.overlapsPrevious],
      );

      expect(fromFile, before);
      expect(fromBytes, before);
    });

    test('runs the hook before every chunk and decodes nothing empty', () {
      var hooks = 0;
      final decoded = <int>[];
      final text = transcribePcmInParakeetChunks(
        Pcm16WavView(wav),
        sampleRate: _rate,
        beforeChunk: () => hooks++,
        decode: (chunk) {
          decoded.add(chunk.length);
          return 'x';
        },
      );
      expect(text, isNotEmpty);
      expect(hooks, decoded.length);
      expect(decoded.every((n) => n > 0), isTrue);
      expect(
        transcribePcmInParakeetChunks(
          Pcm16WavView(wavOf(const [])),
          sampleRate: _rate,
          decode: (_) => fail('an empty recording is never decoded'),
        ),
        '',
      );
    });

    test('an abort in the hook stops before the next chunk', () {
      var decodes = 0;
      expect(
        () => transcribePcmInParakeetChunks(
          Pcm16WavView(wav),
          sampleRate: _rate,
          beforeChunk: () {
            if (decodes == 1) throw StateError('aborted');
          },
          decode: (_) {
            decodes++;
            return 'x';
          },
        ),
        throwsStateError,
      );
      expect(decodes, 1);
    });
  });
}
