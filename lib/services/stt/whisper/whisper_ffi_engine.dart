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
import 'package:path/path.dart' as p;

import '../../audio/pcm_wav_codec.dart';
import '../../hardware_info_service.dart';
import 'whisper_bindings.dart';
import 'whisper_engine.dart';

/// Absolute path to the `libwhisper` shared library bundled next to the running
/// app, per platform. `libwhisper` (plus its `ggml*` backends) is embedded and
/// signed into each platform bundle at build time (ADR-01, Option C) — never
/// downloaded at runtime (Apple Guideline 2.5.2) — and resolved here relative to
/// [Platform.resolvedExecutable] so the OS loader finds the co-located backends
/// via each dylib's `@loader_path`/`$ORIGIN` rpath.
String defaultWhisperLibraryPath() =>
    whisperLibraryPathFor(Platform.resolvedExecutable);

/// Pure resolver behind [defaultWhisperLibraryPath], split out for unit tests
/// (the runtime path depends on [Platform.resolvedExecutable], which a test
/// cannot set). Given the app [executablePath], returns the bundled library
/// path for the current OS:
/// - macOS: `<App>.app/Contents/MacOS/<exe>` → `../Frameworks/libwhisper.dylib`
///   (embedded via the "[WP] Embed & Sign libwhisper" Xcode phase).
/// - Windows: `whisper.dll` next to `whispaste.exe` (Flutter bundle root).
/// - Linux: `lib/libwhisper.so` next to the executable (Flutter bundle layout).
String whisperLibraryPathFor(String executablePath) {
  final execDir = p.dirname(executablePath);
  if (Platform.isMacOS) {
    return p.normalize(p.join(execDir, '..', 'Frameworks', 'libwhisper.dylib'));
  }
  if (Platform.isWindows) {
    return p.join(execDir, 'whisper.dll');
  }
  return p.join(execDir, 'lib', 'libwhisper.so');
}

/// Windows only: makes the OS loader search [libraryPath]'s own directory
/// when resolving `whisper.dll`'s transitive dependencies (the bundled
/// `ggml*.dll` backends).
///
/// Verified during v1.2.45 release prep: a bare `DynamicLibrary.open()` on
/// the bundled `whisper.dll` fails with Win32 error 126 ("The specified
/// module could not be found") even with every `ggml*.dll` sitting right
/// next to it — the default search order only covers the directory of the
/// original EXE for a DEPENDENCY's own dependencies, not the directory of
/// each intermediate DLL in the chain. `SetDllDirectoryW` adds that
/// directory to the search path used for those transitive lookups.
/// macOS/Linux don't need this — their `@loader_path`/`$ORIGIN` rpaths,
/// embedded into the dylibs/.so at build time, already cover it.
void _ensureWindowsDllSearchPath(String libraryPath) {
  if (!Platform.isWindows) return;
  final kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
  final setDllDirectoryW = kernel32
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf16>),
        int Function(ffi.Pointer<Utf16>)
      >('SetDllDirectoryW');
  final dirPointer = p.dirname(libraryPath).toNativeUtf16();
  try {
    setDllDirectoryW(dirPointer);
  } finally {
    malloc.free(dirPointer);
  }
}

/// Loads `libwhisper` in-process and transcribes 16 kHz mono WAV bytes.
///
/// [transcribe] runs synchronously on the calling isolate — acceptable here
/// because this slice does not wire the engine into any UI path. Isolate
/// offload is deferred to Issue 03.
class WhisperFfiEngine implements WhisperEngine {
  WhisperFfiEngine({String? libraryPath, WhisperBackend? backend})
    : _libraryPath = libraryPath ?? defaultWhisperLibraryPath(),
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
      _ensureWindowsDllSearchPath(_libraryPath);
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
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
  }) async {
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
    // Only allocate a native prompt buffer when there is something to bias
    // decoding with — the FFI struct defaults `initial_prompt` to a null
    // pointer, which whisper.cpp already treats as "no prompt".
    final hasPrompt = prompt != null && prompt.isNotEmpty;
    final promptC = hasPrompt ? prompt.toNativeUtf8() : null;
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
      if (promptC != null) {
        params.initial_prompt = promptC.cast<ffi.Char>();
      }

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
      if (promptC != null) malloc.free(promptC);
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
