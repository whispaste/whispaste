/// Dart side of `native/ffi_guard` (`wp_ffi_guard`): routes the FFI calls
/// into whisper.cpp/ggml and sherpa-onnx that can throw C++ exceptions
/// through a native try/catch, so such an exception arrives here as a
/// [NativeCallException] instead of unwinding into a Dart FFI frame —
/// which the VM cannot handle and which ends in `std::terminate` → `abort`
/// (Windows: `0xC0000409` / `FAST_FAIL_FATAL_APP_EXIT`, Sentry 140866975,
/// 135332054, 151627808).
///
/// The guard library is bundled next to `libwhisper` on every platform
/// (`scripts/build-libwhisper-*`, `release.yml`). A missing or incompatible
/// guard (dev checkout without the native build, stale bundle) is not an
/// error: callers then fall back to calling the target directly, exactly as
/// before the guard existed. `whispaste --diagnose` reports a missing guard
/// so packaging regressions still fail the release smoke test.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import 'whisper/whisper_bindings.dart';

final _log = AppLogger('NativeCallGuard');

/// A C++ exception caught by `wp_ffi_guard` around a native call.
class NativeCallException implements Exception {
  NativeCallException(this.code, this.message);

  /// `WPG_STD_EXCEPTION` (-1, [message] is `what()`) or
  /// `WPG_UNKNOWN_EXCEPTION` (-2, a non-`std::exception` was thrown).
  final int code;
  final String message;

  @override
  String toString() => 'NativeCallException($code): $message';
}

typedef _AbiVersionNative = ffi.Int Function();
typedef _SizeOfNative = ffi.Size Function();
typedef _InitFromFileNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<whisper_context_params>,
      ffi.Pointer<ffi.Pointer<whisper_context>>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _InitFromFileDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<whisper_context_params>,
      ffi.Pointer<ffi.Pointer<whisper_context>>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _InitStateNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<ffi.Pointer<whisper_state>>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _InitStateDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<ffi.Pointer<whisper_state>>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _FullNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<whisper_full_params>,
      ffi.Pointer<ffi.Float>,
      ffi.Int,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _FullDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<whisper_full_params>,
      ffi.Pointer<ffi.Float>,
      int,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _FullWithStateNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<whisper_state>,
      ffi.Pointer<whisper_full_params>,
      ffi.Pointer<ffi.Float>,
      ffi.Int,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _FullWithStateDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<whisper_state>,
      ffi.Pointer<whisper_full_params>,
      ffi.Pointer<ffi.Float>,
      int,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _CallVoidPPNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _CallVoidPPDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      int,
    );

typedef _GuardVoidVoidNative =
    ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Size);
typedef _GuardVoidVoidDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, int);
typedef _GuardVoidCStrNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardVoidCStrDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardPtrCStrNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardPtrCStrDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Char>,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardCStrOutNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Char>>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardCStrOutDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Char>>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardCStrPtrNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Char>>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardCStrPtrDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Pointer<ffi.Char>>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardSizeOutNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Size>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardSizeOutDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Size>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardPtrSizeNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Size,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardPtrSizeDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Pointer<ffi.Void>>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardIntPtrNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardScoreNative =
    ffi.Int Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _GuardScoreDart =
    int Function(
      ffi.Pointer<Utf8>,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardIntPtrDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      int,
    );
typedef _GuardFlagGetNative = ffi.Int Function(ffi.Int);
typedef _GuardFlagGetDart = int Function(int);
typedef _GuardFlagSetNative = ffi.Void Function(ffi.Int, ffi.Int);
typedef _GuardFlagSetDart = void Function(int, int);
typedef _GuardLogInstallNative =
    ffi.Int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, ffi.Size);
typedef _GuardLogInstallDart =
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Char>, int);
typedef _GuardLogSinkNative =
    ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Void>);
typedef _GuardLogSinkDart =
    void Function(int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Void>);
typedef _GuardLogPopNative =
    ffi.Int Function(ffi.Pointer<ffi.Int>, ffi.Pointer<ffi.Char>, ffi.Size);
typedef _GuardLogPopDart =
    int Function(ffi.Pointer<ffi.Int>, ffi.Pointer<ffi.Char>, int);
typedef _GuardTakeDroppedNative = ffi.Size Function();
typedef _GuardTakeDroppedDart = int Function();

/// `wpg_process_flag_*` slots (`ffi_guard.h`). Process-wide on the native
/// side, so every isolate of the process sees the same value.
abstract final class WpgFlag {
  /// 0 none, 1 CPU module only, 2 all backend modules.
  static const int backends = 1;

