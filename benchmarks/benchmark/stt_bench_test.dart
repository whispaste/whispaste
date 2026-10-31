/// Repeatable STT latency benchmark against the real whisper.cpp FFI engine —
/// a manual tool, skipped in the default `flutter test` sweep.
///
/// Loads the engine once, transcribes every WAV in `WAV_DIR` `REPEAT` times
/// with the production decode settings (language, punctuation-priming prompt,
/// VAD) and writes per-file median/p90 latencies plus the transcript to `OUT`
/// as JSON, so two runs (before/after a change) can be compared for speed AND
/// for identical output.
///
/// ```sh
/// flutter test test/benchmark/stt_bench_test.dart \
///   --dart-define=WAV_DIR=<dir with 16 kHz mono WAVs> \
///   --dart-define=MODEL=<ggml model> \
///   --dart-define=LIBRARY=<libwhisper.dylib> \
///   --dart-define=VAD_MODEL=<ggml-silero bin> \
///   --dart-define=LANGUAGE=de --dart-define=REPEAT=3 \
///   --dart-define=OUT=/tmp/bench.json
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/punctuation_priming_prompts.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';

const _wavDir = String.fromEnvironment('WAV_DIR');
const _modelPath = String.fromEnvironment('MODEL');
const _libraryPath = String.fromEnvironment('LIBRARY');
const _backendName = String.fromEnvironment('BACKEND', defaultValue: 'metal');
const _vadModelPath = String.fromEnvironment('VAD_MODEL');
const _language = String.fromEnvironment('LANGUAGE', defaultValue: 'de');
const _repeat = int.fromEnvironment('REPEAT', defaultValue: 3);
const _outPath = String.fromEnvironment('OUT');

int _percentile(List<int> sorted, double q) =>
    sorted[((sorted.length - 1) * q).round()];

void main() {
  final available =
      _wavDir.isNotEmpty &&
      _modelPath.isNotEmpty &&
      Directory(_wavDir).existsSync() &&
      File(_modelPath).existsSync();

  test(
    'stt benchmark',
    () async {
      final wavs =
          Directory(_wavDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      final engine = WhisperFfiEngine(
        libraryPath: _libraryPath.isEmpty ? null : _libraryPath,
        backend: whisperBackendFromName(_backendName),
      );
      final loadSw = Stopwatch()..start();
      await engine.load(
        modelPath: _modelPath,
        vadModelPath: _vadModelPath.isEmpty ? null : _vadModelPath,
      );
      loadSw.stop();
      addTearDown(engine.unload);

      Future<String> run(List<int> bytes) => engine.transcribe(
        bytes,
        language: _language,
        prompt: punctuationPrimingPrompts[_language],
        vadEnabled: _vadModelPath.isNotEmpty,
      );

      // One discarded warm-up pass: the first decode pays one-off backend
      // pipeline compilation that no dictation after app start sees again.
      await run(wavs.first.readAsBytesSync());

      final results = <Map<String, Object>>[];
      var totalMedian = 0;
      for (final wav in wavs) {
        final bytes = wav.readAsBytesSync();
        final audioMs = ((bytes.length - 44) / 32000 * 1000).round();
        final times = <int>[];
        var text = '';
        for (var i = 0; i < _repeat; i++) {
          final sw = Stopwatch()..start();
          text = await run(bytes);
          sw.stop();
          times.add(sw.elapsedMilliseconds);
        }
        times.sort();
        final median = _percentile(times, 0.5);
        totalMedian += median;
        results.add({
          'file': p.basename(wav.path),
          'audioMs': audioMs,
          'medianMs': median,
          'p90Ms': _percentile(times, 0.9),
          'minMs': times.first,
          'maxMs': times.last,
          'text': text,
        });
        print(
          '${p.basename(wav.path)}  audio=${audioMs}ms  '
          'median=${median}ms  runs=$times',
        );
      }

      final report = {
        'model': p.basename(_modelPath),
        'language': _language,
        'repeat': _repeat,
        'vad': _vadModelPath.isNotEmpty,
        'loadMs': loadSw.elapsedMilliseconds,
        'sumOfMediansMs': totalMedian,
        'files': results,
      };
      print('load=${loadSw.elapsedMilliseconds}ms  sumOfMedians=$totalMedian');
      if (_outPath.isNotEmpty) {
        File(
          _outPath,
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      }
    },
    timeout: const Timeout(Duration(minutes: 60)),
    skip: available
        ? null
        : 'set --dart-define=WAV_DIR=… and MODEL=… — see the doc comment',
  );
}
