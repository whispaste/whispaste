/// Unit tests for the shared PCM/WAV codec used by the on-device engines.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/pcm_wav_codec.dart';

/// Builds WhisPaste's canonical 44-byte-header, 16 kHz mono, 16-bit PCM WAV
/// around [samples] so tests exercise the exact shape `wav_file_writer.dart`
/// produces.
Uint8List _wav16kMono(List<int> samples) {
  const sampleRate = 16000;
  const bitsPerSample = 16;
  const channels = 1;
  final dataBytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    dataBytes.setInt16(i * 2, samples[i], Endian.little);
  }
  final data = dataBytes.buffer.asUint8List();

  final header = ByteData(44);
  header.setUint8(0, 0x52); // R
  header.setUint8(1, 0x49); // I
  header.setUint8(2, 0x46); // F
  header.setUint8(3, 0x46); // F
  header.setUint32(4, 36 + data.length, Endian.little);
  header.setUint8(8, 0x57); // W
  header.setUint8(9, 0x41); // A
  header.setUint8(10, 0x56); // V
  header.setUint8(11, 0x45); // E
  header.setUint8(12, 0x66); // f
  header.setUint8(13, 0x6D); // m
  header.setUint8(14, 0x74); // t
  header.setUint8(15, 0x20); // (space)
  header.setUint32(16, 16, Endian.little); // fmt chunk size
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(
    28,
    sampleRate * channels * bitsPerSample ~/ 8,
    Endian.little,
  );
  header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  header.setUint8(36, 0x64); // d
  header.setUint8(37, 0x61); // a
  header.setUint8(38, 0x74); // t
  header.setUint8(39, 0x61); // a
  header.setUint32(40, data.length, Endian.little);

  return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
}

void main() {
  group('pcm16WavBytesToFloat32', () {
    test('decodes known 16 kHz mono int16 samples to normalized floats', () {
      final wav = _wav16kMono([0, 16384, -16384, 32767, -32768]);

      final samples = pcm16WavBytesToFloat32(wav);

      expect(samples, hasLength(5));
      expect(samples[0], closeTo(0.0, 1e-9));
      expect(samples[1], closeTo(0.5, 1e-6));
      expect(samples[2], closeTo(-0.5, 1e-6));
      expect(samples[3], closeTo(0.99997, 1e-4));
      expect(samples[4], closeTo(-1.0, 1e-9));
    });

    test('produces one float sample per 16-bit frame', () {
      final wav = _wav16kMono(List<int>.filled(320, 100));

      final samples = pcm16WavBytesToFloat32(wav);

      expect(samples, hasLength(320));
    });

    test('returns empty for header-only / too-short input', () {
      expect(pcm16WavBytesToFloat32(List<int>.filled(44, 0)), isEmpty);
      expect(pcm16WavBytesToFloat32(const [1, 2, 3]), isEmpty);
    });
  });
}
