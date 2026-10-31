/// Real in-process [WhisperEngine] backed by a bundled `libwhisper` via
/// `dart:ffi` (whisper.cpp v1.9.5). Built on the binding proven in the Issue-01
/// durchstich (`whisper_bindings.dart`, ffigen-generated).
///
/// Threading note (from whisper.h): `whisper_full` is NOT thread-safe for the
/// same context and blocks while decoding. Production code never talks to
/// this class directly — [whisperEngineProvider] (`whisper_isolate_engine.dart`)
/// runs it inside a dedicated worker isolate to keep the UI thread free.
///
/// FLUTTER_WHISPASTE-BB root cause (confirmed via WinDbg against a real crash
/// on Windows): the bundled libwhisper is built with `-DGGML_BACKEND_DL=ON`
/// (dynamic backend loading, needed for hardware-inclusivity — see
/// `scripts/bundle-libwhisper-windows.ps1`). With that flag, ggml registers
/// *zero* backends — not even CPU — until the host application explicitly
/// calls `ggml_backend_load_all()`; whisper.cpp itself never calls it. This
/// engine never called it either, so `whisper_init_from_file_with_params`
/// always ran against an empty backend registry. whisper.cpp's own CPU-extra
/// lookup (`ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU)` at
/// whisper.cpp:1388) then returns null, and the very next line
/// (`ggml_backend_dev_backend_reg(cpu_dev)`, :1389) has no null check —
/// unlike every other call site of that function — so `GGML_ASSERT(device)`
/// fires and calls `abort()`, which Windows reports as a fail-fast exception
/// (misleadingly decoded as "stack buffer overrun", 0xC0000409 — nothing to
/// do with actual stack size). [_ensureBackendsLoaded] fixes this at the
/// source instead of working around the crash.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/windows_dll_search_path.dart';
import '../../audio/pcm_wav_codec.dart';
import '../../transcription/continuity_guard.dart' as continuity;
import '../../transcription/transcript_seam.dart' as seam;
import '../native_call_guard.dart';
import 'ggml_backend_registry.dart';
import 'whisper_bindings.dart';
import 'whisper_language_probe.dart';
import 'whisper_engine.dart';

final _log = AppLogger('WhisperFfi');

/// Native signature of `whisper_full_params.new_segment_callback` ("called
/// for every newly generated text segment", `whisper_bindings.dart`) — used
/// to register the live/partial-transcript callback (ticket 11) per
/// [WhisperFfiEngine._decodeOnce] call. Not in the ffigen-generated
/// `whisper_bindings.dart` (do-not-edit) itself, only the struct field's
/// inline type is, so a matching typedef lives here instead.
typedef WhisperNewSegmentCallbackNative =
    ffi.Void Function(
      ffi.Pointer<whisper_context> ctx,
      ffi.Pointer<whisper_state> state,
      ffi.Int nNew,
      ffi.Pointer<ffi.Void> userData,
    );

/// Native signature of `whisper_full_params.progress_callback` (IMP-PROG-2).
/// whisper.cpp passes an integer percentage `0..100` of the current
/// `whisper_full` call. Registered per call in [WhisperFfiEngine._decodeOnce]
/// and closed only after `whisper_full` has returned (WP-48).
typedef WhisperProgressCallbackNative =
    ffi.Void Function(
      ffi.Pointer<whisper_context> ctx,
      ffi.Pointer<whisper_state> state,
      ffi.Int progress,
      ffi.Pointer<ffi.Void> userData,
    );

/// One cut of a long recording (see `WhisperFfiEngine.findPauseSplits`): the
/// cut at [sample], and whether it is a [hard] cut because no pause was found
/// before the chunk limit. A hard cut's chunks overlap by 2 s, and the repeated
/// words are removed from the text seam.
class WhisperPauseSplit {
  const WhisperPauseSplit(this.sample, {this.hard = false});

  final int sample;
  final bool hard;
}

/// Overlap at a hard cut: 2 s of audio, repeated at the start of the next chunk.
const int _hardCutOverlapSamples = 2 * WHISPER_SAMPLE_RATE;

/// Overall fraction `0..1` of a transcription split into [chunkCount] chunks,
/// given the fraction [withinChunk] (`0..1`) of the chunk at [chunkIndex].
/// Chunks are weighted equally, so the result rises monotonically from 0
/// (first chunk, nothing done) to 1 (last chunk, complete). Inputs outside
/// their range are clamped.
@visibleForTesting
double chunkedProgressFraction({
  required int chunkIndex,
  required int chunkCount,
  required double withinChunk,
}) {
  if (chunkCount <= 0) return 0;
  final index = chunkIndex.clamp(0, chunkCount - 1);
  final within = withinChunk.isFinite ? withinChunk.clamp(0.0, 1.0) : 0.0;
  return ((index + within) / chunkCount).clamp(0.0, 1.0);
}

/// Absolute path to the `libwhisper` shared library bundled next to the running
/// app, per platform. `libwhisper` (plus its `ggml*` backends) is embedded and
/// signed into each platform bundle at build time (ADR-01, Option C) — never
/// downloaded at runtime (Apple Guideline 2.5.2) — and resolved here relative to
/// [Platform.resolvedExecutable] so the OS loader finds the co-located backends
/// via each dylib's `@loader_path`/`$ORIGIN` rpath.
String defaultWhisperLibraryPath() =>
    whisperLibraryPathFor(Platform.resolvedExecutable);

/// Whether `wp_ffi_guard` next to [libraryPath] can wrap whisper's calls:
/// present, ABI-compatible and built against the bundled `whisper.h` struct
/// layouts (Befund 28). Backend selection reads this before any load, see
/// `selectWhisperBackend` and [WhisperFfiEngine.load].
bool whisperGuardUsableFor(String libraryPath) =>
    NativeCallGuard.nextTo(libraryPath)?.supportsWhisperStructs ?? false;

/// The CPU module loaded without a guard (see `_loadBackendModules`). Without
/// the guard nothing can be scored, and a higher variant (AVX2, apple_m4, ...)
/// can die with SIGILL on an older CPU. So only the baseline variant that runs
/// on every CPU of its architecture is named here. `null` = none present.
String? cpuBaselineModuleFor(Iterable<String> fileNames, {required String os}) {
  final prefix = switch (os) {
    'macos' => 'libggml-cpu-apple_m1.',
    'linux' => 'libggml-cpu-x64.',
    'windows' => 'ggml-cpu-x64.',
    _ => null,
  };
  if (prefix == null) return null;
  for (final name in fileNames) {
    if (name.startsWith(prefix)) return name;
  }
  return null;
}

/// `ggml_backend_load(const char * path)` (ggml-backend-reg.cpp), used only by
/// the unguarded baseline CPU load in `_loadBaselineCpuWithoutGuard`.
typedef _GgmlBackendLoadNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8> path);
typedef _GgmlBackendLoad =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8> path);

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

/// Absolute path to the bundled Silero-VAD ggml model (see
/// `assets/models/vad/NOTICE.md`), resolved the same way and bundled
/// alongside `libwhisper` itself at build time (`macos/embed_libwhisper.sh`,
/// `scripts/bundle-libwhisper-windows.ps1`,
/// `scripts/build-libwhisper-linux.sh`) — not downloaded at runtime, since
/// unlike the multi-gigabyte STT models it is a single fixed <1MB file. May
/// not exist on a checkout that hasn't run the platform bundling step yet;
/// callers (see [WhisperFfiEngine.load]) treat a missing file as "VAD
/// unavailable this session", never an error.
String defaultWhisperVadModelPath() =>
    whisperVadModelPathFor(Platform.resolvedExecutable);

/// Pure resolver behind [defaultWhisperVadModelPath], split out for unit
/// tests for the same reason as [whisperLibraryPathFor].
String whisperVadModelPathFor(String executablePath) {
  final libraryDir = p.dirname(whisperLibraryPathFor(executablePath));
  return p.join(libraryDir, whisperVadModelFileName);
}

/// File name of the bundled Silero-VAD model, next to the whisper library.
const String whisperVadModelFileName = 'ggml-silero-v5.1.2.bin';

/// One segment whisper.cpp emitted for a [WhisperFfiEngine.transcribe] call.
///
/// [startMs]/[endMs] are `null` unless that call passed
/// `includeTimestamps: true` — see [WhisperFfiEngine.transcribe]'s doc
/// comment for why they're otherwise meaningless sentinels rather than real
/// timestamps — or if the bundled `libwhisper` predates the
/// `whisper_full_get_segment_t0/t1` symbols (see
/// [WhisperFfiEngine._resolveSegmentTimestampLookups]).
class WhisperSegment {
  const WhisperSegment({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.noSpeechProb,
  });

  final int index;
  final int? startMs;
  final int? endMs;
  final String text;

  /// whisper.cpp's own per-segment confidence that this segment contains no
  /// real speech (`whisper_full_get_segment_no_speech_prob`), `0.0`–`1.0`.
  /// Unlike t0/t1, this is populated on every [WhisperFfiEngine.transcribe]
  /// call regardless of `includeTimestamps` — it isn't gated behind
  /// `no_timestamps` in whisper.cpp. `null` only if the bundled `libwhisper`
  /// predates the symbol.
  final double? noSpeechProb;

  @override
  String toString() {
    final ts = startMs != null ? ' ${startMs}ms-${endMs}ms' : '';
    final nsp = noSpeechProb != null
        ? ' noSpeechProb=${noSpeechProb!.toStringAsFixed(3)}'
        : '';
    return 'WhisperSegment[$index]$ts$nsp: $text';
  }
}

