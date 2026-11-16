/// Pure transition gate of the GPU-to-CPU fallback notice (#453).
///
/// Restores the logic checks of the deleted `cpu_fallback_toast_test.dart`
/// that were not covered anywhere else: the notice fires once per transition,
/// not on every status emission while the fallback stays active.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  group('shouldShowCpuFallbackToast (pure transition gate)', () {
    test('no prior status to active fallback triggers the notice', () {
      expect(
        shouldShowCpuFallbackToast(
          null,
          const SttStatus(cpuFallbackActive: true),
        ),
        isTrue,
      );
    });

    test('inactive to active triggers the notice', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: false),
          const SttStatus(cpuFallbackActive: true),
        ),
        isTrue,
      );
    });

    test('active to active does not re-trigger', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: true),
          const SttStatus(cpuFallbackActive: true),
        ),
        isFalse,
        reason:
            'Repeated status emissions while the fallback stays active must '
            'not raise a new notice each time.',
      );
    });

    test('active to inactive (GPU recovered) does not trigger', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: true),
          const SttStatus(cpuFallbackActive: false),
        ),
        isFalse,
      );
    });

    test('inactive to inactive does not trigger', () {
      expect(
        shouldShowCpuFallbackToast(
          const SttStatus(cpuFallbackActive: false),
          const SttStatus(cpuFallbackActive: false),
        ),
        isFalse,
      );
    });
  });
}
