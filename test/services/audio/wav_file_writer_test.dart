/// Tests for [WavFileWriter] — the streaming WAV-container writer used by
/// the PCM-stream recording pipeline.
///
/// Verifies that the writer produces a byte-correct RIFF/WAVE container
/// (16 kHz mono 16-bit PCM by default), correctly patches length fields on
/// close, behaves identically for single- and multi-chunk writes, and
/// handles the empty-file edge case.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/wav_file_writer.dart';

/// Mimics [RandomAccessFile]'s concurrency semantics: starting a second
/// async operation while one is still pending throws a
/// [FileSystemException] ("An async operation is currently pending").
/// Lets the tests prove the writer serialises its sink operations the way
/// the production [FilePcmSink] requires.
class _RafLikeSink implements PcmSink {
  final BytesSink _inner = BytesSink();
  bool _busy = false;
  int overlapAttempts = 0;

  Future<T> _guard<T>(Future<T> Function() op) async {
    if (_busy) {
      overlapAttempts++;
      throw const FileSystemException(
        'An async operation is currently pending',
      );
    }
    _busy = true;
    try {
      // Force a real async gap so overlapping callers are actually caught.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      return await op();
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> add(List<int> bytes) => _guard(() => _inner.add(bytes));

  @override
  Future<void> overwrite(int offset, List<int> bytes) =>
      _guard(() => _inner.overwrite(offset, bytes));

  @override
  Future<void> close() => _guard(() => _inner.close());

  Uint8List takeBytes() => _inner.takeBytes();
}

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

  group('WavFileWriter — sink-operation serialisation', () {
    test('fire-and-forget writeChunk racing close() must not skip the '
        'header patch (FLUTTER_WHISPASTE-7X)', () async {
      final sink = _RafLikeSink();
      final writer = WavFileWriter(
        sink: sink,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );

      // Mirror the production call shape (audio_service.dart): the PCM
      // listener fires writeChunk without awaiting, then stopRecording()
      // closes while chunk writes may still be in flight. Overlapping ops
      // on the RandomAccessFile-backed sink throw — pre-fix this made the
      // close() header patch fail silently, shipping a WAV whose RIFF/data
      // size fields were still zero. whisper-server rejects exactly that
      // shape with HTTP 400 "Invalid request".
      final chunk = Uint8List(3200);
      for (var i = 0; i < 5; i++) {
        unawaited(writer.writeChunk(chunk).catchError((Object _) {}));
      }
      await writer.close();

      final bytes = sink.takeBytes();
      expect(
        sink.overlapAttempts,
        0,
        reason:
            'sink operations must be serialised — RandomAccessFile rejects '
            'overlapping async operations',
      );
      expect(
        _readU32LE(bytes, 40),
        5 * 3200,
        reason: 'all chunks must land and the data-size field be patched',
      );
      expect(_readU32LE(bytes, 4), 36 + 5 * 3200, reason: 'RIFF size patched');
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
