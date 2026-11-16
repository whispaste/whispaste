/// Speech gate in front of both Parakeet backends (libparakeet and sherpa-onnx).
///
/// Parakeet has no built-in voice activity detection, so noise and random
/// bytes come out as short words ("Yeah."). This gate runs the bundled
/// Silero-VAD (`ggml-silero-v5.1.2.bin`, whisper.cpp's `whisper_vad_*` API from
/// `libwhisper`, the same model the Whisper engine uses) and returns "no
/// speech" when it finds no speech segment. The caller then returns an empty
/// transcript, the same way it does for empty audio.
///
/// Fail-open: a missing model or library, a load or inference error, or a
/// call that exceeds [ParakeetSpeechGate.timeout] all mean "speech", so the
/// audio is transcribed as before. The gate can only ever drop a request, never
/// make Parakeet fail.
library;

// Field names mirror the C structs of whisper.h on purpose (snake_case).
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../audio/pcm_wav_codec.dart' show Pcm16WavView;
import '../stt/whisper/whisper_bindings.dart' show whisper_vad_params;
import 'parakeet_gpu_engine.dart'
    show ggmlDeviceCount, loadGgmlBackendModules, openGgmlLibrary;
import '../stt/whisper/whisper_ffi_engine.dart'
    show defaultWhisperLibraryPath, defaultWhisperVadModelPath;

/// Outcome of one VAD check. [unavailable] is fail-open: the audio is
/// transcribed as if [speech] had been found.
enum ParakeetSpeechCheck { speech, noSpeech, unavailable }

/// Maps the number of Silero speech segments (`null` when the VAD could not
/// run) to a check outcome.
ParakeetSpeechCheck parakeetSpeechCheck({required int? segmentCount}) {
  if (segmentCount == null) return ParakeetSpeechCheck.unavailable;
  return segmentCount > 0
      ? ParakeetSpeechCheck.speech
      : ParakeetSpeechCheck.noSpeech;
}

/// Upper bound for one VAD check. Silero needs a few milliseconds for a
/// minute of audio; this only catches a stuck native call.
const Duration parakeetSpeechGateTimeout = Duration(seconds: 5);

/// Whether the audio contains speech, judged by the bundled Silero-VAD.
/// Audio shorter than this (100 ms at 16 kHz) holds no word and is treated as
/// silence. It also keeps such input away from sherpa-onnx: a buffer too short
/// for one feature frame fails its shape check with an uncatchable native
/// abort (0xC0000409 on Windows, measured with a 0-sample WAV).
const int parakeetMinSpeechSamples = 1600;

class ParakeetSpeechGate {
  ParakeetSpeechGate({
    required this.libraryPath,
    required this.modelPath,
    this.timeout = parakeetSpeechGateTimeout,
  });

  /// The gate as the app uses it: libwhisper and the VAD model next to it.
  factory ParakeetSpeechGate.bundled() => ParakeetSpeechGate(
    libraryPath: defaultWhisperLibraryPath(),
    modelPath: defaultWhisperVadModelPath(),
  );

  final String libraryPath;
  final String modelPath;
  final Duration timeout;

  /// Runs the VAD on [samples]. Missing files, errors and timeouts return
  /// [ParakeetSpeechCheck.unavailable].
  Future<ParakeetSpeechCheck> check(Float32List samples) async {
    if (samples.length < parakeetMinSpeechSamples) {
      return ParakeetSpeechCheck.noSpeech;
    }
    if (!File(libraryPath).existsSync() || !File(modelPath).existsSync()) {
      return ParakeetSpeechCheck.unavailable;
    }
    try {
      final count = await Isolate.run(
        () => _countVadSegments(libraryPath, modelPath, samples),
      ).timeout(timeout);
      return parakeetSpeechCheck(segmentCount: count);
    } on Object {
      return ParakeetSpeechCheck.unavailable;
    }
  }

  /// False only when the VAD ran and found no speech. Everything else
  /// (including unavailable) transcribes.
  Future<bool> hasSpeech(Float32List samples) async =>
      await check(samples) != ParakeetSpeechCheck.noSpeech;

  /// [hasSpeech] for a whole recording, checked a window at a time
  /// ([parakeetSpeechGateWindows], #1665), so the recording is never float32
  /// as a whole. Up to [parakeetSpeechGateWindowSeconds] this is one check
  /// on all samples, as before. Stops at the first window that is not
  /// [ParakeetSpeechCheck.noSpeech].
  Future<bool> hasSpeechIn(Pcm16WavView pcm) => hasSpeechInWindows(pcm, check);
}

/// Longest stretch of audio one VAD check gets (3.8 MB as float32).
const int parakeetSpeechGateWindowSeconds = 60;

/// Audio two neighbouring windows share, so speech at a window edge is
/// still seen whole by one of them.
const int parakeetSpeechGateOverlapSeconds = 2;

