/// Standalone VAD (Voice Activity Detection) probe against the bundled
/// `libwhisper` — NOT part of the default `flutter test` sweep, mirrors
/// `transcribe_debug_harness_test.dart`'s doc comment for why `flutter test`
/// (not bare `dart run`) is required on this Dart SDK.
///
/// Built to evaluate whether whisper.cpp's built-in Silero-VAD support
/// (`whisper_vad_*`, confirmed exported by the bundled dylib via `nm -gU`)
/// would have flagged the synthetic silence/noise tails used to
/// investigate the "Vielen Dank" trailing-hallucination report as
/// non-speech — and how long that check takes, since VAD would run before
/// every `whisper_full` call if wired into production.
///
/// This is a pure read probe: no production code path calls any
/// `whisper_vad_*` function. Bindings are resolved manually via
/// `dylib.lookupFunction`, same pattern as the `no_speech_prob`/t0/t1
/// lookups in `whisper_ffi_engine.dart`.
///
/// Usage:
/// ```sh
/// flutter test test/services/stt/whisper/vad_debug_harness_test.dart \
///   --dart-define=WAV=/path/to/clip.wav \
///   --dart-define=VAD_MODEL=/path/to/ggml-silero-v5.1.2.bin \
///   --dart-define=LIBRARY=/path/to/libwhisper.dylib
/// ```
library;

// ignore_for_file: avoid_print — this is a manual diagnosis tool; stdout
// IS the deliverable, not something a future maintainer should silence.
// ignore_for_file: non_constant_identifier_names — struct fields mirror the
// C ABI field names verbatim (same convention as the ffigen-generated
// whisper_bindings.dart), not Dart identifiers.

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/pcm_wav_codec.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';

// ── Manual VAD struct/binding layer (not in the ffigen WhisperBindings) ────

final class WhisperVadContextParams extends ffi.Struct {
  @ffi.Int32()
  external int n_threads;
  @ffi.Bool()
  external bool use_gpu;
  @ffi.Int32()
  external int gpu_device;
}

final class WhisperVadParams extends ffi.Struct {
  @ffi.Float()
  external double threshold;
  @ffi.Int32()
  external int min_speech_duration_ms;
  @ffi.Int32()
  external int min_silence_duration_ms;
  @ffi.Float()
  external double max_speech_duration_s;
  @ffi.Int32()
  external int speech_pad_ms;
  @ffi.Float()
  external double samples_overlap;
}

final class WhisperVadContext extends ffi.Opaque {}

final class WhisperVadSegments extends ffi.Opaque {}

typedef _VadDefaultContextParamsNative = WhisperVadContextParams Function();
typedef _VadDefaultParamsNative = WhisperVadParams Function();
typedef _VadInitNative =
    ffi.Pointer<WhisperVadContext> Function(
      ffi.Pointer<ffi.Char>,
      WhisperVadContextParams,
    );
typedef _VadInitDart =
    ffi.Pointer<WhisperVadContext> Function(
      ffi.Pointer<ffi.Char>,
      WhisperVadContextParams,
    );
typedef _VadSegmentsFromSamplesNative =
    ffi.Pointer<WhisperVadSegments> Function(
      ffi.Pointer<WhisperVadContext>,
      WhisperVadParams,
      ffi.Pointer<ffi.Float>,
      ffi.Int32,
    );
typedef _VadSegmentsFromSamplesDart =
    ffi.Pointer<WhisperVadSegments> Function(
      ffi.Pointer<WhisperVadContext>,
      WhisperVadParams,
      ffi.Pointer<ffi.Float>,
      int,
    );
typedef _VadNSegmentsNative =
    ffi.Int32 Function(ffi.Pointer<WhisperVadSegments>);
typedef _VadNSegmentsDart = int Function(ffi.Pointer<WhisperVadSegments>);
typedef _VadSegmentT0Native =
    ffi.Float Function(ffi.Pointer<WhisperVadSegments>, ffi.Int32);
typedef _VadSegmentT0Dart =
    double Function(ffi.Pointer<WhisperVadSegments>, int);
typedef _VadFreeNative = ffi.Void Function(ffi.Pointer<WhisperVadContext>);
typedef _VadFreeDart = void Function(ffi.Pointer<WhisperVadContext>);
typedef _VadFreeSegmentsNative =
    ffi.Void Function(ffi.Pointer<WhisperVadSegments>);
typedef _VadFreeSegmentsDart = void Function(ffi.Pointer<WhisperVadSegments>);

const _wavPath = String.fromEnvironment('WAV');
const _vadModelPath = String.fromEnvironment('VAD_MODEL');
const _libraryPathOverride = String.fromEnvironment('LIBRARY');

