/// Unit tests for the shared PCM/WAV codec used by the on-device engines.
library;

import 'dart:io';
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

  group('Pcm16WavView (#1642)', () {
    final wav = _wav16kMono([0, 16384, -16384, 32767, -32768, 7, -7]);

    test('the whole range equals pcm16WavBytesToFloat32', () {
      final view = Pcm16WavView(wav);
      expect(view.sampleCount, 7);
      expect(view.toFloat32(0, 7), pcm16WavBytesToFloat32(wav));
      expect([
        for (var i = 0; i < 7; i++) view.sampleAt(i),
      ], pcm16WavBytesToFloat32(wav));
    });

    test('a window reuses the buffer and has exactly its length', () {
      final view = Pcm16WavView(wav);
      final buffer = Float32List(5);
      final window = view.toFloat32Into(2, 5, buffer);
      expect(window, pcm16WavBytesToFloat32(wav).sublist(2, 5));
      buffer[0] = 0.25;
      expect(window[0], 0.25, reason: 'the window is the buffer itself');
      expect(
        () => view.toFloat32Into(0, 7, buffer),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => view.toFloat32(3, 8), throwsA(isA<RangeError>()));
    });

    test('counts no trailing odd byte and no header-only input', () {
      expect(Pcm16WavView([...wav, 1]).sampleCount, 7);
      expect(Pcm16WavView(List<int>.filled(44, 0)).sampleCount, 0);
      expect(Pcm16WavView(const [1, 2, 3]).sampleCount, 0);
    });
  });

  group('Pcm16WavView.file (#1665)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wp1665_codec_'));
    tearDown(() => dir.deleteSync(recursive: true));

    final samples = [for (var i = 0; i < 5000; i++) (i * 7919 % 65536) - 32768];
    final wav = _wav16kMono(samples);

    String write(List<int> bytes, [String name = 'r.wav']) {
      final path = '${dir.path}/$name';
      File(path).writeAsBytesSync(bytes);
      return path;
    }

    test('reads the same samples as the view over the bytes', () {
      final file = Pcm16WavView.file(write(wav));
      final memory = Pcm16WavView(wav);
      expect(file.sampleCount, memory.sampleCount);
      expect(file.toFloat32(0, 5000), memory.toFloat32(0, 5000));
      expect(file.toFloat32(1234, 3210), memory.toFloat32(1234, 3210));
      expect(file.sampleAt(4999), memory.sampleAt(4999));
      final buffer = Float32List(100);
      expect(
        file.toFloat32Into(4900, 5000, buffer),
        memory.toFloat32(4900, 5000),
      );
    });

    test('counts no trailing odd byte and no header-only file', () {
      expect(Pcm16WavView.file(write([...wav, 1])).sampleCount, 5000);
      expect(
        Pcm16WavView.file(write(List<int>.filled(44, 0), 'h.wav')).sampleCount,
        0,
      );
    });

    test('a file shortened after opening fails the read', () {
      final path = write(wav);
      final view = Pcm16WavView.file(path);
      File(path).writeAsBytesSync(wav.sublist(0, 44 + 100));
      expect(
        () => view.toFloat32(0, 5000),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('a missing file fails when opened', () {
      expect(
        () => Pcm16WavView.file('${dir.path}/missing.wav'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('holds no handle between reads, so the file can be deleted', () {
      final path = write(wav);
      final view = Pcm16WavView.file(path);
      view.toFloat32(0, 10);
      File(path).deleteSync();
      expect(File(path).existsSync(), isFalse);
    });

    test('wavFileMatches checks existence and sample count only', () {
      final path = write(wav);
      expect(wavFileMatches(path, wav), isTrue);
      expect(wavFileMatches(path, [...wav, 1]), isTrue);
      expect(wavFileMatches(path, wav.sublist(0, wav.length - 2)), isFalse);
      expect(wavFileMatches('${dir.path}/missing.wav', wav), isFalse);
    });

    test('Pcm16WavSource prefers the matching file, else the bytes', () {
      final path = write(wav);
      expect(Pcm16WavSource.preferFile(wav, path).path, path);
      expect(Pcm16WavSource.preferFile(wav, null).bytes, wav);
      final other = write(_wav16kMono([1, 2, 3]), 'o.wav');
      final fallback = Pcm16WavSource.preferFile(wav, other);
      expect(fallback.path, isNull);
      expect(fallback.open().toFloat32(0, 5000), pcm16WavBytesToFloat32(wav));
      expect(
        Pcm16WavSource.file(path).open().toFloat32(0, 5000),
        pcm16WavBytesToFloat32(wav),
      );
    });
  });
}
