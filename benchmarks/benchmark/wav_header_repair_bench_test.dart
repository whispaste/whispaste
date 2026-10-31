/// Peak-memory check for the broken-header repair (F31-5).
///
/// A recording that ends by crash keeps zeroed size fields. Its 60-minute
/// WAV (16 kHz mono 16-bit, about 115 MB) then goes through
/// `repairWavHeader` on the way to the engine. Skipped in the default sweep.
/// Run with (through the test dispatcher, which forwards the environment):
///
/// ```sh
/// WP_BENCH=1 MINUTES=60 wp-test.sh run <worktree> --host mac \
///   test/benchmark/wav_header_repair_bench_test.dart
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/wav_header_repair.dart';

final _enabled = Platform.environment['WP_BENCH'] == '1';
final _minutes = int.tryParse(Platform.environment['MINUTES'] ?? '') ?? 60;

const _mb = 1024 * 1024;

void main() {
  test(
    'repairWavHeader peak RSS on a broken long recording',
    skip: _enabled ? false : 'set WP_BENCH=1 to run',
    () {
      final pcmBytes = _minutes * 60 * 16000 * 2;
      // Header with zeroed RIFF and data sizes, as the writer leaves it.
      final wav = Uint8List(44 + pcmBytes);
      wav.setRange(0, 4, 'RIFF'.codeUnits);
      wav.setRange(8, 12, 'WAVE'.codeUnits);
      wav.setRange(12, 16, 'fmt '.codeUnits);
      ByteData.sublistView(wav)
        ..setUint32(16, 16, Endian.little)
        ..setUint16(20, 1, Endian.little)
        ..setUint16(22, 1, Endian.little)
        ..setUint32(24, 16000, Endian.little)
        ..setUint32(28, 32000, Endian.little)
        ..setUint16(32, 2, Endian.little)
        ..setUint16(34, 16, Endian.little);
      wav.setRange(36, 40, 'data'.codeUnits);
      for (var i = 44; i < wav.length; i += 4096) {
        wav[i] = (i >> 12) & 0xFF;
      }

      final rssBefore = ProcessInfo.currentRss;
      final maxBefore = ProcessInfo.maxRss;
      final repaired = repairWavHeader(wav);
      final maxAfter = ProcessInfo.maxRss;
      final rssAfter = ProcessInfo.currentRss;

      print(
        'WAV_REPAIR_BENCH minutes=$_minutes input_mb='
        '${(wav.length / _mb).toStringAsFixed(1)} '
        'repaired_len=${repaired.length} '
        'rss_before_mb=${(rssBefore / _mb).toStringAsFixed(1)} '
        'rss_after_mb=${(rssAfter / _mb).toStringAsFixed(1)} '
        'peak_growth_mb=${((maxAfter - maxBefore) / _mb).toStringAsFixed(1)}',
      );
      expect(repaired.length, wav.length);
    },
  );
}