void main() {
  final wavFile = File(_wavPath);
  final available =
      _vadModelPath.isNotEmpty &&
      File(_vadModelPath).existsSync() &&
      wavFile.existsSync();

  test(
    'vad debug harness',
    () async {
      final libraryPath = _libraryPathOverride.isNotEmpty
          ? _libraryPathOverride
          : defaultWhisperLibraryPath();
      final dylib = ffi.DynamicLibrary.open(libraryPath);

      final vadDefaultContextParams = dylib
          .lookupFunction<
            _VadDefaultContextParamsNative,
            _VadDefaultContextParamsNative
          >('whisper_vad_default_context_params');
      final vadDefaultParams = dylib
          .lookupFunction<_VadDefaultParamsNative, _VadDefaultParamsNative>(
            'whisper_vad_default_params',
          );
      final vadInit = dylib.lookupFunction<_VadInitNative, _VadInitDart>(
        'whisper_vad_init_from_file_with_params',
      );
      final vadSegmentsFromSamples = dylib
          .lookupFunction<
            _VadSegmentsFromSamplesNative,
            _VadSegmentsFromSamplesDart
          >('whisper_vad_segments_from_samples');
      final vadNSegments = dylib
          .lookupFunction<_VadNSegmentsNative, _VadNSegmentsDart>(
            'whisper_vad_segments_n_segments',
          );
      final vadSegmentT0 = dylib
          .lookupFunction<_VadSegmentT0Native, _VadSegmentT0Dart>(
            'whisper_vad_segments_get_segment_t0',
          );
      final vadSegmentT1 = dylib
          .lookupFunction<_VadSegmentT0Native, _VadSegmentT0Dart>(
            'whisper_vad_segments_get_segment_t1',
          );
      final vadFree = dylib.lookupFunction<_VadFreeNative, _VadFreeDart>(
        'whisper_vad_free',
      );
      final vadFreeSegments = dylib
          .lookupFunction<_VadFreeSegmentsNative, _VadFreeSegmentsDart>(
            'whisper_vad_free_segments',
          );

      final loadSw = Stopwatch()..start();
      final modelPathC = _vadModelPath.toNativeUtf8();
      final ctxParams = vadDefaultContextParams();
      final vctx = vadInit(modelPathC.cast<ffi.Char>(), ctxParams);
      malloc.free(modelPathC);
      loadSw.stop();
      expect(vctx, isNot(ffi.nullptr), reason: 'VAD model failed to load');
      addTearDown(() => vadFree(vctx));

      final wavBytes = wavFile.readAsBytesSync();
      final samples = pcm16WavBytesToFloat32(wavBytes);
      final samplesPtr = malloc<ffi.Float>(samples.length);
      samplesPtr.asTypedList(samples.length).setAll(0, samples);
      addTearDown(() => malloc.free(samplesPtr));

      final vadParams = vadDefaultParams();

      final detectSw = Stopwatch()..start();
      final segments = vadSegmentsFromSamples(
        vctx,
        vadParams,
        samplesPtr,
        samples.length,
      );
      detectSw.stop();

      final audioDurationMs = (samples.length / 16000 * 1000).round();
      final n = segments == ffi.nullptr ? 0 : vadNSegments(segments);

      print('');
      print('=== vad debug harness ===');
      print('wav: $_wavPath (~${audioDurationMs}ms audio)');
      print(
        'VAD model load: ${loadSw.elapsedMilliseconds}ms  '
        'VAD detect: ${detectSw.elapsedMilliseconds}ms  '
        '(${(detectSw.elapsedMicroseconds / 1000 / (audioDurationMs / 1000)).toStringAsFixed(1)}ms per audio-second)',
      );
      print('speech segments detected: $n');
      for (var i = 0; i < n; i++) {
        // Empirically confirmed (2026-07-29): whisper_vad segment t0/t1 use
        // the same centisecond (10ms) unit as whisper_full_get_segment_t0/t1
        // (see whisper_ffi_engine.dart), NOT raw seconds — a raw value of
        // ~486 against a ~4.8s clip only makes sense as centiseconds.
        final t0 = vadSegmentT0(segments, i) * 10;
        final t1 = vadSegmentT1(segments, i) * 10;
        print(
          '  segment[$i] ${t0.toStringAsFixed(0)}ms-${t1.toStringAsFixed(0)}ms',
        );
      }
      if (n > 0) {
        final lastEnd = vadSegmentT1(segments, n - 1) * 10;
        final trailingSilenceMs = audioDurationMs - lastEnd;
        print(
          'trailing non-speech after last VAD segment: '
          '${trailingSilenceMs.toStringAsFixed(0)}ms of ${audioDurationMs}ms total',
        );
      } else {
        print('no speech detected in the entire clip');
      }
      if (segments != ffi.nullptr) vadFreeSegments(segments);

      expect(true, isTrue); // smoke — this harness is for its stdout output
    },
    timeout: const Timeout(Duration(minutes: 1)),
    skip: available
        ? null
        : 'set --dart-define=WAV=<path> --dart-define=VAD_MODEL=<path> — '
              'see this file\'s doc comment',
  );
}
