import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/audio/wav_header_repair.dart';

/// Builds a 16 kHz mono 16-bit WAV with [pcmBytes] of sample data. The size
/// fields are overwritten with [riffSize] / [dataSize] when given, to imitate
/// a file the writer never finalised.
Uint8List _wav(int pcmBytes, {int? riffSize, int? dataSize}) {
  final bytes = Uint8List(44 + pcmBytes)
    ..setRange(0, 44, wavHeaderPcm16Mono(pcmBytes));
  for (var i = 0; i < pcmBytes; i++) {
    bytes[44 + i] = (i * 7 + 3) & 0xFF;
  }
  final view = ByteData.sublistView(bytes);
  if (riffSize != null) view.setUint32(4, riffSize, Endian.little);
  if (dataSize != null) view.setUint32(40, dataSize, Endian.little);
  return bytes;
}

void main() {
  group('repairWavHeader', () {
    test('returns an intact WAV as the same instance', () {
      final wav = _wav(3200);

      expect(repairWavHeader(wav), same(wav));
    });

    test('returns non-WAV bytes unchanged', () {
      final bytes = Uint8List.fromList(List.filled(64, 9));

      expect(repairWavHeader(bytes), same(bytes));
    });

    test('returns a WAV without a data chunk unchanged', () {
      final bytes = Uint8List.fromList(
        wavHeaderPcm16Mono(0).sublist(0, 36), // RIFF + fmt only
      );

      expect(repairWavHeader(bytes), same(bytes));
    });

    test('sets a zero data size from the file length (crash placeholder)', () {
      final wav = _wav(3200, riffSize: 0, dataSize: 0);

      final repaired = repairWavHeader(wav);

      final view = ByteData.sublistView(Uint8List.fromList(repaired));
      expect(view.getUint32(40, Endian.little), 3200);
      expect(view.getUint32(4, Endian.little), 36 + 3200);
      expect(repaired.length, wav.length);
      expect(repaired.sublist(44), wav.sublist(44));
    });

    test('replaces a 0xFFFFFFFF streaming size with the file length', () {
      final wav = _wav(3200, dataSize: 0xFFFFFFFF);

      final repaired = repairWavHeader(wav);

      final view = ByteData.sublistView(Uint8List.fromList(repaired));
      expect(view.getUint32(40, Endian.little), 3200);
    });

    test('clamps a data size that runs past the end of the file', () {
      // The header promises 10 000 bytes, only 3 200 were written.
      final wav = _wav(3200, dataSize: 10000, riffSize: 10000 + 36);

      final repaired = repairWavHeader(wav);

      final view = ByteData.sublistView(Uint8List.fromList(repaired));
      expect(view.getUint32(40, Endian.little), 3200);
      expect(view.getUint32(4, Endian.little), 36 + 3200);
    });

    test('drops a trailing partial sample frame', () {
      // 3 201 bytes of PCM with 16-bit mono frames: one byte is half a sample.
      final wav = _wav(3201, dataSize: 0);

      final repaired = repairWavHeader(wav);

      expect(repaired.length, 44 + 3200);
      final view = ByteData.sublistView(Uint8List.fromList(repaired));
      expect(view.getUint32(40, Endian.little), 3200);
    });

    test('repairs a header-only file to an empty data chunk', () {
      final wav = _wav(0, dataSize: 0);

      final repaired = repairWavHeader(wav);

      expect(repaired.length, 44);
      final view = ByteData.sublistView(Uint8List.fromList(repaired));
      expect(view.getUint32(40, Endian.little), 0);
    });

    test('finds the data chunk behind a LIST chunk', () {
      const pcm = 1600;
      final fmt = wavHeaderPcm16Mono(0).sublist(12, 36); // 'fmt ' chunk
      final list = Uint8List.fromList([
        ...'LIST'.codeUnits,
        6,
        0,
        0,
        0,
        ...'INFO'.codeUnits,
        0,
        0,
      ]);
      final data = Uint8List(8 + pcm)
        ..setRange(0, 4, 'data'.codeUnits)
        ..setRange(4, 8, [0, 0, 0, 0]);
      for (var i = 0; i < pcm; i++) {
        data[8 + i] = i & 0xFF;
      }
      final bytes = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        0,
        0,
        0,
        0,
        ...'WAVE'.codeUnits,
        ...fmt,
        ...list,
        ...data,
      ]);

      final repaired = repairWavHeader(bytes);

      final view = ByteData.sublistView(Uint8List.fromList(repaired));
      final dataAt = bytes.length - pcm - 8;
      expect(view.getUint32(dataAt + 4, Endian.little), pcm);
      expect(view.getUint32(4, Endian.little), repaired.length - 8);
    });

    test('repairs in place and shares the sample bytes (no copy)', () {
      // A 60-minute recording is about 115 MB; a second buffer of that size
      // doubled the peak memory of the transcription path (F31-5).
      final wav = _wav(3200, riffSize: 0, dataSize: 0);

      final repaired = repairWavHeader(wav);

      expect(repaired.length, wav.length);
      // Aliasing check: a write through the result is visible in the input.
      repaired[44] = 0x5A;
      expect(wav[44], 0x5A);
      final view = ByteData.sublistView(wav);
      expect(view.getUint32(40, Endian.little), 3200);
      expect(view.getUint32(4, Endian.little), 36 + 3200);
    });

    test('a List<int> input is repaired to the same bytes as a Uint8List', () {
      final wav = _wav(3201, dataSize: 0);

      final repaired = repairWavHeader(wav.toList());

      expect(repaired.length, 44 + 3200);
      final view = ByteData.sublistView(repaired);
      expect(view.getUint32(40, Endian.little), 3200);
      expect(repaired.sublist(44), wav.sublist(44, 44 + 3200));
    });

    test('the repaired file decodes to the samples that were written', () {
      final wav = _wav(3200, riffSize: 0, dataSize: 0);

      final repaired = repairWavHeader(wav);
      final decoded = decodeWavBytes(Uint8List.fromList(repaired));

      expect(decoded.samples.length, 1600);
    });
  });
}
