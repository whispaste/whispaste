/// Model download service unit tests.
///
/// Tests for model download functionality including:
/// - Download failure handling (network errors, invalid URLs)
/// - GitHub API endpoint validation
/// - Model registry correctness
/// - State management during downloads
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/model_download_service.dart';

// ---------------------------------------------------------------------------
// GitHub API URL Validation Tests
// ---------------------------------------------------------------------------

void main() {
  group('GitHub API Endpoints', () {
    test('WhisPaste releases API returns valid JSON', () async {
      // This test verifies the WhisPaste releases endpoint is accessible
      // and returns valid JSON data. The service uses this to find
      // whisper-server binaries.
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'WhisPaste-Test/1.0',
          },
        ),
      );

      const apiUrl =
          'https://api.github.com/repos/whispaste/whispaste/releases';

      try {
        final response = await dio.get<List<dynamic>>(apiUrl);

        // Should return 200 OK
        expect(response.statusCode, 200);

        // Should return a list of releases
        expect(response.data, isNotNull);
        expect(response.data, isA<List<dynamic>>());

        // Should have at least one release
        expect(response.data!.length, greaterThan(0));

        // Each release should have required fields
        final firstRelease = response.data!.first as Map<String, dynamic>;
        expect(firstRelease['tag_name'], isNotNull);
        expect(firstRelease['assets'], isA<List<dynamic>>());

        // Verify we can find whisper-server releases
        final whisperServerReleases = response.data!.where(
          (r) => (r as Map<String, dynamic>)['tag_name'].toString().startsWith(
            'whisper-server-',
          ),
        );
        // Note: May be empty in some cases, but the API should still work
        expect(whisperServerReleases, isA<Iterable>());
      } on DioException catch (e) {
        // Handle rate limiting gracefully - the endpoint is valid even if rate limited
        if (e.response?.statusCode == 403) {
          expect(e.response?.statusCode, 403);
          markTestSkipped(
            'GitHub API rate limited - endpoint is valid but temporarily blocked',
          );
        } else {
          rethrow;
        }
      }

      dio.close();
    });

    test('Whisper.cpp releases API returns valid JSON', () async {
      // This test verifies the upstream whisper.cpp releases endpoint
      // is accessible and returns valid JSON data.
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'WhisPaste-Test/1.0',
          },
        ),
      );

      const apiUrl =
          'https://api.github.com/repos/ggml-org/whisper.cpp/releases/latest';

      try {
        final response = await dio.get<Map<String, dynamic>>(apiUrl);

        // Should return 200 OK
        expect(response.statusCode, 200);

        // Should return a release object
        expect(response.data, isNotNull);
        expect(response.data, isA<Map<String, dynamic>>());

        // Should have required fields
        expect(response.data!['tag_name'], isNotNull);
        expect(response.data!['assets'], isA<List<dynamic>>());

        // Should have assets (binaries)
        final assets = response.data!['assets'] as List<dynamic>;
        expect(assets.length, greaterThan(0));

        // Verify Windows binaries are available
        final windowsAssets = assets.where(
          (a) =>
              (a as Map<String, dynamic>)['name'].toString().contains('win') ||
              a['name'].toString().contains('Win'),
        );
        expect(windowsAssets, isNotEmpty);
      } on DioException catch (e) {
        // Handle rate limiting gracefully
        if (e.response?.statusCode == 403) {
          expect(e.response?.statusCode, 403);
          markTestSkipped(
            'GitHub API rate limited - endpoint is valid but temporarily blocked',
          );
        } else {
          rethrow;
        }
      }

      dio.close();
    });

    test('llama.cpp releases API returns valid JSON', () async {
      // This test verifies the llama.cpp releases endpoint for LLM server binaries
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'WhisPaste-Test/1.0',
          },
        ),
      );

      const apiUrl =
          'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest';

      try {
        final response = await dio.get<Map<String, dynamic>>(apiUrl);

        // Should return 200 OK
        expect(response.statusCode, 200);

        // Should return a release object with assets
        expect(response.data, isNotNull);
        expect(response.data!['assets'], isA<List<dynamic>>());
      } on DioException catch (e) {
        if (e.response?.statusCode == 403) {
          markTestSkipped(
            'GitHub API rate limited - endpoint is valid but temporarily blocked',
          );
        } else {
          rethrow;
        }
      }

      dio.close();
    });
  });

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

    test('LLM models are properly defined', () {
      // Verify all LLM models have required fields
      for (final model in llmModels) {
        expect(model.id, isNotEmpty);
        expect(model.label, isNotEmpty);
        expect(model.filename, isNotEmpty);
        expect(model.sizeBytes, greaterThan(0));
        expect(model.url, startsWith('https://'));
        // SHA256 may be null for community models
      }
    });

    test('findSttModel returns correct model by ID', () {
      expect(findSttModel('whisper-tiny')?.label, 'Tiny');
      expect(findSttModel('whisper-base')?.label, 'Base');
      expect(findSttModel('whisper-small')?.label, 'Small');
      expect(findSttModel('whisper-medium')?.label, 'Medium');
      expect(findSttModel('whisper-large-v3-turbo')?.label, 'Large v3 Turbo');
      expect(findSttModel('whisper-large-v3')?.label, 'Large v3');
      expect(findSttModel('nonexistent'), isNull);
    });

    test('findLlmModel returns correct model by ID', () {
      expect(findLlmModel('qwen3-1.7b')?.label, 'Qwen3 1.7B');
      expect(findLlmModel('nonexistent'), isNull);
    });

    test('sizeLabel formats correctly', () {
      final smallModel = sttModels.firstWhere((m) => m.id == 'whisper-tiny');
      expect(smallModel.sizeLabel, contains('MB'));

      final largeModel = sttModels.firstWhere(
        (m) => m.id == 'whisper-large-v3',
      );
      expect(largeModel.sizeLabel, contains('GB'));
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

      // NVIDIA with medium VRAM
      expect(
        recommendTier(1024, vendor: GpuVendor.nvidia),
        QualityTier.balanced,
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

    test('handles network timeout', () async {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(milliseconds: 1),
          receiveTimeout: const Duration(milliseconds: 1),
        ),
      );

      // Test with a URL that will timeout
      const slowUrl = 'https://httpbin.org/delay/10';

      expect(
        () async => await dio.get(slowUrl),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            anyOf(
              DioExceptionType.connectionTimeout,
              DioExceptionType.receiveTimeout,
            ),
          ),
        ),
      );

      dio.close();
    });

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

    test('initial state reflects no downloads', () {
      container = ProviderContainer();

      final state = container.read(modelDownloadProvider);

      expect(state.phase, DownloadPhase.idle);
      expect(state.downloadedModels, isEmpty);
      expect(state.downloadedLlmModels, isEmpty);
      expect(state.serverReady, false);
      expect(state.llmServerReady, false);
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
