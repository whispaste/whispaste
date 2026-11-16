import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/quality_tier.dart';
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/short_model_benchmark.dart';

void main() {
  test('warm-up is discarded and two speech runs are averaged', () {
    expect(
      compactRtfFromReport({
        'model': 'whisper-small',
        'audioDurationMs': 6000,
        'runs': [
          {'transcribeMs': 15000},
          {'transcribeMs': 1200},
          {'transcribeMs': 2400},
        ],
      }),
      0.3,
    );
  });

  test('missing, partial and invalid results preserve static fallback', () {
    for (final report in [
      null,
      {},
      {
        'model': 'whisper-small',
        'audioDurationMs': 6000,
        'runs': [
          {'transcribeMs': 1200},
        ],
      },
    ]) {
      expect(compactRtfFromReport(report), isNull);
    }
    for (final rtf in [null, double.nan, double.infinity, 0.0, -1.0]) {
      expect(projectCompactBenchmark(rtf), isNull);
      final recommendation = recommendWhisper(
        vendor: GpuVendor.none,
        vramMB: 0,
        cpuCores: 4,
        ramMB: 8192,
        compactBenchmarkRtf: rtf,
      );
      expect(recommendation.tier, QualityTier.compact);
      expect(recommendation.basis, RecommendationBasis.cpuOnly);
    }
  });

  test('projection uses calibrated ratios and a strict fluent threshold', () {
    final premiumLimit = 0.8 / compactBenchmarkRatios[QualityTier.premium]!;
    final fast = recommendWhisper(compactBenchmarkRtf: premiumLimit * 0.99);
    expect(fast.tier, QualityTier.premium);
    expect(fast.basis, RecommendationBasis.projected);
    expect(
      recommendWhisper(compactBenchmarkRtf: premiumLimit).tier,
      isNot(QualityTier.premium),
    );
    expect(
      projectCompactBenchmark(0.2)![QualityTier.balanced],
      closeTo(0.64478, 0.000001),
    );
  });

  test('slow compact result never claims fluent performance', () {
    final rec = recommendWhisper(compactBenchmarkRtf: 1.2);
    expect(rec.tier, QualityTier.compact);
    expect(rec.projectedFluent, isFalse);
  });

  test('direct tier measurements override the projection for that tier', () {
    final recommendation = recommendWhisper(
      measuredRtf: {QualityTier.premium: 0.9, QualityTier.balanced: 0.5},
      compactBenchmarkRtf: 0.01,
    );
    expect(recommendation.basis, RecommendationBasis.measured);
    expect(recommendation.tier, QualityTier.balanced);
  });

  test(
    'strong hardware skips measurement; unknown and software GPU do not',
    () {
      bool needs(
        GpuVendor? vendor,
        int? memory, {
        String? name,
        bool cuda = false,
      }) => needsShortModelBenchmark(
        vendor: vendor,
        vramMB: memory,
        ramMB: 16384,
        gpuName: name,
        cudaUsable: cuda,
      );
      expect(needs(GpuVendor.apple, null), isFalse);
      expect(needs(GpuVendor.nvidia, 4096, cuda: true), isFalse);
      expect(needs(GpuVendor.nvidia, 4095, cuda: true), isTrue);
      expect(needs(GpuVendor.intel, 12288), isFalse);
      expect(needs(GpuVendor.intel, 12288, name: 'llvmpipe'), isTrue);
      expect(needs(null, null), isTrue);
      expect(needs(GpuVendor.none, 0), isTrue);
    },
  );
}
