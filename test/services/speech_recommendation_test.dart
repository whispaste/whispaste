/// MV-04: onboarding (via [speechRecommendationFor]) and Settings (via
/// [whisperRecommendationFor]) answer with the same Whisper recommendation
/// and reason for the same hardware, on every platform and in every app
/// language. MV-03: the reason names the hardware class.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_info.dart' as app;
import 'package:whispaste/core/config/quality_tier.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/initial_locale.dart'
    show systemLocalesProvider;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/engine_recommendation.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/speech_recommendation.dart';
import 'package:whispaste/services/stt/backend_utilization_notifier.dart'
    show processorCountProvider;
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

class _WritableSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.requireValue));
  }
}

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
            // German gets Parakeet unless the machine carries the premium
            // Whisper tier fluently; Hebrew always needs Whisper.
            expect(
              onboarding.recommendation.engine,
              language == 'de' && whisper.tier != QualityTier.premium
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

  group('speechRecommendationProvider', () {
    // Every onboarding page change stores its position. A rebuild of the
    // recommendation then was flushed inside the next page's layout and
    // notified its dependents mid-build.
    test('a write the recommendation does not read leaves it as it is, a '
        'language change recomputes it', () async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_WritableSettings.new),
          hw.gpuInfoProvider.overrideWith(
            (ref) async =>
                const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test'),
          ),
          systemLocalesProvider.overrideWithValue(const [Locale('de')]),
          processorCountProvider.overrideWithValue(8),
        ],
      );
      addTearDown(container.dispose);
      var updates = 0;
      container.listen(
        speechRecommendationProvider,
        (_, _) => updates++,
        fireImmediately: false,
      );
      await container.read(speechRecommendationProvider.future);
      final settled = updates;
      final settings = container.read(settingsProvider.notifier);

      await settings.updateSettings(
        (s) => s.copyWithSections(
          onboarding: s.onboarding.copyWith(onboardingCurrentStep: 4),
        ),
      );
      await container.pump();
      expect(updates, settled);
      expect(container.read(speechRecommendationProvider).isLoading, isFalse);

      await settings.updateSettings(
        (s) => s.copyWithSections(stt: s.stt.copyWith(language: 'English')),
      );
      await container.read(speechRecommendationProvider.future);
      expect(updates, greaterThan(settled));
    });
  });
}
