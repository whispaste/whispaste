/// NVIDIA EULA consent for the optional CUDA pack: the per-version rule, the
/// persisted field, and the notifier gate that keeps a download from starting
/// without consent (the dialog is only one UI path to it).
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/stt/whisper/cuda_pack.dart';

const _pack = CudaPackInfo(
  id: 'ggml-test-r1',
  url: 'https://example.invalid/pack.zip',
  archiveSizeBytes: 1024,
  archiveSha256: '',
  files: [],
);

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

/// Records each download attempt and fails it as a user cancel, so the
/// notifier returns to idle without touching the network.
class _RecordingFetcher extends HttpModelFetcher {
  int calls = 0;

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    calls++;
    throw DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.cancel,
    );
  }
}

ProviderContainer _container({
  required Directory root,
  required _RecordingFetcher fetcher,
  required AppSettings settings,
}) {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
      deployChannelProvider.overrideWithValue(DeployChannel.packageManaged),
      cudaPackProvider.overrideWith(
        () => CudaPackNotifier()
          ..packOverride = _pack
          ..storeOverride = CudaPackStore(rootDir: root.path)
          ..fetcherOverride = fetcher,
      ),
    ],
  );
}

AppSettings _withAccepted(String packId) =>
    AppSettings.defaults.copyWithSections(
      behavior: AppSettings.defaults.behavior.copyWith(
        cudaEulaAccepted: cudaEulaConsentValue(packId),
      ),
    );

void main() {
  group('isCudaEulaAcceptedFor', () {
    test('never accepted matches nothing', () {
      expect(isCudaEulaAcceptedFor(accepted: '', packId: _pack.id), isFalse);
    });

    test('the accepted pack version matches', () {
      expect(
        isCudaEulaAcceptedFor(
          accepted: cudaEulaConsentValue(_pack.id),
          packId: _pack.id,
        ),
        isTrue,
      );
    });

    test('a new EULA version asks again, even for the same pack version', () {
      expect(
        isCudaEulaAcceptedFor(
          accepted: '${_pack.id}+eula-2025-01-01',
          packId: _pack.id,
        ),
        isFalse,
      );
    });

    test('a new pack version asks again', () {
      expect(
        isCudaEulaAcceptedFor(
          accepted: 'ggml-v1.9.5-cu12.8-r1',
          packId: 'ggml-v1.9.5-cu12.8-r2',
        ),
        isFalse,
      );
    });
  });

  test(
    'the acceptance is stored in the behavior settings, empty by default',
    () {
      expect(BehaviorSettings.defaults.cudaEulaAccepted, isEmpty);
      final restored = BehaviorSettings.fromMap(
        const BehaviorSettings(cudaEulaAccepted: 'ggml-x-r1').toMap(),
      );
      expect(restored.cudaEulaAccepted, 'ggml-x-r1');
    },
  );

  group('CudaPackNotifier consent gate', () {
    late Directory root;
    late _RecordingFetcher fetcher;

    setUp(() {
      root = Directory.systemTemp.createTempSync('cuda_eula_test');
      fetcher = _RecordingFetcher();
    });

    tearDown(() {
      root.deleteSync(recursive: true);
    });

    test('install() without consent starts no download', () async {
      final container = _container(
        root: root,
        fetcher: fetcher,
        settings: AppSettings.defaults,
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await container.read(cudaPackProvider.notifier).install();

      expect(fetcher.calls, 0);
      expect(container.read(cudaPackProvider).phase, CudaPackPhase.idle);
    });

    test(
      'install() with consent for another pack version starts nothing',
      () async {
        final container = _container(
          root: root,
          fetcher: fetcher,
          settings: _withAccepted('ggml-old-r1'),
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        await container.read(cudaPackProvider.notifier).install();

        expect(fetcher.calls, 0);
      },
    );

    test(
      'acceptEulaAndInstall() stores the pack version, then downloads',
      () async {
        final container = _container(
          root: root,
          fetcher: fetcher,
          settings: AppSettings.defaults,
        );
        addTearDown(container.dispose);
        await container.read(settingsProvider.future);

        await container.read(cudaPackProvider.notifier).acceptEulaAndInstall();

        final stored = container
            .read(settingsProvider)
            .value!
            .behavior
            .cudaEulaAccepted;
        expect(stored, cudaEulaConsentValue(_pack.id));
        expect(fetcher.calls, 1);
      },
    );
  });
}
