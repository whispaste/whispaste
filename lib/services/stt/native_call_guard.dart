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
  static const abiVersion = 1;

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
}
