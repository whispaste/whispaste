/// Regression test for the Parakeet bundle directory's orphaned-`.tmp`
/// cleanup gap.
///
/// [parakeetModelDir] is a subdirectory of `sttDir()`
/// (`sttDir()/parakeet-tdt-0.6b-v3/`). The startup/post-download sweeps in
/// `main.dart` and `model_download_service.dart` only ever passed `sttDir()`
/// to [sweepOrphanedTmpFiles], which lists its target directory
/// non-recursively — so an orphaned `.tmp` fragment left inside the Parakeet
/// subdirectory (e.g. from a crash or an abandoned download the user never
/// resumed) was never reaped, unlike the flat whisper `ggml-*.bin.tmp` case.
///
/// This test drives [ParakeetDownloadNotifier.downloadBundle] through a full
/// successful run (using [parakeetModelFilesOverride] so the fixture bytes
/// stay tiny instead of the real multi-hundred-MB bundle) and asserts that a
/// pre-existing, aged orphan `.tmp` fragment in the bundle directory is gone
/// afterwards — the sweep call added to `downloadBundle()`'s success path.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

/// Fake fetcher — writes [ParakeetModelFile.sizeBytes] bytes of zero-filled
/// content directly to `destPath`, mirroring the real fetcher's post-download
/// state (the atomic `.tmp` → final rename has already happened by the time
/// `fetch()` returns).
class _FakeFetcher extends HttpModelFetcher {
  _FakeFetcher({Set<String>? corruptFirstFetchOf})
    : corruptFirstFetchOf = {...?corruptFirstFetchOf};

  /// URLs whose next fetch writes same-sized bytes that do not match the
  /// pinned SHA-256 (a corrupt transfer). Consumed on use.
  final Set<String> corruptFirstFetchOf;
  final List<String> requestedUrls = [];

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    requestedUrls.add(url);
    final corrupt = corruptFirstFetchOf.remove(url);
    await File(
      destPath,
    ).writeAsBytes(List<int>.filled(expectedSize, corrupt ? 1 : 0));
    onProgress?.call(
      FetchProgress(
        bytesReceived: expectedSize,
        totalBytes: expectedSize,
        speedBytesPerSec: 1024,
      ),
    );
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

/// Fails every fetch with [error], the way the real fetcher surfaces a
/// transfer it could not complete.
class _FailingFetcher extends HttpModelFetcher {
  _FailingFetcher(this.error);

  final Object error;

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async => throw error;

