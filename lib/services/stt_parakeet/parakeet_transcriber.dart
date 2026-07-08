/// [Transcriber] adapter for the Parakeet (sherpa_onnx) engine.
///
/// Mirrors [LocalSttTranscriber] (`lib/services/stt/local_transcriber.dart`)
/// exactly — a thin delegate to the engine notifier, translating its
/// [StateError]s into [TranscriberException]s.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transcription/transcriber_exception.dart';
import '../transcription/transcriber_interface.dart' show Transcriber;
import 'parakeet_engine_notifier.dart';

class ParakeetTranscriber implements Transcriber {
  const ParakeetTranscriber({required this.ref});

  final Ref ref;

  ParakeetEngineNotifier get _notifier =>
      ref.read(parakeetEngineProvider.notifier);

  @override
  Future<void> prepare() async {
    try {
      await _notifier.ensureRunning();
    } on StateError catch (e) {
      throw TranscriberException(
        e.message,
        reason: TranscriberFailureReason.notReady,
      );
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    // Parakeet TDT (this repo/model) is English-only — [language] is accepted
    // for interface parity with the other adapters but has no effect.
    try {
      return await _notifier.transcribeWavBytes(wavBytes);
    } on StateError catch (e) {
      throw TranscriberException(
        e.message,
        reason: TranscriberFailureReason.notReady,
      );
    }
  }

  @override
  void release() {
    // No idle-timer semantics yet (unlike whisper's idle-shutdown) — the
    // worker isolate stays warm for the app session. Matches this plan's
    // Phase-1 scope; an idle-timeout policy can be added analogously to
    // `stt_idle_timer.dart` later without changing this interface.
  }
}
