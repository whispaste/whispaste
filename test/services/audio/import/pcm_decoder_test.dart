/// Unit tests for the pure-Dart WAV decoder used by the file import queue.
///
/// All fixtures are generated in code (sine tones written with the layouts
/// the decoder must read), so no binary test assets are needed.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

/// Builds a RIFF/WAVE file. [dataSizeOverride] simulates an unfinished
/// recording whose data size field was never patched.
Uint8List _wav({
  required int formatTag,
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required Uint8List data,
  bool extensible = false,
  int? dataSizeOverride,
}) {
  final fmtSize = extensible ? 40 : 16;
  final total = 12 + 8 + fmtSize + 8 + data.length;
  final out = ByteData(total);
  final bytes = out.buffer.asUint8List();
  void tag(int at, String t) {
    for (var i = 0; i < 4; i++) {
      bytes[at + i] = t.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, total - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, fmtSize, Endian.little);
  final blockAlign = channels * bitsPerSample ~/ 8;
  out.setUint16(20, extensible ? 0xFFFE : formatTag, Endian.little);
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * blockAlign, Endian.little);
  out.setUint16(32, blockAlign, Endian.little);
  out.setUint16(34, bitsPerSample, Endian.little);
  if (extensible) {
    out.setUint16(36, 22, Endian.little); // cbSize
    out.setUint16(38, bitsPerSample, Endian.little); // valid bits
    out.setUint32(40, 4, Endian.little); // channel mask (unused here)
    out.setUint16(44, formatTag, Endian.little); // sub-format GUID head
  }
  final dataAt = 12 + 8 + fmtSize;
  tag(dataAt, 'data');
  out.setUint32(dataAt + 4, dataSizeOverride ?? data.length, Endian.little);
  bytes.setRange(dataAt + 8, dataAt + 8 + data.length, data);
  return bytes;
}

/// Interleaved 16-bit samples of a sine at [freq], [channels] copies.
Uint8List _sine16(
  double freq,
  int sampleRate,
  double seconds, {
  int channels = 1,
  double amp = 0.5,
}) {
  final frames = (sampleRate * seconds).round();
  final data = ByteData(frames * channels * 2);
  for (var f = 0; f < frames; f++) {
    final v = (math.sin(2 * math.pi * freq * f / sampleRate) * amp * 32767)
        .round();
    for (var c = 0; c < channels; c++) {
      data.setInt16((f * channels + c) * 2, v, Endian.little);
    }
  }
  return data.buffer.asUint8List();
}

double _rms(Float32List s) {
  var acc = 0.0;
  for (final v in s) {
    acc += v * v;
  }
  return math.sqrt(acc / s.length);
}