  /// 0 not attempted, 1 attempted.
  static const int cudaPack = 2;
}

/// One line popped from the native ggml/whisper log ring.
class NativeLogLine {
  const NativeLogLine(this.level, this.text);

  /// `ggml_log_level`: 0 none, 1 debug, 2 info, 3 warn, 4 error, 5 continue.
  final int level;
  final String text;
}

/// Loaded `wp_ffi_guard` library. Obtain via [NativeCallGuard.nextTo] or
/// [NativeCallGuard.tryOpen]; every call throws [NativeCallException] when
/// the target threw.
class NativeCallGuard {
  NativeCallGuard._(this.library)
    : _initFromFile = library
          .lookupFunction<_InitFromFileNative, _InitFromFileDart>(
            'wpg_whisper_init_from_file',
          ),
      _initState = library.lookupFunction<_InitStateNative, _InitStateDart>(
        'wpg_whisper_init_state',
      ),
      _full = library.lookupFunction<_FullNative, _FullDart>(
        'wpg_whisper_full',
      ),
      _fullWithState = library
          .lookupFunction<_FullWithStateNative, _FullWithStateDart>(
            'wpg_whisper_full_with_state',
          ),
      _callVoidPP = library.lookupFunction<_CallVoidPPNative, _CallVoidPPDart>(
        'wpg_call_void_pp',
      ),
      supportsWhisperStructs =
          library.lookupFunction<_SizeOfNative, int Function()>(
                'wpg_sizeof_whisper_context_params',
              )() ==
              ffi.sizeOf<whisper_context_params>() &&
          library.lookupFunction<_SizeOfNative, int Function()>(
                'wpg_sizeof_whisper_full_params',
              )() ==
              ffi.sizeOf<whisper_full_params>();

  /// `WPG_ABI_VERSION` this binding was written against (`ffi_guard.h`).
  static const abiVersion = 2;

  /// Bytes reserved for the exception message (truncated natively).
  static const _errorBufferLength = 512;

  final ffi.DynamicLibrary library;
  final _InitFromFileDart _initFromFile;
  final _InitStateDart _initState;
  final _FullDart _full;
  final _FullWithStateDart _fullWithState;
  final _CallVoidPPDart _callVoidPP;

  /// Whether the guard was compiled against the same `whisper_*_params`
  /// layout as `whisper_bindings.dart`. The whisper wrappers copy those
  /// structs byte-for-byte, so callers must not use them when this is false.
  final bool supportsWhisperStructs;

  /// Platform file name of the guard library.
  static String get fileName => Platform.isWindows
      ? 'wp_ffi_guard.dll'
      : Platform.isMacOS
      ? 'libwp_ffi_guard.dylib'
      : 'libwp_ffi_guard.so';

  /// The guard bundled in the same directory as [whisperLibraryPath].
  static String pathNextTo(String whisperLibraryPath) =>
      p.join(p.dirname(whisperLibraryPath), fileName);

  static final Map<String, NativeCallGuard?> _cache = {};

  /// [tryOpen] on [pathNextTo], cached per path for the isolate's lifetime.
  static NativeCallGuard? nextTo(String whisperLibraryPath) {
    final path = pathNextTo(whisperLibraryPath);
    return _cache.putIfAbsent(path, () => tryOpen(path));
  }

  /// Opens the guard at [path], or returns `null` (logged) when it is
  /// missing, fails to load or has an unknown ABI version.
  static NativeCallGuard? tryOpen(String path) {
    if (!File(path).existsSync()) {
      _log.warning('FFI guard not found at $path — native calls unguarded');
      return null;
    }
    try {
      final library = ffi.DynamicLibrary.open(path);
      final version = library.lookupFunction<_AbiVersionNative, int Function()>(
        'wpg_abi_version',
      )();
      if (version != abiVersion) {
        _log.warning(
          'FFI guard at $path has ABI $version, expected $abiVersion — '
          'native calls unguarded',
        );
        return null;
      }
      final guard = NativeCallGuard._(library);
      if (!guard.supportsWhisperStructs) {
        _log.warning(
          'FFI guard at $path was built against different whisper.h struct '
          'layouts — whisper calls unguarded',
        );
      }
      return guard;
    } on Object catch (e) {
      _log.warning('FFI guard at $path failed to load: $e');
      return null;
    }
  }

