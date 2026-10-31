/// WAV format gate for `POST /v1/transcriptions` (ticket / 8.2).
///
/// The API accepts only what the existing transcription path takes today:
/// RIFF/WAVE, PCM, mono, 16 kHz, 16-bit. Anything else is refused with a
/// reason, never guessed at. The general decoder (ticket) will widen this.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/wav_format.dart';

import '../../test_helpers/wav_bytes.dart';

void main() {
  test('a 16 kHz mono 16-bit PCM WAV is accepted', () {
    expect(checkWav16kMono16(buildWavBytes()), isNull);
  });

  test('non-RIFF input is refused', () {
    expect(checkWav16kMono16(buildWavBytes(riff: 'RIFX')), isNotNull);
    expect(checkWav16kMono16(buildWavBytes(wave: 'AVI ')), isNotNull);
  });

  test('stereo, other sample rates, 8/24-bit and float are refused', () {
    expect(checkWav16kMono16(buildWavBytes(channels: 2)), isNotNull);
    expect(checkWav16kMono16(buildWavBytes(sampleRate: 44100)), isNotNull);
    expect(checkWav16kMono16(buildWavBytes(bits: 8)), isNotNull);
    expect(checkWav16kMono16(buildWavBytes(bits: 24)), isNotNull);
    expect(checkWav16kMono16(buildWavBytes(audioFormat: 3)), isNotNull);
  });

  test('a WAV without a data chunk is refused', () {
    expect(checkWav16kMono16(buildWavBytes(withData: false)), isNotNull);
  });

  test('truncated and empty input never throws', () {
    expect(checkWav16kMono16(const []), isNotNull);
    expect(checkWav16kMono16(buildWavBytes().sublist(0, 20)), isNotNull);
    expect(checkWav16kMono16(buildWavBytes().sublist(0, 30)), isNotNull);
  });

  group('header fuzzing: lying sizes and damaged bytes', () {
    // Offsets of the size fields in the canonical layout that
    // buildWavBytes() writes: RIFF size at 4, fmt size at 16, data size at 40.
    const sizeFields = [4, 16, 40];

    test('every truncation of a valid file returns a result, never throws', () {
      final valid = buildWavBytes();
      for (var length = 0; length <= valid.length; length++) {
        expect(
          () => checkWav16kMono16(valid.sublist(0, length)),
          returnsNormally,
          reason: 'truncated to $length bytes',
        );
      }
    });

    test('a chunk size far beyond the file is refused or accepted, never '
        'a crash, and returns quickly', () {
      final stopwatch = Stopwatch()..start();
      for (final field in sizeFields) {
        for (final size in [0xFFFFFFFF, 0x7FFFFFFF, 0x80000000, 1 << 30]) {
          final bytes = buildWavBytes();
          bytes.setRange(field, field + 4, [
            size & 0xff,
            (size >> 8) & 0xff,
            (size >> 16) & 0xff,
            (size >> 24) & 0xff,
          ]);
          expect(
            () => checkWav16kMono16(bytes),
            returnsNormally,
            reason: 'size $size at offset $field',
          );
        }
      }
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('random damage to up to eight bytes never throws', () {
      final random = Random(20261017);
      final valid = buildWavBytes();
      for (var i = 0; i < 3000; i++) {
        final bytes = List<int>.of(valid);
        final edits = 1 + random.nextInt(8);
        for (var e = 0; e < edits; e++) {
          bytes[random.nextInt(bytes.length)] = random.nextInt(256);
        }
        final cut = random.nextInt(bytes.length + 1);
        expect(
          () => checkWav16kMono16(bytes.sublist(0, cut)),
          returnsNormally,
          reason: 'iteration $i',
        );
      }
    });

    test('a huge chunk size before the fmt chunk does not hide it from '
        'the parser or allocate', () {
      final bytes = buildWavBytes();
      // Replace the fmt chunk id with an unknown chunk claiming 4 GB: the
      // parser must step over it in one jump and then find nothing usable.
      bytes.setRange(12, 16, 'junk'.codeUnits);
      bytes.setRange(16, 20, [0xff, 0xff, 0xff, 0xff]);
      expect(checkWav16kMono16(bytes), 'missing fmt chunk');
    });
  });
}
