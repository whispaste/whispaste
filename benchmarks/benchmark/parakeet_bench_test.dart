/// Repeatable latency benchmark for the Parakeet (sherpa_onnx) path, mirroring
/// `ParakeetEngineNotifier` (`lib/services/stt_parakeet/`) as the app runs it:
/// same `OfflineRecognizerConfig` (provider cpu, modelType nemo_transducer,
/// numThreads = clamp(cores - 1, 2, 8)), same WAV decoding and the same
/// `splitForParakeet` chunking, one stream per chunk, chunk texts joined with
/// a space. Differences to the production path: the decode runs in the test
/// isolate (not the worker isolate) and without the `_GuardedDecode`
/// C-symbol guard; both are documented in the benchmark report.
///
/// Manual tool, skipped in the default sweep. Protocol identical to
/// `stt_bench_test.dart`: load (timed), first transcription (timed, cold),
/// then REPEAT timed runs per file. Writes JSON to OUT.
///
/// ```sh
/// flutter test test/benchmark/parakeet_bench_test.dart \
///   --dart-define=WAV_DIR=<dir> \
///   --dart-define=MODEL_DIR=<dir with encoder/decoder/joiner .int8.onnx + tokens.txt> \
///   --dart-define=LIBRARY=<dir containing libsherpa-onnx-c-api.dylib> \
///   --dart-define=REPEAT=5 --dart-define=OUT=<out.json>
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:whispaste/services/audio/pcm_wav_codec.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_audio_chunker.dart';
import 'package:whispaste/services/transcription/transcript_seam.dart';

const _wavDir = String.fromEnvironment('WAV_DIR');
const _modelDir = String.fromEnvironment('MODEL_DIR');
const _libraryPath = String.fromEnvironment('LIBRARY');
const _repeat = int.fromEnvironment('REPEAT', defaultValue: 5);
const _outPath = String.fromEnvironment('OUT');

int _percentile(List<int> sorted, double q) =>
    sorted[((sorted.length - 1) * q).round()];

/// Same as `_decodeChunk` in parakeet_engine_notifier.dart (minus the guard).
String _decodeChunk(
  sherpa_onnx.OfflineRecognizer r,
  Float32List samples,
  int sampleRate,
) {
  final stream = r.createStream();
  try {
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    r.decode(stream);
    return r.getResult(stream).text;
  } finally {
    stream.free();
  }
}

void main() {
  final available =
      _wavDir.isNotEmpty &&
      _modelDir.isNotEmpty &&
      _libraryPath.isNotEmpty &&
      Directory(_wavDir).existsSync() &&
      File(p.join(_modelDir, 'tokens.txt')).existsSync();

  test(
    'parakeet (sherpa_onnx) benchmark',
    () async {
      final wavs =
          Directory(_wavDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      // Identical thread rule to ParakeetEngineNotifier._threadCount().
      final threads = (Platform.numberOfProcessors - 1).clamp(2, 8);

      final loadSw = Stopwatch()..start();
      sherpa_onnx.initBindings(_libraryPath);
      final recognizer = sherpa_onnx.OfflineRecognizer(
        sherpa_onnx.OfflineRecognizerConfig(
          model: sherpa_onnx.OfflineModelConfig(
            transducer: sherpa_onnx.OfflineTransducerModelConfig(
              encoder: p.join(_modelDir, 'encoder.int8.onnx'),
              decoder: p.join(_modelDir, 'decoder.int8.onnx'),
              joiner: p.join(_modelDir, 'joiner.int8.onnx'),
            ),
            tokens: p.join(_modelDir, 'tokens.txt'),
            numThreads: threads,
            provider: 'cpu',
            modelType: 'nemo_transducer',
            debug: false,
          ),
        ),
      );
      loadSw.stop();
      addTearDown(recognizer.free);

      String run(Uint8List bytes) {
        final samples = pcm16WavBytesToFloat32(bytes);
        if (samples.isEmpty) return '';
        final texts = <String>[];
        final overlaps = <bool>[];
        for (final chunk in splitForParakeet(samples, sampleRate: 16000)) {
          texts.add(_decodeChunk(recognizer, chunk.samples, 16000).trim());
          overlaps.add(chunk.overlapsPrevious);
        }
        return joinSeamTexts(texts, overlaps);
      }

      // First call = cold first transcription (no discarded warm-up), so the
      // report can show first-transcription latency separately.
      final results = <Map<String, Object>>[];
      var totalMedian = 0;
      var firstMs = -1;
      for (var idx = 0; idx < wavs.length; idx++) {
        final wav = wavs[idx];
        final bytes = wav.readAsBytesSync();
        final audioMs = ((bytes.length - 44) / 32000 * 1000).round();
        var text = '';
        var first = 0;
        final sw0 = Stopwatch()..start();
        text = run(bytes);
        sw0.stop();
        first = sw0.elapsedMilliseconds;
        if (idx == 0) firstMs = first;
        final times = <int>[];
        for (var i = 0; i < _repeat; i++) {
          final sw = Stopwatch()..start();
          text = run(bytes);
          sw.stop();
          times.add(sw.elapsedMilliseconds);
        }
        times.sort();
        final median = _percentile(times, 0.5);
        totalMedian += median;
        results.add({
          'file': p.basename(wav.path),
          'audioMs': audioMs,
          'firstMs': first,
          'medianMs': median,
          'p90Ms': _percentile(times, 0.9),
          'minMs': times.first,
          'maxMs': times.last,
          'text': text,
        });
        print(
          '${p.basename(wav.path)}  audio=${audioMs}ms  first=${first}ms  '
          'median=${median}ms  runs=$times',
        );
      }

      final report = {
        'engine': 'sherpa_onnx',
        'model': p.basename(_modelDir),
        'threads': threads,
        'provider': 'cpu',
        'repeat': _repeat,
        'loadMs': loadSw.elapsedMilliseconds,
        'firstTranscriptionMs': firstMs,
        'sumOfMediansMs': totalMedian,
        'files': results,
      };
      print(
        'load=${loadSw.elapsedMilliseconds}ms  first=${firstMs}ms  '
        'sumOfMedians=$totalMedian',
      );
      if (_outPath.isNotEmpty) {
        File(
          _outPath,
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      }
    },
    timeout: const Timeout(Duration(minutes: 60)),
    skip: available
        ? null
        : 'set --dart-define=WAV_DIR, MODEL_DIR and LIBRARY — see the doc comment',
  );
}
