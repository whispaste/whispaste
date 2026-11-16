import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/pcm_wav_codec.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_speech_gate.dart';

/// Unit tests for the Parakeet speech gate. The real Silero-VAD run is in
/// benchmarks/benchmark/parakeet_speech_gate_test.dart (manual, needs libwhisper).
void main() {
  group('parakeetSpeechCheck', () {
    test('no segments is noSpeech, any segment is speech', () {
      expect(
        parakeetSpeechCheck(segmentCount: 0),
        ParakeetSpeechCheck.noSpeech,
      );
      expect(parakeetSpeechCheck(segmentCount: 1), ParakeetSpeechCheck.speech);
      expect(parakeetSpeechCheck(segmentCount: 7), ParakeetSpeechCheck.speech);
    });

    test('a VAD that could not run is unavailable (fail-open)', () {
      expect(
        parakeetSpeechCheck(segmentCount: null),
        ParakeetSpeechCheck.unavailable,
      );
    });
  });

  group('ParakeetSpeechGate fail-open', () {
    final samples = Float32List(16000);

    test(
      'missing model file: unavailable, and hasSpeech transcribes',
      () async {
        final gate = ParakeetSpeechGate(
          libraryPath: Platform.resolvedExecutable,
          modelPath: '/nonexistent/ggml-silero.bin',
        );
        expect(await gate.check(samples), ParakeetSpeechCheck.unavailable);
        expect(await gate.hasSpeech(samples), isTrue);
      },
    );

    test('missing library: unavailable, and hasSpeech transcribes', () async {
      final gate = ParakeetSpeechGate(
        libraryPath: '/nonexistent/libwhisper.dylib',
        modelPath: Platform.resolvedExecutable,
      );
      expect(await gate.check(samples), ParakeetSpeechCheck.unavailable);
      expect(await gate.hasSpeech(samples), isTrue);
    });

    test('empty audio is noSpeech without touching the VAD', () async {
      final gate = ParakeetSpeechGate(
        libraryPath: '/nonexistent/libwhisper.dylib',
        modelPath: '/nonexistent/ggml-silero.bin',
      );
      expect(await gate.check(Float32List(0)), ParakeetSpeechCheck.noSpeech);
      expect(await gate.hasSpeech(Float32List(0)), isFalse);
    });

    test('audio below 100 ms is noSpeech without touching the VAD', () async {
      final gate = ParakeetSpeechGate(
        libraryPath: '/nonexistent/libwhisper.dylib',
        modelPath: '/nonexistent/ggml-silero.bin',
      );
      expect(
        await gate.check(Float32List(parakeetMinSpeechSamples - 1)),
        ParakeetSpeechCheck.noSpeech,
      );
      // From 100 ms on the (missing) VAD decides: fail-open.
      expect(
        await gate.check(Float32List(parakeetMinSpeechSamples)),
        ParakeetSpeechCheck.unavailable,
      );
    });
  });

  group('ParakeetSpeechGate timeout', () {
    const lib = '.build/libwhisper/macos/libwhisper.dylib';
    const model = 'assets/models/vad/ggml-silero-v5.1.2.bin';
    final skip = File(lib).existsSync() && File(model).existsSync()
        ? null
        : 'libwhisper or the Silero model is not present';

    test(
      'a check that exceeds its budget falls open to transcription',
      () async {
        final gate = ParakeetSpeechGate(
          libraryPath: File(lib).absolute.path,
          modelPath: File(model).absolute.path,
          timeout: Duration.zero,
        );
        expect(
          await gate.check(Float32List(16000)),
          ParakeetSpeechCheck.unavailable,
        );
        expect(await gate.hasSpeech(Float32List(16000)), isTrue);
      },
      skip: skip,
    );
  });

  group('windowed check (#1665)', () {
    Uint8List wavOfSeconds(double seconds) =>
        Uint8List(44 + (seconds * 16000).round() * 2);

    test('up to one window it is one check on all samples', () {
      expect(parakeetSpeechGateWindows(0), [(0, 0)]);
      expect(parakeetSpeechGateWindows(60 * 16000), [(0, 60 * 16000)]);
    });

    test('longer audio is covered by overlapping windows of 60 s', () {
      const length = 3600 * 16000 + 123;
      final windows = parakeetSpeechGateWindows(length);
      expect(windows.first.$1, 0);
      expect(windows.last.$2, length);
      for (final (start, end) in windows) {
        expect(end - start, lessThanOrEqualTo(60 * 16000));
        expect(end, greaterThan(start));
      }
      for (var i = 1; i < windows.length; i++) {
        expect(windows[i - 1].$2 - windows[i].$1, 2 * 16000);
      }
    });

    test('stops at the first window with speech', () async {
      final checked = <int>[];
      var call = 0;
      final hasSpeech = await hasSpeechInWindows(
        Pcm16WavView(wavOfSeconds(200)),
        (samples) async {
          checked.add(samples.length);
          return call++ == 1
              ? ParakeetSpeechCheck.speech
              : ParakeetSpeechCheck.noSpeech;
        },
      );
      expect(hasSpeech, isTrue);
      expect(checked, [60 * 16000, 60 * 16000]);
    });

    test('an unavailable window counts as speech (fail-open)', () async {
      expect(
        await hasSpeechInWindows(
          Pcm16WavView(wavOfSeconds(130)),
          (_) async => ParakeetSpeechCheck.unavailable,
        ),
        isTrue,
      );
    });

    test('no speech only when every window found none', () async {
      var checks = 0;
      expect(
        await hasSpeechInWindows(Pcm16WavView(wavOfSeconds(130)), (_) async {
          checks++;
          return ParakeetSpeechCheck.noSpeech;
        }),
        isFalse,
      );
      expect(checks, parakeetSpeechGateWindows(130 * 16000).length);
    });
  });
}
