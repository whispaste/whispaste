// dart:ffi bindings for the subset of libparakeet (whisper.cpp v1.9.5,
// include/parakeet.h) that WhisPaste calls. Hand-written in the style of the
// ffigen output in `stt/whisper/whisper_bindings.dart`, which covers the full
// whisper header; the Parakeet header is only used for this small surface, so
// it is kept by hand to keep the generated file out of the repo.
//
// Struct layouts mirror the C declarations exactly. Dart FFI lays out structs
// with the same natural alignment as C, so the field order below must match
// `struct parakeet_full_params` in parakeet.h. Changing the header means
// changing this file in the same commit.
// Field names mirror the C header on purpose (snake_case).
// ignore_for_file: non_constant_identifier_names
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

/// `enum parakeet_sampling_strategy`; only greedy decoding exists in v1.9.5.
const int parakeetSamplingGreedy = 0;

/// `struct parakeet_context_params`.
final class ParakeetContextParams extends ffi.Struct {
  @ffi.Bool()
  // loam-ignore: unused-public-exports – written into the native params struct, read only by libparakeet
  external bool use_gpu;

  @ffi.Int()
  // loam-ignore: unused-public-exports – written into the native params struct, read only by libparakeet
  external int gpu_device;
}

/// `struct parakeet_full_params`. Callback fields are typed as opaque pointers:
/// only the abort callback is set (see the engine), the others stay null, and
/// a null pointer has the same size and ABI for every function type.
final class ParakeetFullParams extends ffi.Struct {
  @ffi.Int()
  // loam-ignore: unused-public-exports – written into the native params struct, read only by libparakeet
  external int strategy;

  @ffi.Int()
  // loam-ignore: unused-public-exports – written into the native params struct, read only by libparakeet
  external int n_threads;

  @ffi.Int()
  // loam-ignore: unused-public-exports – written into the native params struct, read only by libparakeet
  external int offset_ms;

  @ffi.Int()
  // loam-ignore: unused-public-exports – written into the native params struct, read only by libparakeet
  external int duration_ms;

  @ffi.Bool()
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external bool no_context;

  @ffi.Int()
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external int audio_ctx;

  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> new_segment_callback;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> new_segment_callback_user_data;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> new_token_callback;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> new_token_callback_user_data;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> progress_callback;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> progress_callback_user_data;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> encoder_begin_callback;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> encoder_begin_callback_user_data;

  /// `ggml_abort_callback`: `bool (*)(void * data)`, polled by ggml between
  /// graph computations. Returning true aborts `parakeet_full` with an error.
  // loam-ignore: unused-public-exports – written into the native params struct, read only by libparakeet
  external ffi.Pointer<ffi.Void> abort_callback;
  // loam-ignore: unused-public-exports – C struct layout field, set or read by libparakeet only
  external ffi.Pointer<ffi.Void> abort_callback_user_data;
}

typedef _VersionNative = ffi.Pointer<Utf8> Function();
typedef _VersionDart = ffi.Pointer<Utf8> Function();

typedef _FullDefaultParamsNative = ParakeetFullParams Function(ffi.Int32);
typedef _FullDefaultParamsDart = ParakeetFullParams Function(int);

typedef _InitFromFileNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ParakeetContextParams);
typedef _InitFromFileDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ParakeetContextParams);

typedef _FullNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void>,
      ParakeetFullParams,
      ffi.Pointer<ffi.Float>,
      ffi.Int32,
    );
typedef _FullDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ParakeetFullParams,
      ffi.Pointer<ffi.Float>,
      int,
    );

typedef _NSegmentsNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _NSegmentsDart = int Function(ffi.Pointer<ffi.Void>);

typedef _SegmentTextNative =
    ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SegmentTextDart =
    ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, int);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);

/// Lookups for one loaded libparakeet. Constructed from a [ffi.DynamicLibrary]
/// so tests can open the real library, and the engine can run without any
/// Flutter dependency.
class ParakeetBindings {
  ParakeetBindings(ffi.DynamicLibrary lib)
    : _version = lib.lookupFunction<_VersionNative, _VersionDart>(
        'parakeet_version',
      ),
      _contextDefaultParams = lib
          .lookupFunction<
            ParakeetContextParams Function(),
            ParakeetContextParams Function()
          >('parakeet_context_default_params'),
      _initFromFile = lib
          .lookupFunction<_InitFromFileNative, _InitFromFileDart>(
            'parakeet_init_from_file_with_params',
          ),
      _fullDefaultParams = lib
          .lookupFunction<_FullDefaultParamsNative, _FullDefaultParamsDart>(
            'parakeet_full_default_params',
          ),
      _full = lib.lookupFunction<_FullNative, _FullDart>('parakeet_full'),
      _nSegments = lib.lookupFunction<_NSegmentsNative, _NSegmentsDart>(
        'parakeet_full_n_segments',
      ),
      _segmentText = lib.lookupFunction<_SegmentTextNative, _SegmentTextDart>(
        'parakeet_full_get_segment_text',
      ),
      _free = lib.lookupFunction<_FreeNative, _FreeDart>('parakeet_free');

  final _VersionDart _version;
  final ParakeetContextParams Function() _contextDefaultParams;
  final _InitFromFileDart _initFromFile;
  final _FullDefaultParamsDart _fullDefaultParams;
  final _FullDart _full;
  final _NSegmentsDart _nSegments;
  final _SegmentTextDart _segmentText;
  final _FreeDart _free;

  /// Version string compiled into libparakeet (e.g. `1.9.5-dev`).
  String version() => _version().toDartString();

  /// Default context params, returned by value from the library.
  ParakeetContextParams contextDefaultParams() => _contextDefaultParams();

  /// Loads a GGUF model. Returns a null pointer on failure.
  ffi.Pointer<ffi.Void> initFromFile(
    String path,
    ParakeetContextParams params,
  ) {
    final pathC = path.toNativeUtf8();
    try {
      return _initFromFile(pathC, params);
    } finally {
      malloc.free(pathC);
    }
  }

  /// Default full-params for greedy decoding, returned by value.
  ParakeetFullParams fullDefaultParams() =>
      _fullDefaultParams(parakeetSamplingGreedy);

  /// Runs PCM -> mel -> encoder -> decoder for [samples] (16 kHz mono float).
  /// Returns 0 on success; non-zero on error or abort. Not thread-safe for
  /// the same context.
  int full(
    ffi.Pointer<ffi.Void> ctx,
    ParakeetFullParams params,
    ffi.Pointer<ffi.Float> samples,
    int n,
  ) => _full(ctx, params, samples, n);

  /// Number of text segments produced by the last [full] call.
  int segmentCount(ffi.Pointer<ffi.Void> ctx) => _nSegments(ctx);

  /// Text of one segment; the pointer is owned by the context.
  String segmentText(ffi.Pointer<ffi.Void> ctx, int index) =>
      _segmentText(ctx, index).toDartString();

  void free(ffi.Pointer<ffi.Void> ctx) => _free(ctx);
}
