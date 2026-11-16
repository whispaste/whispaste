/// The slow-tier info line quotes only numbers that were measured. An
/// unmeasured tier gets an explicit estimate, never a made-up multiplier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/widgets/tier_performance_presentation.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  String? slowMessage({double? rtf, Map<QualityTier, double>? benchmarkRtf}) =>
      WpTierPerformancePresentation.message(
        l10n: l10n,
        tier: QualityTier.premium,
        performance: TierPerformance.slow,
        rtf: rtf,
        benchmarkRtf: benchmarkRtf,
      );

  test(
    'an unmeasured slow tier is marked as an estimate, without a number',
    () {
      final text = slowMessage();
      expect(text, l10n.qualityTierInfoSlowEstimate);
      expect(text, isNot(contains('2.0')));
      expect(text, isNot(contains('~')));
    },
  );

  test('a measured tier is compared with the measured compact tier', () {
    expect(
      slowMessage(
        rtf: 1.0,
        benchmarkRtf: {QualityTier.compact: 0.25, QualityTier.premium: 1.0},
      ),
      l10n.qualityTierInfoSlowerThanCompact('4.0'),
    );
  });

  test('a measured tier without a compact reference stays qualitative', () {
    final text = slowMessage(
      rtf: 1.0,
      benchmarkRtf: {QualityTier.premium: 1.0},
    );
    expect(text, l10n.qualityTierInfoSlow);
    expect(text, isNot(contains('2.0')));
  });
}
