/// Unit tests for the pure [WhisperResiliencePolicy] — the FFI-era analogue
/// of `SttGpuFallbackPolicy`. Mirrors that file's dedicated test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_resilience_policy.dart';

void main() {
  const policy = WhisperResiliencePolicy();

  group('WhisperResiliencePolicy.shouldRetryOnCpu', () {
    test('a GPU crash degrades to CPU', () {
      expect(policy.shouldRetryOnCpu(WhisperFailureKind.gpuCrash), isTrue);
    });

    test('OOM does NOT degrade to CPU (orchestrator recovers it)', () {
      expect(policy.shouldRetryOnCpu(WhisperFailureKind.oom), isFalse);
    });

    test('timeout / transient / other never degrade to CPU', () {
      expect(policy.shouldRetryOnCpu(WhisperFailureKind.timeout), isFalse);
      expect(policy.shouldRetryOnCpu(WhisperFailureKind.transient), isFalse);
      expect(policy.shouldRetryOnCpu(WhisperFailureKind.other), isFalse);
    });
  });
}