/// The sample ranges `[start, end)` the gate checks for a recording of
/// [length] samples: one range up to [parakeetSpeechGateWindowSeconds],
/// otherwise windows of that length that overlap by
/// [parakeetSpeechGateOverlapSeconds]; the last one ends at [length].
List<(int, int)> parakeetSpeechGateWindows(
  int length, {
  int sampleRate = 16000,
}) {
  final window = parakeetSpeechGateWindowSeconds * sampleRate;
  final step = window - parakeetSpeechGateOverlapSeconds * sampleRate;
  if (length <= window) return [(0, length)];
  final windows = <(int, int)>[];
  var start = 0;
  while (start + window < length) {
    windows.add((start, start + window));
    start += step;
  }
  windows.add((start, length));
  return windows;
}

/// Runs [check] on each window of [pcm] in turn: false only when every
/// window found no speech.
Future<bool> hasSpeechInWindows(
  Pcm16WavView pcm,
  Future<ParakeetSpeechCheck> Function(Float32List samples) check,
) async {
  for (final (start, end) in parakeetSpeechGateWindows(pcm.sampleCount)) {
    final result = await check(pcm.toFloat32(start, end));
    if (result != ParakeetSpeechCheck.noSpeech) return true;
  }
  return false;
}

// --- FFI for the whisper_vad_* subset ---------------------------------------

/// `struct whisper_vad_context_params` (int, bool, int: 12 bytes).
final class _VadContextParams extends ffi.Struct {
  @ffi.Int32()
  external int n_threads;

  @ffi.Bool()
  external bool use_gpu;

  @ffi.Int32()
  external int gpu_device;
}

typedef _CtxDefaultNative = _VadContextParams Function();
typedef _CtxDefaultDart = _VadContextParams Function();
typedef _VadDefaultNative = whisper_vad_params Function();
typedef _VadDefaultDart = whisper_vad_params Function();
typedef _InitNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, _VadContextParams);
typedef _InitDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, _VadContextParams);
typedef _SegmentsNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      whisper_vad_params,
      ffi.Pointer<ffi.Float>,
      ffi.Int32,
    );
typedef _SegmentsDart =
    ffi.Pointer<ffi.Void> Function(
      ffi.Pointer<ffi.Void>,
      whisper_vad_params,
      ffi.Pointer<ffi.Float>,
      int,
    );
typedef _CountNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _CountDart = int Function(ffi.Pointer<ffi.Void>);
typedef _VoidPtrNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _VoidPtrDart = void Function(ffi.Pointer<ffi.Void>);

/// Runs in a background isolate: opens the library, loads the VAD model,
/// counts speech segments and frees everything again. Returns `null` on any
/// failure. The model is loaded per call (about 0.9 MB), which keeps the gate
/// stateless and makes a stuck call harmless.
int? _countVadSegments(
  String libraryPath,
  String modelPath,
  Float32List samples,
) {
  final lib = ffi.DynamicLibrary.open(libraryPath);
  final ctxDefault = lib.lookupFunction<_CtxDefaultNative, _CtxDefaultDart>(
    'whisper_vad_default_context_params',
  )();
  final vadDefault = lib.lookupFunction<_VadDefaultNative, _VadDefaultDart>(
    'whisper_vad_default_params',
  );
  final init = lib.lookupFunction<_InitNative, _InitDart>(
    'whisper_vad_init_from_file_with_params',
  );
  final segmentsFromSamples = lib
      .lookupFunction<_SegmentsNative, _SegmentsDart>(
        'whisper_vad_segments_from_samples',
      );
  final segmentCount = lib.lookupFunction<_CountNative, _CountDart>(
    'whisper_vad_segments_n_segments',
  );
  final freeSegments = lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
    'whisper_vad_free_segments',
  );
  final freeContext = lib.lookupFunction<_VoidPtrNative, _VoidPtrDart>(
    'whisper_vad_free',
  );

  // whisper_vad_init needs a CPU backend device. Backends are loaded from
  // modules next to libggml, so load them if nothing has registered one yet
  // (libparakeet or the Whisper engine may already have done it).
  final dir = p.dirname(libraryPath);
  final ggml = openGgmlLibrary(dir);
  if (ggml != null && (ggmlDeviceCount(ggml, dir) ?? 0) == 0) {
    loadGgmlBackendModules(ggml, dir);
  }

  // CPU only: the VAD is tiny, and the GPU belongs to the transcriber.
  ctxDefault.n_threads = 1;
  ctxDefault.use_gpu = false;
  ctxDefault.gpu_device = 0;

  final pathC = modelPath.toNativeUtf8();
  final pcm = calloc<ffi.Float>(samples.length);
  ffi.Pointer<ffi.Void> ctx = ffi.nullptr;
  try {
    pcm.asTypedList(samples.length).setAll(0, samples);
    ctx = init(pathC, ctxDefault);
    if (ctx == ffi.nullptr) return null;
    final segments = segmentsFromSamples(
      ctx,
      vadDefault(),
      pcm,
      samples.length,
    );
    if (segments == ffi.nullptr) return null;
    try {
      return segmentCount(segments);
    } finally {
      freeSegments(segments);
    }
  } on Object {
    return null;
  } finally {
    if (ctx != ffi.nullptr) freeContext(ctx);
    malloc.free(pathC);
    calloc.free(pcm);
  }
}
