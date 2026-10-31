import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt/native_call_guard.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_engine.dart';

void main() {
  // A local engine failure that reaches the orchestrator unclassified must
  // map to a repeatable code, so its audio is parked for a retry instead of
  // being deleted with the temp WAV.
  group('unclassifiedTranscribeErrorCode', () {
    test('an engine timeout is repeatable', () {
      final code = unclassifiedTranscribeErrorCode(
        const WhisperEngineException(
          WhisperFailureKind.timeout,
          'pipeline_timeout: transcription exceeded the stuck-guard budget',
        ),
      );

      expect(code, 'transcription_timeout');
      expect(isRepeatableTranscriptionError(code), isTrue);
    });

    for (final kind in [
      WhisperFailureKind.other,
      WhisperFailureKind.transient,
      WhisperFailureKind.gpuCrash,
    ]) {
      test('a ${kind.name} engine failure is repeatable', () {
        final code = unclassifiedTranscribeErrorCode(
          WhisperEngineException(kind, 'engine failed'),
        );

        expect(code, 'stt_server_failed');
        expect(isRepeatableTranscriptionError(code), isTrue);
      });
    }

    test('an out-of-memory engine failure keeps the OOM code', () {
      final code = unclassifiedTranscribeErrorCode(
        const WhisperEngineException(
          WhisperFailureKind.oom,
          'stt_cuda_oom: out of memory',
        ),
      );

      expect(code, 'stt_cuda_oom');
    });
  });

  // Parakeet and native-guard failures reach the orchestrator unwrapped. They
  // must keep the audio like the Whisper failures above: a GPU timeout on a
  // long dictation is exactly the case where deleting the WAV loses the text.
  group('unclassifiedTranscribeErrorCode for Parakeet and native failures', () {
    test('a Parakeet GPU timeout is repeatable', () {
      final code = unclassifiedTranscribeErrorCode(
        ParakeetGpuException('transcribe_timeout'),
      );

      expect(code, 'transcription_timeout');
      expect(isRepeatableTranscriptionError(code), isTrue);
    });

    test('a Parakeet GPU engine failure is repeatable', () {
      final code = unclassifiedTranscribeErrorCode(
        ParakeetGpuException('parakeet_full rc=-1'),
      );

      expect(code, 'stt_server_failed');
      expect(isRepeatableTranscriptionError(code), isTrue);
    });

    test('a native C++ exception in the engine is repeatable', () {
      final code = unclassifiedTranscribeErrorCode(
        NativeCallException(-1, 'std::bad_alloc'),
      );

      expect(code, 'stt_server_failed');
      expect(isRepeatableTranscriptionError(code), isTrue);
    });
  });
}
