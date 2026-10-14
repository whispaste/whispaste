/// Manual robustness run for the GPU Parakeet engine against the real
/// libparakeet. Skipped in the default sweep. Prints one `ROBUST|` line per
/// measurement so the numbers can be copied into the benchmark notes.
///
/// ```sh
/// WP_PARAKEET_GGUF=<q8_0.bin> WP_ROBUST_WAVS=<dir with long_300s.wav etc.> \
///   WP_CORRUPT_GGUF=<truncated copy> WP_FLIPPED_GGUF=<one byte flipped copy> \
///   flutter test test/benchmark/parakeet_gpu_robustness_test.dart
/// ```
/// Read from the process environment at run time, like the other real-library tests.
library;

// ignore_for_file: avoid_print — a manual measurement tool; stdout is the
// deliverable.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/pcm_wav_codec.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_engine.dart';

String _env(String name) => Platform.environment[name] ?? '';
final _model = _env('WP_PARAKEET_GGUF');
final _wavs = _env('WP_ROBUST_WAVS');
final _corrupt = _env('WP_CORRUPT_GGUF');
final _flipped = _env('WP_FLIPPED_GGUF');
const _libPath = '.build/libwhisper/macos/libparakeet.dylib';

/// Resident set size of this process in MB, from `ps` (KB column).
Future<double> _rssMb() async {
  final r = await Process.run('ps', ['-o', 'rss=', '-p', '$pid']);
  return (int.tryParse('${r.stdout}'.trim()) ?? 0) / 1024;
}

/// Samples RSS once per second while [body] runs and returns the peak.
Future<(T, double)> _withPeakRss<T>(Future<T> Function() body) async {
  var peak = await _rssMb();
  final timer = Timer.periodic(const Duration(seconds: 1), (_) async {
    final now = await _rssMb();
    if (now > peak) peak = now;
  });
  try {
    final result = await body();
    return (result, peak);
  } finally {
    timer.cancel();
  }
}

Float32List _speech(String name) =>
    pcm16WavBytesToFloat32(File(p.join(_wavs, name)).readAsBytesSync());

Float32List _noise(int samples, double amplitude, int seed) {
  final rng = Random(seed);
  final out = Float32List(samples);
  for (var i = 0; i < samples; i++) {
    out[i] = (rng.nextDouble() * 2 - 1) * amplitude;
  }
  return out;
}

void main() {
  final lib = File(_libPath).existsSync();
  final skip = !lib
      ? 'libparakeet not built (scripts/build-libwhisper-macos.sh)'
      : _model.isEmpty || !File(_model).existsSync()
      ? 'set WP_PARAKEET_GGUF to a verified GGUF file'
      : _wavs.isEmpty || !Directory(_wavs).existsSync()
      ? 'set WP_ROBUST_WAVS to the directory with the test clips'
      : null;

  group('GPU Parakeet robustness (real libparakeet)', () {
    late ParakeetGpuEngine engine;
    setUpAll(() async {
      if (skip != null) return;
      final rss0 = await _rssMb();
      final sw = Stopwatch()..start();
      engine = await ParakeetGpuEngine.open(
        libraryPath: File(_libPath).absolute.path,
        modelPath: _model,
        threads: 4,
      );
      print(
        'ROBUST|load|ms=${sw.elapsedMilliseconds}|rssMb=${(await _rssMb()).toStringAsFixed(0)}|rssBeforeMb=${rss0.toStringAsFixed(0)}|device=${engine.device}',
      );
    });
    tearDownAll(() async {
      if (skip == null) await engine.close();
    });

    test(
      'silence, low-level noise and random bytes do not crash and are reported',
      () async {
        final cases = <String, Float32List>{
          'silence_3s': Float32List(16000 * 3),
          'noise_low_3s': _noise(16000 * 3, 0.002, 1),
          'noise_loud_3s': _noise(16000 * 3, 0.3, 2),
          'random_wav': pcm16WavBytesToFloat32(
            File(p.join(_wavs, 'c_random.wav')).readAsBytesSync(),
          ),
        };
        for (final entry in cases.entries) {
          final sw = Stopwatch()..start();
          final text = await engine.transcribe(
            entry.value,
            timeout: const Duration(seconds: 60),
          );
          print(
            'ROBUST|noise|case=${entry.key}|ms=${sw.elapsedMilliseconds}|text="$text"',
          );
          expect(text, isA<String>());
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'clips shorter than one second run and stay sane',
      () async {
        final speech = _speech('long_040s.wav');
        for (final ms in [100, 300, 500, 900]) {
          final clip = Float32List.sublistView(speech, 0, 16 * ms);
          final sw = Stopwatch()..start();
          final text = await engine.transcribe(
            clip,
            timeout: const Duration(seconds: 30),
          );
          print(
            'ROBUST|short|clipMs=$ms|ms=${sw.elapsedMilliseconds}|text="$text"',
          );
        }
        // Zero samples: must be refused or answered empty, never crash.
        try {
          final text = await engine.transcribe(
            Float32List(0),
            timeout: const Duration(seconds: 10),
          );
          print('ROBUST|short|clipMs=0|text="$text"');
          expect(text, isEmpty);
        } on ParakeetGpuException catch (e) {
          print('ROBUST|short|clipMs=0|refused=${e.message}');
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'a 300 s clip is chunked; time and peak RSS are reported',
      () async {
        final clip = _speech('long_300s.wav');
        final before = await _rssMb();
        final sw = Stopwatch()..start();
        final (text, peak) = await _withPeakRss(
          () => engine.transcribe(clip, timeout: const Duration(minutes: 4)),
        );
        print(
          'ROBUST|long300|audioS=${(clip.length / 16000).toStringAsFixed(1)}|ms=${sw.elapsedMilliseconds}|rssBeforeMb=${before.toStringAsFixed(0)}|peakRssMb=${peak.toStringAsFixed(0)}|words=${text.split(' ').length}',
        );
        expect(text.trim(), isNotEmpty);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'abort_callback stops a 300 s clip within the budget',
      () async {
        final clip = _speech('long_300s.wav');
        final sw = Stopwatch()..start();
        await expectLater(
          engine.transcribe(clip, timeout: const Duration(seconds: 2)),
          throwsA(isA<ParakeetGpuException>()),
        );
        print(
          'ROBUST|abort|budgetMs=2000|returnedMs=${sw.elapsedMilliseconds}',
        );
        expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
        // The engine must still serve a normal request after an abort.
        final again = await engine.transcribe(
          _speech('long_040s.wav').sublist(0, 16000 * 3),
          timeout: const Duration(seconds: 60),
        );
        print('ROBUST|abort|afterAbortText="$again"');
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'corrupt GGUF files are refused by the SHA-256 gate before any native load',
      () async {
        if (_corrupt.isNotEmpty && File(_corrupt).existsSync()) {
          final check = await verifyParakeetGguf(_corrupt, parakeetGgufActive);
          print('ROBUST|gguf|truncated=${check.name}');
          expect(check, isNot(ParakeetGgufCheck.ok));
        }
        if (_flipped.isNotEmpty && File(_flipped).existsSync()) {
          final check = await verifyParakeetGguf(_flipped, parakeetGgufActive);
          print('ROBUST|gguf|flippedByte=${check.name}');
          expect(check, ParakeetGgufCheck.hashMismatch);
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
