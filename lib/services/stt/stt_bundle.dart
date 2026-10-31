/// Barrel file for the modular STT subsystem.
///
/// Re-exports all public APIs and defines [localSttBundleProvider] —
/// the composed entry-point for external consumers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stt_server_state_notifier.dart';

export 'inference_client_rejected.dart';
export 'local_transcriber.dart';
export 'stt_benchmark.dart';
export 'stt_exit_classifier.dart';
export 'stt_gpu_fallback_policy.dart';
export 'stt_idle_timer.dart';
export 'stt_server_state_notifier.dart';
export 'whisper/gpu_load_crash_guard.dart';
export 'whisper/whisper_engine.dart';
export 'whisper/whisper_ffi_engine.dart';
export 'whisper/whisper_isolate_engine.dart';

/// Provider that wraps [SttServerStateNotifier] — the composed entry-point
/// for the new modular STT subsystem.
///
/// External consumers read this provider for [SttStatus] and call
/// `.notifier` to access server lifecycle methods ([ensureRunning], [stop],
/// [transcribeBytes], etc.).
final localSttBundleProvider =
    NotifierProvider<SttServerStateNotifier, SttStatus>(
      SttServerStateNotifier.new,
    );
