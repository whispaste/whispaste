/// Tests for [repairZeroedWavSizeFields] — the pre-send repair for WAV
/// payloads whose RIFF/data size fields were never patched
/// (FLUTTER_WHISPASTE-7X: whisper-server answers HTTP 400 "Invalid request"
/// for exactly that container shape).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/wav_header_repair.dart';

/// Builds a canonical 44-byte-header WAV (16 kHz mono 16-bit) with
/// [sampleBytes] bytes of PCM payload. [patchSizes] mirrors whether
/// `WavFileWriter.close()` got to patch the size fields.
Uint8List _wav({required int sampleBytes, required bool patchSizes}) {
  final bytes = Uint8List(44 + sampleBytes);
  final bd = ByteData.view(bytes.buffer);

  void tag(int offset, String t) {
    for (var i = 0; i < t.length; i++) {
      bytes[offset + i] = t.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  bd.setUint32(4, patchSizes ? 36 + sampleBytes : 0, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, 16000, Endian.little);
  bd.setUint32(28, 32000, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bd.setUint32(40, patchSizes ? sampleBytes : 0, Endian.little);
  return bytes;
}

int _u32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

void main() {
  group('repairZeroedWavSizeFields', () {
    test('repairs zeroed size fields when PCM data is present', () {
      final broken = _wav(sampleBytes: 32000, patchSizes: false);

      final repaired = repairZeroedWavSizeFields(broken);

      expect(repaired, isNotNull);
      expect(_u32(repaired!, 4), 36 + 32000, reason: 'RIFF size = len - 8');
      expect(_u32(repaired, 40), 32000, reason: 'data size = len - 44');
      // Payload untouched.
      expect(repaired.sublist(44), broken.sublist(44));
      // Input not mutated (repair returns a copy).
      expect(_u32(broken, 4), 0);
    });

    test('returns null for a correctly patched WAV', () {
      final ok = _wav(sampleBytes: 32000, patchSizes: true);
      expect(repairZeroedWavSizeFields(ok), isNull);
    });

    test('returns null for header-only payload (no PCM data)', () {
      final empty = _wav(sampleBytes: 0, patchSizes: false);
      expect(repairZeroedWavSizeFields(empty), isNull);
    });

    test('returns null for non-canonical layout (no data tag at 36)', () {
      final broken = _wav(sampleBytes: 1000, patchSizes: false);
      broken[36] = 0x4C; // 'data' → 'Lata' — extra-chunk style layout
      expect(repairZeroedWavSizeFields(broken), isNull);
    });

    test('repairs when only one of the two size fields is zero', () {
      final halfPatched = _wav(sampleBytes: 1000, patchSizes: false);
      // RIFF size patched, data size still zero.
      final bd = ByteData.view(halfPatched.buffer);
      bd.setUint32(4, 36 + 1000, Endian.little);

      final repaired = repairZeroedWavSizeFields(halfPatched);
      expect(repaired, isNotNull);
      expect(_u32(repaired!, 40), 1000);
    });
  });
}
