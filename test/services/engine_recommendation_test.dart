/// Unit tests for [recommendEngine] — pure function, no widget tree needed.
///
/// The decision is language-first: Parakeet is faster than Whisper on every
/// machine (CONTEXT.md §4.2), so hardware never rules it out — only the
/// dictation language can. Hardware only feeds the Whisper-tier
/// recommendation once Parakeet is already ineligible.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/hardware_info_service.dart' show GpuVendor;
import 'package:whispaste/services/model_download_service.dart'
    show QualityTier, TierRecommendationSource;

void main() {
  group('recommendationLanguage — the chosen dictation language wins', () {
    test('auto-detect falls back to the UI locale', () {
      expect(
        recommendationLanguage(sttLanguageCode: 'auto', uiLocale: 'de'),
        'de',
      );
    });

    test('a chosen dictation language beats the UI locale', () {
      // German UI, Japanese dictation: Parakeet does not cover Japanese, so it
      // must not be recommended just because the UI is German.
      final language = recommendationLanguage(
        sttLanguageCode: 'ja',
        uiLocale: 'de',
      );
      expect(language, 'ja');
      expect(parakeetRecommendedFor(language), isFalse);
    });
  });

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

  group(
    'recommendEngine — one answer for onboarding and settings (UIA-RT-03)',
    () {
      test(
        'a measured fast tier beats the VRAM estimate for the same machine',
        () {
          // VRAM alone says Premium for 24 GB NVIDIA; the measurement says
          // Compact is fast enough, and Settings already trusts that verdict.
          final rec = recommendEngine(
            dictationLanguageCode: 'he',
            vendor: GpuVendor.nvidia,
            vramMB: 24576,
            measuredRtf: const {
              QualityTier.compact: 0.2,
              QualityTier.balanced: 0.5,
            },
          );

          expect(rec.engine, OnDeviceEngine.whisper);
          expect(rec.tier, QualityTier.compact);
          expect(rec.tierSource, TierRecommendationSource.measured);
        },
      );

      test('without a measurement the tier is the VRAM estimate', () {
        final rec = recommendEngine(
          dictationLanguageCode: 'he',
          vendor: GpuVendor.nvidia,
          vramMB: 24576,
        );

        expect(rec.tier, QualityTier.premium);
        expect(rec.tierSource, TierRecommendationSource.estimated);
      });

      test('an empty benchmark counts as no measurement', () {
        final rec = recommendEngine(
          dictationLanguageCode: 'he',
          vendor: GpuVendor.nvidia,
          vramMB: 24576,
          measuredRtf: const {},
        );

        expect(rec.tier, QualityTier.premium);
        expect(rec.tierSource, TierRecommendationSource.estimated);
      });

      test(
        'a benchmark where every tier is slow picks the fastest measured',
        () {
          final rec = recommendEngine(
            dictationLanguageCode: 'he',
            vendor: GpuVendor.none,
            vramMB: 0,
            measuredRtf: const {
              QualityTier.compact: 1.5,
              QualityTier.balanced: 2.0,
            },
          );

          expect(rec.tier, QualityTier.compact);
          expect(rec.tierSource, TierRecommendationSource.measured);
        },
      );

      test('a Parakeet language ignores the measurement entirely', () {
        final rec = recommendEngine(
          dictationLanguageCode: 'de',
          vendor: GpuVendor.nvidia,
          vramMB: 24576,
          measuredRtf: const {QualityTier.compact: 0.2},
        );

        expect(rec.engine, OnDeviceEngine.parakeet);
        expect(rec.tier, isNull);
      });

      test('unknown VRAM and no measurement give Whisper no tier at all', () {
        final rec = recommendEngine(
          dictationLanguageCode: 'he',
          vendor: null,
          vramMB: null,
        );

        expect(rec.engine, OnDeviceEngine.whisper);
        expect(rec.tier, isNull);
      });

      test('unknown VRAM still takes a measurement', () {
        final rec = recommendEngine(
          dictationLanguageCode: 'he',
          vendor: null,
          vramMB: null,
          measuredRtf: const {QualityTier.balanced: 0.4},
        );

        expect(rec.tier, QualityTier.balanced);
        expect(rec.tierSource, TierRecommendationSource.measured);
      });

      test('parakeetRecommendedFor is a language-only decision', () {
        expect(parakeetRecommendedFor('de'), isTrue);
        expect(parakeetRecommendedFor('de_DE'), isTrue);
        expect(parakeetRecommendedFor('he'), isFalse);
        expect(parakeetRecommendedFor(''), isFalse);
      });
    },
  );

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

  // MV-03: the Whisper tier follows the hardware class (CPU cores, RAM, GPU
  // and its backend), a measurement still wins, and software Vulkan counts
  // as CPU (XP-7-03). Pure function, so every platform gets the same answer.
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    group('recommendWhisper by hardware class on ${platform.name} (MV-03)', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      for (final (label, profile, tier, basis) in [
        (
          'weak laptop (iGPU, 4 cores, 8 GB)',
          (GpuVendor.intel, 'Intel(R) UHD Graphics 620', 512, false, 4, 8192),
          QualityTier.compact,
          RecommendationBasis.vulkanGpu,
        ),
        (
          'weak laptop with little RAM caps an iGPU estimate',
          (GpuVendor.intel, 'Intel(R) Iris Xe Graphics', 4096, false, 4, 4096),
          QualityTier.compact,
          RecommendationBasis.vulkanGpu,
        ),
        (
          'mid-range (AMD, 8 cores, 16 GB)',
          (GpuVendor.amd, 'AMD Radeon 780M', 4096, false, 8, 16384),
          QualityTier.balanced,
          RecommendationBasis.vulkanGpu,
        ),
        (
          'CUDA GPU',
          (GpuVendor.nvidia, 'NVIDIA GeForce RTX 3060', 12288, true, 8, 16384),
          QualityTier.premium,
          RecommendationBasis.cudaGpu,
        ),
        (
          'NVIDIA without CUDA runs on Vulkan',
          (GpuVendor.nvidia, 'NVIDIA GeForce GTX 1050', 2048, false, 4, 8192),
          QualityTier.compact,
          RecommendationBasis.vulkanGpu,
        ),
        (
          'Apple Silicon (unified memory from RAM)',
          (GpuVendor.apple, 'Apple M2', null, false, 8, 16384),
          QualityTier.premium,
          RecommendationBasis.appleSilicon,
        ),
        (
          'only llvmpipe counts as CPU',
          (
            GpuVendor.intel,
            'llvmpipe (LLVM 15.0.7, 256 bits)',
            8192,
            false,
            4,
            8192,
          ),
          QualityTier.compact,
          RecommendationBasis.softwareRenderer,
        ),
        (
          'llvmpipe on a strong CPU never reaches premium',
          (
            GpuVendor.amd,
            'llvmpipe (LLVM 17.0.6, 256 bits)',
            16384,
            false,
            16,
            32768,
          ),
          QualityTier.balanced,
          RecommendationBasis.softwareRenderer,
        ),
        (
          'CPU only, weak',
          (GpuVendor.none, 'Unknown', 0, false, 4, 8192),
          QualityTier.compact,
          RecommendationBasis.cpuOnly,
        ),
        (
          'CPU only, strong',
          (GpuVendor.none, 'Unknown', 0, false, 12, 32768),
          QualityTier.balanced,
          RecommendationBasis.cpuOnly,
        ),
        (
          'CPU only with unknown RAM stays compact',
          (GpuVendor.none, 'Unknown', 0, false, 16, null),
          QualityTier.compact,
          RecommendationBasis.cpuOnly,
        ),
      ]) {
        test(label, () {
          final (vendor, name, vram, cuda, cores, ram) = profile;
          final rec = recommendWhisper(
            vendor: vendor,
            vramMB: vram,
            gpuName: name,
            cudaUsable: cuda,
            cpuCores: cores,
            ramMB: ram,
          );

          expect(rec.engine, OnDeviceEngine.whisper);
          expect(rec.tier, tier);
          expect(rec.basis, basis);
          expect(rec.tierSource, TierRecommendationSource.estimated);
        });
      }

      test('a measurement wins over the hardware class', () {
        final rec = recommendWhisper(
          vendor: GpuVendor.none,
          vramMB: 0,
          gpuName: 'llvmpipe (LLVM 15.0.7, 256 bits)',
          cpuCores: 4,
          ramMB: 8192,
          measuredRtf: const {
            QualityTier.compact: 0.1,
            QualityTier.balanced: 0.3,
          },
        );

        expect(rec.basis, RecommendationBasis.measured);
        expect(rec.tierSource, TierRecommendationSource.measured);
      });

      test('Parakeet is recommended for its languages', () {
        final rec = recommendEngine(
          dictationLanguageCode: 'de',
          vendor: GpuVendor.none,
          vramMB: 0,
          cpuCores: 2,
          ramMB: 4096,
        );

        expect(rec.engine, OnDeviceEngine.parakeet);
        expect(rec.basis, RecommendationBasis.language);
        expect(
          rec.whisper.tier,
          QualityTier.compact,
          reason: 'the Whisper tier is still known for a manual switch',
        );
      });

      test('without GPU info and measurement there is no tier', () {
        final rec = recommendWhisper(cpuCores: 8, ramMB: 16384);

        expect(rec.tier, isNull);
        expect(rec.basis, RecommendationBasis.unknown);
      });
    });
  }

  group('isSoftwareRenderer (XP-7-03)', () {
    for (final name in [
      'llvmpipe (LLVM 15.0.7, 256 bits)',
      'lavapipe',
      'SwiftShader Device (Subzero)',
      'softpipe',
      'Microsoft Basic Render Driver',
    ]) {
      test('"$name" is software', () {
        expect(isSoftwareRenderer(name), isTrue);
      });
    }
    for (final name in ['NVIDIA GeForce RTX 3060', 'AMD Radeon 780M', '']) {
      test('"$name" is hardware', () {
        expect(isSoftwareRenderer(name), isFalse);
      });
    }
  });
}
