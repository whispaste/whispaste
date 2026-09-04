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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/windows_dll_search_path.dart';
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
  return p.join(libraryDir, 'ggml-silero-v5.1.2.bin');
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
class WhisperFfiEngine implements WhisperEngine {
  WhisperFfiEngine({String? libraryPath, WhisperBackend? backend})
    : _libraryPath = libraryPath ?? defaultWhisperLibraryPath(),
      _backend = backend ?? WhisperBackend.cpu,
      _confirmedBackend = backend ?? WhisperBackend.cpu;

  final String _libraryPath;
  final WhisperBackend _backend;

  /// [_backend] as actually confirmed against ggml's device registry by
  /// [_confirmBackend] — see its doc comment. Equals [_backend] until the
  /// first [load] call.
  WhisperBackend _confirmedBackend;

  WhisperBindings? _bindings;
  ffi.Pointer<whisper_context>? _ctx;
  String? _errorMessage;

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
    backend: _confirmedBackend,
    errorMessage: _errorMessage,
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
      _ensureBackendsLoaded(dylib, _libraryPath);
      _confirmedBackend = _confirmBackend(dylib, _backend);
      final bindings = WhisperBindings.fromLookup(dylib.lookup);
      _ensureLogCallbackRegistered(bindings);
      _resolveSegmentTimestampLookups(dylib);
      final cparams = bindings.whisper_context_default_params();
      cparams.use_gpu = _confirmedBackend != WhisperBackend.cpu;
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
    var resolved = dylib;
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
      resolved = ggml;
      loadAll = ggml.lookupFunction<ffi.Void Function(), void Function()>(
        'ggml_backend_load_all',
      );
    }
    loadAll();
    _resolvedGgmlLibrary = resolved;
    _backendsLoaded = true;
  }

  /// The library [_ensureBackendsLoaded] actually found `ggml_backend_load_all`
  /// in — `dylib` itself, or the separate `libggml`/`ggml.dll` fallback next to
  /// it. [_confirmBackend] probes this same library for the device-registry
  /// symbols, since a split-library bundle (observed on Windows: `ggml.dll`
  /// exports the registry API, `ggml-base.dll` only lower-level accessors —
  /// see this class's file doc comment) may not export them from `dylib`.
  static ffi.DynamicLibrary? _resolvedGgmlLibrary;

  /// `ggml_backend_dev_type`'s GPU-classifying values (`ggml-backend.h`'s
  /// `enum ggml_backend_dev_type`, confirmed against the bundled macOS
  /// dylib: `MTL0`→1, `BLAS`→3, `CPU`→0). CPU and ACCEL (e.g. Apple's BLAS
  /// backend) are deliberately excluded — an ACCEL device alongside CPU-only
  /// does not mean GPU acceleration is happening.
  static const _ggmlBackendDeviceTypeGpu = 1;
  static const _ggmlBackendDeviceTypeIgpu = 2;

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
  static WhisperBackend _confirmBackend(
    ffi.DynamicLibrary dylib,
    WhisperBackend requested,
  ) {
    if (requested == WhisperBackend.cpu) return WhisperBackend.cpu;
    final candidates = <ffi.DynamicLibrary>[
      dylib,
      if (_resolvedGgmlLibrary != null &&
          !identical(_resolvedGgmlLibrary, dylib))
        _resolvedGgmlLibrary!,
    ];
    for (final lib in candidates) {
      try {
        final devCount = lib
            .lookupFunction<ffi.Size Function(), int Function()>(
              'ggml_backend_dev_count',
            );
        final devGet = lib
            .lookupFunction<
              ffi.Pointer<ffi.Void> Function(ffi.Size),
              ffi.Pointer<ffi.Void> Function(int)
            >('ggml_backend_dev_get');
        final devType = lib
            .lookupFunction<
              ffi.Int32 Function(ffi.Pointer<ffi.Void>),
              int Function(ffi.Pointer<ffi.Void>)
            >('ggml_backend_dev_type');
        for (var i = 0; i < devCount(); i++) {
          final type = devType(devGet(i));
          if (type == _ggmlBackendDeviceTypeGpu ||
              type == _ggmlBackendDeviceTypeIgpu) {
            return requested;
          }
        }
        _log.warning(
          'Requested $requested but no GPU device is registered in the '
          'ggml backend registry — downgrading to CPU',
        );
        return WhisperBackend.cpu;
      } on ArgumentError {
        continue;
      }
    }
    return requested;
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
  }) async {
    final bindings = _bindings;
    final ctx = _ctx;
    if (bindings == null || ctx == null) {
      throw StateError('whisper_engine_not_loaded');
    }

    final samples = pcm16WavBytesToFloat32(wavBytes);
    if (samples.isEmpty) return '';

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
    // investigation (`.scratch/transcription-quality-under-load/PRD.md`):
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

  /// Finds sample indices to split [samples] on, each a real pause of at
  /// least [_minPauseDurationMs], such that no resulting chunk exceeds
  /// [_maxChunkDurationMs]. Falls back to a hard cut at
  /// [_maxChunkDurationMs] when no pause is found within that span (rare in
  /// natural speech, but must still be bounded to preserve the mechanism
  /// this exists for). Pure and allocation-light — safe to unit-test without
  /// the native library.
  @visibleForTesting
  static List<int> findPauseSplitPoints(
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

    final splitFrames = <int>[];
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
      if (chosen == -1) {
        // No natural pause in range — force a hard cut so the invariant
        // (no chunk exceeds maxChunkDurationMs) always holds.
        chosen = chunkLimitFrame;
      }
      splitFrames.add(chosen);
      lastSplitFrame = chosen;
    }

    return splitFrames.map((f) => f * frameLen).toList(growable: false);
  }

  /// Trailing words of [text] to carry forward as extra continuity context
  /// into the next chunk's prompt — bounded the same way
  /// `params.n_max_text_ctx = 64` bounds whisper's own internal
  /// window-to-window conditioning (see that comment below), so a degraded
  /// chunk's output can still poison at most this much of the next chunk's
  /// prompt, never the whole rest of the recording.
  static const _continuityContextChars = 200;

  @visibleForTesting
  static String continuityContextFrom(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= _continuityContextChars) return trimmed;
    return trimmed.substring(trimmed.length - _continuityContextChars);
  }

  Future<String> _transcribeInChunks(
    WhisperBindings bindings,
    ffi.Pointer<whisper_context> ctx,
    Float32List samples, {
    required String? language,
    required String? prompt,
    required bool includeTimestamps,
    required bool vadEnabled,
    required bool reducedThreads,
  }) async {
    final splitPoints = findPauseSplitPoints(samples);
    if (splitPoints.isEmpty) {
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
      );
    }

    _log.debug(
      'long dictation (${(samples.length * 1000 / WHISPER_SAMPLE_RATE).round()}ms) '
      'split into ${splitPoints.length + 1} chunks at natural pauses',
    );

    final buffer = StringBuffer();
    String? carryPrompt = prompt;
    var chunkStart = 0;
    var segmentIndexOffset = 0;
    final boundaries = [...splitPoints, samples.length];
    for (var i = 0; i < boundaries.length; i++) {
      final chunkEnd = boundaries[i];
      final chunkSamples = Float32List.sublistView(
        samples,
        chunkStart,
        chunkEnd,
      );
      final chunkStartMs = (chunkStart * 1000 / WHISPER_SAMPLE_RATE).round();
      final chunkText = await _decodeOnce(
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
      );
      buffer.write(chunkText);
      segmentIndexOffset = _lastSegments.length;

      final tail = continuityContextFrom(chunkText);
      final hasOriginalPrompt = prompt != null && prompt.isNotEmpty;
      carryPrompt = tail.isEmpty
          ? prompt
          : (hasOriginalPrompt ? '$prompt $tail' : tail);

      chunkStart = chunkEnd;
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
        // (`.scratch/transcription-quality-under-load/PRD.md`): the
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

  @override
  Future<void> unload() async {
    final ctx = _ctx;
    if (ctx != null) {
      _bindings?.whisper_free(ctx);
    }
    _ctx = null;
    _bindings = null;
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
WhisperBackend confirmBackendForTesting(
  ffi.DynamicLibrary dylib,
  String libraryPath,
  WhisperBackend requested,
) {
  WhisperFfiEngine._ensureBackendsLoaded(dylib, libraryPath);
  return WhisperFfiEngine._confirmBackend(dylib, requested);
}