void main() {
  group('decodeWavBytes', () {
    test('reads 16-bit mono PCM at native rate', () {
      final wav = _wav(
        formatTag: 1,
        channels: 1,
        sampleRate: 16000,
        bitsPerSample: 16,
        data: _sine16(440, 16000, 0.5),
      );
      final decoded = decodeWavBytes(wav);
      expect(decoded.sampleRate, 16000);
      expect(decoded.samples.length, 8000);
      expect(decoded.samples[0], closeTo(0, 1e-4));
      expect(_rms(decoded.samples), closeTo(0.5 / math.sqrt2, 0.01));
    });

    test('downmixes stereo to mono by averaging channels', () {
      final data = ByteData(4 * 2)
        ..setInt16(0, 16384, Endian.little)
        ..setInt16(2, -16384, Endian.little)
        ..setInt16(4, 32767, Endian.little)
        ..setInt16(6, 32767, Endian.little);
      final wav = _wav(
        formatTag: 1,
        channels: 2,
        sampleRate: 16000,
        bitsPerSample: 16,
        data: data.buffer.asUint8List(),
      );
      final decoded = decodeWavBytes(wav);
      expect(decoded.samples.length, 2);
      expect(decoded.samples[0], closeTo(0, 1e-4));
      expect(decoded.samples[1], closeTo(1, 1e-4));
    });

    test('reads 24-bit and 8-bit integer PCM', () {
      final d24 = Uint8List(3)..setRange(0, 3, [0x00, 0x00, 0x40]); // 0x400000
      final w24 = _wav(
        formatTag: 1,
        channels: 1,
        sampleRate: 8000,
        bitsPerSample: 24,
        data: d24,
      );
      expect(decodeWavBytes(w24).samples[0], closeTo(0.5, 1e-6));

      final w8 = _wav(
        formatTag: 1,
        channels: 1,
        sampleRate: 8000,
        bitsPerSample: 8,
        data: Uint8List.fromList([255, 0, 128]),
      );
      final s8 = decodeWavBytes(w8).samples;
      expect(s8[0], closeTo(127 / 128, 1e-6));
      expect(s8[1], -1.0);
      expect(s8[2], 0.0);
    });

    test('reads 32-bit float PCM', () {
      final data = ByteData(8)
        ..setFloat32(0, 0.25, Endian.little)
        ..setFloat32(4, -0.75, Endian.little);
      final wav = _wav(
        formatTag: 3,
        channels: 1,
        sampleRate: 48000,
        bitsPerSample: 32,
        data: data.buffer.asUint8List(),
      );
      final s = decodeWavBytes(wav).samples;
      expect(s[0], closeTo(0.25, 1e-6));
      expect(s[1], closeTo(-0.75, 1e-6));
    });

    test('accepts WAVE_FORMAT_EXTENSIBLE with PCM sub-format', () {
      final wav = _wav(
        formatTag: 1,
        channels: 1,
        sampleRate: 16000,
        bitsPerSample: 16,
        data: _sine16(440, 16000, 0.1),
        extensible: true,
      );
      expect(decodeWavBytes(wav).samples.length, 1600);
    });

    test('clamps a zero data size (unfinished recording) to the file end', () {
      final wav = _wav(
        formatTag: 1,
        channels: 1,
        sampleRate: 16000,
        bitsPerSample: 16,
        data: _sine16(440, 16000, 0.25),
        dataSizeOverride: 0,
      );
      expect(decodeWavBytes(wav).samples.length, 4000);
    });

    test('rejects non-RIFF input with AudioDecodeException', () {
      expect(
        () => decodeWavBytes(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('rejects an unsupported format tag', () {
      final wav = _wav(
        formatTag: 6, // A-law
        channels: 1,
        sampleRate: 8000,
        bitsPerSample: 8,
        data: Uint8List(4),
      );
      expect(() => decodeWavBytes(wav), throwsA(isA<AudioDecodeException>()));
    });
  });

  group('resampleLinearSinc', () {
    test('returns the input unchanged for equal rates', () {
      final input = Float32List.fromList([0.1, 0.2, 0.3]);
      expect(identical(resampleLinearSinc(input, 16000, 16000), input), isTrue);
    });

    test('produces the expected length when downsampling 48 kHz to 16 kHz', () {
      final input = Float32List(48000);
      expect(resampleLinearSinc(input, 48000, 16000).length, 16000);
    });

    test('keeps a 440 Hz tone at its amplitude when downsampling', () {
      final input = decodeWavBytes(
        _wav(
          formatTag: 1,
          channels: 1,
          sampleRate: 48000,
          bitsPerSample: 16,
          data: _sine16(440, 48000, 1.0),
        ),
      ).samples;
      final out = resampleLinearSinc(input, 48000, 16000);
      // Skip the filter edges, where the kernel is truncated.
      final body = Float32List.sublistView(out, 200, out.length - 200);
      expect(_rms(body), closeTo(0.5 / math.sqrt2, 0.02));
    });

    test('attenuates a 12 kHz tone that would alias into the 16 kHz band', () {
      final input = decodeWavBytes(
        _wav(
          formatTag: 1,
          channels: 1,
          sampleRate: 48000,
          bitsPerSample: 16,
          data: _sine16(12000, 48000, 1.0),
        ),
      ).samples;
      final out = resampleLinearSinc(input, 48000, 16000);
      final body = Float32List.sublistView(out, 200, out.length - 200);
      expect(_rms(body), lessThan(0.05));
    });
  });

  group('floatToPcm16 / encodePcm16MonoWav', () {
    test('clips to the int16 range and round-trips through the WAV reader', () {
      final pcm = floatToPcm16(Float32List.fromList([0.5, -1.5, 1.5, -1]));
      expect(pcm, [16384, -32768, 32767, -32767]);
      final wav = encodePcm16MonoWav(pcm);
      expect(wav.length, 44 + 8);
      final back = decodeWavBytes(wav);
      expect(back.sampleRate, 16000);
      expect(back.samples.length, 4);
      expect(back.samples[0], closeTo(0.5, 1e-4));
    });
  });
}
