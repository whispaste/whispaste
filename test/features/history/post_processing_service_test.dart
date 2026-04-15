/// Post-processing service unit tests.
///
/// Tests that the service properly throws Exception (not StateError) when
/// the local LLM model is not downloaded, allowing the UI to handle it gracefully.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/llm_service.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/post_processing_service.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake settings notifier that returns fixed settings.
class _FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _settings;

  _FakeSettingsNotifier(this._settings);

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) update) async {
    // No-op for tests
  }
}

/// Fake model download notifier with configurable download state.
class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  final ModelDownloadState _state;

  _FakeModelDownloadNotifier(this._state);

  @override
  ModelDownloadState build() => _state;
}

/// Fake LLM service notifier that simulates a running server.
class _FakeLlmServiceNotifier extends LlmServiceNotifier {
  final bool _throwOnEnsureRunning;
  final String _response;

  _FakeLlmServiceNotifier({
    bool throwOnEnsureRunning = false,
    String response = 'Processed text',
  }) : _throwOnEnsureRunning = throwOnEnsureRunning,
       _response = response;

  @override
  LlmStatus build() => const LlmStatus(
    serverState: LlmServerState.ready,
    port: 9999,
    modelId: 'qwen3-1.7b',
  );

  @override
  Future<void> ensureRunning() async {
    if (_throwOnEnsureRunning) {
      throw Exception('LLM server failed to start');
    }
  }

  @override
  Future<String> complete(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    return _response;
  }

  @override
  Future<List<String>> suggestTags(String text) async {
    return ['tag1', 'tag2'];
  }

  @override
  Future<String> suggestTitle(String text) async {
    return 'Suggested Title';
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PostProcessingNotifier', () {
    late ProviderContainer container;

    tearDown(() {
      container.dispose();
    });

    group('when local model is not downloaded', () {
      test('process() throws Exception with helpful message', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        // Model NOT downloaded, server NOT ready
        const downloadState = ModelDownloadState(
          downloadedLlmModels: {}, // Empty - model not downloaded
          llmServerReady: false,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        // Should throw Exception (not StateError) with helpful message
        expect(
          () => notifier.process('Test text', PostProcessPreset.cleanup),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('not downloaded'),
            ),
          ),
        );
      });

      test('suggestTags() throws Exception with helpful message', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        const downloadState = ModelDownloadState(
          downloadedLlmModels: {},
          llmServerReady: false,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        expect(
          () => notifier.suggestTags('Test text'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('not downloaded'),
            ),
          ),
        );
      });

      test('suggestTitle() throws Exception with helpful message', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        const downloadState = ModelDownloadState(
          downloadedLlmModels: {},
          llmServerReady: false,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        expect(
          () => notifier.suggestTitle('Test text'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('not downloaded'),
            ),
          ),
        );
      });

      test('error state is set with friendly message', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        const downloadState = ModelDownloadState(
          downloadedLlmModels: {},
          llmServerReady: false,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        // Attempt to process (will fail)
        try {
          await notifier.process('Test text', PostProcessPreset.cleanup);
          fail('Should have thrown');
        } on Exception {
          // Expected
        }

        // Verify error state was set
        final state = container.read(postProcessingProvider);
        expect(state.state, PostProcessingState.error);
        expect(state.errorMessage, isNotNull);
        expect(state.errorMessage, contains('not downloaded'));
      });
    });

    group('when local model is downloaded but server binary is missing', () {
      test('process() throws Exception mentioning download', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        // Model downloaded but server binary NOT ready
        const downloadState = ModelDownloadState(
          downloadedLlmModels: {'qwen3-1.7b'}, // Model IS downloaded
          llmServerReady: false, // But server binary is NOT ready
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        // Should still throw because server is not ready
        expect(
          () => notifier.process('Test text', PostProcessPreset.cleanup),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('not downloaded'),
            ),
          ),
        );
      });
    });

    group('when local model is fully ready', () {
      test('process() proceeds without throwing', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        // Model downloaded AND server ready
        const downloadState = ModelDownloadState(
          downloadedLlmModels: {'qwen3-1.7b'},
          llmServerReady: true,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        // Should complete without throwing
        final result = await notifier.process(
          'Test text',
          PostProcessPreset.cleanup,
        );
        expect(result, 'Processed text');
      });

      test('suggestTags() proceeds without throwing', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        const downloadState = ModelDownloadState(
          downloadedLlmModels: {'qwen3-1.7b'},
          llmServerReady: true,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        final result = await notifier.suggestTags('Test text');
        expect(result, ['tag1', 'tag2']);
      });

      test('suggestTitle() proceeds without throwing', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        const downloadState = ModelDownloadState(
          downloadedLlmModels: {'qwen3-1.7b'},
          llmServerReady: true,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        final result = await notifier.suggestTitle('Test text');
        expect(result, 'Suggested Title');
      });

      test('state transitions correctly through the process', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        const downloadState = ModelDownloadState(
          downloadedLlmModels: {'qwen3-1.7b'},
          llmServerReady: true,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        // Initial state
        expect(
          container.read(postProcessingProvider).state,
          PostProcessingState.idle,
        );

        // Start processing
        final future = notifier.process('Test text', PostProcessPreset.cleanup);

        // Should be in starting or processing state
        expect(
          container.read(postProcessingProvider).state,
          anyOf(PostProcessingState.starting, PostProcessingState.processing),
        );

        // Complete
        await future;

        // Back to idle
        expect(
          container.read(postProcessingProvider).state,
          PostProcessingState.idle,
        );
      });
    });

    group('concurrent operation protection', () {
      test('throws StateError when process() called while busy', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'Local',
        );

        const downloadState = ModelDownloadState(
          downloadedLlmModels: {'qwen3-1.7b'},
          llmServerReady: true,
        );

        // Create a fake that will delay to keep us in "busy" state
        final fakeLlm = _FakeLlmServiceNotifier();

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => fakeLlm),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        // Start first operation
        final future1 = notifier.process('Test 1', PostProcessPreset.cleanup);

        // Immediately try second operation (should fail)
        expect(
          () => notifier.process('Test 2', PostProcessPreset.cleanup),
          throwsA(isA<StateError>()),
        );

        // Complete first operation
        await future1;
      });
    });

    group('cloud provider (no local model check)', () {
      test('process() with OpenAI does not check local model download', () async {
        final settings = AppSettings.defaults.copyWith(
          postProcessProvider: 'OpenAI',
          openAiApiKey: 'test-key',
          cloudLlmModel: 'gpt-4',
        );

        // Even with no local model downloaded, cloud provider should work
        const downloadState = ModelDownloadState(
          downloadedLlmModels: {},
          llmServerReady: false,
        );

        container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(
              () => _FakeSettingsNotifier(settings),
            ),
            modelDownloadProvider.overrideWith(
              () => _FakeModelDownloadNotifier(downloadState),
            ),
            llmServiceProvider.overrideWith(() => _FakeLlmServiceNotifier()),
          ],
        );

        final notifier = container.read(postProcessingProvider.notifier);

        // This will fail with API error, but NOT with "model not downloaded" error
        try {
          await notifier.process('Test text', PostProcessPreset.cleanup);
          // If we have a fake cloud provider, it might succeed
        } on Exception catch (e) {
          // Should NOT be the "not downloaded" error
          expect(e.toString(), isNot(contains('not downloaded')));
        }
      });
    });
  });
}
