/// Unit tests for stt_gpu_fallback_policy.dart — stateless class.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/stt_exit_classifier.dart';
import 'package:whispaste/services/stt/stt_gpu_fallback_policy.dart';

void main() {
  const policy = SttGpuFallbackPolicy();

  group('SttGpuFallbackPolicy.shouldRetryOnCpu', () {
    test('gpuFatal → true', () {
      expect(policy.shouldRetryOnCpu(SttExitKind.gpuFatal), isTrue);
    });

    test('dllMissing → true', () {
      expect(policy.shouldRetryOnCpu(SttExitKind.dllMissing), isTrue);
    });

    test('dllEntryPoint → true', () {
      expect(policy.shouldRetryOnCpu(SttExitKind.dllEntryPoint), isTrue);
    });

    test('heapCorruption → true', () {
      expect(policy.shouldRetryOnCpu(SttExitKind.heapCorruption), isTrue);
    });

    test('modelLoad → false', () {
      expect(policy.shouldRetryOnCpu(SttExitKind.modelLoad), isFalse);
    });

    test('other → false', () {
      expect(policy.shouldRetryOnCpu(SttExitKind.other), isFalse);
    });
  });
}
