/// [Transcriber] adapter for the Parakeet (sherpa_onnx) engine.
///
/// Mirrors [LocalSttTranscriber] (`lib/services/stt/local_transcriber.dart`)
/// exactly — a thin delegate to the engine notifier, translating its
/// [StateError]s into [TranscriberException]s.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/wav_header_repair.dart';
import '../transcription/transcriber_exception.dart';
import '../transcription/transcriber_interface.dart'
    show Transcriber, WavFileTranscriber;
import 'parakeet_engine_notifier.dart';

class ParakeetTranscriber implements Transcriber, WavFileTranscriber {
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
  Future<String> transcribe(List<int> wavBytes, {String? language}) =>
      _transcribe(wavBytes);

  /// The Parakeet worker reads [wavPath] itself, one chunk at a time
  /// (#1665), see [WavFileTranscriber].
  @override
  Future<String> transcribeWavFile(
    String wavPath,
    List<int> wavBytes, {
    String? language,
  }) => _transcribe(wavBytes, wavPath: wavPath);

  Future<String> _transcribe(List<int> wavBytes, {String? wavPath}) async {
    // Parakeet TDT v3 auto-detects among its ~25 supported languages; the
    // sherpa_onnx OfflineRecognizer binding used here has no per-request
    // language override. [language] is accepted for interface parity with
    // the other adapters but has no effect — see the language-selector row
    // in stt_section.dart, hidden for this engine for the same reason.
    try {
      // The header repair touches only the size fields, which the worker
      // never reads from the file; the samples stay the same.
      return await _notifier.transcribeWavBytes(
        repairWavHeader(wavBytes),
        wavPath: wavPath,
      );
    } on StateError catch (e) {
      // A budget overrun is the same repeatable `transcription_timeout` as
      // on whisper, so the audio is parked for a retry instead of deleted
      // (#1639).
      final code = e.message == 'parakeet_transcribe_timeout'
          ? 'transcription_timeout'
          : e.message;
      throw TranscriberException(
        code,
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