/// Loads `libwhisper` in-process and transcribes 16 kHz mono WAV bytes.
///
/// [transcribe] runs synchronously on the calling isolate — acceptable here
/// because this slice does not wire the engine into any UI path. Isolate
/// offload is deferred to Issue 03.
class WhisperFfiEngine
    implements
        WhisperEngine,
        PartialTranscriptSource,
        DetectedLanguageSource,
        LivePreviewEngine,
        PromptTokenCounter {
  WhisperFfiEngine({
    String? libraryPath,
    WhisperBackend? backend,
    this._cudaPackDir,
  }) : _libraryPath = libraryPath ?? defaultWhisperLibraryPath(),
       _backend = backend ?? WhisperBackend.cpu,
       _confirmedBackend = backend ?? WhisperBackend.cpu;

  final String _libraryPath;
  final WhisperBackend _backend;

  /// Directory of an installed optional CUDA pack (`ggml-cuda` plus the
  /// CUDA runtime libraries, see `cuda_pack.dart`), or `null` when none is
  /// installed or the user switched it off. When set and a GPU backend is
  /// requested, [load] registers the module with ggml and prefers its
  /// `CUDA0` device over Vulkan — see [_ensureCudaPackLoaded].
  final String? _cudaPackDir;

  /// [_backend] as actually confirmed against ggml's device registry by
  /// [_confirmBackend] — see its doc comment. Equals [_backend] until the
  /// first [load] call.
  WhisperBackend _confirmedBackend;

  WhisperBindings? _bindings;
  ffi.Pointer<whisper_context>? _ctx;

  /// `wp_ffi_guard` next to [_libraryPath], set by [load] — `null` when it
  /// is missing or built against other struct layouts. The throwing entry
  /// points are then called directly, and [load] runs CPU only (Befund 28,
  /// see [backendAllowedByGuard]). See `native_call_guard.dart`.
  NativeCallGuard? _guard;

  /// Raw addresses of the entry points routed through [_guard].
  ffi.Pointer<ffi.Void> _initStateFn = ffi.nullptr;
  ffi.Pointer<ffi.Void> _fullFn = ffi.nullptr;
  ffi.Pointer<ffi.Void> _fullWithStateFn = ffi.nullptr;

  /// Whether [load] routes whisper's throwing entry points through
  /// `wp_ffi_guard`.
  @visibleForTesting
  bool get usesNativeCallGuard => _guard != null;
  String? _errorMessage;

  /// See [WhisperEngineStatus.cpuFeatures]; set by [load].
  String? _cpuFeatures;

  /// See [WhisperEngineStatus.gpuDevice]; set by [load].
  String? _gpuDevice;

  /// Resolved path to the bundled Silero-VAD ggml model, set by [load].
  /// `null` means VAD is unavailable this session (path not resolved / not
  /// bundled on this platform yet) — [transcribe]'s `vadEnabled` is then a
  /// no-op regardless of its value, never an error.
  String? _vadModelPath;

  /// Raw lookups for `whisper_full_get_segment_t0/t1` — not covered by the
  /// ffigen-generated [WhisperBindings] (`whisper_bindings.dart`, do-not-edit).
  /// Resolved once in [load]; `null` if the symbol is missing from an older
  /// bundled `libwhisper` build, in which case [_logSegments] degrades to
  /// segment count + text length only. Diagnostic-only — see [_logSegments].
  int Function(ffi.Pointer<whisper_context>, int)? _segmentT0;
  int Function(ffi.Pointer<whisper_context>, int)? _segmentT1;

  /// Raw lookup for `whisper_full_get_segment_no_speech_prob` — same
  /// not-in-[WhisperBindings] situation as [_segmentT0]/[_segmentT1].
  double Function(ffi.Pointer<whisper_context>, int)? _segmentNoSpeechProb;

  /// Raw lookups for `whisper_full_lang_id` and `whisper_lang_str`, same
  /// not-in-[WhisperBindings] situation as [_segmentT0]. `null` on a build
  /// without them; the detected language is then simply unknown.
  int Function(ffi.Pointer<whisper_context>)? _fullLangId;
  ffi.Pointer<ffi.Char> Function(int)? _langStr;

  String? _lastDetectedLanguage;

  @override
  String? get lastDetectedLanguage => _lastDetectedLanguage;

  /// Per-segment breakdown of the most recent [transcribe] call. Populated
  /// by [_logSegments]; empty before the first call or if the last call
  /// failed before segment assembly. Exposed (read-only) so diagnostic
  /// tooling — see `test/services/stt/whisper/transcribe_debug_harness_test.dart`
  /// — can inspect segment boundaries/text directly without depending on
  /// [AppLogger] being initialized. Not used by any production call site.
  List<WhisperSegment> get lastSegments => List.unmodifiable(_lastSegments);
  List<WhisperSegment> _lastSegments = const [];

  // ── Live/partial transcript (ticket 11) ──────────────────────────────────
  //
  // whisper.cpp's `new_segment_callback` (set per-call on `whisper_full_
  // params`, not globally like `whisper_log_set`) fires synchronously on
  // this same isolate's thread once for every newly completed segment
  // *during* a `whisper_full` call — see [_decodeOnce]. `.isolateLocal` (not
  // `.listener`, unlike [installProcessLogForwarder]'s ggml log callback)
  // is correct and safe here because the callback only ever fires on the
  // thread that is blocked inside `whisper_full`, i.e. this isolate's own —
  // there is no cross-thread hazard to guard against.
  final StreamController<String> _partialController =
      StreamController<String>.broadcast();

  @override
  Stream<String> get partialTranscript => _partialController.stream;

  /// Text already produced by earlier chunks of the CURRENT [transcribe]
  /// call ([_transcribeInChunks] splits long recordings at pauses — see its
  /// doc comment). Reset to `''` at the top of [transcribe]; advanced after
  /// each chunk's [_decodeOnce] completes. The in-flight chunk's own
  /// progressively-growing text is appended to this prefix by
  /// [_emitPartialTranscript] on every `new_segment_callback` firing, so a
  /// listener always sees the whole transcript-so-far, not just the current
  /// chunk's.
  String _partialPrefix = '';

  /// Joins every segment decoded so far in [ctx] onto [_partialPrefix] and
  /// broadcasts it — the `new_segment_callback` body. Mirrors exactly how
  /// [_decodeOnce] itself joins segments into its final return value, so a
  /// listener's last event before completion equals that chunk's result.
  void _emitPartialTranscript(
    WhisperBindings bindings,
    ffi.Pointer<whisper_context> ctx,
  ) {
    if (!_partialController.hasListener) return;
    final buffer = StringBuffer(_partialPrefix);
    final n = bindings.whisper_full_n_segments(ctx);
    for (var i = 0; i < n; i++) {
      final textPtr = bindings.whisper_full_get_segment_text(ctx, i);
      buffer.write(textPtr.cast<Utf8>().toDartString());
    }
    _partialController.add(buffer.toString());
  }

  @override
  WhisperEngineStatus get status => WhisperEngineStatus(
    isLoaded: _ctx != null,
    backend: _confirmedBackend,
    errorMessage: _errorMessage,
    cpuFeatures: _cpuFeatures,
    gpuDevice: _gpuDevice,
  );

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    if (_ctx != null) return;

    if (!File(modelPath).existsSync()) {
      _errorMessage = 'whisper_model_not_found';
      throw StateError('whisper_model_not_found: $modelPath');
    }
    // Deliberately not an error if missing — VAD is an opt-in quality
    // improvement (see [transcribe]'s `vadEnabled`), not a hard dependency;
    // a missing/not-yet-bundled VAD model degrades to today's behaviour.
    _vadModelPath = (vadModelPath != null && File(vadModelPath).existsSync())
        ? vadModelPath
        : null;

    try {
      ensureWindowsDllSearchPath(_libraryPath);
      final dylib = ffi.DynamicLibrary.open(_libraryPath);
      final ggml = _registryFor(_libraryPath);
      // Befund 28 (Maintainer 10a): without a usable guard no GPU module is
      // loaded and no GPU device is initialised, because whisper_init would
      // run that vendor code unguarded. The load is then CPU only; the CPU
      // module itself is still loaded through the guard when one is present.
      final guardUsable = whisperGuardUsableFor(_libraryPath);
      final wanted = backendAllowedByGuard(_backend, guardUsable: guardUsable);
      if (wanted != _backend) {
        _log.warning(
          'GPU backend ${_backend.name} not initialised: wp_ffi_guard is '
          'missing or built against other whisper.h struct layouts, so a GPU '
          'init could not be caught. Loading on CPU.',
        );
      }
      // A backend module that throws (caught by the guard) must not take the
      // process down: the load goes on with CPU and the reason in the log.
      final backendFailure = _ensureBackendsLoaded(
        dylib,
        _libraryPath,
        cpuOnly: wanted == WhisperBackend.cpu,
      );
      if (backendFailure != null) {
        _log.warning(
          'GPU backend unavailable, loading on CPU: $backendFailure',
        );
      }
      final requested = backendFailure == null ? wanted : WhisperBackend.cpu;
      final cudaPackDir = _cudaPackDir;
      if (cudaPackDir != null && requested != WhisperBackend.cpu) {
        _ensureCudaPackLoaded(dylib, cudaPackDir, _libraryPath);
      }
      final (backend, gpuDevice, gpuIndex) = _confirmBackend(
        dylib,
        requested,
        preferCuda: cudaPackDir != null,
        ggml: ggml,
      );
      _confirmedBackend = backend;
      _gpuDevice = gpuDevice;
      if (!_hasCpuDevice(dylib, ggml)) {
        // whisper_init would dereference the null CPU device and abort.
        _errorMessage = 'whisper_no_cpu_backend';
        throw StateError(
          'whisper_no_cpu_backend: ggml registered no CPU device',
        );
      }
      final bindings = WhisperBindings.fromLookup(dylib.lookup);
      _cpuFeatures = _readCpuFeatures(dylib, ggml);
      _resolveSegmentTimestampLookups(dylib);
      _resolveLanguageLookups(dylib);
      final guard = NativeCallGuard.nextTo(_libraryPath);
      _guard = guard != null && guard.supportsWhisperStructs ? guard : null;
      _initStateFn = dylib.lookup<ffi.Void>('whisper_init_state');
      _fullFn = dylib.lookup<ffi.Void>('whisper_full');
      _fullWithStateFn = dylib.lookup<ffi.Void>('whisper_full_with_state');
      final cparams = bindings.whisper_context_default_params();
      cparams.use_gpu = _confirmedBackend != WhisperBackend.cpu;
      cparams.gpu_device = gpuIndex;
      final pathC = modelPath.toNativeUtf8();
      try {
        final ffi.Pointer<whisper_context> ctx;
        try {
          ctx = _guard != null
              ? _guard!.whisperInitFromFile(
                  dylib.lookup<ffi.Void>('whisper_init_from_file_with_params'),
                  pathC.cast<ffi.Char>(),
                  cparams,
                )
              : bindings.whisper_init_from_file_with_params(
                  pathC.cast<ffi.Char>(),
                  cparams,
                );
        } on NativeCallException catch (e) {
          // E.g. ggml-vulkan's vk::SystemError while creating the device
          // (Sentry 140866975/151627808) — previously a process abort. A
          // StateError lets SttServerStateNotifier retry the load on CPU.
          _log.warning('whisper_init threw natively: ${e.message}');
          _errorMessage = 'whisper_init_failed';
          throw StateError('whisper_init_failed: ${e.message}');
        }
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
    } finally {
      drainNativeLog(_libraryPath);
    }
  }

  /// Registers ggml's backends exactly as [load] does and returns the CPU
  /// backend's features (see [cpuBackendFeaturesFromSystemInfo]) without
  /// loading a model — `null` when no CPU backend was registered. Used by
  /// `whispaste --diagnose` to prove a package's backend modules are found.
  static String? probeCpuBackend(ffi.DynamicLibrary dylib, String libraryPath) {
    _ensureBackendsLoaded(dylib, libraryPath);
    return _readCpuFeatures(dylib, _registryFor(libraryPath));
  }

  /// Reads which CPU backend variant ggml loaded (see
  /// [cpuBackendFeaturesFromSystemInfo]) and logs it once per load, so
  /// both the app log and the In-App-Diagnostik show it. Never throws —
  /// a library without the call just reports nothing.
  static String? _readCpuFeatures(
    ffi.DynamicLibrary dylib,
    GgmlBackendRegistry ggml,
  ) {
    try {
      final info = ggml.printSystemInfo(dylib);
      if (info == null) {
        _log.info('whisper_print_system_info is not exported');
        return null;
      }
      final features = cpuBackendFeaturesFromSystemInfo(info);
      _log.info('ggml CPU backend features: ${features ?? '(none reported)'}');
      return features;
    } on Object catch (e) {
      _log.warning('whisper_print_system_info failed: $e');
      return null;
    }
  }

  static bool _logForwarderInstalled = false;

  /// Routes ggml/whisper.cpp's internal logging into the native ring buffer
  /// of `wp_ffi_guard` (`wpg_log_sink`, `native/ffi_guard/ffi_guard.cpp`)
  /// instead of its stderr default — a console-less Windows GUI/MSIX process
  /// has no guaranteed-valid stderr handle (FLUTTER_WHISPASTE-BB).
  ///
  /// There is no Dart callback in this path any more. The earlier
  /// `NativeCallable.listener` (WP-48) was closed with its isolate: ggml kept
  /// the pointer, and a line logged after a worker isolate had ended — or
  /// logged from a backend module during a load in a fresh worker — called
  /// into a dead Dart callback and aborted the VM (`dart::Assert::Fail`,
  /// Sentry 153865283). The sink is plain C++ and cannot call into Dart; the
  /// lines are fetched by [drainNativeLog] on whatever isolate runs a load.
  ///
  /// Idempotent per process. Without the guard library ggml keeps logging to
  /// stderr (the pre-guard behaviour).
  static void installProcessLogForwarder(String libraryPath) {
    if (_logForwarderInstalled) return;
    _logForwarderInstalled = true;
    try {
      ensureWindowsDllSearchPath(libraryPath);
      final guard = NativeCallGuard.nextTo(libraryPath);
      if (guard == null) {
        _log.warning(
          'ggml log forwarding not installed: wp_ffi_guard missing — '
          'ggml logs to stderr',
        );
        return;
      }
      final dylib = ffi.DynamicLibrary.open(libraryPath);
      guard.installLogSink(dylib.lookup<ffi.Void>('whisper_log_set'));
    } catch (e) {
      _log.warning('ggml log forwarding not installed: $e');
    }
  }

  /// Moves every ggml/whisper line buffered natively since the last drain
  /// into the app log. Safe on any isolate (the buffer is process-wide) and
  /// never throws. Called at the end of each [WhisperFfiEngine.load].
  static void drainNativeLog(String libraryPath) {
    final guard = NativeCallGuard.nextTo(libraryPath);
    if (guard == null) return;
    // These lines never carry dictated text. whisper.cpp prints segment text
    // only under print_realtime, with printf, not through the log callback
    // that fills this ring. Both whisper_full call sites in this file set
    // print_realtime, print_progress, print_timestamps and print_special to
    // false, so the callback carries model, backend and error metadata only.
    // The allowlist entry for `text` in no_transcript_in_logs_test.dart
    // refers to this reasoning.
    try {
      for (final line in guard.drainLog()) {
        if (line.level >= 4) {
          _log.warning('native ggml/whisper: ${line.text}');
        } else {
          _log.debug('native ggml/whisper: ${line.text}');
        }
      }
      final dropped = guard.takeDroppedLogLines();
      if (dropped > 0) {
        _log.warning('$dropped native ggml/whisper log lines dropped');
      }
    } on Object catch (e) {
      _log.debug('native log drain failed: $e');
    }
  }

  /// Process-wide state of the backend registration, see [_ensureBackendsLoaded].
  /// Read and written through `wp_ffi_guard` when it is present (a Dart static
  /// is per isolate, and every worker isolate starts with it cleared); the
  /// static is the fallback without the guard.
  static const int _backendsNone = 0;
  static const int _backendsCpuOnly = 1;
  static const int _backendsAll = 2;
  static const int _backendsFailed = 3;
  static int _backendsState = _backendsNone;

  static int _readBackendsState(NativeCallGuard? guard) =>
      guard?.processFlag(WpgFlag.backends) ?? _backendsState;

  static void _writeBackendsState(NativeCallGuard? guard, int state) {
    guard?.setProcessFlag(WpgFlag.backends, state);
    _backendsState = state;
  }

  /// The [GgmlBackendRegistry] for [libraryPath]: guarded when `wp_ffi_guard`
  /// is bundled next to it.
  static GgmlBackendRegistry _registryFor(String libraryPath) =>
      GgmlBackendRegistry(NativeCallGuard.nextTo(libraryPath));

  /// Registers ggml's dynamically loaded backends — once per PROCESS, not per
  /// isolate — see the file doc comment for why this is required at all with
  /// `-DGGML_BACKEND_DL=ON`.
  ///
  /// Scans [libraryPath]'s own directory via
  /// `ggml_backend_load_all_from_path` — that is where every build script
  /// stages the backend modules (`ggml-cpu-*.dll`/`libggml-cpu-*.so`,
  /// `ggml-vulkan`). The argument-less `ggml_backend_load_all()` only scans
  /// the executable's directory and the CWD: identical to [libraryPath]'s
  /// directory on Windows, but on Linux the modules live in `<bundle>/lib/`
  /// next to `libwhisper.so`, one level below the executable — so ggml found
  /// no backend at all there (not even CPU) and whisper.cpp aborted on its
  /// null CPU device. `ggml_backend_load_all()` stays as the fallback for an
  /// older bundled library without the `_from_path` export.
  ///
  /// The registry is process-wide, so a second isolate that loads again would
  /// only re-scan the same modules. Each isolate still re-resolves the ggml
  /// library handles it needs ([_resolvedGgmlLibrary], [_ggmlBaseLibrary]) —
  /// those are per isolate.
  ///
  /// With [cpuOnly] (the user chose "Nur CPU") only the CPU module is loaded,
  /// see [_loadBestCpuModule]: loading the GPU modules would initialise GPU
  /// drivers (Vulkan/CUDA device enumeration) that a CPU-only run never uses.
  /// A full load still happens later if a GPU engine is needed in the same
  /// process; a CPU-only load never blocks it.
  ///
  /// Returns `null` when the backends this request needs are registered, or
  /// the reason they are not. A backend module that throws is caught by the
  /// guard, so the process survives; the caller then runs on CPU with the
  /// reason in the log. The failure is recorded process-wide, so later
  /// isolates do not retry the module that threw.
  static String? _ensureBackendsLoaded(
    ffi.DynamicLibrary dylib,
    String libraryPath, {
    bool cpuOnly = false,
  }) {
    final guard = NativeCallGuard.nextTo(libraryPath);
    final registry = GgmlBackendRegistry(guard);
    var resolved = dylib;
    if (!dylib.providesSymbol('ggml_backend_load_all')) {
      final ggmlName = Platform.isWindows
          ? 'ggml.dll'
          : (Platform.isMacOS ? 'libggml.dylib' : 'libggml.so');
      final ggmlPath = p.join(p.dirname(libraryPath), ggmlName);
      if (!File(ggmlPath).existsSync()) return null;
      resolved = ffi.DynamicLibrary.open(ggmlPath);
    }
    final state = _readBackendsState(guard);
    String? failure;
    if (state == _backendsFailed) {
      failure = 'ggml backend load failed earlier in this process';
    } else if (!(state == _backendsAll ||
        (state == _backendsCpuOnly && cpuOnly))) {
      failure = _loadBackendModules(
        registry,
        resolved,
        p.dirname(libraryPath),
        cpuOnly: cpuOnly,
        guard: guard,
      );
    }
    _resolvedGgmlLibrary = resolved;
    // The per-device accessors (`ggml_backend_dev_type`/`_name`) live in
    // ggml-base.dll, and unlike dlsym on Linux, GetProcAddress does not
    // search a DLL's imports — so [_confirmBackend] needs its own handle.
    final basePath = p.join(p.dirname(libraryPath), 'ggml-base.dll');
    if (Platform.isWindows && File(basePath).existsSync()) {
      _ggmlBaseLibrary = ffi.DynamicLibrary.open(basePath);
    }
    return failure;
  }

  /// Does the actual registration for [_ensureBackendsLoaded]; returns the
  /// failure reason, or `null` on success.
  static String? _loadBackendModules(
    GgmlBackendRegistry registry,
    ffi.DynamicLibrary lib,
    String libraryDir, {
    required bool cpuOnly,
    required NativeCallGuard? guard,
  }) {
    // Without the guard no backend module is opened at all: loading one
    // unguarded could abort the process (see ggml_backend_registry.dart).
    // Maintainer decision 12a (2026-10-25): without the guard the baseline CPU
    // module is still loaded, unguarded, so transcription runs on CPU. GPU
    // modules stay out (only the CPU baseline is ever named here).
    if (guard == null) {
      return _loadBaselineCpuWithoutGuard(lib, libraryDir);
    }
    try {
      if (cpuOnly && _loadBestCpuModule(registry, lib, libraryDir)) {
        // Only the CPU backend is registered; the GPU modules stay unloaded.
        _writeBackendsState(guard, _backendsCpuOnly);
        return null;
      }
      if (cpuOnly) {
        // Expected for a static CPU build (no module exists); otherwise it
        // keeps whisper from aborting on a null CPU device.
        _log.info(
          'No ggml CPU backend module in $libraryDir (static CPU build?) — '
          'loading all backends',
        );
      }
      registry.loadAllFromPath(lib, libraryDir) || registry.loadAll(lib);
      _writeBackendsState(guard, _backendsAll);
      return null;
    } on NativeCallException catch (e) {
      // ggml-vulkan / a GPU driver threw while registering a module
      // (Sentry 155114205). Keep the process; run on CPU and remember it.
      _log.warning(
        'ggml backend load threw natively: ${e.message} — running on CPU',
      );
      _writeBackendsState(guard, _backendsFailed);
      try {
        _loadBestCpuModule(registry, lib, libraryDir);
      } on NativeCallException catch (cpuError) {
        _log.warning('ggml CPU module load threw too: ${cpuError.message}');
      }
      return 'ggml backend load threw: ${e.message}';
    }
  }

  /// No-guard path of [_loadBackendModules]: loads only the baseline CPU module
  /// (see [cpuBaselineModuleFor]) through `ggml_backend_load`, without the
  /// guard. Logs the reason. Returns `null` on success, else the failure reason.
  static String? _loadBaselineCpuWithoutGuard(
    ffi.DynamicLibrary lib,
    String libraryDir,
  ) {
    final String? name;
    try {
      name = cpuBaselineModuleFor(
        Directory(
          libraryDir,
        ).listSync().whereType<File>().map((f) => p.basename(f.path)),
        os: Platform.operatingSystem,
      );
    } on FileSystemException catch (e) {
      return 'cannot list $libraryDir: $e';
    }
    if (name == null || !lib.providesSymbol('ggml_backend_load')) {
      _log.warning(
        'wp_ffi_guard is not bundled next to $libraryDir and no baseline CPU '
        'module is available: ggml backends are not loaded',
      );
      return 'wp_ffi_guard is not bundled and no baseline CPU module exists';
    }
    _log.warning(
      'wp_ffi_guard is not bundled next to $libraryDir: loading the baseline '
      'CPU module $name unguarded; GPU backends stay off',
    );
    final load = lib.lookupFunction<_GgmlBackendLoadNative, _GgmlBackendLoad>(
      'ggml_backend_load',
    );
    final pathC = p.join(libraryDir, name).toNativeUtf8();
    try {
      if (load(pathC) == ffi.nullptr) {
        return 'ggml_backend_load returned null for $name';
      }
    } finally {
      malloc.free(pathC);
    }
    return null;
  }

  /// `ggml-base.dll` on Windows (see [_ensureBackendsLoaded]), else `null`.
  static ffi.DynamicLibrary? _ggmlBaseLibrary;

  /// Loads only the ggml CPU module that ggml itself would pick from [dir],
  /// returning `false` (nothing loaded) when there is none to load.
  ///
  /// ggml's `ggml_backend_load_best` is not part of the public header, so
  /// this mirrors it: each `ggml-cpu-<level>` module exports
  /// `ggml_backend_score()` (0 = unsupported by this CPU), and the highest
  /// score wins. Candidates are only opened for their score here; the chosen
  /// one is then registered with `ggml_backend_load` through the guard.
  static bool _loadBestCpuModule(
    GgmlBackendRegistry registry,
    ffi.DynamicLibrary lib,
    String dir,
  ) {
    if (!lib.providesSymbol('ggml_backend_load')) return false;
    final scores = <String, int>{};
    try {
      for (final entity in Directory(dir).listSync()) {
        if (entity is! File) continue;
        if (!_isCpuModuleFileName(p.basename(entity.path))) continue;
        scores[entity.path] = _scoreModule(registry, entity.path);
      }
    } on FileSystemException catch (e) {
      _log.warning('Cannot list backend modules in $dir: $e');
      return false;
    }
    final best = pickBestCpuModule(scores);
    if (best == null) return false;
    final reg = registry.loadModule(lib, best);
    if (reg == null) return false;
    _log.info('CPU-only backend load: registered ${p.basename(best)}');
    return true;
  }

  /// Whether [name] is a ggml CPU backend module for this platform.
  static bool _isCpuModuleFileName(String name) {
    final lower = name.toLowerCase();
    // ggml names its dynamically loaded backend modules `*.so` on every
    // non-Windows platform, macOS included (ggml-backend-reg.cpp).
    final ext = Platform.isWindows ? '.dll' : '.so';
    final stem =
        lower.startsWith('libggml-cpu') || lower.startsWith('ggml-cpu');
    return stem && lower.endsWith(ext);
  }

  /// `ggml_backend_score()` of the module at [modulePath], opened and closed
  /// inside the guard. A module that cannot be opened, or that threw while it
  /// was opened or scored, counts as unsupported (0).
  static int _scoreModule(GgmlBackendRegistry registry, String modulePath) {
    try {
      return registry.backendScore(modulePath);
    } on NativeCallException catch (e) {
      _log.warning(
        'Backend module $modulePath threw while scored: ${e.message}',
      );
      return 0;
    }
  }

  /// The library [_ensureBackendsLoaded] actually found `ggml_backend_load_all`
  /// in — `dylib` itself, or the separate `libggml`/`ggml.dll` fallback next to
  /// it. [_confirmBackend] probes this same library for the device-registry
  /// symbols, since a split-library bundle (observed on Windows: `ggml.dll`
  /// exports the registry API, `ggml-base.dll` only lower-level accessors —
  /// see this class's file doc comment) may not export them from `dylib`.
  static ffi.DynamicLibrary? _resolvedGgmlLibrary;

  /// Confirms [requested] against ggml's own device registry, downgrading to
  /// [WhisperBackend.cpu] when no matching device is actually registered.
  ///
  /// `cparams.use_gpu = true` is not a guarantee: whisper.cpp/ggml can
  /// silently fall back to CPU inside `whisper_init_from_file_with_params`
  /// itself (no compatible GPU device registered on this machine, a driver
  /// that fails GPU backend init, ...) without throwing — so trusting the
  /// pre-load [requested] value (as this engine did before) can report a GPU
  /// backend the load never actually used. Missing registry symbols (older
  /// bundled lib) degrade to trusting [requested] unchanged, matching
  /// [_resolveSegmentTimestampLookups]'s degrade-gracefully contract — this
  /// is a confirmation layer, not a hard requirement.
  ///
  /// Also returns the name of the GPU device whisper.cpp will pick (see
  /// [WhisperEngineStatus.gpuDevice]), `null` when it runs on CPU or the
  /// registry cannot be read, and that device's index among the registered
  /// GPU devices — the value `whisper_context_params.gpu_device` expects.
  /// [preferCuda] picks the first `CUDA*` device when one is registered (see
  /// [pickGpuDeviceIndex]): CUDA first, then discrete, then integrated GPUs.
  /// The GPU and integrated-GPU devices ggml registers in [dylib], in the
  /// order whisper.cpp's `gpu_device` index counts them. `null` when the
  /// library predates the registry API.
  static ({List<String?> names, List<int> types})? _gpuDevices(
    ffi.DynamicLibrary dylib,
    GgmlBackendRegistry ggml,
  ) {
    final all = _registryDevices(dylib, ggml);
    if (all == null) return null;
    // Same filter and order as whisper_backend_init_gpu: only GPU and IGPU
    // devices count, and `gpu_device` indexes into exactly this list.
    final names = <String?>[];
    final types = <int>[];
    for (final device in all) {
      if (device.type == ggmlDeviceTypeGpu ||
          device.type == ggmlDeviceTypeIgpu) {
        names.add(device.name);
        types.add(device.type);
      }
    }
    return (names: names, types: types);
  }

  /// Every device in ggml's registry, in registry order, or `null` when the
  /// library has no registry API. A split Windows bundle spreads the API over
  /// ggml.dll (count/get) and ggml-base.dll (type/name); each symbol comes
  /// from the first library that exports it.
  static List<({String? name, int type})>? _registryDevices(
    ffi.DynamicLibrary dylib,
    GgmlBackendRegistry ggml,
  ) {
    final candidates = <ffi.DynamicLibrary>[
      dylib,
      ?_resolvedGgmlLibrary,
      ?_ggmlBaseLibrary,
    ];
    ffi.DynamicLibrary? providing(String symbol) {
      for (final lib in candidates) {
        if (lib.providesSymbol(symbol)) return lib;
      }
      return null;
    }

    final countLib = providing('ggml_backend_dev_count');
    final getLib = providing('ggml_backend_dev_get');
    final typeLib = providing('ggml_backend_dev_type');
    final nameLib = providing('ggml_backend_dev_name');
    if (countLib == null || getLib == null || typeLib == null) return null;
    final count = ggml.devCount(countLib) ?? 0;
    final devices = <({String? name, int type})>[];
    for (var i = 0; i < count; i++) {
      final dev = ggml.devGet(getLib, i);
      if (dev == null) continue;
      final type = ggml.devType(typeLib, dev) ?? -1;
      final name = nameLib == null ? null : ggml.devName(nameLib, dev);
      devices.add((name: name, type: type));
    }
    return devices;
  }

  /// Whether ggml registered a CPU device. whisper.cpp dereferences the CPU
  /// device without a null check (GGML_ASSERT → abort), so [load] refuses to
  /// call into whisper when there is none. An old bundle without the
  /// registry API reports `true` and keeps the pre-existing behaviour.
  static bool _hasCpuDevice(
    ffi.DynamicLibrary dylib,
    GgmlBackendRegistry ggml,
  ) {
    final all = _registryDevices(dylib, ggml);
    if (all == null) return true;
    return all.any((device) => device.type == ggmlDeviceTypeCpu);
  }

  /// Lists the GPU devices in [dylib] for `whispaste --diagnose`, with the
  /// device [pickGpuDeviceIndex] picks without a CUDA preference
  /// (`defaultIndex` is `null` when there is no device). `null` when the
  /// library has no registry API. Loads the ggml backends as [load] does.
  static ({List<({String? name, int type})> devices, int? defaultIndex})?
  probeGpuDevices(ffi.DynamicLibrary dylib, String libraryPath) {
    _ensureBackendsLoaded(dylib, libraryPath);
    final ggml = _registryFor(libraryPath);
    final registry = _gpuDevices(dylib, ggml);
    if (registry == null) return null;
    final devices = [
      for (var i = 0; i < registry.names.length; i++)
        (name: registry.names[i], type: registry.types[i]),
    ];
    final defaultIndex = devices.isEmpty
        ? null
        : pickGpuDeviceIndex(
            registry.names,
            preferCuda: false,
            gpuTypes: registry.types,
          );
    return (devices: devices, defaultIndex: defaultIndex);
  }

  /// Threads a transcription uses on this machine by default.
  static int get defaultThreadCount => _threadCount();

  static (WhisperBackend, String?, int) _confirmBackend(
    ffi.DynamicLibrary dylib,
    WhisperBackend requested, {
    bool preferCuda = false,
    GgmlBackendRegistry ggml = const GgmlBackendRegistry(null),
  }) {
    if (requested == WhisperBackend.cpu) return (WhisperBackend.cpu, null, 0);
    final registry = _gpuDevices(dylib, ggml);
    // Older bundled library without the registry API: trust [requested].
    if (registry == null) return (requested, null, 0);
    final gpuNames = registry.names;
    final gpuTypes = registry.types;
    if (gpuNames.isEmpty) {
      _log.warning(
        'Requested $requested but no GPU device is registered in the '
        'ggml backend registry — downgrading to CPU',
      );
      return (WhisperBackend.cpu, null, 0);
    }
    final index = pickGpuDeviceIndex(
      gpuNames,
      gpuTypes: gpuTypes,
      preferCuda: preferCuda,
    );
    final described = [
      for (var i = 0; i < gpuNames.length; i++)
        '${gpuNames[i]} (${_gpuTypeLabel(gpuTypes[i])})',
    ].join(', ');
    _log.info('GPU devices in registry order: $described — using index $index');
    if (preferCuda && !(gpuNames[index]?.startsWith('CUDA') ?? false)) {
      _log.warning(
        'CUDA pack is enabled but no CUDA device is registered '
        '(driver too old or no supported NVIDIA GPU) — using '
        '${gpuNames[index]} instead',
      );
    }
    return (
      backendForDevice(gpuNames[index], requested),
      gpuNames[index],
      index,
    );
  }

  /// Process-wide: the CUDA pack directory whose module is already
  /// registered with ggml. ggml's registry cannot unregister a backend, so a
  /// second pack directory in the same process is ignored (the user would
  /// only get there by reinstalling a pack, which restarts the engine but
  /// not the process; the old module keeps working until the next launch).
  static String? _cudaPackLoadedFrom;

  /// Whether the CUDA module was already attempted in this PROCESS. Read
  /// through the guard so a worker isolate does not register it a second time
  /// (ggml would list the CUDA devices twice and shift `gpu_device`).
  static bool _cudaAttempted(NativeCallGuard? guard) => guard != null
      ? guard.processFlag(WpgFlag.cudaPack) == 1
      : _cudaPackLoadedFrom != null;

  /// Registers the optional CUDA module from [packDir] with ggml via
  /// `ggml_backend_load`, once per process. The module lives outside the
  /// app's own library folder (installed packages are read-only), so
  /// [_ensureBackendsLoaded]'s directory scan never sees it.
  ///
  /// Dependency resolution: on Linux the module's `$ORIGIN` RUNPATH finds
  /// the CUDA runtime next to it and `libggml-base.so.0` is matched by
  /// soname against the copy libwhisper already loaded. On Windows ggml calls
  /// a plain `LoadLibraryW`, whose transitive imports (`cudart64_12.dll`,
  /// `cublas64_12.dll`) are searched in the `SetDllDirectoryW` folder — so
  /// that folder points at [packDir] for the call and back at the app's
  /// library folder afterwards; `ggml-base.dll` is already loaded by name.
  ///
  /// Never throws: a missing, corrupt or driver-incompatible pack only means
  /// no `CUDA*` device gets registered, and [_confirmBackend] then keeps the
  /// Vulkan device. A module that throws while registering is caught by the
  /// guard and recorded as attempted, so it is not retried in this process.
  static void _ensureCudaPackLoaded(
    ffi.DynamicLibrary dylib,
    String packDir,
    String libraryPath,
  ) {
    final guard = NativeCallGuard.nextTo(libraryPath);
    if (_cudaAttempted(guard)) {
      if (_cudaPackLoadedFrom != null && _cudaPackLoadedFrom != packDir) {
        _log.warning(
          'CUDA module already loaded from $_cudaPackLoadedFrom; '
          'ignoring $packDir until the next launch',
        );
      }
      return;
    }
    final modulePath = p.join(packDir, cudaModuleFileName());
    if (!File(modulePath).existsSync()) {
      _log.warning('CUDA pack has no module at $modulePath');
      return;
    }
    final lib = _resolvedGgmlLibrary ?? dylib;
    guard?.setProcessFlag(WpgFlag.cudaPack, 1);
    _cudaPackLoadedFrom = packDir;
    try {
      ensureWindowsDllSearchPath(modulePath);
      final reg = GgmlBackendRegistry(guard).loadModule(lib, modulePath);
      if (reg == null) {
        // loadModule returns null for a missing guard as well as for a
        // rejected module, and the log must name the real reason.
        _log.warning(
          guard == null
              ? 'CUDA module not loaded: wp_ffi_guard is not bundled next to '
                    '$libraryPath'
              : 'ggml_backend_load did not register the CUDA module '
                    '(rejected or export missing)',
        );
      } else {
        _log.info('CUDA module registered from $packDir');
      }
    } on NativeCallException catch (e) {
      _log.warning(
        'CUDA module threw while registering: ${e.message} — CUDA is not '
        'used this session, Vulkan stays',
      );
    } finally {
      ensureWindowsDllSearchPath(libraryPath);
    }
  }

  /// Best-effort lookup of `whisper_full_get_segment_t0/t1`, used only by
  /// [_logSegments] to diagnose dropped-sentence reports (see that method's
  /// doc comment). Never throws — an older bundled `libwhisper` missing
  /// these symbols just means segment logging falls back to count + text
  /// length, which is still a useful signal on its own.
  void _resolveSegmentTimestampLookups(ffi.DynamicLibrary dylib) {
    try {
      _segmentT0 = dylib
          .lookupFunction<
            ffi.Int64 Function(ffi.Pointer<whisper_context>, ffi.Int32),
            int Function(ffi.Pointer<whisper_context>, int)
          >('whisper_full_get_segment_t0');
      _segmentT1 = dylib
          .lookupFunction<
            ffi.Int64 Function(ffi.Pointer<whisper_context>, ffi.Int32),
            int Function(ffi.Pointer<whisper_context>, int)
          >('whisper_full_get_segment_t1');
    } on ArgumentError {
      _segmentT0 = null;
      _segmentT1 = null;
    }
    try {
      _segmentNoSpeechProb = dylib
          .lookupFunction<
            ffi.Float Function(ffi.Pointer<whisper_context>, ffi.Int32),
            double Function(ffi.Pointer<whisper_context>, int)
          >('whisper_full_get_segment_no_speech_prob');
    } on ArgumentError {
      _segmentNoSpeechProb = null;
    }
  }

  /// Logs each segment whisper.cpp produced for the current [transcribe]
  /// call, at debug level.
  ///
  /// Added to diagnose intermittent "transcription swallowed a sentence"
  /// reports: the app sends the *whole* recording to a single `whisper_full`
  /// call (no app-level chunking, see `CONTEXT.md` §4.2) and simply
  /// concatenates every segment's text — so a dropped sentence must show up
  /// here as either a missing segment (a timestamp gap vs. the next
  /// segment's t0) or as fewer segments than the audio's duration would
  /// suggest. Debug-level: invisible in release-build logs (see
  /// `app_logger.dart`'s `kReleaseMode` level gate) so this never adds
  /// per-segment noise to a normal user's log file; visible during a
  /// diagnosis session run in debug mode.
  ///
  /// [includeTimestamps] must mirror the same-named [transcribe] parameter:
  /// `whisper_full_get_segment_t0/t1` only return real values when whisper
  /// was actually asked to compute them (`params.no_timestamps = false`).
  /// With the production default (`no_timestamps = true`), both getters
  /// return a fixed sentinel pair instead of failing or returning zero —
  /// confirmed empirically (2026-07-29) by comparing two completely
  /// different audio clips and getting byte-identical "timestamps" back —
  /// so timestamps are only recorded/logged when [includeTimestamps] is
  /// `true`; otherwise segments carry `null` start/end rather than that
  /// misleading sentinel.
  /// [timeOffsetMs]/[indexOffset] let a pause-split chunk's segments (see
  /// [_transcribeInChunks]) land in [_lastSegments] with globally meaningful
  /// timestamps/indices instead of each chunk restarting at zero;
  /// [reset] clears any segments from a previous chunk/call before
  /// appending this call's — only the first chunk of a chunked transcribe
  /// (or a normal, unchunked call) passes `true`.
  void _logSegments(
    WhisperBindings bindings,
    ffi.Pointer<whisper_context> ctx, {
    required bool includeTimestamps,
    int timeOffsetMs = 0,
    int indexOffset = 0,
    bool reset = true,
  }) {
    final n = bindings.whisper_full_n_segments(ctx);
    final t0 = includeTimestamps ? _segmentT0 : null;
    final t1 = includeTimestamps ? _segmentT1 : null;
    final nsp = _segmentNoSpeechProb;
    final segments = <WhisperSegment>[];
    for (var i = 0; i < n; i++) {
      final textPtr = bindings.whisper_full_get_segment_text(ctx, i);
      final text = textPtr.cast<Utf8>().toDartString();
      final noSpeechProb = nsp?.call(ctx, i);
      final globalIndex = indexOffset + i;
      if (t0 != null && t1 != null) {
        // whisper.cpp reports t0/t1 in centiseconds (10 ms units).
        final startMs = t0(ctx, i) * 10 + timeOffsetMs;
        final endMs = t1(ctx, i) * 10 + timeOffsetMs;
        segments.add(
          WhisperSegment(
            index: globalIndex,
            startMs: startMs,
            endMs: endMs,
            text: text,
            noSpeechProb: noSpeechProb,
          ),
        );
        _log.debug(
          'segment[$globalIndex/$n] ${startMs}ms-${endMs}ms textLen=${text.length} '
          'noSpeechProb=$noSpeechProb',
        );
      } else {
        segments.add(
          WhisperSegment(
            index: globalIndex,
            startMs: null,
            endMs: null,
            text: text,
            noSpeechProb: noSpeechProb,
          ),
        );
        _log.debug(
          'segment[$globalIndex/$n] textLen=${text.length} noSpeechProb=$noSpeechProb',
        );
      }
    }
    _lastSegments = reset ? segments : [..._lastSegments, ...segments];
  }

  /// Above this input duration, [transcribe] splits the audio at natural
  /// pauses and decodes each piece with its own `whisper_full` call instead
  /// of one call for the whole recording — see [_splitAtPauses]'s doc
  /// comment for why. Below it, behaviour is byte-for-byte unchanged from
  /// before this constant existed (single call, no splitting), so every
  /// short dictation — the overwhelming majority, and everything the
  /// existing test fixtures cover — takes the exact same path it always
  /// has.
  static const _pauseChunkingThresholdMs = 20000;

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool includeTimestamps = false,
    bool vadEnabled = false,
    bool reducedThreads = false,
    void Function(double fraction)? onProgress,
  }) async {
    final bindings = _bindings;
    final ctx = _ctx;
    if (bindings == null || ctx == null) {
      throw StateError('whisper_engine_not_loaded');
    }

    final samples = pcm16WavBytesToFloat32(wavBytes);
    if (samples.isEmpty) return '';

    // New call: no prior chunk's text to prefix live updates with.
    _partialPrefix = '';

    // ── VAD-trim diagnostic (2026-08-27) ────────────────────────────────
    // Debug-level only (see `_logSegments`' doc comment on the release-mode
    // gate) so this adds no per-call overhead in production. Logged before
    // `useVad` is even known so a diagnosis session can always compute this
    // input's total duration against the last segment's `endMs` (only
    // populated when `includeTimestamps: true`, i.e. the debug harness) to
    // catch VAD silently discarding real speech as noise -- the working
    // hypothesis for "skips a portion of what I said" reports that correlate
    // with a loud/busy machine (fan noise raising the ambient noise floor
    // the fixed `vad_params.threshold` of 0.5, see below, has no visibility
    // into). A duration far exceeding the last segment's `endMs` is the
    // signature to look for.
    final totalDurationMs = (samples.length * 1000 / WHISPER_SAMPLE_RATE)
        .round();
    _log.debug(
      'audio duration: ${totalDurationMs}ms '
      '(${samples.length} samples @ ${WHISPER_SAMPLE_RATE}Hz)',
    );

    // ── Pause-based chunk segmentation (2026-08-27) ─────────────────────
    // The "größer/später" measure from the transcription-quality-under-load
    // investigation (`internal-notes`):
    // whisper.cpp decodes a long recording as a sequence of internal ~30s
    // windows (`WHISPER_CHUNK_SIZE`) and conditions each window on the
    // previous window's own decoded text (see the "Long-dictation
    // repetition hardening" comment below) — once one window degrades into
    // a repeat loop, that mechanism keeps reinforcing it for the rest of
    // the recording. Splitting the input ourselves at real pauses, each
    // chunk safely under that internal window size, means a single
    // `whisper_full` call never itself spans more than one internal
    // window — the cross-window conditioning this bug depends on simply
    // cannot trigger inside one chunk. A degraded chunk's output therefore
    // stays local to that chunk instead of poisoning everything after it.
    // This also directly answers the PRD's open "punctuation-priming drift"
    // question: [prompt] (vocabulary/style priming) is now re-applied to
    // every chunk instead of only conditioning whisper's own first internal
    // window.
    //
    // Deliberately implemented in pure Dart over the already-decoded
    // float32 sample buffer instead of binding whisper.cpp's standalone VAD
    // segment API (`whisper_vad_segments_from_samples`) — the PRD's
    // documented reason not to do that in this session still applies (new
    // FFI struct/signature work, unverifiable here against all three
    // bundled platform builds without new native crash risk). A
    // pause/silence detector needs no native binding at all: it only reads
    // memory this method already owns.
    if (totalDurationMs > _pauseChunkingThresholdMs) {
      return _transcribeInChunks(
        bindings,
        ctx,
        samples,
        language: language,
        prompt: prompt,
        includeTimestamps: includeTimestamps,
        vadEnabled: vadEnabled,
        reducedThreads: reducedThreads,
        onProgress: onProgress,
      );
    }

    return _decodeOnce(
      bindings,
      ctx,
      samples,
      language: language,
      prompt: prompt,
      includeTimestamps: includeTimestamps,
      vadEnabled: vadEnabled,
      reducedThreads: reducedThreads,
      segmentTimeOffsetMs: 0,
      segmentIndexOffset: 0,
      resetLastSegments: true,
      onProgress: onProgress,
    );
  }

  /// Longest a single pause-split chunk is allowed to be — safely under
  /// whisper.cpp's internal ~30s decode window (see [_pauseChunkingThresholdMs]'s
  /// doc comment) so no chunk can itself span an internal window boundary.
  static const _maxChunkDurationMs = 25000;

  @visibleForTesting
  static const maxChunkDurationMsForTesting = _maxChunkDurationMs;

  /// Shortest silence run [findPauseSplitPoints] accepts as a real pause
  /// rather than a brief in-word/in-phrase dip.
  static const _minPauseDurationMs = 700;

  /// RMS amplitude (of 16-bit PCM normalized to `[-1.0, 1.0]`) below which a
  /// short analysis frame counts as silence. Conservative (i.e. low) on
  /// purpose: a missed pause only costs a slightly longer chunk (still
  /// capped by [_maxChunkDurationMs]'s forced cut), while a falsely
  /// detected pause mid-word would corrupt output — asymmetric risk, so
  /// this errs toward under-detecting pauses.
  static const _silenceRmsThreshold = 0.015;

  static const _analysisFrameMs = 20;

  /// Sample indices of [findPauseSplits], without the hard-cut flags.
  @visibleForTesting
  static List<int> findPauseSplitPoints(
    Float32List samples, {
    int sampleRate = WHISPER_SAMPLE_RATE,
    int maxChunkDurationMs = _maxChunkDurationMs,
    int minPauseDurationMs = _minPauseDurationMs,
    double silenceRmsThreshold = _silenceRmsThreshold,
  }) => [
    for (final split in findPauseSplits(
      samples,
      sampleRate: sampleRate,
      maxChunkDurationMs: maxChunkDurationMs,
      minPauseDurationMs: minPauseDurationMs,
      silenceRmsThreshold: silenceRmsThreshold,
    ))
      split.sample,
  ];

  /// Finds the cuts for [samples] (see [WhisperPauseSplit]): each one a real
  /// pause of at least [_minPauseDurationMs], such that no resulting chunk
  /// exceeds [_maxChunkDurationMs]. Falls back to a hard cut at
  /// [_maxChunkDurationMs] when no pause is found within that span (rare in
  /// natural speech, but must still be bounded to preserve the mechanism
  /// this exists for). Pure and allocation-light — safe to unit-test without
  /// the native library.
  @visibleForTesting
  static List<WhisperPauseSplit> findPauseSplits(
    Float32List samples, {
    int sampleRate = WHISPER_SAMPLE_RATE,
    int maxChunkDurationMs = _maxChunkDurationMs,
    int minPauseDurationMs = _minPauseDurationMs,
    double silenceRmsThreshold = _silenceRmsThreshold,
  }) {
    final frameLen = (sampleRate * _analysisFrameMs / 1000).round();
    if (frameLen <= 0 || samples.length < frameLen) return const [];

    final frameCount = samples.length ~/ frameLen;
    final silentFrame = List<bool>.filled(frameCount, false);
    for (var f = 0; f < frameCount; f++) {
      final start = f * frameLen;
      var sumSquares = 0.0;
      for (var i = start; i < start + frameLen; i++) {
        sumSquares += samples[i] * samples[i];
      }
      final rms = math.sqrt(sumSquares / frameLen);
      silentFrame[f] = rms < silenceRmsThreshold;
    }

    final minPauseFrames = (minPauseDurationMs / _analysisFrameMs).ceil();
    final maxChunkFrames = (maxChunkDurationMs / _analysisFrameMs).floor();

    // Every pause run's midpoint frame, in order.
    final pauseMidpoints = <int>[];
    var runStart = -1;
    for (var f = 0; f <= frameCount; f++) {
      final isSilent = f < frameCount && silentFrame[f];
      if (isSilent && runStart == -1) {
        runStart = f;
      } else if (!isSilent && runStart != -1) {
        final runLen = f - runStart;
        if (runLen >= minPauseFrames) {
          pauseMidpoints.add(runStart + runLen ~/ 2);
        }
        runStart = -1;
      }
    }

    final splits = <WhisperPauseSplit>[];
    var lastSplitFrame = 0;
    var pauseIdx = 0;
    while (lastSplitFrame < frameCount) {
      final chunkLimitFrame = lastSplitFrame + maxChunkFrames;
      if (chunkLimitFrame >= frameCount) break;

      // Find the last pause midpoint still within this chunk's budget.
      var chosen = -1;
      while (pauseIdx < pauseMidpoints.length &&
          pauseMidpoints[pauseIdx] <= chunkLimitFrame) {
        if (pauseMidpoints[pauseIdx] > lastSplitFrame) {
          chosen = pauseMidpoints[pauseIdx];
        }
        pauseIdx++;
      }
      // A pause consumed above but before `lastSplitFrame` must not be
      // re-considered for the next chunk either.
      var hard = false;
      if (chosen == -1) {
        // No natural pause in range — force a hard cut so the invariant
        // (no chunk exceeds maxChunkDurationMs) always holds.
        chosen = chunkLimitFrame;
        hard = true;
      }
      splits.add(WhisperPauseSplit(chosen * frameLen, hard: hard));
      lastSplitFrame = chosen;
    }

    return splits;
  }

  /// Trailing words of [text] to carry forward as extra continuity context
  /// into the next chunk's prompt — bounded the same way
  /// `params.n_max_text_ctx = 64` bounds whisper's own internal
  /// window-to-window conditioning (see that comment below), so a degraded
  /// chunk's output can still poison at most this much of the next chunk's
  /// prompt, never the whole rest of the recording. Loop guard: see
  /// `continuity_guard.dart`.
  @visibleForTesting
  static String continuityContextFrom(String text) =>
      continuity.continuityContextFrom(text);

  Future<String> _transcribeInChunks(
    WhisperBindings bindings,
    ffi.Pointer<whisper_context> ctx,
    Float32List samples, {
    required String? language,
    required String? prompt,
    required bool includeTimestamps,
    required bool vadEnabled,
    required bool reducedThreads,
    void Function(double fraction)? onProgress,
  }) async {
    final splits = findPauseSplits(samples);
    if (splits.isEmpty) {
      // No usable pause anywhere (e.g. one long unbroken utterance) — the
      // hard-cut fallback in [findPauseSplitPoints] only activates once a
      // chunk boundary is actually being searched for, so an entirely
      // silence-free clip under [_maxChunkDurationMs] * frame math edge
      // cases can still come back empty. Decode it as a single call rather
      // than risk splitting mid-word for no benefit.
      return _decodeOnce(
        bindings,
        ctx,
        samples,
        language: language,
        prompt: prompt,
        includeTimestamps: includeTimestamps,
        vadEnabled: vadEnabled,
        reducedThreads: reducedThreads,
        segmentTimeOffsetMs: 0,
        segmentIndexOffset: 0,
        resetLastSegments: true,
        onProgress: onProgress,
      );
    }

    _log.debug(
      'long dictation (${(samples.length * 1000 / WHISPER_SAMPLE_RATE).round()}ms) '
      'split into ${splits.length + 1} chunks at natural pauses',
    );

    final buffer = StringBuffer();
    String? carryPrompt = prompt;
    // The continuity text this chunk's prompt carries, if any (not the
    // vocabulary prompt): a copy of it at the start of the output is an echo.
    String? carriedText;
    var previousText = '';
    var chunkStart = 0;
    var segmentIndexOffset = 0;
    final boundaries = [...splits.map((s) => s.sample), samples.length];
    for (var i = 0; i < boundaries.length; i++) {
      final chunkEnd = boundaries[i];
      final chunkSamples = Float32List.sublistView(
        samples,
        chunkStart,
        chunkEnd,
      );
      final chunkStartMs = (chunkStart * 1000 / WHISPER_SAMPLE_RATE).round();
      final rawText = await _decodeOnce(
        bindings,
        ctx,
        chunkSamples,
        language: language,
        prompt: carryPrompt,
        includeTimestamps: includeTimestamps,
        vadEnabled: vadEnabled,
        reducedThreads: reducedThreads,
        segmentTimeOffsetMs: chunkStartMs,
        segmentIndexOffset: segmentIndexOffset,
        resetLastSegments: i == 0,
        onProgress: onProgress == null
            ? null
            : (withinChunk) => onProgress(
                chunkedProgressFraction(
                  chunkIndex: i,
                  chunkCount: boundaries.length,
                  withinChunk: withinChunk,
                ),
              ),
      );
      // A decoder that copied the carried text back is stripped of the copy;
      // at a hard cut the overlap is removed from the seam (see WhisperPauseSplit).
      var chunkText = rawText;
      final echoed = carriedText;
      if (echoed != null) {
        chunkText = continuity.stripPromptEcho(echoed, chunkText);
      }
      final hardSeam = i > 0 && splits[i - 1].hard;
      if (hardSeam) {
        chunkText = seam.dropSeamRepeat(previousText, chunkText);
      }
      buffer.write(chunkText);
      previousText = chunkText;
      // Advance the live-transcript prefix so the next chunk's callback
      // firings report the whole transcript-so-far, not just its own text.
      _partialPrefix = buffer.toString();
      segmentIndexOffset = _lastSegments.length;

      // A looping chunk carries nothing forward (see continuity_guard.dart).
      final carry = continuity.continuityCarryFor(chunkText);
      final hasOriginalPrompt = prompt != null && prompt.isNotEmpty;
      carriedText = carry;
      carryPrompt = carry == null
          ? prompt
          : (hasOriginalPrompt ? '$prompt $carry' : carry);

      final hardCut = i < splits.length && splits[i].hard;
      // A hard cut repeats the last 2 s of audio at the start of the next
      // chunk; the seam above removes the words that were heard twice.
      chunkStart = hardCut ? chunkEnd - _hardCutOverlapSamples : chunkEnd;
    }
    return buffer.toString();
  }

  /// One `whisper_full` decode call over [samples] — the single-call body
  /// [transcribe] always ran before pause-based chunking existed, extracted
  /// unchanged so both the short-dictation path and each chunk of a long
  /// dictation go through the exact same, already-verified decode setup.
  Future<String> _decodeOnce(
    WhisperBindings bindings,
    ffi.Pointer<whisper_context> ctx,
    Float32List samples, {
    required String? language,
    required String? prompt,
    required bool includeTimestamps,
    required bool vadEnabled,
    required bool reducedThreads,
    required int segmentTimeOffsetMs,
    required int segmentIndexOffset,
    required bool resetLastSegments,
    void Function(double withinCall)? onProgress,
  }) async {
    final samplesPtr = malloc<ffi.Float>(samples.length);
    samplesPtr.asTypedList(samples.length).setAll(0, samples);
    final languageC = (language ?? 'auto').toNativeUtf8();
    // Only allocate a native prompt buffer when there is something to bias
    // decoding with — the FFI struct defaults `initial_prompt` to a null
    // pointer, which whisper.cpp already treats as "no prompt".
    final hasPrompt = prompt != null && prompt.isNotEmpty;
    final promptC = hasPrompt ? prompt.toNativeUtf8() : null;
    final vadModelPath = _vadModelPath;
    final useVad = vadEnabled && vadModelPath != null;
    final vadModelPathC = useVad ? vadModelPath.toNativeUtf8() : null;
    try {
      final params = bindings.whisper_full_default_params(
        WhisperSamplingStrategy.WHISPER_SAMPLING_GREEDY,
      );
      params.print_progress = false;
      params.print_realtime = false;
      params.print_timestamps = false;
      params.print_special = false;
      // [includeTimestamps] defaults to `false` (`no_timestamps = true`,
      // unchanged production behaviour) because computing real per-segment
      // t0/t1 costs extra decode time the app doesn't need for plain text
      // output. Confirmed empirically (2026-07-29, diagnosis session): with
      // `no_timestamps = true`, `whisper_full_get_segment_t0/t1` do NOT
      // return real timestamps — they return a fixed sentinel pair (t1 ==
      // `WHISPER_CHUNK_SIZE` exactly, in whisper_bindings.dart) identical
      // across totally different audio, so [WhisperSegment.startMs]/[endMs]
      // are only meaningful when this flag is `true`. Only the diagnosis
      // harness (`transcribe_debug_harness_test.dart`) passes `true`; no
      // production call site does, so this is a pure opt-in addition.
      params.no_timestamps = !includeTimestamps;
      params.translate = false;
      params.language = languageC.cast<ffi.Char>();
      // ── Audio-capture protection (2026-08-27) ──────────────────────────
      // [reducedThreads] lets a caller shrink this decode's own CPU
      // footprint instead of leaving OS scheduling to sort out the
      // contention on its own — the concrete, implementable answer to
      // "Audio-Capture-Thread real-time-priorisieren, unabhängig von der
      // Whisper-Last" for this app's actual architecture. True OS-level
      // audio-thread priority isn't a lever this app owns (the `record`
      // package delegates capture to AVAudioEngine/WASAPI's own realtime
      // threads, entirely outside the Dart isolate), but this app DOES own
      // how many cores its own inference competes with those threads for.
      // `stt_server_state_notifier.dart` sets this whenever a NEW recording
      // is actively capturing while a PREVIOUS utterance's transcription is
      // still decoding on this same batch pipeline — the one real,
      // in-this-app's-control case where Whisper's own CPU load can
      // directly compete with a live recording for the same cores.
      params.n_threads = _threadCount(reducedThreads: reducedThreads);
      if (promptC != null) {
        params.initial_prompt = promptC.cast<ffi.Char>();
      }

      // ── Quality/hallucination hardening (2026-07-29 diagnosis) ─────────
      // Investigated real dictations for "swallowed sentence" reports:
      // history.db shows the app is mostly transcribing cleanly, but a
      // small recurring artifact appears — a short, ungrammatical fragment
      // tacked on right after the real content already reads complete
      // (e.g. "...tatsächlich dauert. funktionieren."). That shape matches
      // whisper.cpp's documented "hallucination on trailing silence/noise"
      // failure class (see ggml-org/whisper.cpp issues #1724, #1026;
      // discussion #2286) rather than app-level chunking (there is none —
      // the whole recording goes through one `whisper_full` call).
      //
      // Two settings the app never touched, left at whisper.cpp's
      // built-in defaults, both cross-referenced against the actual
      // decode source (`.build/deps/whisper.cpp/v1.9.5/src/whisper.cpp`)
      // before changing:
      //
      // 1. `suppress_nst` (default `false`) — suppresses a fixed table of
      //    symbol/bracket/music-note tokens during decoding (not real
      //    words). OpenAI's reference Python implementation suppresses
      //    these by default; whisper.cpp does not unless asked. Zero risk
      //    to real speech — enabling it.
      //
      // 2. `temperature_inc` (default `0.2`) — when a decode pass fails
      //    whisper's own confidence gates (`entropy_thold`/`logprob_thold`),
      //    whisper.cpp retries at increasing temperature (more randomness)
      //    up to 1.0. This escalation is whisper.cpp's own documented
      //    hallucination lever: low-confidence audio (e.g. trailing
      //    breath/room tone after real speech ends) is exactly what fails
      //    those gates, and a higher-temperature retry is more likely to
      //    produce a fluent-sounding but fabricated word than the initial
      //    greedy pass — the "--no-fallback" mitigation documented in
      //    whisper.cpp discussion #1087. Setting `temperature_inc = 0.0`
      //    disables the escalation entirely (confirmed in source: the
      //    fallback loop at whisper.cpp:6845 only runs `if
      //    (params.temperature_inc > 0.0f)`), so every clip gets exactly
      //    one deterministic greedy pass at `temperature = 0.0`.
      //    Trade-off: genuinely ambiguous *real* speech (heavy accent,
      //    overlapping noise) loses the extra attempts that might have
      //    decoded it better — accepted here because greedy-only was
      //    already the app's default behaviour for the pass that succeeds
      //    99%+ of the time, and the fallback ladder existing at all is
      //    the more likely source of confident-sounding fabricated text.
      params.suppress_nst = true;
      params.temperature_inc = 0.0;

      // ── Long-dictation repetition hardening (2026-08-04 diagnosis) ─────
      // Different failure class than the trailing-hallucination fix above:
      // reports of *repeated* text near the end of long (multi-minute)
      // German dictations, sometimes with a hard cutoff. whisper_full()
      // decodes one long recording as a sequence of internal ~30s windows
      // (no app-level chunking — confirmed above), and each window is
      // conditioned on the previous window's decoded text whenever
      // `params.n_max_text_ctx > 0 && t_cur < WHISPER_HISTORY_CONDITIONING_
      // TEMP_CUTOFF` (whisper.cpp:7081, cutoff = 0.5 at whisper.cpp:145).
      // Because `temperature_inc = 0.0` above pins `t_cur` at `0.0` for
      // every window of a long recording, that condition is permanently
      // true — so once one window's output degrades into a repeat loop,
      // up to `min(n_max_text_ctx, whisper_n_text_ctx(ctx)/2)` tokens of it
      // (224 tokens — several sentences — at this model's context size,
      // since the app never touched `n_max_text_ctx` and its unset default
      // of 16384 is only capped by that model-size division) get carried
      // into the prompt for the next window, reinforcing it further. This
      // is whisper.cpp's own documented long-form repetition mechanism
      // (ggml-org/whisper.cpp issue #3744; discussions #1490, #2286).
      //
      // Re-enabling `temperature_inc` (whisper.cpp/OpenAI's own default:
      // `0.2`, escalating to `1.0`) would let a degraded window retry and
      // break out, but reopens exactly the higher-temperature fabrication
      // risk the trailing-hallucination fix above was written to close —
      // and whisper.cpp has no separate cap on how high that retry
      // temperature can climb, so it is all-or-nothing. Capping
      // `n_max_text_ctx` instead shrinks the blast radius of the same
      // mechanism without touching that trade-off: less of a degraded
      // window can propagate forward, while genuine short-range continuity
      // (mid-sentence carry across a window boundary) is still kept. `64`
      // matches the community-recommended value for this exact symptom
      // (ggml-org/whisper.cpp discussions #1490, #2286: `--context 64`).
      params.n_max_text_ctx = 64;

      // ── VAD-gated hallucination hardening (2026-07-29 follow-up) ───────
      // whisper.cpp's own internal `no_speech_prob`/`no_speech_thold` gate
      // (already active by default, see `_logSegments`' doc comment) is
      // provably insufficient on its own: it did not catch the "Vielen
      // Dank" trailing-hallucination reports this was built to address,
      // because a hallucinated closing phrase is exactly the case where
      // the model is confidently wrong — no_speech_prob stays low. Community
      // consensus (openai/whisper discussion #679; ggml-org/whisper.cpp
      // issue #1724) is that only an independent, acoustic VAD signal
      // reliably tells trailing silence apart from real speech.
      //
      // `params.vad`/`vad_model_path`/`vad_params` (all already present on
      // [WhisperBindings]' generated struct — nothing hand-rolled) delegate
      // to whisper.cpp's own built-in Silero-VAD integration: it re-segments
      // the input to only the detected-speech regions (joined with a fixed
      // gap) before decoding, so a long silence/noise tail is never seen by
      // the decoder at all. `[useVad]` degrades silently to today's
      // behaviour when no VAD model is bundled/resolved for this platform
      // yet (see [_vadModelPath]) or the caller opts out via [vadEnabled]
      // (`SttSettings.vadEnabled`).
      if (useVad) {
        params.vad = true;
        params.vad_model_path = vadModelPathC!.cast<ffi.Char>();

        // ── Noise-floor tolerance under system load (2026-08-27) ─────────
        // Direct response to the transcription-quality-under-load feedback
        // (`internal-notes`): the
        // maintainer and a user both report words/phrases silently missing
        // specifically when the machine is under load (fan audibly
        // running). A running fan raises the *ambient noise floor* the
        // microphone picks up underneath real speech. `vad_params` used to
        // sit at `whisper_full_default_params`' library defaults
        // (`threshold=0.5`, `speech_pad_ms=30`) — tuned by whisper.cpp's
        // authors against clean studio audio, not a noisy room. A
        // borderline-quiet real word riding on an elevated noise floor is
        // exactly what a `threshold=0.5` Silero-VAD pass can misclassify as
        // non-speech and drop before it ever reaches the decoder — this is
        // the acoustic mechanism the PRD's diagnostic logging was added to
        // go looking for, and it matches the reported symptom (a whole
        // portion of speech silently missing, not corrupted/hallucinated)
        // better than any of the decode-side hallucination mitigations
        // above, none of which touch pre-decode VAD trimming.
        //
        // Lowering `threshold` to [_vadThresholdUnderNoise] makes Silero
        // classify more borderline-energy audio as speech (fewer false
        // negatives), at the cost of passing slightly more true silence
        // through to the decoder — an acceptable trade given
        // `temperature_inc = 0.0` and `suppress_nst = true` above already
        // harden that decoder pass against turning residual silence into a
        // hallucination. Raising `speech_pad_ms` to
        // [_vadSpeechPadMsUnderNoise] additionally protects word onsets/
        // offsets right at a detected-speech boundary from being clipped —
        // the same failure shape ("skips a portion") if the boundary itself
        // sits a few tens of ms into a real word. Both values are a
        // reasoned, conservative adjustment in the correct *direction* for
        // this specific, described symptom, not a blind guess; the existing
        // VAD-trim diagnostic logging directly ahead of this block gives a
        // concrete way to validate/re-tune them once real field data comes
        // in, as flagged in the PRD.
        params.vad_params.threshold = _vadThresholdUnderNoise;
        params.vad_params.speech_pad_ms = _vadSpeechPadMsUnderNoise;
      }

      // ── Live/partial transcript callback (ticket 11) ───────────────────
      // Registered per-call (unlike `whisper_log_set`, `new_segment_callback`
      // is a field on `whisper_full_params`, not a global) so it is always
      // torn down in this same `finally` block, never left dangling on a
      // freed context. No-op cost when nobody is listening — the callback
      // body's own `hasListener` guard skips the segment walk entirely.
      final segmentCallable =
          ffi.NativeCallable<WhisperNewSegmentCallbackNative>.isolateLocal((
            ffi.Pointer<whisper_context> segCtx,
            ffi.Pointer<whisper_state> segState,
            int nNew,
            ffi.Pointer<ffi.Void> userData,
          ) {
            _emitPartialTranscript(bindings, segCtx);
          });
      params.new_segment_callback = segmentCallable.nativeFunction;
      params.new_segment_callback_user_data = ffi.nullptr;

      // ── Progress callback (IMP-PROG-2) ─────────────────────────────────
      // Same threading model as the segment callback above: whisper.cpp
      // fires it on the thread blocked inside `whisper_full`, which is this
      // isolate's own thread, so `.isolateLocal` is safe. It is closed only
      // after `whisper_full` returned (WP-48): native code may call it at
      // any point before that. Absent when nobody listens.
      final progressSink = onProgress;
      final progressCallable = progressSink == null
          ? null
          : ffi.NativeCallable<WhisperProgressCallbackNative>.isolateLocal((
              ffi.Pointer<whisper_context> progCtx,
              ffi.Pointer<whisper_state> progState,
              int progress,
              ffi.Pointer<ffi.Void> userData,
            ) {
              progressSink((progress.clamp(0, 100)) / 100.0);
            });
      if (progressCallable != null) {
        params.progress_callback = progressCallable.nativeFunction;
        params.progress_callback_user_data = ffi.nullptr;
      }

      final int rc;
      try {
        final guard = _guard;
        rc = guard != null
            ? guard.whisperFull(
                _fullFn,
                ctx,
                params,
                samplesPtr,
                samples.length,
              )
            : bindings.whisper_full(ctx, params, samplesPtr, samples.length);
      } on NativeCallException catch (e) {
        throw _nativeInferenceFailure('whisper_full', e);
      } finally {
        segmentCallable.close();
        progressCallable?.close();
      }
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

      _lastDetectedLanguage = _readDetectedLanguage(ctx);

      _logSegments(
        bindings,
        ctx,
        includeTimestamps: includeTimestamps,
        timeOffsetMs: segmentTimeOffsetMs,
        indexOffset: segmentIndexOffset,
        reset: resetLastSegments,
      );

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
      if (vadModelPathC != null) malloc.free(vadModelPathC);
    }
  }

  void _resolveLanguageLookups(ffi.DynamicLibrary dylib) {
    try {
      _fullLangId = dylib
          .lookupFunction<
            ffi.Int Function(ffi.Pointer<whisper_context>),
            int Function(ffi.Pointer<whisper_context>)
          >('whisper_full_lang_id');
      _langStr = dylib
          .lookupFunction<
            ffi.Pointer<ffi.Char> Function(ffi.Int),
            ffi.Pointer<ffi.Char> Function(int)
          >('whisper_lang_str');
    } on ArgumentError {
      _fullLangId = null;
      _langStr = null;
    }
  }

  /// The language whisper decoded the last chunk in, or `null` when the
  /// library lacks the lookups. Reads native state only after `whisper_full`
  /// has returned successfully.
  String? _readDetectedLanguage(ffi.Pointer<whisper_context> ctx) {
    final fullLangId = _fullLangId;
    final langStr = _langStr;
    if (fullLangId == null || langStr == null) return null;
    return detectedLanguageCode(fullLangId(ctx), (id) {
      final ptr = langStr(id);
      return ptr.address == 0 ? null : ptr.cast<Utf8>().toDartString();
    });
  }

  @override
  Future<void> unload() async {
    // Never leave a live-preview state dangling on a context that is about
    // to be freed — [whisper_free] does not implicitly free states opened
    // via [whisper_init_state] (they are independent allocations).
    await stopLivePreview();
    final ctx = _ctx;
    if (ctx != null) {
      _bindings?.whisper_free(ctx);
    }
    _ctx = null;
    _bindings = null;
  }

  // ── Live-transcript-during-recording preview (live-transcript-streaming
  // ticket) ──────────────────────────────────────────────────────────────
  //
  // Decodes against a SEPARATE `whisper_state` from the context's own
  // default state used by [transcribe]/[_decodeOnce] above — so a preview
  // decode triggered mid-recording can never corrupt or be corrupted by the
  // final, unchanged batch `whisper_full` call once recording stops. Kept
  // deliberately minimal compared to [_decodeOnce]: no VAD, no pause-based
  // chunking, no live/partial-transcript callback, no segment-timestamp
  // logging — this is a lightweight preview, not the code path whose output
  // is ever inserted/pasted.

  /// The dedicated live-preview decode state, or `null` when
  /// [startLivePreview] has not (yet) been called, or was stopped.
  ffi.Pointer<whisper_state>? _previewState;

  /// Int32 that aborts a running [decodeLivePreview] once non-zero (ticket
  /// 30). Owned and raised by another isolate ([WhisperIsolateEngine]) so a
  /// stop does not wait behind a whole preview window; only honoured when
  /// the guard exports `wpg_abort_flag_cb`, otherwise previews run to the
  /// end as before.
  ffi.Pointer<ffi.Int32>? livePreviewAbortFlag;

  /// Maps a C++ exception caught by `wp_ffi_guard` during inference to the
  /// notifier's resilience taxonomy: on a GPU backend it is treated like a
  /// GPU fault (ggml-vulkan/Metal throwing mid-decode) so the notifier
  /// re-runs the transcription on CPU; on CPU there is nothing to degrade
  /// to, so it is surfaced as [WhisperFailureKind.other].
  WhisperEngineException _nativeInferenceFailure(
    String call,
    NativeCallException e,
  ) {
    _log.warning('$call threw natively: ${e.message}');
    return nativeInferenceFailure(call, e, _confirmedBackend);
  }

  @override
  Future<void> startLivePreview() async {
    if (_previewState != null) return;
    final bindings = _bindings;
    final ctx = _ctx;
    if (bindings == null || ctx == null) {
      throw StateError('whisper_engine_not_loaded');
    }
    final ffi.Pointer<whisper_state> state;
    try {
      final guard = _guard;
      state = guard != null
          ? guard.whisperInitState(_initStateFn, ctx)
          : bindings.whisper_init_state(ctx);
    } on NativeCallException catch (e) {
      throw _nativeInferenceFailure('whisper_init_state', e);
    }
    if (state == ffi.nullptr) {
      throw StateError('whisper_init_state_failed');
    }
    _previewState = state;
  }

  @override
  Future<String> decodeLivePreview(
    Float32List samples, {
    String? language,
    String? prompt,
  }) async {
    final bindings = _bindings;
    final ctx = _ctx;
    final state = _previewState;
    if (bindings == null || ctx == null || state == null) {
      throw StateError('whisper_live_preview_not_started');
    }
    if (samples.isEmpty) return '';

    final samplesPtr = malloc<ffi.Float>(samples.length);
    samplesPtr.asTypedList(samples.length).setAll(0, samples);
    final languageC = (language ?? 'auto').toNativeUtf8();
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
      params.suppress_nst = true;
      params.temperature_inc = 0.0;
      // Always throttled: a preview decode always runs while this same
      // process's audio-capture thread is actively recording — the one
      // case [_decodeOnce]'s `reducedThreads` flag exists for — so this
      // never has to be asked for, it's the only correct value here.
      params.n_threads = _threadCount(reducedThreads: true);
      if (promptC != null) {
        params.initial_prompt = promptC.cast<ffi.Char>();
      }
      final abortFlag = livePreviewAbortFlag;
      final abortCallback = _guard?.abortFlagCallback;
      if (abortFlag != null && abortCallback != null) {
        params.abort_callback = abortCallback;
        params.abort_callback_user_data = abortFlag.cast();
      }

      final int rc;
      try {
        final guard = _guard;
        rc = guard != null
            ? guard.whisperFullWithState(
                _fullWithStateFn,
                ctx,
                state,
                params,
                samplesPtr,
                samples.length,
              )
            : bindings.whisper_full_with_state(
                ctx,
                state,
                params,
                samplesPtr,
                samples.length,
              );
      } on NativeCallException catch (e) {
        throw _nativeInferenceFailure('whisper_full_with_state', e);
      }
      // Stopped mid-decode: whatever whisper produced is stale, and an
      // aborted run is not an error.
      if (abortFlag != null && abortFlag.value != 0) return '';
      if (rc != 0) {
        throw WhisperEngineException(
          WhisperFailureKind.transient,
          'whisper_full_with_state failed with code $rc',
        );
      }

      final buffer = StringBuffer();
      // Read back from `state`, NOT `ctx` — whisper_full_n_segments/
      // whisper_full_get_segment_text (used by [_decodeOnce] above) read
      // ctx's own default state, which whisper_full_with_state never
      // touches. Using the ctx-based getters here would silently read
      // stale/unrelated results.
      final segments = bindings.whisper_full_n_segments_from_state(state);
      for (var i = 0; i < segments; i++) {
        final textPtr = bindings.whisper_full_get_segment_text_from_state(
          state,
          i,
        );
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
  Future<void> stopLivePreview() async {
    final state = _previewState;
    if (state == null) return;
    _bindings?.whisper_free_state(state);
    _previewState = null;
  }

  /// Silero-VAD speech-probability threshold used while under system load —
  /// see the "Noise-floor tolerance under system load" comment above.
  /// whisper.cpp's own library default is `0.5`.
  @visibleForTesting
  static const vadThresholdUnderNoise = 0.35;
  static const _vadThresholdUnderNoise = vadThresholdUnderNoise;

  /// Padding (ms) added before/after each detected-speech region — see the
  /// same comment. whisper.cpp's own library default is `30`.
  @visibleForTesting
  static const vadSpeechPadMsUnderNoise = 100;
  static const _vadSpeechPadMsUnderNoise = vadSpeechPadMsUnderNoise;

  /// Cores reserved for other work when [reducedThreads] is requested —
  /// see [_decodeOnce]'s "Audio-capture protection" comment. Deliberately
  /// leaves at least [_minReducedThreads] threads so a throttled
  /// transcription still makes real forward progress instead of stalling.
  static const _reducedThreadCoreReserve = 4;
  static const _minReducedThreads = 2;
  static const _maxReducedThreads = 4;

  @visibleForTesting
  static int computeThreadCount(int cores, {bool reducedThreads = false}) {
    if (reducedThreads) {
      return (cores - _reducedThreadCoreReserve).clamp(
        _minReducedThreads,
        _maxReducedThreads,
      );
    }
    return (cores - 1).clamp(2, 8);
  }

  static int _threadCount({bool reducedThreads = false}) {
    return computeThreadCount(
      Platform.numberOfProcessors,
      reducedThreads: reducedThreads,
    );
  }

  // ── PromptTokenCounter (prompt-token-budget fix) ────────────────────────

  /// Exact whisper.cpp token count of [text] via `whisper_tokenize` in
  /// count-only mode (`tokens: nullptr, n_max_tokens: 0`), which returns the
  /// negated count instead of writing into a buffer — see
  /// [WhisperBindings.whisper_tokenize]'s doc comment. Synchronous native
  /// call wrapped in `Future` only to satisfy [PromptTokenCounter]'s async
  /// contract (kept async so a future non-FFI engine, or an isolate-proxied
  /// one, can implement it without a signature change).
  @override
  Future<int> countPromptTokens(String text) async {
    final ctx = _ctx;
    final bindings = _bindings;
    if (ctx == null || bindings == null) {
      throw StateError('countPromptTokens called before load()');
    }
    if (text.isEmpty) return 0;
    final textC = text.toNativeUtf8();
    try {
      final result = bindings.whisper_tokenize(
        ctx,
        textC.cast<ffi.Char>(),
        ffi.nullptr,
        0,
      );
      // Negative in count-only mode (`-actualTokenCount`); a non-negative
      // result here would mean the native call somehow wrote into a
      // zero-capacity buffer, which whisper.cpp's own contract rules out.
      return result < 0 ? -result : result;
    } finally {
      malloc.free(textC);
    }
  }
}

/// Test-only entry point for [WhisperFfiEngine._confirmBackend] — probes the
/// real ggml device registry in [dylib] (having first ensured its backends
/// are registered, mirroring [WhisperFfiEngine.load]'s own sequencing)
/// without needing a full model load. Lets tests exercise the actual
/// registry-probing logic against a real bundled dylib (e.g. the app's own
/// already-built `libwhisper.dylib`) without the multi-gigabyte production
/// model or the gitignored durchstich fixtures this file's other tests skip
/// without.
@visibleForTesting
(WhisperBackend, String?) confirmBackendForTesting(
  ffi.DynamicLibrary dylib,
  String libraryPath,
  WhisperBackend requested,
) {
  WhisperFfiEngine._ensureBackendsLoaded(dylib, libraryPath);
  final (backend, device, _) = WhisperFfiEngine._confirmBackend(
    dylib,
    requested,
    ggml: WhisperFfiEngine._registryFor(libraryPath),
  );
  return (backend, device);
}

/// Picks the CPU module to load from [scores] (module path to score): the
/// highest score above 0 wins, ties go to the lexicographically first path so
/// the choice does not depend on directory listing order. `null` if no module
/// reports support.
@visibleForTesting
String? pickBestCpuModule(Map<String, int> scores) {
  String? best;
  var bestScore = 0;
  for (final path in scores.keys.toList()..sort()) {
    final score = scores[path]!;
    if (score > bestScore) {
      best = path;
      bestScore = score;
    }
  }
  return best;
}

/// File name of the ggml CUDA module inside an optional CUDA pack.
String cudaModuleFileName() =>
    Platform.isWindows ? 'ggml-cuda.dll' : 'libggml-cuda.so';

/// `enum ggml_backend_dev_type` values for the GPU-classifying devices
/// (`ggml-backend.h`; confirmed against the vendored v1.9.5 header and the
/// bundled macOS dylib: `MTL0`→1). CPU (0) and ACCEL (3, e.g. Apple's BLAS
/// backend) are deliberately not GPU devices — an ACCEL device alongside
/// CPU-only does not mean GPU acceleration is happening.
const int ggmlDeviceTypeGpu = 1;
const int ggmlDeviceTypeIgpu = 2;

String _gpuTypeLabel(int type) => switch (type) {
  ggmlDeviceTypeGpu => 'discrete',
  ggmlDeviceTypeIgpu => 'integrated',
  _ => 'type $type',
};

/// Index (among the registered GPU devices, in registry order) of the device
/// whisper.cpp should use — the value for `whisper_context_params.gpu_device`.
///
/// whisper.cpp counts only GPU and IGPU devices in registry order and takes
/// the N-th one. ggml-vulkan registers integrated and discrete adapters in OS
/// enumeration order without preference, so on a hybrid laptop index 0 can be
/// the iGPU. Ranking, first match wins:
///
/// 1. with [preferCuda], the first `CUDA*` device: the optional CUDA pack is
///    registered after the bundled backends, so on an NVIDIA machine the same
///    card usually shows up first as `Vulkan0` and later as `CUDA0`;
/// 2. the first discrete GPU ([ggmlDeviceTypeGpu]);
/// 3. the first integrated GPU ([ggmlDeviceTypeIgpu]).
///
/// [gpuTypes] is parallel to [gpuNames]. Without it every device is treated
/// as discrete, which reduces the rule to "first device" (whisper.cpp's
/// default of `0`).
int pickGpuDeviceIndex(
  List<String?> gpuNames, {
  required bool preferCuda,
  List<int>? gpuTypes,
}) {
  if (preferCuda) {
    final cuda = gpuNames.indexWhere((n) => n?.startsWith('CUDA') ?? false);
    if (cuda >= 0) return cuda;
  }
  final types = gpuTypes ?? List.filled(gpuNames.length, ggmlDeviceTypeGpu);
  final discrete = types.indexOf(ggmlDeviceTypeGpu);
  if (discrete >= 0) return discrete;
  final integrated = types.indexOf(ggmlDeviceTypeIgpu);
  return integrated >= 0 ? integrated : 0;
}

/// Backend that actually runs on the registry device [deviceName] (as chosen
/// by [pickGpuDeviceIndex]). The requested backend is only a guess: with CUDA
/// requested but no CUDA device registered, whisper.cpp runs on a Vulkan
/// device, and the status, diagnostics and crash recovery must say so.
/// Falls back to [requested] for unknown or missing names.
@visibleForTesting
WhisperBackend backendForDevice(String? deviceName, WhisperBackend requested) {
  final name = deviceName ?? '';
  if (name.startsWith('CUDA')) return WhisperBackend.cuda;
  if (name.startsWith('Vulkan')) return WhisperBackend.vulkan;
  if (name.startsWith('MTL')) return WhisperBackend.metal;
  return requested;
}

/// Pure mapping behind [WhisperFfiEngine._nativeInferenceFailure], split out
/// for unit tests.
@visibleForTesting
WhisperEngineException nativeInferenceFailure(
  String call,
  NativeCallException e,
  WhisperBackend backend,
) => WhisperEngineException(
  backend == WhisperBackend.cpu
      ? WhisperFailureKind.other
      : WhisperFailureKind.gpuCrash,
  '$call threw a native exception: ${e.message}',
);
