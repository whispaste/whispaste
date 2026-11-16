/// Unit tests for the pure [WhisperResiliencePolicy] — the FFI-era analogue
/// of `SttGpuFallbackPolicy`. Mirrors that file's dedicated test.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_resilience_policy.dart';

void main() {
  const policy = WhisperResiliencePolicy();

  group('WhisperResiliencePolicy.shouldRetryOnCpu', () {
    test('a GPU crash degrades to CPU', () {
      expect(policy.shouldRetryOnCpu(WhisperFailureKind.gpuCrash), isTrue);
    });

    test('a lost GPU backend degrades to CPU (after the rebuild)', () {
      expect(
        policy.shouldRetryOnCpu(WhisperFailureKind.gpuBackendLost),
        isTrue,
      );
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

  group('WhisperResiliencePolicy.shouldRebuildBackend', () {
    test('only a lost GPU backend is rebuilt', () {
      for (final kind in WhisperFailureKind.values) {
        expect(
          policy.shouldRebuildBackend(kind),
          kind == WhisperFailureKind.gpuBackendLost,
          reason: kind.name,
        );
      }
    });
  });

  group('whisperFullFailureKind', () {
    // -3 language auto-detect, -6 encoder, -7 KV cache, -8/-9 decoder.
    const backendCodes = [-3, -6, -7, -8, -9];

    test('a failed graph on a GPU is a lost backend, also with language '
        'auto-detection (-3)', () {
      for (final backend in [
        WhisperBackend.metal,
        WhisperBackend.cuda,
        WhisperBackend.vulkan,
      ]) {
        for (final rc in backendCodes) {
          expect(
            whisperFullFailureKind(rc, backend),
            WhisperFailureKind.gpuBackendLost,
            reason: '$rc on ${backend.name}',
          );
        }
      }
    });

    test('CPU and other codes stay transient', () {
      for (final rc in backendCodes) {
        expect(
          whisperFullFailureKind(rc, WhisperBackend.cpu),
          WhisperFailureKind.transient,
          reason: '$rc on cpu',
        );
      }
      for (final rc in [-1, -2, -4, -5]) {
        expect(
          whisperFullFailureKind(rc, WhisperBackend.metal),
          WhisperFailureKind.transient,
          reason: '$rc on metal',
        );
      }
    });
  });
}
