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
import 'package:whispaste/core/config/whisper_languages.dart'
    show suggestedDictationLanguage;
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/hardware_info_service.dart' show GpuVendor;
import 'package:whispaste/services/model_download_service.dart'
    show QualityTier, TierRecommendationSource;

void main() {
  group('recommendationLanguages — the chosen dictation language wins', () {
    test('auto-detect uses every system language Whisper writes, in order', () {
      expect(
        recommendationLanguages(
          sttLanguageCode: 'auto',
          systemLanguages: ['de_DE', 'en-US', 'de', 'xx'],
          uiLocale: 'en',
        ),
        ['de', 'en'],
      );
    });

    test(
      'auto-detect falls back to the UI locale without system languages',
      () {
        expect(
          recommendationLanguages(
            sttLanguageCode: 'auto',
            systemLanguages: const [],
            uiLocale: 'de',
          ),
          ['de'],
        );
      },
    );

    test('a chosen dictation language comes first, the system languages '
        'still count', () {
      // German system, Japanese dictation: Parakeet does not cover Japanese.
      final languages = recommendationLanguages(
        sttLanguageCode: 'ja',
        systemLanguages: ['de'],
        uiLocale: 'de',
      );
      expect(languages, ['ja', 'de']);
      expect(parakeetRecommendedFor(languages), isFalse);
    });

    test('German dictation on a German and Japanese system: Whisper', () {
      final languages = recommendationLanguages(
        sttLanguageCode: 'de',
        systemLanguages: ['de-DE', 'ja-JP'],
        uiLocale: 'de',
      );
      expect(languages, ['de', 'ja']);
      expect(parakeetRecommendedFor(languages), isFalse);
    });

    test('German dictation on a German and English system: Parakeet', () {
      expect(
        parakeetRecommendedFor(
          recommendationLanguages(
            sttLanguageCode: 'de',
            systemLanguages: ['de-DE', 'en-US'],
            uiLocale: 'de',
          ),
        ),
        isTrue,
      );
    });

    test(
      'an unsupported system language is not replaced by the English UI',
      () {
        // Japanese system, English UI (no Japanese translation): the
        // recommendation is made for Japanese, so Whisper.
        final languages = recommendationLanguages(
          sttLanguageCode: 'auto',
          systemLanguages: ['ja-JP'],
          uiLocale: 'en',
        );
        expect(languages, ['ja']);
        expect(parakeetRecommendedFor(languages), isFalse);
      },
    );
  });

  group('recommendEngine — every system language must fit Parakeet', () {
    test('German and English both fit: Parakeet', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['de', 'en'],
        vendor: GpuVendor.none,
        vramMB: 0,
      );
      expect(rec.engine, OnDeviceEngine.parakeet);
    });

    test('German and Japanese: Whisper, for the Japanese', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['de', 'ja'],
        vendor: GpuVendor.none,
        vramMB: 0,
      );
      expect(rec.engine, OnDeviceEngine.whisper);
    });

    test('no language: Whisper', () {
      expect(parakeetRecommendedFor(const []), isFalse);
    });
  });

  group('suggestedDictationLanguage — first start', () {
    test('the first system language Whisper writes is the suggestion', () {
      expect(suggestedDictationLanguage(['ja-JP']), 'ja');
      expect(suggestedDictationLanguage(['xx', 'pl_PL', 'en']), 'pl');
      expect(suggestedDictationLanguage(['de-DE', 'en-US']), 'de');
    });

    test('automatic detection only when the system names none', () {
      expect(suggestedDictationLanguage(const []), isNull);
      expect(suggestedDictationLanguage(['xx', 'auto']), isNull);
    });
  });

  group('recommendEngine — language decides engine eligibility', () {
    test(
      'German (de, European) recommends Parakeet regardless of hardware',
      () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['de'],
          vendor: GpuVendor.none,
          vramMB: 0,
        );

        expect(rec.engine, OnDeviceEngine.parakeet);
        expect(rec.tier, isNull, reason: 'Parakeet has no quality tiers');
      },
    );

    test('English (en, European) recommends Parakeet', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['en'],
        vendor: GpuVendor.apple,
        vramMB: 8192,
      );

      expect(rec.engine, OnDeviceEngine.parakeet);
    });

    test(
      'Hebrew (he, not in the Parakeet language set) recommends Whisper',
      () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['he'],
          vendor: GpuVendor.apple,
          vramMB: 8192,
        );

        expect(rec.engine, OnDeviceEngine.whisper);
        expect(rec.tier, isNotNull);
      },
    );

    test('unrecognized locale code ("auto") falls back to Whisper', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['auto'],
        vendor: GpuVendor.none,
        vramMB: 0,
      );

      expect(rec.engine, OnDeviceEngine.whisper);
    });

    test('empty locale code falls back to Whisper', () {
      final rec = recommendEngine(
        dictationLanguageCodes: [''],
        vendor: GpuVendor.none,
        vramMB: 0,
      );

      expect(rec.engine, OnDeviceEngine.whisper);
    });

    test('locale codes normalize by stripping region/script suffixes', () {
      // 'de_DE', 'de-DE', and 'DE' must all resolve the same way as 'de'.
      for (final code in ['de_DE', 'de-DE', 'DE']) {
        final rec = recommendEngine(
          dictationLanguageCodes: [code],
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

    test('hardware that runs the premium tier fluently keeps Whisper for a '
        'non-English language: it is a little more accurate there', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['fr'],
        vendor: GpuVendor.nvidia,
        vramMB: 24576,
        cudaUsable: true,
      );

      expect(rec.engine, OnDeviceEngine.whisper);
      expect(rec.tier, QualityTier.premium);
    });

    test('German on Apple Silicon with 16 GB: premium Whisper', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['de'],
        vendor: GpuVendor.apple,
        ramMB: 16384,
      );

      expect(rec.engine, OnDeviceEngine.whisper);
      expect(rec.tier, QualityTier.premium);
    });

    test('English on premium hardware: Parakeet, which leads in English', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['en'],
        vendor: GpuVendor.nvidia,
        vramMB: 24576,
        cudaUsable: true,
      );

      expect(rec.engine, OnDeviceEngine.parakeet);
      expect(rec.whisper.tier, QualityTier.premium);
    });

    test('hardware below the premium tier: Parakeet, more accurate than the '
        'smaller Whisper tiers and fluent everywhere', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['de'],
        vendor: GpuVendor.none,
        vramMB: 0,
        cpuCores: 4,
        ramMB: 8192,
      );

      expect(rec.engine, OnDeviceEngine.parakeet);
      expect(rec.whisper.tier, QualityTier.compact);
    });
  });

  group(
    'recommendEngine — one answer for onboarding and settings (UIA-RT-03)',
    () {
      test(
        'a measured fast tier beats the VRAM estimate for the same machine',
        () {
          // VRAM alone says Premium for 24 GB NVIDIA; the measurement only
          // proves up to Balanced fluent, and Settings trusts that verdict.
          final rec = recommendEngine(
            dictationLanguageCodes: ['he'],
            vendor: GpuVendor.nvidia,
            vramMB: 24576,
            measuredRtf: const {
              QualityTier.compact: 0.2,
              QualityTier.balanced: 0.5,
            },
          );

          expect(rec.engine, OnDeviceEngine.whisper);
          expect(rec.tier, QualityTier.balanced);
          expect(rec.tierSource, TierRecommendationSource.measured);
        },
      );

      test('without a measurement the tier is the VRAM estimate', () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['he'],
          vendor: GpuVendor.nvidia,
          vramMB: 24576,
        );

        expect(rec.tier, QualityTier.premium);
        expect(rec.tierSource, TierRecommendationSource.estimated);
      });

      test('an empty benchmark counts as no measurement', () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['he'],
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
            dictationLanguageCodes: ['he'],
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

      test('a measurement that only proves the compact tier fluent leaves '
          'a Parakeet language on Parakeet', () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['de'],
          vendor: GpuVendor.nvidia,
          vramMB: 24576,
          measuredRtf: const {QualityTier.compact: 0.2},
        );

        expect(rec.engine, OnDeviceEngine.parakeet);
        expect(rec.tier, isNull);
      });

      test('a measured fluent premium tier wins for German', () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['de'],
          vendor: GpuVendor.nvidia,
          vramMB: 24576,
          measuredRtf: const {
            QualityTier.compact: 0.1,
            QualityTier.balanced: 0.2,
            QualityTier.premium: 0.4,
          },
        );

        expect(rec.engine, OnDeviceEngine.whisper);
        expect(rec.tier, QualityTier.premium);
        expect(rec.tierSource, TierRecommendationSource.measured);
      });

      test('unknown VRAM and no measurement give Whisper no tier at all', () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['he'],
          vendor: null,
          vramMB: null,
        );

        expect(rec.engine, OnDeviceEngine.whisper);
        expect(rec.tier, isNull);
      });

      test('unknown VRAM still takes a measurement', () {
        final rec = recommendEngine(
          dictationLanguageCodes: ['he'],
          vendor: null,
          vramMB: null,
          measuredRtf: const {QualityTier.balanced: 0.4},
        );

        expect(rec.tier, QualityTier.balanced);
        expect(rec.tierSource, TierRecommendationSource.measured);
      });

      test('parakeetRecommendedFor is a language-only decision', () {
        expect(parakeetRecommendedFor(['de']), isTrue);
        expect(parakeetRecommendedFor(['de_DE']), isTrue);
        expect(parakeetRecommendedFor(['he']), isFalse);
        expect(parakeetRecommendedFor(['']), isFalse);
      });
    },
  );

  group('recommendEngine — Whisper tier feeds off recommendTier', () {
    test('Apple Silicon with ≥4GB unified memory recommends premium', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['he'],
        vendor: GpuVendor.apple,
        vramMB: 8192,
      );

      expect(rec.tier, QualityTier.premium);
    });

    test('NVIDIA with low VRAM recommends compact', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['he'],
        vendor: GpuVendor.nvidia,
        vramMB: 1024,
      );

      expect(rec.tier, QualityTier.compact);
    });

    test('GpuVendor.none (CPU-only) recommends compact', () {
      final rec = recommendEngine(
        dictationLanguageCodes: ['he'],
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
          dictationLanguageCodes: ['de'],
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

  group('fasterChoiceWhenSlow — the practice page offer (2a)', () {
    const parakeet = EngineRecommendation(
      engine: OnDeviceEngine.parakeet,
      basis: RecommendationBasis.language,
      withinWhisper: EngineRecommendation(
        engine: OnDeviceEngine.whisper,
        tier: QualityTier.compact,
      ),
    );
    const whisperCompact = EngineRecommendation(
      engine: OnDeviceEngine.whisper,
      tier: QualityTier.compact,
    );

    test('a fluent or unmeasured model gets no offer', () {
      for (final rtf in [null, 0.3, 0.79]) {
        expect(
          fasterChoiceWhenSlow(
            tier: QualityTier.premium,
            rtf: rtf,
            recommendation: parakeet,
          ),
          isNull,
        );
      }
    });

    test('a slow model offers Parakeet where it writes the languages', () {
      final offer = fasterChoiceWhenSlow(
        tier: QualityTier.premium,
        rtf: 1.4,
        recommendation: parakeet,
      );
      expect(offer?.engine, OnDeviceEngine.parakeet);
    });

    test('otherwise the smaller Whisper tier the recommendation gives', () {
      final offer = fasterChoiceWhenSlow(
        tier: QualityTier.balanced,
        rtf: 0.9,
        recommendation: whisperCompact,
      );
      expect(offer?.engine, OnDeviceEngine.whisper);
      expect(offer?.tier, QualityTier.compact);
    });

    test('no offer when nothing smaller is recommended', () {
      expect(
        fasterChoiceWhenSlow(
          tier: QualityTier.compact,
          rtf: 1.5,
          recommendation: whisperCompact,
        ),
        isNull,
      );
    });
  });
}
