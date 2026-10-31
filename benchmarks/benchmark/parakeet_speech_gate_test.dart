/// Manual check of the Parakeet speech gate (Silero-VAD via libwhisper) against
/// the real library. Skipped in the default sweep. Prints `GATE|` lines.
///
/// ```sh
/// WP_PERF_WAVS=<dir with the 18 dictations> WP_ROBUST_WAVS=<dir with c_random.wav
///   and long_300s.wav> WP_PARAKEET_GGUF=<q8_0.bin> \
///   flutter test test/benchmark/parakeet_speech_gate_test.dart
/// ```
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/pcm_wav_codec.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_engine.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_speech_gate.dart';

String _env(String name) => Platform.environment[name] ?? '';

const _libPath = '.build/libwhisper/macos/libwhisper.dylib';
const _vadPath = 'assets/models/vad/ggml-silero-v5.1.2.bin';

Float32List _wav(String path) =>
    pcm16WavBytesToFloat32(File(path).readAsBytesSync());

Float32List _noise(int n, double amp, int seed) {
  final rng = Random(seed);
  return Float32List.fromList([
    for (var i = 0; i < n; i++) (rng.nextDouble() * 2 - 1) * amp,
  ]);
}

Future<double> _medianMs(Future<void> Function() body, int runs) async {
  final times = <int>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    await body();
    times.add(sw.elapsedMicroseconds);
  }
  times.sort();
  return times[times.length ~/ 2] / 1000;
}

void main() {
  final perf = _env('WP_PERF_WAVS');
  final robust = _env('WP_ROBUST_WAVS');
  final model = _env('WP_PARAKEET_GGUF');
  final skip = !File(_libPath).existsSync() || !File(_vadPath).existsSync()
      ? 'libwhisper or the Silero VAD model is missing'
      : perf.isEmpty || !Directory(perf).existsSync()
      ? 'set WP_PERF_WAVS to the directory with the dictations'
      : null;

  final gate = ParakeetSpeechGate(
    libraryPath: File(_libPath).absolute.path,
    modelPath: File(_vadPath).absolute.path,
  );

  test(
    'noise, silence and random bytes are judged noSpeech by the real VAD',
    () async {
      final cases = <String, Float32List>{
        'silence_3s': Float32List(16000 * 3),
        'noise_quiet_3s': _noise(16000 * 3, 0.002, 1),
        'noise_loud_3s': _noise(16000 * 3, 0.3, 2),
        if (robust.isNotEmpty)
          'random_bytes': _wav(p.join(robust, 'c_random.wav')),
      };
      for (final e in cases.entries) {
        final c = await gate.check(e.value);
        print('GATE|noise|case=${e.key}|result=${c.name}');
        expect(c, ParakeetSpeechCheck.noSpeech, reason: e.key);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'all dictations are judged speech, and the engine transcribes each one',
    () async {
      final files =
          Directory(perf)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(18));

      ParakeetGpuEngine? engine;
      if (model.isNotEmpty && File(model).existsSync()) {
        engine = await ParakeetGpuEngine.open(
          libraryPath: File(
            '.build/libwhisper/macos/libparakeet.dylib',
          ).absolute.path,
          modelPath: model,
          threads: 4,
        );
      }
      addTearDown(() async => engine?.close());

      var noSpeech = 0;
      for (final f in files) {
        final samples = _wav(f.path);
        final sw = Stopwatch()..start();
        final check = await gate.check(samples);
        final gateMs = sw.elapsedMilliseconds;
        var text = '(engine not run)';
        if (engine != null) {
          text = await engine.transcribe(
            samples,
            timeout: const Duration(seconds: 60),
          );
        }
        print(
          'GATE|dictation|file=${p.basename(f.path)}|audioS=${(samples.length / 16000).toStringAsFixed(1)}|'
          'gate=${check.name}|gateMs=$gateMs|text="$text"',
        );
        if (check != ParakeetSpeechCheck.speech) noSpeech++;
        expect(check, ParakeetSpeechCheck.speech, reason: f.path);
        if (engine != null) expect(text.trim(), isNotEmpty, reason: f.path);
      }
      print('GATE|dictation|summary|total=${files.length}|noSpeech=$noSpeech');
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 20)),
  );

  test(
    'latency of the gate for 3 s and 60 s of speech',
    () async {
      final first =
          Directory(perf)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.wav'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final speech = _wav(first.last.path);
      final clip3 = Float32List.sublistView(
        speech,
        0,
        min(speech.length, 16000 * 3),
      );
      // 60 s: repeat the dictation until it is long enough.
      final long = Float32List(16000 * 60);
      // An empty clip would never advance `pos` below: fail instead of hang.
      expect(speech, isNotEmpty, reason: 'speech clip must not be empty');
      var pos = 0;
      while (pos < long.length) {
        final n = min(speech.length, long.length - pos);
        long.setRange(pos, pos + n, speech);
        pos += n;
      }
      for (final e in {'3s': clip3, '60s': long}.entries) {
        final ms = await _medianMs(() async {
          await gate.check(e.value);
        }, 7);
        print(
          'GATE|latency|clip=${e.key}|audioS=${(e.value.length / 16000).toStringAsFixed(1)}|medianMs=${ms.toStringAsFixed(1)}',
        );
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