  @override
  void cancel([String reason = 'cancelled']) {}
}

/// SHA-256 of the zero-filled fixture [_FakeFetcher] writes for [n] bytes.
String _zeroSha256(int n) => sha256.convert(List<int>.filled(n, 0)).toString();

final _fakeFiles = [
  ParakeetModelFile(
    filename: 'encoder.int8.onnx',
    url: 'https://x/e',
    sizeBytes: 8,
    sha256: _zeroSha256(8),
  ),
  ParakeetModelFile(
    filename: 'decoder.int8.onnx',
    url: 'https://x/d',
    sizeBytes: 4,
    sha256: _zeroSha256(4),
  ),
  ParakeetModelFile(
    filename: 'joiner.int8.onnx',
    url: 'https://x/j',
    sizeBytes: 4,
    sha256: _zeroSha256(4),
  ),
  ParakeetModelFile(
    filename: 'tokens.txt',
    url: 'https://x/t',
    sizeBytes: 2,
    sha256: _zeroSha256(2),
  ),
];

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_parakeet_dl_');
    sttDirOverride = tempDir.path;
    parakeetModelFilesOverride = _fakeFiles;
  });

  tearDown(() async {
    sttDirOverride = null;
    parakeetModelFilesOverride = null;
    parakeetFileExistsOverride = null;
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('a successful downloadBundle() reaps a pre-existing aged orphan .tmp '
      'fragment from the bundle directory', () async {
    // Simulate a fragment abandoned in an earlier, unrelated session (e.g.
    // the app crashed mid-download of a since-renamed/retired bundle
    // file). Back-dated well past sweepOrphanedTmpFiles' 1h default
    // threshold.
    final bundleDir = Directory(parakeetModelDir());
    await bundleDir.create(recursive: true);
    final orphan = File(p.join(bundleDir.path, 'stale-fragment.onnx.tmp'));
    await orphan.writeAsBytes([1, 2, 3]);
    await orphan.setLastModified(
      DateTime.now().subtract(const Duration(hours: 2)),
    );

    final fetcher = _FakeFetcher();
    final container = ProviderContainer(
      overrides: [
        parakeetDownloadProvider.overrideWith(() {
          final notifier = ParakeetDownloadNotifier();
          notifier.fetcherOverride = fetcher;
          return notifier;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(parakeetDownloadProvider.notifier).downloadBundle();

    expect(
      container.read(parakeetDownloadProvider).phase,
      ParakeetDownloadPhase.done,
    );
    expect(fetcher.requestedUrls, hasLength(_fakeFiles.length));

    // The sweep added to downloadBundle()'s success path is fire-and-forget
    // (unawaited) — poll until its async I/O has run; a fixed short delay
    // flaked on a heavily loaded machine.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (orphan.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(
      orphan.existsSync(),
      isFalse,
      reason:
          'downloadBundle() must sweep orphaned .tmp fragments from the '
          'Parakeet bundle directory on success, the same way the whisper '
          'model path does after model_download_service.dart\'s '
          '_markModelDone',
    );
  });

  group('SHA-256 verification of freshly downloaded files', () {
    test(
      'a hash mismatch deletes the file and errors; retry recovers',
      () async {
        final fetcher = _FakeFetcher(corruptFirstFetchOf: {'https://x/d'});
        final container = ProviderContainer(
          overrides: [
            parakeetDownloadProvider.overrideWith(
              () => ParakeetDownloadNotifier()..fetcherOverride = fetcher,
            ),
          ],
        );
        addTearDown(container.dispose);
        final notifier = container.read(parakeetDownloadProvider.notifier);

        await notifier.downloadBundle();

        final failed = container.read(parakeetDownloadProvider);
        expect(failed.phase, ParakeetDownloadPhase.error);
        expect(failed.installed, isFalse);
        expect(failed.errorMessage, contains('decoder.int8.onnx'));
        expect(failed.errorMessage, contains('checksum'));
        expect(
          File(p.join(parakeetModelDir(), 'decoder.int8.onnx')).existsSync(),
          isFalse,
          reason: 'a file that fails its pinned hash must not stay on disk',
        );

        await notifier.downloadBundle();

        expect(
          container.read(parakeetDownloadProvider).phase,
          ParakeetDownloadPhase.done,
        );
        expect(
          fetcher.requestedUrls.where((u) => u == 'https://x/d'),
          hasLength(2),
          reason: 'retry re-downloads only the rejected file',
        );
      },
    );
  });

  group('a failed transfer ends in a retryable error state', () {
    Future<ParakeetDownloadState> runWith(Object error) async {
      final container = ProviderContainer(
        overrides: [
          parakeetDownloadProvider.overrideWith(
            () =>
                ParakeetDownloadNotifier()
                  ..fetcherOverride = _FailingFetcher(error),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Called fire-and-forget by the UI — it must never throw.
      await container.read(parakeetDownloadProvider.notifier).downloadBundle();
      return container.read(parakeetDownloadProvider);
    }

    test('connection lost (Sentry 138737241)', () async {
      final state = await runWith(
        DioException.connectionError(
          requestOptions: RequestOptions(path: 'https://x/e'),
          reason: 'Connection closed while receiving data',
          error: const HttpException('Connection closed while receiving data'),
        ),
      );
      expect(state.phase, ParakeetDownloadPhase.error);
      expect(state.errorMessage, isNotNull);
      expect(state.isBusy, isFalse);
    });

    test('a disk error does not escape as an unhandled exception', () async {
      final state = await runWith(
        const FileSystemException('No space left on device', 'encoder.tmp'),
      );
      expect(state.phase, ParakeetDownloadPhase.error);
      expect(state.isBusy, isFalse);
    });
  });
}
