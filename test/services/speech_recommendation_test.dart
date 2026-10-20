/// MV-04: onboarding (via [speechRecommendationFor]) and Settings (via
/// [whisperRecommendationFor]) answer with the same Whisper recommendation
/// and reason for the same hardware, on every platform and in every app
/// language. MV-03: the reason names the hardware class.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_info.dart' as app;
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/speech_recommendation.dart';
import 'package:whispaste/services/stt/benchmark_freshness.dart';
import 'package:whispaste/widgets/recommendation_reason.dart';

typedef _Profile = ({String label, hw.GpuInfo gpu, int cores, int? ramMB});

const List<_Profile> _profiles = [
  (
    label: 'weak laptop',
    gpu: hw.GpuInfo(
      vendor: hw.GpuVendor.intel,
      name: 'Intel(R) UHD Graphics 620',
      vramMB: 512,
      vulkanAvailable: true,
    ),
    cores: 4,
    ramMB: 8192,
  ),
  (
    label: 'mid-range',
    gpu: hw.GpuInfo(
      vendor: hw.GpuVendor.amd,
      name: 'AMD Radeon 780M',
      vramMB: 4096,
      vulkanAvailable: true,
    ),
    cores: 8,
    ramMB: 16384,
  ),
  (
    label: 'CUDA GPU',
    gpu: hw.GpuInfo(
      vendor: hw.GpuVendor.nvidia,
      name: 'NVIDIA GeForce RTX 3060',
      vramMB: 12288,
      cudaAvailable: true,
    ),
    cores: 8,
    ramMB: 32768,
  ),
  (
    label: 'Apple Silicon',
    gpu: hw.GpuInfo(vendor: hw.GpuVendor.apple, name: 'Apple M2'),
    cores: 8,
    ramMB: 16384,
  ),
  (
    label: 'only llvmpipe',
    gpu: hw.GpuInfo(
      vendor: hw.GpuVendor.none,
      name: 'llvmpipe (LLVM 15.0.7, 256 bits)',
      vulkanAvailable: true,
    ),
    cores: 4,
    ramMB: null,
  ),
];

AppSettings _settings(String language) =>
    AppSettings.defaults.copyWith(locale: language);

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    group('onboarding and Settings agree on ${platform.name} (MV-04)', () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      for (final profile in _profiles) {
        for (final language in ['de', 'he']) {
          test('${profile.label}, $language', () {
            final settings = _settings(language);
            final onboarding = speechRecommendationFor(
              settings: settings,
              gpu: profile.gpu,
              cpuCores: profile.cores,
              ramMB: profile.ramMB,
            );
            final settingsTier = whisperRecommendationFor(
              gpu: profile.gpu,
              measuredRtf: benchmarkRtfForMachine(
                benchmark: settings.benchmark,
                gpu: profile.gpu,
                appVersion: app.appVersion,
              ),
              cpuCores: profile.cores,
              ramMB: profile.ramMB,
            );

            final whisper = onboarding.recommendation.whisper;
            expect(whisper.tier, settingsTier.tier);
            expect(whisper.tierSource, settingsTier.tierSource);
            expect(whisper.basis, settingsTier.basis);
            expect(
              onboarding.recommendation.engine,
              language == 'de'
                  ? OnDeviceEngine.parakeet
                  : OnDeviceEngine.whisper,
            );
          });
        }
      }
    });
  }

  test('llvmpipe counts as CPU and Apple Silicon reads its RAM (MV-03)', () {
    final llvmpipe = speechRecommendationFor(
      settings: _settings('he'),
      gpu: _profiles[4].gpu,
      cpuCores: 4,
      ramMB: null,
    ).recommendation;
    expect(llvmpipe.basis, RecommendationBasis.softwareRenderer);

    final apple = speechRecommendationFor(
      settings: _settings('he'),
      gpu: _profiles[3].gpu,
      cpuCores: 8,
      ramMB: 16384,
    ).recommendation;
    expect(apple.basis, RecommendationBasis.appleSilicon);
    expect(apple.tier, isNotNull);
  });

  group('the reason reads in every app language (MV-03)', () {
    for (final locale in L10n.supportedLocales) {
      test(locale.languageCode, () {
        final l10n = lookupL10n(Locale(locale.languageCode));
        for (final profile in _profiles) {
          for (final language in ['de', 'he']) {
            final facts = speechRecommendationFor(
              settings: _settings(language),
              gpu: profile.gpu,
              cpuCores: profile.cores,
              ramMB: profile.ramMB,
            );
            final reason = recommendationReason(
              l10n,
              facts,
              facts.recommendation,
            );
            expect(reason, isNotNull, reason: profile.label);
            expect(reason, isNot(contains('{')), reason: profile.label);
            if (facts.recommendation.basis ==
                RecommendationBasis.softwareRenderer) {
              expect(reason, contains('llvmpipe'));
            }
          }
        }
      });
    }
  });
}
