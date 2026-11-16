/// The recommendation prefers this machine's measurements and falls back to
/// the VRAM estimate only when nothing was measured here.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';

void main() {
  group('resolveTierRecommendation', () {
    test('uses the measured verdict when this machine has results', () {
      final r = resolveTierRecommendation(
        vramMB: 16384,
        vendor: hw.GpuVendor.nvidia,
        measuredRtf: const {QualityTier.compact: 0.2},
      );
      expect(r.tier, QualityTier.compact);
      expect(r.source, TierRecommendationSource.measured);
    });

    test('falls back to the VRAM estimate without measurements', () {
      final r = resolveTierRecommendation(
        vramMB: 16384,
        vendor: hw.GpuVendor.nvidia,
      );
      expect(r.tier, recommendTier(16384, vendor: hw.GpuVendor.nvidia));
      expect(r.source, TierRecommendationSource.estimated);
    });

    test('an empty measurement map does not count as a measurement', () {
      final r = resolveTierRecommendation(
        vramMB: 2048,
        vendor: hw.GpuVendor.nvidia,
        measuredRtf: const {},
      );
      expect(r.source, TierRecommendationSource.estimated);
    });
  });

  group('recommendTierFromBenchmark — only measured tiers count', () {
    test('a slow compact alone is not replaced by an unmeasured premium', () {
      expect(
        recommendTierFromBenchmark(const {QualityTier.compact: 0.9}),
        QualityTier.compact,
      );
    });

    test('the most accurate fluent tier wins, not the first fluent one', () {
      expect(
        recommendTierFromBenchmark(const {
          QualityTier.compact: 0.1,
          QualityTier.balanced: 0.3,
          QualityTier.premium: 0.6,
        }),
        QualityTier.premium,
      );
      expect(
        recommendTierFromBenchmark(const {
          QualityTier.compact: 0.1,
          QualityTier.balanced: 0.5,
          QualityTier.premium: 1.2,
        }),
        QualityTier.balanced,
      );
    });

    test('a slow premium alone is still the best measured answer', () {
      expect(
        recommendTierFromBenchmark(const {QualityTier.premium: 1.5}),
        QualityTier.premium,
      );
    });
  });
}
