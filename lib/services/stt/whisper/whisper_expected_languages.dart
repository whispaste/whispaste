/// Native language detection for opt-in constrained recognition.
library;

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../native_call_guard.dart';
import 'whisper_bindings.dart';
import 'whisper_language_probe.dart';

typedef _DetectNative =
    ffi.Int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<ffi.Float>,
      ffi.Int,
      ffi.Int,
      ffi.Pointer<ffi.Float>,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      ffi.Size,
    );
typedef _DetectDart =
    int Function(
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<ffi.Void>,
      ffi.Pointer<whisper_context>,
      ffi.Pointer<ffi.Float>,
      int,
      int,
      ffi.Pointer<ffi.Float>,
      ffi.Pointer<ffi.Int>,
      ffi.Pointer<ffi.Char>,
      int,
    );

String detectExpectedLanguage({
  required ffi.DynamicLibrary whisper,
  required NativeCallGuard? guard,
  required ffi.Pointer<whisper_context> context,
  required ffi.Pointer<ffi.Float> samples,
  required int count,
  required int threads,
  required List<String> allowed,
}) {
  if (allowed.length == 1) return allowed.single;
  // Older bundles must surface a recoverable error, never ignore the restriction.
  if (guard == null ||
      !guard.library.providesSymbol('wpg_whisper_language_probs')) {
    throw StateError('whisper_language_detection_guard_missing');
  }
  final maxId = whisper.lookupFunction<ffi.Int Function(), int Function()>(
    'whisper_lang_max_id',
  )();
  final langStr = whisper
      .lookupFunction<
        ffi.Pointer<ffi.Char> Function(ffi.Int),
        ffi.Pointer<ffi.Char> Function(int)
      >('whisper_lang_str');
  final probs = calloc<ffi.Float>(maxId + 1);
  final rc = calloc<ffi.Int>();
  final err = calloc<ffi.Char>(512);
  try {
    final status =
        guard.library.lookupFunction<_DetectNative, _DetectDart>(
          'wpg_whisper_language_probs',
        )(
          whisper.lookup<ffi.Void>('whisper_pcm_to_mel'),
          whisper.lookup<ffi.Void>('whisper_lang_auto_detect'),
          context,
          samples,
          count,
          threads,
          probs,
          rc,
          err,
          512,
        );
    if (status != 0) {
      throw NativeCallException(status, err.cast<Utf8>().toDartString());
    }
    if (rc.value < 0) {
      throw WhisperLanguageDetectionFailure(rc.value);
    }
    return mostLikelyExpectedLanguage({
      for (var id = 0; id <= maxId; id++)
        langStr(id).cast<Utf8>().toDartString(): probs[id],
    }, allowed);
  } finally {
    calloc.free(probs);
    calloc.free(rc);
    calloc.free(err);
  }
}

/// Native error code, classified by the engine like its regular decode failures.
class WhisperLanguageDetectionFailure implements Exception {
  const WhisperLanguageDetectionFailure(this.code);
  final int code;
}
