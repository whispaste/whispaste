/// Retry after a failed model download (#1498): the same model is fetched
/// again, a success clears the error, a second failure shows it again.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/file_verification_service.dart';
import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;

class _ScriptedFetcher extends HttpModelFetcher {
  _ScriptedFetcher(this.outcomes);

  /// One entry per call: true = file written, false = throws.
  final List<bool> outcomes;
  final List<String> urls = [];

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    urls.add(url);
    if (!outcomes[urls.length - 1]) {
      throw const SocketException('offline');
    }
    await File(destPath).writeAsBytes(const [1, 2, 3]);
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

class _OkVerifier extends FileVerificationService {
  @override
  Future<VerificationResult> verifyStamped(
    File file,
    String expectedHash,
  ) async => const VerificationOk();
}

void main() {
  late Directory tempDir;
  final model = sttModels.first;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_retry_');
    sttDirOverride = tempDir.path;
  });

  tearDown(() async {
    sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  ProviderContainer build(_ScriptedFetcher fetcher) {
    final container = ProviderContainer(
      overrides: [
        modelDownloadProvider.overrideWith(
          () => ModelDownloadNotifier()
            ..fetcherOverride = fetcher
            ..verifierOverride = _OkVerifier(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('retry fetches the failed model again and clears the error', () async {
    final fetcher = _ScriptedFetcher([false, true]);
    final container = build(fetcher);
    final notifier = container.read(modelDownloadProvider.notifier);
    await notifier.awaitInitialScan();

    await notifier.downloadModel(model.id);
    var state = container.read(modelDownloadProvider);
    expect(state.isError, isTrue);
    expect(state.activeModelId, model.id);

    await notifier.retry();
    state = container.read(modelDownloadProvider);
    expect(fetcher.urls, [model.url, model.url]);
    expect(state.isError, isFalse);
    expect(state.errorMessage, isNull);
  });

  test('a failing retry shows the error again', () async {
    final fetcher = _ScriptedFetcher([false, false]);
    final container = build(fetcher);
    final notifier = container.read(modelDownloadProvider.notifier);
    await notifier.awaitInitialScan();

    await notifier.downloadModel(model.id);
    await notifier.retry();

    final state = container.read(modelDownloadProvider);
    expect(fetcher.urls.length, 2);
    expect(state.isError, isTrue);
    expect(state.errorMessage, isNotNull);
  });

  test('retry without a kept model uses the fallback model', () async {
    final fetcher = _ScriptedFetcher([true]);
    final container = build(fetcher);
    final notifier = container.read(modelDownloadProvider.notifier);
    await notifier.awaitInitialScan();

    await notifier.retry(fallbackModelId: model.id);
    expect(fetcher.urls, [model.url]);
  });
}
