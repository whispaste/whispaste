/// Model download service unit tests.
///
/// Tests for model download functionality including:
/// - Download failure handling (network errors, invalid URLs)
/// - Model registry correctness
/// - State management during downloads
///
/// Live-network smoke tests against the real GitHub Releases API used to
/// live here ("GitHub API Endpoints" group) — removed 2026-07-21. They
/// asserted on GitHub's actual API response (status code, release count,
/// asset names) instead of anything in this codebase, so they failed
/// whenever GitHub rate-limited the CI runner's shared IP, had a network
/// hiccup, or — as happened during a release-tag cleanup — the repo
/// briefly had zero releases. That's recurring CI flakiness unrelated to
/// app correctness; real coverage of ModelDownloadService lives in
/// model_download_service_behavior_snapshot_test.dart and
/// model_download_service_nonblocking_init_test.dart, both mocked.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/model_download_service.dart';

void main() {
  group('Model Registry', () {
    test('STT models are properly defined', () {
      // Verify all STT models have required fields
      for (final model in sttModels) {
        expect(model.id, isNotEmpty);
        expect(model.label, isNotEmpty);
        expect(model.filename, isNotEmpty);
        expect(model.sizeBytes, greaterThan(0));
        expect(model.url, startsWith('https://'));
        expect(model.sha256, hasLength(64)); // SHA256 is 64 hex chars
      }
    });

    test('findSttModel returns correct model by ID', () {
      expect(findSttModel('whisper-small')?.label, 'Small');
      expect(findSttModel('whisper-medium')?.label, 'Medium');
      expect(findSttModel('whisper-large-v3-turbo')?.label, 'Large v3 Turbo');
      expect(findSttModel('nonexistent'), isNull);
    });

    test('sizeLabel formats correctly', () {
      // Sub-GB models render as MB.
      const mb = SttModelInfo(
        id: 'fake-mb',
        label: 'Fake',
        filename: 'fake.bin',
        sizeBytes: 190085487,
        url: 'https://example.invalid/fake.bin',
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      );
      expect(mb.sizeLabel, contains('MB'));

      // ≥1 GiB renders as GB.
      const gb = SttModelInfo(
        id: 'fake-gb',
        label: 'Fake',
        filename: 'fake.bin',
        sizeBytes: 1500000000,
        url: 'https://example.invalid/fake.bin',
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      );
      expect(gb.sizeLabel, contains('GB'));
    });
  });

  group('Quality Tiers', () {
    test('modelsForTier returns correct models', () {
      final compact = modelsForTier(QualityTier.compact);
      expect(compact.map((m) => m.id), contains('whisper-small'));

      final balanced = modelsForTier(QualityTier.balanced);
      expect(balanced.map((m) => m.id), contains('whisper-medium'));

      final premium = modelsForTier(QualityTier.premium);
      expect(premium.map((m) => m.id), contains('whisper-large-v3-turbo'));
    });

    test('bestModelForTier returns first model', () {
      expect(bestModelForTier(QualityTier.compact).id, 'whisper-small');
      expect(bestModelForTier(QualityTier.balanced).id, 'whisper-medium');
      expect(
        bestModelForTier(QualityTier.premium).id,
        'whisper-large-v3-turbo',
      );
    });

    test('tierForModel returns correct tier', () {
      expect(tierForModel('whisper-small'), QualityTier.compact);
      expect(tierForModel('whisper-medium'), QualityTier.balanced);
      expect(tierForModel('whisper-large-v3-turbo'), QualityTier.premium);
      expect(tierForModel('unknown'), isNull);
    });

    test('recommendTier suggests appropriate tier for hardware', () {
      // NVIDIA with plenty of VRAM
      expect(
        recommendTier(4096, vendor: GpuVendor.nvidia),
        QualityTier.premium,
      );

      // NVIDIA with medium VRAM: 1024MB is below the 2150MB threshold
      // for balanced even with 0.70 safety margin, so compact is correct
      expect(
        recommendTier(1024, vendor: GpuVendor.nvidia),
        QualityTier.compact,
      );

      // NVIDIA with low VRAM
      expect(recommendTier(256, vendor: GpuVendor.nvidia), QualityTier.compact);

      // Intel/AMD integrated (conservative)
      expect(
        recommendTier(16384, vendor: GpuVendor.intel),
        QualityTier.premium,
      );

      // CPU only
      expect(recommendTier(0, vendor: GpuVendor.none), QualityTier.compact);
    });

    test('tierSizeLabel returns human-readable size', () {
      expect(tierSizeLabel(QualityTier.compact), contains('MB'));
      expect(tierSizeLabel(QualityTier.balanced), contains('MB'));
      expect(tierSizeLabel(QualityTier.premium), contains('MB'));
    });

    test('tierPerformance returns fast for benchmark RTF < 0.3', () {
      const gpu = GpuInfo(vendor: GpuVendor.none, name: 'CPU');

      final result = tierPerformance(
        QualityTier.compact,
        gpu,
        benchmarkRtf: {QualityTier.compact: 0.15},
      );
      expect(result, TierPerformance.fast);
    });

    test('tierPerformance returns moderate for benchmark RTF 0.3-0.8', () {
      const gpu = GpuInfo(vendor: GpuVendor.none, name: 'CPU');

      final result = tierPerformance(
        QualityTier.balanced,
        gpu,
        benchmarkRtf: {QualityTier.balanced: 0.5},
      );
      expect(result, TierPerformance.moderate);
    });

    test('tierPerformance returns slow for benchmark RTF >= 0.8', () {
      const gpu = GpuInfo(vendor: GpuVendor.none, name: 'CPU');

      final result = tierPerformance(
        QualityTier.premium,
        gpu,
        benchmarkRtf: {QualityTier.premium: 1.2},
      );
      expect(result, TierPerformance.slow);
    });

    test('tierPerformance estimates from VRAM when no benchmark data', () {
      // NVIDIA without CUDA — should fall back to conservative estimate.
      const gpu = GpuInfo(vendor: GpuVendor.nvidia, name: 'RTX 4090');
      expect(
        tierPerformance(QualityTier.compact, gpu),
        TierPerformance.moderate,
      );

      // NVIDIA with CUDA — should estimate as fast for compact.
      const gpuCuda = GpuInfo(
        vendor: GpuVendor.nvidia,
        name: 'RTX 4090',
        vramMB: 8192,
        cudaAvailable: true,
      );
      expect(
        tierPerformance(QualityTier.compact, gpuCuda),
        TierPerformance.fast,
      );

      // Apple Silicon with 16GB — should estimate fast.
      const apple = GpuInfo(
        vendor: GpuVendor.apple,
        name: 'Apple M5',
        vramMB: 16384,
      );
      expect(tierPerformance(QualityTier.premium, apple), TierPerformance.fast);
    });

    test(
      'recommendTierFromBenchmark returns compact when all tiers are fast',
      () {
        final rtfMap = {
          QualityTier.compact: 0.1,
          QualityTier.balanced: 0.2,
          QualityTier.premium: 0.5,
        };

        expect(recommendTierFromBenchmark(rtfMap), QualityTier.compact);
      },
    );

    test(
      'recommendTierFromBenchmark skips compact if too slow, returns balanced',
      () {
        final rtfMap = {
          QualityTier.compact: 0.9, // too slow
          QualityTier.balanced: 0.4,
          QualityTier.premium: 0.6,
        };

        expect(recommendTierFromBenchmark(rtfMap), QualityTier.balanced);
      },
    );

    test(
      'recommendTierFromBenchmark returns premium when all tiers exceed RTF 0.8',
      () {
        final rtfMap = {
          QualityTier.compact: 1.2,
          QualityTier.balanced: 1.5,
          QualityTier.premium: 2.0,
        };

        expect(recommendTierFromBenchmark(rtfMap), QualityTier.premium);
      },
    );

    test('recommendTierFromBenchmark returns null for empty map', () {
      expect(recommendTierFromBenchmark({}), isNull);
    });
  });

  group('ModelDownloadState', () {
    test('default state is idle', () {
      const state = ModelDownloadState();
      expect(state.phase, DownloadPhase.idle);
      expect(state.isDownloading, false);
      expect(state.isError, false);
      expect(state.isBusy, false);
    });

    test('copyWith creates correct copy', () {
      const state = ModelDownloadState();
      final newState = state.copyWith(
        phase: DownloadPhase.downloading,
        progressPercent: 50,
        activeModelId: 'whisper-small',
      );

      expect(newState.phase, DownloadPhase.downloading);
      expect(newState.progressPercent, 50);
      expect(newState.activeModelId, 'whisper-small');

      // Original should be unchanged
      expect(state.phase, DownloadPhase.idle);
    });

    test('isBusy returns true for active phases', () {
      expect(
        const ModelDownloadState(phase: DownloadPhase.downloading).isBusy,
        true,
      );
      expect(
        const ModelDownloadState(phase: DownloadPhase.extracting).isBusy,
        true,
      );
      expect(
        const ModelDownloadState(phase: DownloadPhase.verifying).isBusy,
        true,
      );
      expect(const ModelDownloadState(phase: DownloadPhase.idle).isBusy, false);
      expect(const ModelDownloadState(phase: DownloadPhase.done).isBusy, false);
    });
  });

  group('Download Failure Handling', () {
    test('handles 404 errors gracefully', () async {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      // Test with a URL that doesn't exist
      const invalidUrl =
          'https://api.github.com/repos/nonexistent-org-12345/nonexistent-repo-67890/releases';

      expect(
        () async => await dio.get(invalidUrl),
        throwsA(isA<DioException>()),
      );

      dio.close();
    });

    test(
      'handles network timeout',
      () async {
        // Skip: Dio timeout behavior is environment-dependent in test environment
      },
      skip: 'Dio timeout behavior is environment-dependent',
    );

    test('handles invalid URL format', () async {
      final dio = Dio();

      // Test with malformed URL
      const malformedUrl = 'not-a-valid-url';

      expect(
        () async => await dio.get(malformedUrl),
        throwsA(isA<DioException>()),
      );

      dio.close();
    });
  });

  group('ModelDownloadNotifier', () {
    late ProviderContainer container;

    tearDown(() {
      container.dispose();
    });

    test('initial state reflects idle phase', () {
      container = ProviderContainer();

      final state = container.read(modelDownloadProvider);

      // Only check phase — serverReady and downloadedModels reflect REAL disk state
      // and may differ between development environments.
      expect(state.phase, DownloadPhase.idle);
    });

    test('cancelDownload resets state when idle', () {
      container = ProviderContainer();

      final notifier = container.read(modelDownloadProvider.notifier);

      // Should not throw when idle
      notifier.cancelDownload();

      final state = container.read(modelDownloadProvider);
      expect(state.phase, DownloadPhase.idle);
    });

    test('refresh updates state', () {
      container = ProviderContainer();

      final notifier = container.read(modelDownloadProvider.notifier);

      // Should not throw
      notifier.refresh();

      final state = container.read(modelDownloadProvider);
      expect(state.phase, DownloadPhase.idle);
    });
  });
}
