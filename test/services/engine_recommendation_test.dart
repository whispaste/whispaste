/// Unit tests for [recommendEngine] — pure function, no widget tree needed.
///
/// The decision is language-first: Parakeet is faster than Whisper on every
/// machine (CONTEXT.md §4.2), so hardware never rules it out — only the
/// dictation language can. Hardware only feeds the Whisper-tier
/// recommendation once Parakeet is already ineligible.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/quality_tier.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/hardware_info_service.dart' show GpuVendor;

void main() {
  group('recommendEngine — language decides engine eligibility', () {
    test(
      'German (de, European) recommends Parakeet regardless of hardware',
      () {
        final rec = recommendEngine(
          dictationLanguageCode: 'de',
          vendor: GpuVendor.none,
          vramMB: 0,
        );

        expect(rec.engine, OnDeviceEngine.parakeet);
        expect(rec.tier, isNull, reason: 'Parakeet has no quality tiers');
      },
    );

    test('English (en, European) recommends Parakeet', () {
      final rec = recommendEngine(
        dictationLanguageCode: 'en',
        vendor: GpuVendor.apple,
        vramMB: 8192,
      );

      expect(rec.engine, OnDeviceEngine.parakeet);
    });

    test(
      'Hebrew (he, not in the Parakeet language set) recommends Whisper',
      () {
        final rec = recommendEngine(
          dictationLanguageCode: 'he',
          vendor: GpuVendor.apple,
          vramMB: 8192,
        );

        expect(rec.engine, OnDeviceEngine.whisper);
        expect(rec.tier, isNotNull);
      },
    );

    test('unrecognized locale code ("auto") falls back to Whisper', () {
      final rec = recommendEngine(
        dictationLanguageCode: 'auto',
        vendor: GpuVendor.none,
        vramMB: 0,
      );

      expect(rec.engine, OnDeviceEngine.whisper);
    });

    test('empty locale code falls back to Whisper', () {
      final rec = recommendEngine(
        dictationLanguageCode: '',
        vendor: GpuVendor.none,
        vramMB: 0,
      );

      expect(rec.engine, OnDeviceEngine.whisper);
    });

    test('locale codes normalize by stripping region/script suffixes', () {
      // 'de_DE', 'de-DE', and 'DE' must all resolve the same way as 'de'.
      for (final code in ['de_DE', 'de-DE', 'DE']) {
        final rec = recommendEngine(
          dictationLanguageCode: code,
          vendor: GpuVendor.none,
          vramMB: 0,
        );
        expect(
          rec.engine,
          OnDeviceEngine.parakeet,
          reason: '"$code" must normalize to "de"',
        );
      }
    });

    test('a GPU with plenty of VRAM does not flip a European-language '
        'recommendation to Whisper', () {
      final rec = recommendEngine(
        dictationLanguageCode: 'fr',
        vendor: GpuVendor.nvidia,
        vramMB: 24576,
      );

      expect(
        rec.engine,
        OnDeviceEngine.parakeet,
        reason:
            'Parakeet is faster on every machine — hardware never rules '
            'it out once the language qualifies.',
      );
    });
  });

  group('recommendEngine — Whisper tier feeds off recommendTier', () {
    test('Apple Silicon with ≥4GB unified memory recommends premium', () {
      final rec = recommendEngine(
        dictationLanguageCode: 'he',
        vendor: GpuVendor.apple,
        vramMB: 8192,
      );

      expect(rec.tier, QualityTier.premium);
    });

    test('NVIDIA with low VRAM recommends compact', () {
      final rec = recommendEngine(
        dictationLanguageCode: 'he',
        vendor: GpuVendor.nvidia,
        vramMB: 1024,
      );

      expect(rec.tier, QualityTier.compact);
    });

    test('GpuVendor.none (CPU-only) recommends compact', () {
      final rec = recommendEngine(
        dictationLanguageCode: 'he',
        vendor: GpuVendor.none,
        vramMB: 0,
      );

      expect(rec.tier, QualityTier.compact);
    });
  });
}