  int _run(int Function(ffi.Pointer<ffi.Char> err, int errLen) call) {
    final err = calloc<ffi.Char>(_errorBufferLength);
    try {
      final code = call(err, _errorBufferLength);
      if (code != 0) {
        throw NativeCallException(code, err.cast<Utf8>().toDartString());
      }
      return code;
    } finally {
      calloc.free(err);
    }
  }

  /// `whisper_init_from_file_with_params(path, params)` via [fn].
  ffi.Pointer<whisper_context> whisperInitFromFile(
    ffi.Pointer<ffi.Void> fn,
    ffi.Pointer<ffi.Char> path,
    whisper_context_params params,
  ) {
    final paramsPtr = calloc<whisper_context_params>();
    final out = calloc<ffi.Pointer<whisper_context>>();
    try {
      paramsPtr.ref = params;
      _run((err, len) => _initFromFile(fn, path, paramsPtr, out, err, len));
      return out.value;
    } finally {
      calloc
        ..free(paramsPtr)
        ..free(out);
    }
  }

  /// `whisper_init_state(ctx)` via [fn].
  ffi.Pointer<whisper_state> whisperInitState(
    ffi.Pointer<ffi.Void> fn,
    ffi.Pointer<whisper_context> ctx,
  ) {
    final out = calloc<ffi.Pointer<whisper_state>>();
    try {
      _run((err, len) => _initState(fn, ctx, out, err, len));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// `whisper_full(ctx, params, samples, nSamples)` via [fn]; returns its
  /// return code.
  int whisperFull(
    ffi.Pointer<ffi.Void> fn,
    ffi.Pointer<whisper_context> ctx,
    whisper_full_params params,
    ffi.Pointer<ffi.Float> samples,
    int nSamples,
  ) {
    final paramsPtr = calloc<whisper_full_params>();
    final rc = calloc<ffi.Int>();
    try {
      paramsPtr.ref = params;
      _run(
        (err, len) =>
            _full(fn, ctx, paramsPtr, samples, nSamples, rc, err, len),
      );
      return rc.value;
    } finally {
      calloc
        ..free(paramsPtr)
        ..free(rc);
    }
  }

  /// `whisper_full_with_state(ctx, state, params, samples, nSamples)` via
  /// [fn]; returns its return code.
  int whisperFullWithState(
    ffi.Pointer<ffi.Void> fn,
    ffi.Pointer<whisper_context> ctx,
    ffi.Pointer<whisper_state> state,
    whisper_full_params params,
    ffi.Pointer<ffi.Float> samples,
    int nSamples,
  ) {
    final paramsPtr = calloc<whisper_full_params>();
    final rc = calloc<ffi.Int>();
    try {
      paramsPtr.ref = params;
      _run(
        (err, len) => _fullWithState(
          fn,
          ctx,
          state,
          paramsPtr,
          samples,
          nSamples,
          rc,
          err,
          len,
        ),
      );
      return rc.value;
    } finally {
      calloc
        ..free(paramsPtr)
        ..free(rc);
    }
  }

  /// `void fn(a, b)`, e.g. `SherpaOnnxDecodeOfflineStream(recognizer,
  /// stream)`.
  void callVoidPP(
    ffi.Pointer<ffi.Void> fn,
    ffi.Pointer<ffi.Void> a,
    ffi.Pointer<ffi.Void> b,
  ) {
    _run((err, len) => _callVoidPP(fn, a, b, err, len));
  }

  /// `wpg_abort_flag_cb` (see `ffi_guard.h`): a whisper `abort_callback`
  /// that fires once the int32 its user data points at is non-zero — lets
  /// another isolate cancel an in-flight decode. `null` for a guard built
  /// before the export existed.
  late final ffi.Pointer<
    ffi.NativeFunction<ffi.Bool Function(ffi.Pointer<ffi.Void>)>
  >?
  abortFlagCallback = library.providesSymbol('wpg_abort_flag_cb')
      ? library.lookup('wpg_abort_flag_cb')
      : null;

  /// Address of the guard's own throwing test hook (`wpg_selftest_throw`,
  /// see `ffi_guard.h`) — for tests and `--diagnose` only.
  ffi.Pointer<ffi.Void> get selfTestThrow =>
      library.lookup<ffi.Void>('wpg_selftest_throw');

  /// Proves the catch path works in this process: calls the self-test hook
  /// through [callVoidPP] with `kind` (0 = no throw, 1 = std::exception,
  /// 2 = non-std exception).
  void selfTest(int kind) {
    final kindPtr = calloc<ffi.Int>()..value = kind;
    try {
      callVoidPP(selfTestThrow, kindPtr.cast(), ffi.nullptr);
    } finally {
      calloc.free(kindPtr);
    }
  }

  // ── ggml backend registry and log sink (ABI 2) ─────────────────────────
  //
  // Each wrapper takes the target's address (`fn`, resolved by the caller
  // from the app's own library) and turns a C++ exception from it into a
  // [NativeCallException]. The lookups are lazy: they are only needed on the
  // backend-load path and in tests.

  late final _GuardVoidVoidDart _callVoidFn = library
      .lookupFunction<_GuardVoidVoidNative, _GuardVoidVoidDart>(
        'wpg_call_void',
      );
  late final _GuardVoidCStrDart _callVoidCStrFn = library
      .lookupFunction<_GuardVoidCStrNative, _GuardVoidCStrDart>(
        'wpg_call_void_cstr',
      );
  late final _GuardPtrCStrDart _callPtrCStrFn = library
      .lookupFunction<_GuardPtrCStrNative, _GuardPtrCStrDart>(
        'wpg_call_ptr_cstr',
      );
  late final _GuardCStrOutDart _callCStrVoidFn = library
      .lookupFunction<_GuardCStrOutNative, _GuardCStrOutDart>(
        'wpg_call_cstr_void',
      );
  late final _GuardCStrPtrDart _callCStrPtrFn = library
      .lookupFunction<_GuardCStrPtrNative, _GuardCStrPtrDart>(
        'wpg_call_cstr_ptr',
      );
  late final _GuardSizeOutDart _callSizeVoidFn = library
      .lookupFunction<_GuardSizeOutNative, _GuardSizeOutDart>(
        'wpg_call_size_void',
      );
  late final _GuardPtrSizeDart _callPtrSizeFn = library
      .lookupFunction<_GuardPtrSizeNative, _GuardPtrSizeDart>(
        'wpg_call_ptr_size',
      );
  late final _GuardIntPtrDart _callIntPtrFn = library
      .lookupFunction<_GuardIntPtrNative, _GuardIntPtrDart>('wpg_call_int_ptr');
  late final _GuardScoreDart _backendScoreFn = library
      .lookupFunction<_GuardScoreNative, _GuardScoreDart>('wpg_backend_score');
  late final _GuardFlagGetDart _flagGetFn = library
      .lookupFunction<_GuardFlagGetNative, _GuardFlagGetDart>(
        'wpg_process_flag_get',
      );
  late final _GuardFlagSetDart _flagSetFn = library
      .lookupFunction<_GuardFlagSetNative, _GuardFlagSetDart>(
        'wpg_process_flag_set',
      );
  late final _GuardLogInstallDart _logInstallFn = library
      .lookupFunction<_GuardLogInstallNative, _GuardLogInstallDart>(
        'wpg_log_install',
      );
  late final _GuardLogSinkDart _logSinkFn = library
      .lookupFunction<_GuardLogSinkNative, _GuardLogSinkDart>('wpg_log_sink');
  late final _GuardLogPopDart _logPopFn = library
      .lookupFunction<_GuardLogPopNative, _GuardLogPopDart>('wpg_log_pop');
  late final _GuardTakeDroppedDart _takeDroppedFn = library
      .lookupFunction<_GuardTakeDroppedNative, _GuardTakeDroppedDart>(
        'wpg_log_take_dropped',
      );

  /// `ggml_backend_load_all()` via [fn].
  void callVoid(ffi.Pointer<ffi.Void> fn) {
    _run((err, len) => _callVoidFn(fn, err, len));
  }

  /// `ggml_backend_load_all_from_path(arg)` via [fn].
  void callVoidCString(ffi.Pointer<ffi.Void> fn, String arg) {
    final argC = arg.toNativeUtf8();
    try {
      _run((err, len) => _callVoidCStrFn(fn, argC.cast(), err, len));
    } finally {
      malloc.free(argC);
    }
  }

  /// `ggml_backend_load(arg)` via [fn]: the registered backend, or `null`
  /// when ggml rejected the module.
  ffi.Pointer<ffi.Void> callPtrCString(ffi.Pointer<ffi.Void> fn, String arg) {
    final argC = arg.toNativeUtf8();
    final out = calloc<ffi.Pointer<ffi.Void>>();
    try {
      _run((err, len) => _callPtrCStrFn(fn, argC.cast(), out, err, len));
      return out.value;
    } finally {
      calloc.free(out);
      malloc.free(argC);
    }
  }

  /// `whisper_print_system_info()` or any `const char*` function without
  /// arguments, via [fn].
  String? callCStringVoid(ffi.Pointer<ffi.Void> fn) {
    final out = calloc<ffi.Pointer<ffi.Char>>();
    try {
      _run((err, len) => _callCStrVoidFn(fn, out, err, len));
      final ptr = out.value;
      return ptr == ffi.nullptr ? null : ptr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// `ggml_backend_dev_name(dev)` via [fn]; `null` for a null result.
  String? callCStringPtr(ffi.Pointer<ffi.Void> fn, ffi.Pointer<ffi.Void> dev) {
    final out = calloc<ffi.Pointer<ffi.Char>>();
    try {
      _run((err, len) => _callCStrPtrFn(fn, dev, out, err, len));
      final ptr = out.value;
      return ptr == ffi.nullptr ? null : ptr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// `ggml_backend_dev_count()` via [fn].
  int callSizeVoid(ffi.Pointer<ffi.Void> fn) {
    final out = calloc<ffi.Size>();
    try {
      _run((err, len) => _callSizeVoidFn(fn, out, err, len));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// `ggml_backend_dev_get(index)` via [fn].
  ffi.Pointer<ffi.Void> callPtrSize(ffi.Pointer<ffi.Void> fn, int index) {
    final out = calloc<ffi.Pointer<ffi.Void>>();
    try {
      _run((err, len) => _callPtrSizeFn(fn, index, out, err, len));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Score of the ggml backend module at [path] (`wpg_backend_score`): it is
  /// opened and closed inside the guard. 0 when the module cannot be opened.
  /// Throws [NativeCallException] when opening or scoring threw.
  int backendScore(String path) {
    final pathC = path.toNativeUtf8();
    final out = calloc<ffi.Int>();
    try {
      _run((err, len) => _backendScoreFn(pathC, out, err, len));
      return out.value;
    } finally {
      calloc.free(out);
      calloc.free(pathC);
    }
  }

  /// `ggml_backend_dev_type(dev)` via [fn].
  int callIntPtr(ffi.Pointer<ffi.Void> fn, ffi.Pointer<ffi.Void> dev) {
    final out = calloc<ffi.Int>();
    try {
      _run((err, len) => _callIntPtrFn(fn, dev, out, err, len));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Reads a process-wide [WpgFlag] slot.
  int processFlag(int which) => _flagGetFn(which);

  /// Writes a process-wide [WpgFlag] slot.
  void setProcessFlag(int which, int value) => _flagSetFn(which, value);

  /// Routes ggml/whisper logging into the native ring buffer. [whisperLogSet]
  /// is the address of the target's `whisper_log_set`. Idempotent per
  /// process; the sink never calls into Dart (see `ffi_guard.h`).
  void installLogSink(ffi.Pointer<ffi.Void> whisperLogSet) {
    _run((err, len) => _logInstallFn(whisperLogSet, err, len));
  }

  /// Pops every buffered log line, oldest first.
  List<NativeLogLine> drainLog() {
    final level = calloc<ffi.Int>();
    const bufferLength = 512;
    final text = calloc<ffi.Char>(bufferLength);
    try {
      final lines = <NativeLogLine>[];
      while (_logPopFn(level, text, bufferLength) == 1) {
        lines.add(NativeLogLine(level.value, text.cast<Utf8>().toDartString()));
      }
      return lines;
    } finally {
      calloc
        ..free(level)
        ..free(text);
    }
  }

  /// Lines dropped from the ring since the last call.
  int takeDroppedLogLines() => _takeDroppedFn();

  /// Feeds one line through the sink exactly as ggml would (tests only).
  void pushLogLineForTesting(int level, String text) {
    final textC = text.toNativeUtf8();
    try {
      _logSinkFn(level, textC.cast(), ffi.nullptr);
    } finally {
      malloc.free(textC);
    }
  }

  /// `wpg_selftest_throw_void` (tests only): throws inside a nested frame.
  ffi.Pointer<ffi.Void> get selfTestThrowVoid =>
      library.lookup<ffi.Void>('wpg_selftest_throw_void');

  /// `wpg_selftest_throw_cstr` (tests only): throws "wpg selftest: " plus the argument.
  ffi.Pointer<ffi.Void> get selfTestThrowCString =>
      library.lookup<ffi.Void>('wpg_selftest_throw_cstr');

  /// `wpg_selftest_throw_ptr_cstr` (tests only): throws like the above.
  ffi.Pointer<ffi.Void> get selfTestThrowPtrCString =>
      library.lookup<ffi.Void>('wpg_selftest_throw_ptr_cstr');
}
