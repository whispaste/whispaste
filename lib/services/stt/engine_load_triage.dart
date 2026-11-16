/// Why a local speech engine failed to load (#561), and what to do about it.
///
/// A load failure has two causes that need opposite answers. A damaged model
/// file loads on no device: it is checked against its catalog hash and loaded
/// again only when the check fails. A GPU, driver or backend that cannot run
/// the model would fail the same way on every start: the load moves to the
/// CPU and that result is remembered for this GPU, driver, OS and app
/// version, so a later driver or system update tries the GPU again.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/crash_fingerprints.dart';
import '../../core/logging/crash_reporter.dart';
import '../file_verification_service.dart';

/// Checks a model file against its catalog hash after a load failure;
/// tests replace it.
final modelFileVerifierProvider = Provider<FileVerificationService>(
  (ref) => const FileVerificationService(),
);

/// The cause behind a failed engine load.
enum EngineLoadCause {
  /// The model file is damaged or unreadable; another device would not help.
  fileDefect,

  /// The GPU, driver or compute backend cannot run the model; the file is
  /// fine and the CPU is the way out.
  hardwareIncompatible,
}

/// Signs of a GPU, driver or backend problem in a load error. Checked first:
/// a backend error mentions the model too ("failed to load model on
/// Vulkan"), while a file error never names a device.
const List<String> _hardwareMarkers = [
  'vk::',
  'vulkan',
  'cuda',
  'cublas',
  'metal',
  'mtl',
  'ggml_backend',
  'backend',
  'device',
  'driver',
  'gpu',
  'out of memory',
  'outofdevicememory',
  'timeout',
  'timed out',
];

/// Signs of a damaged or unreadable model file.
const List<String> _fileMarkers = [
  'whisper_model_not_found',
  'invalid model',
  'bad magic',
  'invalid magic',
  'magic',
  'failed to read',
  'unexpected end',
  'eof',
  'mmap',
  'corrupt',
  'truncated',
  'tensor',
  'vocab',
  'gguf',
];

/// Sorts a whisper load error into [EngineLoadCause]. [onGpu] says whether
/// the failed load ran on a GPU backend.
///
/// Without a clear sign the device decides: a failure on the GPU counts as
/// hardware (the CPU retry is the safe next step, and the file check still
/// runs if the CPU fails too), a failure on the CPU counts as the file,
/// because the CPU path has no driver in between.
EngineLoadCause classifyWhisperLoadFailure(
  Object error, {
  required bool onGpu,
}) {
  final text = '$error'.toLowerCase();
  if (_hardwareMarkers.any(text.contains)) {
    return EngineLoadCause.hardwareIncompatible;
  }
  if (_fileMarkers.any(text.contains)) return EngineLoadCause.fileDefect;
  return onGpu
      ? EngineLoadCause.hardwareIncompatible
      : EngineLoadCause.fileDefect;
}

/// Causes that can pass by themselves: a first GPU start that compiles its
/// shaders past the load timeout, or video memory another program holds for
/// the moment. They move this session to the CPU but are not remembered, so
/// the next start tries the GPU again (#561). `failed to allocate` is how
/// whisper.cpp names a weight, KV cache, compute buffer or ggml context it
/// could not get, `bad allocation` (MSVC) and `bad_alloc` (libstdc++, libc++)
/// a C++ allocation that ran out of system memory (#1669,
/// `whisperInitErrorWithNativeLines` carries the native lines).
const List<String> _transientMarkers = [
  'timeout',
  'timed out',
  'out of memory',
  'outofdevicememory',
  'device memory',
  'failed to allocate',
  'bad allocation',
  'bad_alloc',
];

/// Whether a hardware load failure may pass by itself and must not mark the
/// GPU as unusable beyond this session.
bool isTransientWhisperLoadFailure(Object error) {
  final text = '$error'.toLowerCase();
  return _transientMarkers.any(text.contains);
}

/// Sends the `stt_model_corrupted` Sentry event at most once per app session
/// (#561): the error quota is shared and a damaged file repeats on
/// every start until the new download finishes. [send] is replaced in tests.
class ModelCorruptedReporter {
  ModelCorruptedReporter({
    void Function(String message, Map<String, Object?> extras)? send,
  }) : _send = send ?? _sendToSentry;

  final void Function(String message, Map<String, Object?> extras) _send;
  bool _sent = false;

  /// Returns whether the event was sent (false when one already went out).
  bool report(String message, Map<String, Object?> extras) {
    if (_sent) return false;
    _sent = true;
    _send(message, extras);
    return true;
  }

  static void _sendToSentry(String message, Map<String, Object?> extras) {
    CrashReporter.instance?.captureError(
      message: message,
      severity: 'error',
      type: 'stt_model_corrupted',
      fingerprint: const [sttModelCorrupted],
      extras: extras,
    );
  }
}

/// One reporter per app session.
final modelCorruptedReporterProvider = Provider<ModelCorruptedReporter>(
  (ref) => ModelCorruptedReporter(),
);
