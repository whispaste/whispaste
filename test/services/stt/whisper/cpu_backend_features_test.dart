/// Unit tests for [cpuBackendFeaturesFromSystemInfo] — the parser that turns
/// whisper.cpp's `whisper_print_system_info()` into the loaded CPU backend
/// variant shown in the app log and the In-App-Diagnostik.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';

void main() {
  group('cpuBackendFeaturesFromSystemInfo', () {
    test('keeps only the enabled CPU features (x86 variant build)', () {
      const info =
          'WHISPER : COREML = 0 | OPENVINO = 0 | '
          'CPU : SSE3 = 1 | SSSE3 = 1 | AVX = 1 | AVX2 = 1 | F16C = 1 | '
          'FMA = 1 | BMI2 = 1 | AVX512 = 0 | REPACK = 1 | ';

      expect(
        cpuBackendFeaturesFromSystemInfo(info),
        'SSE3 SSSE3 AVX AVX2 F16C FMA BMI2 REPACK',
      );
    });

    test('ignores feature lists of other backend registries', () {
      const info =
          'WHISPER : COREML = 0 | OPENVINO = 0 | '
          'Metal : EMBED_LIBRARY = 1 | '
          'CPU : NEON = 1 | ARM_FMA = 1 | DOTPROD = 1 | SVE_CNT = 16 | '
          'BLAS : ACCELERATE = 1 | ';

      expect(
        cpuBackendFeaturesFromSystemInfo(info),
        'NEON ARM_FMA DOTPROD SVE_CNT=16',
      );
    });

    test('returns null without a CPU section (no backend loaded)', () {
      expect(
        cpuBackendFeaturesFromSystemInfo(
          'WHISPER : COREML = 0 | OPENVINO = 0 | ',
        ),
        isNull,
      );
      expect(cpuBackendFeaturesFromSystemInfo(''), isNull);
    });
  });
}
