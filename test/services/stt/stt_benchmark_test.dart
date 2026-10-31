/// Unit tests for SttBenchmark.
///
/// `SttBenchmark.run()` (HTTP `POST /inference` timing against the
/// whisper-server subprocess) was retired in Issue 15 — benchmarking now
/// happens via `WhisperEngine.transcribe` at the notifier call site (see
/// `stt_server_state_notifier_test.dart`, group "benchmark via engine
/// seam"). Only the shared WAV-generation contract remains here.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/stt_benchmark.dart';

void main() {
  group('SttBenchmark.generateBenchmarkWav', () {
    test('produces a 3-second, 16 kHz mono 16-bit PCM WAV', () {
      final wav = SttBenchmark.generateBenchmarkWav();

      const sampleRate = 16000;
      const durationSeconds = 3;
      const bytesPerSample = 2;
      const headerSize = 44;
      const expectedDataSize = sampleRate * durationSeconds * bytesPerSample;

      expect(wav.length, headerSize + expectedDataSize);
      // RIFF/WAVE header magic bytes.
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    });

    test('is deterministic across calls', () {
      final first = SttBenchmark.generateBenchmarkWav();
      final second = SttBenchmark.generateBenchmarkWav();
      expect(first, equals(second));
    });
  });
}
