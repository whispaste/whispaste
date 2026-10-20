/// Central pre-download disk-space check (RE2-20 / OW-P19): every model
/// download refuses to start when the volume holds less than 1.2 x its size.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/download_disk_space.dart';
import 'package:whispaste/services/free_disk_space.dart';
import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeModelDirOverride;
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

/// Records whether a download started. Never touches the network.
class _RecordingFetcher extends HttpModelFetcher {
  bool started = false;

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    started = true;
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

/// A probe that reports [freeBytes] for every path.
FreeDiskSpaceProbe _probeReporting(int? freeBytes) =>
    (_) async => freeBytes;

void main() {
  group('checkDownloadDiskSpace', () {
    Future<DiskSpaceShortage?> check({
      required int downloadBytes,
      required int? freeBytes,
    }) => checkDownloadDiskSpace(
      dir: Directory.systemTemp.path,
      downloadBytes: downloadBytes,
      probe: _probeReporting(freeBytes),
    );

    test('needs 1.2 x the download size to be free', () async {
      final shortage = await check(downloadBytes: 1000, freeBytes: 1199);

      expect(shortage, isNotNull);
      expect(shortage!.neededBytes, 1200);
      expect(shortage.freeBytes, 1199);
    });

    test('exactly 1.2 x the download size is enough', () async {
      expect(await check(downloadBytes: 1000, freeBytes: 1200), isNull);
    });

    test(
      'an unknown free space does not block the download (fail-open)',
      () async {
        expect(await check(downloadBytes: 1000, freeBytes: null), isNull);
      },
    );

    test('a shortage message round-trips through the error code', () {
      const shortage = DiskSpaceShortage(neededBytes: 1200, freeBytes: 7);

      final decoded = DiskSpaceShortage.fromErrorCode(shortage.errorCode);

      expect(decoded?.neededBytes, 1200);
      expect(decoded?.freeBytes, 7);
    });

    test('other error messages are not disk-space shortages', () {
      expect(DiskSpaceShortage.fromErrorCode(null), isNull);
      expect(DiskSpaceShortage.fromErrorCode('Download failed: x'), isNull);
      expect(DiskSpaceShortage.fromErrorCode('disk_space_short:x:y'), isNull);
    });
  });

  group('a download does not start when the disk is too full', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('wp_disk_precheck_');
      sttDirOverride = tempDir.path;
      smartModeModelDirOverride = tempDir.path;
    });

    tearDown(() {
      sttDirOverride = null;
      smartModeModelDirOverride = null;
      parakeetModelFilesOverride = null;
      tempDir.deleteSync(recursive: true);
    });

    test('settings model download (Whisper)', () async {
      final fetcher = _RecordingFetcher();
      final container = ProviderContainer(
        overrides: [
          freeDiskSpaceProbeProvider.overrideWithValue(_probeReporting(1024)),
          modelDownloadProvider.overrideWith(
            () => ModelDownloadNotifier()..fetcherOverride = fetcher,
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(modelDownloadProvider.notifier);

      await notifier.downloadModel(sttModels.first.id);

      final state = container.read(modelDownloadProvider);
      expect(fetcher.started, isFalse);
      expect(state.phase, DownloadPhase.error);
      expect(
        DiskSpaceShortage.fromErrorCode(state.errorMessage)?.freeBytes,
        1024,
      );
    });

    test('smart mode model download', () async {
      final fetcher = _RecordingFetcher();
      final container = ProviderContainer(
        overrides: [
          freeDiskSpaceProbeProvider.overrideWithValue(_probeReporting(1024)),
          smartModeDownloadProvider.overrideWith(
            () => SmartModeDownloadNotifier()..fetcherOverride = fetcher,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(smartModeDownloadProvider.notifier).downloadModel();

      final state = container.read(smartModeDownloadProvider);
      expect(fetcher.started, isFalse);
      expect(state.phase, SmartModeDownloadPhase.error);
      expect(
        DiskSpaceShortage.fromErrorCode(state.errorMessage)?.neededBytes,
        (smartModeModel.sizeBytes * downloadDiskSpaceFactor).ceil(),
      );
    });

    test('Parakeet bundle download', () async {
      parakeetModelFilesOverride = [
        ParakeetModelFile(
          filename: 'encoder.int8.onnx',
          url: 'https://x/e',
          sizeBytes: 4096,
          sha256: '0' * 64,
        ),
      ];
      final fetcher = _RecordingFetcher();
      final container = ProviderContainer(
        overrides: [
          freeDiskSpaceProbeProvider.overrideWithValue(_probeReporting(1024)),
          parakeetDownloadProvider.overrideWith(
            () => ParakeetDownloadNotifier()..fetcherOverride = fetcher,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(parakeetDownloadProvider.notifier).downloadBundle();

      final state = container.read(parakeetDownloadProvider);
      expect(fetcher.started, isFalse);
      expect(state.phase, ParakeetDownloadPhase.error);
      expect(DiskSpaceShortage.fromErrorCode(state.errorMessage), isNotNull);
    });
  });
}
