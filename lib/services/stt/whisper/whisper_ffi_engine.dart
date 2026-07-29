/// Real in-process [WhisperEngine] backed by a bundled `libwhisper` via
/// `dart:ffi` (whisper.cpp v1.8.4). Built on the binding proven in the Issue-01
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

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../audio/pcm_wav_codec.dart';
import 'whisper_bindings.dart';
import 'whisper_engine.dart';

final _log = AppLogger('WhisperFfi');

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
  });

  final int index;
  final int? startMs;
  final int? endMs;
  final String text;

  @override
  String toString() => startMs != null
      ? 'WhisperSegment[$index] ${startMs}ms-${endMs}ms: $text'
      : 'WhisperSegment[$index]: $text';
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

  /// Raw lookups for `whisper_full_get_segment_t0/t1` — not covered by the
  /// ffigen-generated [WhisperBindings] (`whisper_bindings.dart`, do-not-edit).
  /// Resolved once in [load]; `null` if the symbol is missing from an older
  /// bundled `libwhisper` build, in which case [_logSegments] degrades to
  /// segment count + text length only. Diagnostic-only — see [_logSegments].
  int Function(ffi.Pointer<whisper_context>, int)? _segmentT0;
  int Function(ffi.Pointer<whisper_context>, int)? _segmentT1;

  /// Per-segment breakdown of the most recent [transcribe] call. Populated
  /// by [_logSegments]; empty before the first call or if the last call
  /// failed before segment assembly. Exposed (read-only) so diagnostic
  /// tooling — see `test/services/stt/whisper/transcribe_debug_harness_test.dart`
  /// — can inspect segment boundaries/text directly without depending on
  /// [AppLogger] being initialized. Not used by any production call site.
  List<WhisperSegment> get lastSegments => List.unmodifiable(_lastSegments);
  List<WhisperSegment> _lastSegments = const [];

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
      _ensureBackendsLoaded(dylib, _libraryPath);
      final bindings = WhisperBindings.fromLookup(dylib.lookup);
      _ensureLogCallbackRegistered(bindings);
      _resolveSegmentTimestampLookups(dylib);
      final cparams = bindings.whisper_context_default_params();
      cparams.use_gpu = _backend != WhisperBackend.cpu;
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

  static bool _logCallbackRegistered = false;

  // Never read — this reference exists solely to keep the NativeCallable
  // (and the native function pointer ggml now holds via whisper_log_set)
  // alive for the process lifetime. Letting it go out of scope would let
  // the GC close the callable and invalidate that pointer while ggml still
  // has it registered.
  // ignore: unused_field
  static ffi.NativeCallable<GgmlLogCallbackNative>? _logCallable;

  /// Redirects ggml/whisper.cpp's internal logging away from its stderr
  /// default (see `whisper_log_set`'s doc comment in ggml.h: "If this is
  /// not called, or NULL is supplied, everything is output on stderr") — a
  /// console-less Windows GUI/MSIX process has no guaranteed-valid stderr
  /// handle for that default path (FLUTTER_WHISPASTE-BB).
  ///
  /// Deliberately does NOT read the native `text` pointer: ggml formats each
  /// log line into a buffer that is stack-local (or freed immediately after
  /// the synchronous call) in `ggml_log_internal_v` — safe to read only
  /// within that synchronous call, which `NativeCallable.listener` cannot
  /// guarantee (it defers running the Dart callback body onto the isolate's
  /// event loop, by which point the native buffer may already be gone).
  /// `.listener` is required over `.isolateLocal` because ggml can log from
  /// worker threads never registered with the Dart isolate. Only the `level`
  /// (a plain int, always safe to read) is forwarded.
  static void _ensureLogCallbackRegistered(WhisperBindings bindings) {
    if (_logCallbackRegistered) return;
    _logCallbackRegistered = true;
    final callable = ffi.NativeCallable<GgmlLogCallbackNative>.listener(
      _onGgmlLog,
    );
    _logCallable = callable;
    bindings.whisper_log_set(callable.nativeFunction, ffi.nullptr);
  }

  static void _onGgmlLog(
    int level,
    ffi.Pointer<ffi.Char> text,
    ffi.Pointer<ffi.Void> userData,
  ) {
    // level: 0=none 1=debug 2=info 3=warn 4=error 5=cont (ggml_log_level).
    if (level >= 4) {
      _log.warning('native ggml/whisper log (level=$level)');
    } else {
      _log.debug('native ggml/whisper log (level=$level)');
    }
  }

  static bool _backendsLoaded = false;

  /// Calls ggml's `ggml_backend_load_all()` exactly once per process — see
  /// the file doc comment for why this is required at all with
  /// `-DGGML_BACKEND_DL=ON`. Safe/idempotent to skip on repeat [load] calls;
  /// ggml's own registry dedupes by backend name regardless, this guard just
  /// avoids the redundant directory scan.
  ///
  /// Usually exported by a separate `ggml` shared library next to
  /// [libraryPath] (confirmed via `dumpbin /exports` against the real
  /// production DLLs on Windows: `ggml.dll` exports the full registry API —
  /// `ggml_backend_load_all`, `ggml_backend_dev_by_type`, etc. — while
  /// `ggml-base.dll` only exports lower-level per-device accessors like
  /// `ggml_backend_dev_backend_reg`, which is where the crash this fixes
  /// symbolicated via WinDbg) — but some bundles statically link ggml into
  /// the main whisper library instead, so [dylib] itself is tried first.
  static void _ensureBackendsLoaded(
    ffi.DynamicLibrary dylib,
    String libraryPath,
  ) {
    if (_backendsLoaded) return;
    void Function()? loadAll;
    try {
      loadAll = dylib.lookupFunction<ffi.Void Function(), void Function()>(
        'ggml_backend_load_all',
      );
    } on ArgumentError {
      final ggmlName = Platform.isWindows
          ? 'ggml.dll'
          : (Platform.isMacOS ? 'libggml.dylib' : 'libggml.so');
      final ggmlPath = p.join(p.dirname(libraryPath), ggmlName);
      if (!File(ggmlPath).existsSync()) return;
      final ggml = ffi.DynamicLibrary.open(ggmlPath);
      loadAll = ggml.lookupFunction<ffi.Void Function(), void Function()>(
        'ggml_backend_load_all',
      );
    }
    loadAll();
    _backendsLoaded = true;
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
  void _logSegments(
    WhisperBindings bindings,
    ffi.Pointer<whisper_context> ctx, {
    required bool includeTimestamps,
  }) {
    final n = bindings.whisper_full_n_segments(ctx);
    final t0 = includeTimestamps ? _segmentT0 : null;
    final t1 = includeTimestamps ? _segmentT1 : null;
    final segments = <WhisperSegment>[];
    for (var i = 0; i < n; i++) {
      final textPtr = bindings.whisper_full_get_segment_text(ctx, i);
      final text = textPtr.cast<Utf8>().toDartString();
      if (t0 != null && t1 != null) {
        // whisper.cpp reports t0/t1 in centiseconds (10 ms units).
        final startMs = t0(ctx, i) * 10;
        final endMs = t1(ctx, i) * 10;
        segments.add(
          WhisperSegment(index: i, startMs: startMs, endMs: endMs, text: text),
        );
        _log.debug(
          'segment[$i/$n] ${startMs}ms-${endMs}ms textLen=${text.length}',
        );
      } else {
        segments.add(
          WhisperSegment(index: i, startMs: null, endMs: null, text: text),
        );
        _log.debug('segment[$i/$n] textLen=${text.length}');
      }
    }
    _lastSegments = segments;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool includeTimestamps = false,
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
      params.n_threads = _threadCount();
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
      // decode source (`.build/deps/whisper.cpp/v1.8.4/src/whisper.cpp`)
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

      _logSegments(bindings, ctx, includeTimestamps: includeTimestamps);

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
