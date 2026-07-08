/// Real in-process [WhisperEngine] backed by a bundled `libwhisper` via
/// `dart:ffi` (whisper.cpp v1.8.4). Built on the binding proven in the Issue-01
/// durchstich (`whisper_bindings.dart`, ffigen-generated).
///
/// Threading note (from whisper.h): `whisper_full` is NOT thread-safe for the
/// same context and blocks while decoding. This slice runs it on the calling
/// isolate (as the durchstich did) — moving the heavy call into a worker
/// isolate belongs to the notifier wiring (Issue 03), see the class doc.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/pcm_wav_codec.dart';
import '../../hardware_info_service.dart';
import 'whisper_bindings.dart';
import 'whisper_engine.dart';

/// The conventional bundled library file name per platform. Issue 11 (bundling
/// + signing) resolves this to an absolute in-bundle path; until then
/// [DynamicLibrary.open] relies on the OS loader search path.
String defaultWhisperLibraryName() {
  if (Platform.isMacOS) return 'libwhisper.dylib';
  if (Platform.isWindows) return 'whisper.dll';
  return 'libwhisper.so';
}

/// Loads `libwhisper` in-process and transcribes 16 kHz mono WAV bytes.
///
/// [transcribe] runs synchronously on the calling isolate — acceptable here
/// because this slice does not wire the engine into any UI path. Isolate
/// offload is deferred to Issue 03.
class WhisperFfiEngine implements WhisperEngine {
  WhisperFfiEngine({String? libraryPath, WhisperBackend? backend})
    : _libraryPath = libraryPath ?? defaultWhisperLibraryName(),
      _backend = backend ?? WhisperBackend.cpu;

  final String _libraryPath;
  final WhisperBackend _backend;

  WhisperBindings? _bindings;
  ffi.Pointer<whisper_context>? _ctx;
  String? _errorMessage;

  @override
  WhisperEngineStatus get status => WhisperEngineStatus(
    isLoaded: _ctx != null,
    backend: _backend,
    errorMessage: _errorMessage,
  );

  @override
  Future<void> load({required String modelPath}) async {
    if (_ctx != null) return;

    if (!File(modelPath).existsSync()) {
      _errorMessage = 'whisper_model_not_found';
      throw StateError('whisper_model_not_found: $modelPath');
    }

    try {
      final dylib = ffi.DynamicLibrary.open(_libraryPath);
      final bindings = WhisperBindings.fromLookup(dylib.lookup);
      final cparams = bindings.whisper_context_default_params();
      final pathC = modelPath.toNativeUtf8();
      try {
        final ctx = bindings.whisper_init_from_file_with_params(
          pathC.cast<ffi.Char>(),
          cparams,
        );
        if (ctx == ffi.nullptr) {
          _errorMessage = 'whisper_init_failed';
          throw StateError('whisper_init_from_file_with_params returned null');
        }
        _bindings = bindings;
        _ctx = ctx;
        _errorMessage = null;
      } finally {
        malloc.free(pathC);
      }
    } on StateError {
      rethrow;
    } catch (e) {
      _errorMessage = 'whisper_library_load_failed';
      throw StateError('whisper_library_load_failed: $e');
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    final bindings = _bindings;
    final ctx = _ctx;
    if (bindings == null || ctx == null) {
      throw StateError('whisper_engine_not_loaded');
    }

    final samples = pcm16WavBytesToFloat32(wavBytes);
    if (samples.isEmpty) return '';

    final samplesPtr = malloc<ffi.Float>(samples.length);
    samplesPtr.asTypedList(samples.length).setAll(0, samples);
    final languageC = (language ?? 'auto').toNativeUtf8();
    try {
      final params = bindings.whisper_full_default_params(
        WhisperSamplingStrategy.WHISPER_SAMPLING_GREEDY,
      );
      params.print_progress = false;
      params.print_realtime = false;
      params.print_timestamps = false;
      params.print_special = false;
      params.no_timestamps = true;
      params.translate = false;
      params.language = languageC.cast<ffi.Char>();
      params.n_threads = _threadCount();

      final rc = bindings.whisper_full(ctx, params, samplesPtr, samples.length);
      if (rc != 0) {
        // whisper.cpp reports decode failures as a generic non-zero return
        // without a taxonomy that separates OOM / GPU-fault / transient. Map
        // it to a retryable [WhisperFailureKind.transient] so the notifier's
        // resilience wrapper gets a chance before surfacing. Finer native
        // classification (reading GGML backend error signals for a real OOM
        // vs. GPU abort) is deferred to the hardware-acceptance issues.
        throw WhisperEngineException(
          WhisperFailureKind.transient,
          'whisper_full failed with code $rc',
        );
      }

      final buffer = StringBuffer();
      final segments = bindings.whisper_full_n_segments(ctx);
      for (var i = 0; i < segments; i++) {
        final textPtr = bindings.whisper_full_get_segment_text(ctx, i);
        buffer.write(textPtr.cast<Utf8>().toDartString());
      }
      return buffer.toString();
    } finally {
      malloc.free(samplesPtr);
      malloc.free(languageC);
    }
  }

  @override
  Future<void> unload() async {
    final ctx = _ctx;
    if (ctx != null) {
      _bindings?.whisper_free(ctx);
    }
    _ctx = null;
    _bindings = null;
  }

  static int _threadCount() {
    final cores = Platform.numberOfProcessors;
    return (cores - 1).clamp(2, 8);
  }
}

/// Overrideable [WhisperEngine] for the on-device whisper path.
///
/// Defaults to the real [WhisperFfiEngine], configured with the compute backend
/// derived from hardware detection ([gpuInfoProvider]): NVIDIA→CUDA, Apple→Metal,
/// AMD/Intel→Vulkan, and CPU whenever no compatible GPU is detected (or while
/// detection is still in flight). Tests override it with a fake.
final whisperEngineProvider = Provider<WhisperEngine>((ref) {
  final gpu = ref.watch(gpuInfoProvider).value;
  return WhisperFfiEngine(backend: whisperBackendFromName(gpu?.optimalBackend));
});
