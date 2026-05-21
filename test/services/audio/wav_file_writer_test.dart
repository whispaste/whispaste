/// Tests for [WavFileWriter] — the streaming WAV-container writer used by
/// the PCM-stream recording pipeline.
///
/// Verifies that the writer produces a byte-correct RIFF/WAVE container
/// (16 kHz mono 16-bit PCM by default), correctly patches length fields on
/// close, behaves identically for single- and multi-chunk writes, and
/// handles the empty-file edge case.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/wav_file_writer.dart';

/// Reads a little-endian unsigned 32-bit integer from [bytes] at [offset].
int _readU32LE(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// Reads a little-endian unsigned 16-bit integer from [bytes] at [offset].
int _readU16LE(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

/// Reads an ASCII tag of [length] bytes from [bytes] at [offset].
String _readTag(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

void main() {
  group('WavFileWriter — header layout (16 kHz, mono, 16-bit)', () {
    test('empty file emits valid header with data-size = 0', () async {
      final sink = BytesSink();
      final writer = WavFileWriter(
        sink: sink,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );
      await writer.close();

      final bytes = sink.takeBytes();

      // Total length = 44-byte canonical header.
      expect(bytes.length, 44);

      // RIFF chunk.
      expect(_readTag(bytes, 0, 4), 'RIFF');
      // Riff size = file size - 8 bytes.
      expect(_readU32LE(bytes, 4), 36);
      expect(_readTag(bytes, 8, 4), 'WAVE');

      // fmt subchunk.
      expect(_readTag(bytes, 12, 4), 'fmt ');
      expect(_readU32LE(bytes, 16), 16, reason: 'fmt chunk size = 16 for PCM');
      expect(_readU16LE(bytes, 20), 1, reason: 'PCM format tag');
      expect(_readU16LE(bytes, 22), 1, reason: 'channels = 1 (mono)');
      expect(_readU32LE(bytes, 24), 16000, reason: 'sample rate');
      // byteRate = sampleRate * channels * bitsPerSample / 8
      expect(_readU32LE(bytes, 28), 32000, reason: 'byte rate');
      // blockAlign = channels * bitsPerSample / 8
      expect(_readU16LE(bytes, 32), 2, reason: 'block align');
      expect(_readU16LE(bytes, 34), 16, reason: 'bits per sample');

      // data subchunk.
      expect(_readTag(bytes, 36, 4), 'data');
      expect(_readU32LE(bytes, 40), 0, reason: 'data size = 0 for empty');
    });

    test('header reflects sample data length after single write', () async {
      final sink = BytesSink();
      final writer = WavFileWriter(
        sink: sink,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );

      // 4 samples × 2 bytes = 8 bytes of PCM data.
      final pcm = Uint8List.fromList([
        0x10, 0x27, // +10000
        0xF0, 0xD8, // -10000
        0x00, 0x00, //   0
        0xFF, 0x7F, // +32767
      ]);
      await writer.writeChunk(pcm);
      await writer.close();

      final bytes = sink.takeBytes();
      expect(bytes.length, 44 + 8);
      expect(_readU32LE(bytes, 4), 36 + 8, reason: 'riff size patched');
      expect(_readU32LE(bytes, 40), 8, reason: 'data size patched');

      // Payload roundtrip.
      expect(bytes.sublist(44), pcm);
    });
  });

  group('WavFileWriter — chunk identity', () {
    test(
      'multi-chunk write produces same bytes as single-chunk write',
      () async {
        // Build a payload spanning multiple chunks.
        final whole = Uint8List(60);
        for (var i = 0; i < whole.length; i++) {
          whole[i] = i & 0xFF;
        }

        final singleSink = BytesSink();
        final singleWriter = WavFileWriter(
          sink: singleSink,
          sampleRate: 16000,
          channels: 1,
          bitsPerSample: 16,
        );
        await singleWriter.writeChunk(whole);
        await singleWriter.close();

        final multiSink = BytesSink();
        final multiWriter = WavFileWriter(
          sink: multiSink,
          sampleRate: 16000,
          channels: 1,
          bitsPerSample: 16,
        );
        // Split into three chunks of unequal length.
        await multiWriter.writeChunk(Uint8List.sublistView(whole, 0, 8));
        await multiWriter.writeChunk(Uint8List.sublistView(whole, 8, 30));
        await multiWriter.writeChunk(Uint8List.sublistView(whole, 30));
        await multiWriter.close();

        expect(multiSink.takeBytes(), singleSink.takeBytes());
      },
    );
  });
}
