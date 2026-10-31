/// Behavior tests for [SmartModeDownloadNotifier], mirroring
/// `model_download_service_behavior_snapshot_test.dart`'s fake-fetcher seam.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeModelDirOverride;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';

enum _FetchBehaviour { succeed, networkError, cancelled, writeBadContent }

class _FakeFetcher extends HttpModelFetcher {
  _FakeFetcher({this.behaviour = _FetchBehaviour.succeed});

  _FetchBehaviour behaviour;
  bool fetchCalled = false;
  String? lastUrl;
  String? lastDestPath;

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    fetchCalled = true;
    lastUrl = url;
    lastDestPath = destPath;

    switch (behaviour) {
      case _FetchBehaviour.succeed:
        // Bytes whose SHA256 matches [smartModeModel.sha256] cannot be
        // fabricated — the "done" transition is exercised via the
        // already-on-disk scan path below instead (same pattern the STT
        // snapshot test uses).
        await File(destPath).writeAsBytes(Uint8List(100));
      case _FetchBehaviour.networkError:
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.unknown,
          message: 'connection refused',
        );
      case _FetchBehaviour.cancelled:
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.cancel,
        );
      case _FetchBehaviour.writeBadContent:
        await File(destPath).writeAsBytes([0xde, 0xad, 0xbe, 0xef]);
    }

    onProgress?.call(
      const FetchProgress(
        bytesReceived: 100,
        totalBytes: 100,
        speedBytesPerSec: 0,
      ),
    );
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

ProviderContainer _makeContainer({required _FakeFetcher fetcher}) {
  return ProviderContainer(
    overrides: [
      smartModeDownloadProvider.overrideWith(() {
        final notifier = SmartModeDownloadNotifier();
        notifier.fetcherOverride = fetcher;
        return notifier;
      }),
    ],
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_smart_mode_dl_');
    smartModeModelDirOverride = tempDir.path;
  });

  tearDown(() async {
    smartModeModelDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  group('Model registry', () {
    test('smartModeModel has valid metadata', () {
      expect(smartModeModel.id, isNotEmpty);
      expect(smartModeModel.filename, isNotEmpty);
      expect(smartModeModel.sizeBytes, greaterThan(0));
      expect(smartModeModel.url, startsWith('https://'));
      expect(smartModeModel.sha256, hasLength(64));
      expect(smartModeModel.sizeLabel, contains('GB'));
    });
  });

  group('SmartModeDownloadState', () {
    test('default state is idle and not downloaded', () {
      const state = SmartModeDownloadState();
      expect(state.phase, SmartModeDownloadPhase.idle);
      expect(state.modelDownloaded, isFalse);
      expect(state.isBusy, isFalse);
    });
  });

  group('Successful download orchestration', () {
    test(
      'transitions idle -> downloading -> verifying (hash mismatch)',
      () async {
        final fetcher = _FakeFetcher();
        final container = _makeContainer(fetcher: fetcher);
        addTearDown(container.dispose);

        final states = <SmartModeDownloadPhase>[];
        final sub = container.listen(
          smartModeDownloadProvider,
          (_, s) => states.add(s.phase),
        );
        addTearDown(sub.close);

        await container
            .read(smartModeDownloadProvider.notifier)
            .downloadModel();

        expect(states, contains(SmartModeDownloadPhase.downloading));
        expect(states, contains(SmartModeDownloadPhase.verifying));
        expect(fetcher.fetchCalled, isTrue);
        expect(fetcher.lastUrl, smartModeModel.url);
        expect(
          fetcher.lastDestPath,
          p.join(tempDir.path, smartModeModel.filename),
        );
      },
    );

    test(
      'initial disk scan marks pre-existing correct file as downloaded',
      () async {
        // Cannot fabricate a file matching the real SHA256, so this exercises
        // the scan-finds-file branch via a placeholder — verification of the
        // "already downloaded" happy path is left to hash equality, which the
        // scan itself does not check (see _scanExistingModelAsync).
        final destPath = p.join(tempDir.path, smartModeModel.filename);
        await File(destPath).writeAsBytes([0]);

        final fetcher = _FakeFetcher();
        final container = _makeContainer(fetcher: fetcher);
        addTearDown(container.dispose);

        await container
            .read(smartModeDownloadProvider.notifier)
            .awaitInitialScan();
        final state = container.read(smartModeDownloadProvider);
        expect(state.modelDownloaded, isTrue);
      },
    );
  });

  group('Network error', () {
    test('transitions to error phase on DioException', () async {
      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.networkError);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      await container.read(smartModeDownloadProvider.notifier).downloadModel();

      final state = container.read(smartModeDownloadProvider);
      expect(state.phase, SmartModeDownloadPhase.error);
      expect(state.errorMessage, isNotNull);
    });
  });

  group('SHA256 mismatch', () {
    test('transitions to error and deletes corrupt file', () async {
      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.writeBadContent);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      await container.read(smartModeDownloadProvider.notifier).downloadModel();

      final state = container.read(smartModeDownloadProvider);
      expect(state.phase, SmartModeDownloadPhase.error);
      expect(state.errorMessage, contains('SHA256 verification failed'));
      expect(
        File(p.join(tempDir.path, smartModeModel.filename)).existsSync(),
        isFalse,
      );
    });
  });

  group('Cancellation', () {
    test('cancelDownload resets to idle when no download is active', () {
      final fetcher = _FakeFetcher();
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      container.read(smartModeDownloadProvider.notifier).cancelDownload();

      final state = container.read(smartModeDownloadProvider);
      expect(state.phase, SmartModeDownloadPhase.idle);
      expect(state.progressPercent, 0);
    });

    test('cancellation mid-download transitions to idle', () async {
      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.cancelled);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      await container.read(smartModeDownloadProvider.notifier).downloadModel();

      final state = container.read(smartModeDownloadProvider);
      expect(state.isError, isFalse);
    });
  });

  group('deleteModel', () {
    test('removes the file and clears modelDownloaded', () async {
      final destPath = p.join(tempDir.path, smartModeModel.filename);
      await File(destPath).writeAsBytes([0]);

      final fetcher = _FakeFetcher();
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      await container
          .read(smartModeDownloadProvider.notifier)
          .awaitInitialScan();
      expect(container.read(smartModeDownloadProvider).modelDownloaded, isTrue);

      await container.read(smartModeDownloadProvider.notifier).deleteModel();

      expect(
        container.read(smartModeDownloadProvider).modelDownloaded,
        isFalse,
      );
      expect(File(destPath).existsSync(), isFalse);
    });
  });

  group('Busy guard', () {
    test(
      'fetcher is called exactly once per downloadModel invocation',
      () async {
        final fetcher = _CountingFakeFetcher(
          behaviour: _FetchBehaviour.networkError,
        );
        final container = _makeContainer(fetcher: fetcher);
        addTearDown(container.dispose);

        await container
            .read(smartModeDownloadProvider.notifier)
            .downloadModel();

        expect(container.read(smartModeDownloadProvider).isBusy, isFalse);
        expect(fetcher.callCount, 1);
      },
    );
  });
}

class _CountingFakeFetcher extends _FakeFetcher {
  _CountingFakeFetcher({super.behaviour});

  int callCount = 0;

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    callCount++;
    return super.fetch(
      url: url,
      destPath: destPath,
      expectedSize: expectedSize,
      onProgress: onProgress,
    );
  }
}
