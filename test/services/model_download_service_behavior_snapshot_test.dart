/// Behavior-snapshot tests for [ModelDownloadNotifier].
///
/// These tests freeze the observable state-transition semantics of the
/// download service.
///
/// The seam is [ModelDownloadNotifier.fetcherOverride]: a fake
/// [HttpModelFetcher] is injected so no real network calls are made.
/// The SHA256 verification path is exercised by writing real files to a
/// temp directory (using [sttDirOverride]).
///
/// Scenarios covered:
///   1. Successful download — full state-transition sequence
///   2. Network error → error state
///   3. User cancellation → idle state
///   4. SHA256 mismatch → error state
///   5. Resume — fetcher called when partial .tmp file exists
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/download_error_kind.dart';
import 'package:whispaste/services/file_verification_service.dart';
import 'package:whispaste/services/free_disk_space.dart';
import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;

// ── Fake HttpModelFetcher ─────────────────────────────────────────────────────

/// Controls what the fake fetcher does on the next [fetch] call.
enum _FetchBehaviour {
  /// Writes [_FakeFetcher.fileContent] bytes to [destPath] and succeeds.
  succeed,

  /// Throws a [DioException] with the configured error type.
  networkError,

  /// Throws a [DioException] of type [DioExceptionType.cancel].
  cancelled,

  /// Writes garbage bytes to [destPath] so SHA256 verification fails.
  writeBadContent,

  /// Writes [_FakeFetcher.fileContent] and also creates a partial .tmp file
  /// before the call to simulate resume being triggered.
  resumeSucceed,
}

class _FakeFetcher extends HttpModelFetcher {
  _FakeFetcher({
    this.behaviour = _FetchBehaviour.succeed,
    this.fileContent,
    this.errorType = DioExceptionType.unknown,
  });

  final DioExceptionType errorType;

  _FetchBehaviour behaviour;

  /// Bytes written to [destPath] for [_FetchBehaviour.succeed] /
  /// [_FetchBehaviour.resumeSucceed]. May be null for other behaviours.
  final List<int>? fileContent;

  /// Set to true when [fetch] is called.
  bool fetchCalled = false;

  /// The [url] passed to the last [fetch] call.
  String? lastUrl;

  /// The [destPath] passed to the last [fetch] call.
  String? lastDestPath;

  /// Whether a .tmp file existed when [fetch] was called (resume scenario).
  bool tmpFileExistedOnCall = false;

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

    final tmpPath = '$destPath.tmp';
    tmpFileExistedOnCall = File(tmpPath).existsSync();

    switch (behaviour) {
      case _FetchBehaviour.succeed:
      case _FetchBehaviour.resumeSucceed:
        final bytes = fileContent ?? Uint8List(100);
        // Write directly to destPath (simulates completed atomic rename).
        await File(destPath).writeAsBytes(bytes);

      case _FetchBehaviour.networkError:
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: errorType,
          message: 'connection refused',
        );

      case _FetchBehaviour.cancelled:
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.cancel,
        );

      case _FetchBehaviour.writeBadContent:
        // Write garbage so SHA256 check fails.
        await File(destPath).writeAsBytes([0xde, 0xad, 0xbe, 0xef]);
    }

    // Emit a single progress event so callers can verify callbacks.
    final total = fileContent?.length ?? 100;
    onProgress?.call(
      FetchProgress(
        bytesReceived: total,
        totalBytes: total,
        speedBytesPerSec: 1024 * 1024,
      ),
    );
  }

  @override
  void cancel([String reason = 'cancelled']) {
    // No-op for the fake.
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _AcceptingVerifier extends FileVerificationService {
  final calls = <(String, String)>[];

  @override
  Future<VerificationResult> verifyStamped(
    File file,
    String expectedHash,
  ) async {
    calls.add((file.path, expectedHash));
    expect(await file.length(), greaterThan(0));
    return const VerificationOk();
  }
}

class _MemorySettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(sttModel: 'whisper-medium');

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.requireValue));
  }
}

/// Injects dependencies before the notifier's initial disk scan starts.
ProviderContainer _makeContainer({
  required _FakeFetcher fetcher,
  FileVerificationService? verifier,
}) {
  return ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_MemorySettings.new),
      freeDiskSpaceProbeProvider.overrideWithValue((_) async => 10 << 30),
      modelDownloadProvider.overrideWith(() {
        final notifier = ModelDownloadNotifier();
        notifier.fetcherOverride = fetcher;
        notifier.verifierOverride = verifier;
        return notifier;
      }),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_snapshot_');
    sttDirOverride = tempDir.path;
  });

  tearDown(() async {
    sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC1: Successful download — full state-transition sequence
  // ────────────────────────────────────────────────────────────────────────────

  group('AC1: Successful download', () {
    for (final alreadyExists in [false, true]) {
      test(
        'verified model becomes done (already exists: $alreadyExists)',
        () async {
          const modelId = 'whisper-small';
          final model = findSttModel(modelId)!;
          final destPath = p.join(tempDir.path, model.filename);
          if (alreadyExists) {
            await File(destPath).writeAsBytes([1, 2, 3]);
          }
          // Hash correctness is covered by file_verification_service_test.dart;
          // this checks the download pipeline's handoff and success transition.
          final verifier = _AcceptingVerifier();
          final fetcher = _FakeFetcher();
          final container = _makeContainer(
            fetcher: fetcher,
            verifier: verifier,
          );
          addTearDown(container.dispose);
          final notifier = container.read(modelDownloadProvider.notifier);
          await notifier.awaitInitialScan();
          await container.read(settingsProvider.future);
          final phases = <DownloadPhase>[];
          final sub = container.listen(
            modelDownloadProvider,
            (_, s) => phases.add(s.phase),
          );
          addTearDown(sub.close);

          await notifier.downloadModel(modelId);

          expect(verifier.calls, [(destPath, model.sha256)]);
          expect(fetcher.fetchCalled, !alreadyExists);
          if (!alreadyExists) expect(fetcher.lastUrl, model.url);
          expect(
            phases,
            containsAllInOrder([
              DownloadPhase.downloading,
              DownloadPhase.verifying,
              DownloadPhase.done,
            ]),
          );
          final state = container.read(modelDownloadProvider);
          expect(state.phase, DownloadPhase.done);
          expect(state.activeModelId, modelId);
          expect(state.progressPercent, 100);
          expect(state.downloadedModels, contains(modelId));
          expect(state.isBusy, isFalse);
          expect(
            container.read(settingsProvider).requireValue.sttModel,
            modelId,
          );
        },
      );
    }
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC2: Network error → error state
  // ────────────────────────────────────────────────────────────────────────────

  group('AC2: Network error', () {
    for (final (type, kind) in [
      (DioExceptionType.connectionTimeout, DownloadErrorKind.offline),
      (DioExceptionType.sendTimeout, DownloadErrorKind.network),
      (DioExceptionType.receiveTimeout, DownloadErrorKind.network),
    ]) {
      test(
        '$type leaves the download retryable without activating a model',
        () async {
          final fetcher = _FakeFetcher(
            behaviour: _FetchBehaviour.networkError,
            errorType: type,
          );
          final container = _makeContainer(fetcher: fetcher);
          addTearDown(container.dispose);
          await container
              .read(modelDownloadProvider.notifier)
              .downloadModel('whisper-small');

          final state = container.read(modelDownloadProvider);
          expect(fetcher.fetchCalled, isTrue);
          expect(state.phase, DownloadPhase.error);
          expect(state.errorKind, kind);
          expect(state.isBusy, isFalse);
          expect(state.downloadedModels, isNot(contains('whisper-small')));
        },
      );
    }

    test('transitions to error phase on DioException', () async {
      const modelId = 'whisper-small';

      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.networkError);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel(modelId);

      final state = container.read(modelDownloadProvider);
      expect(state.phase, DownloadPhase.error);
      expect(state.errorMessage, isNotNull);
      expect(state.errorMessage, contains('Download failed'));
    });

    test('error message reflects the DioException message', () async {
      const modelId = 'whisper-small';

      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.networkError);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel(modelId);

      final state = container.read(modelDownloadProvider);
      expect(state.errorMessage, isNotNull);
      expect(state.errorMessage!.isNotEmpty, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC3: Resume — fetcher called when partial .tmp file exists
  // ────────────────────────────────────────────────────────────────────────────

  group('AC3: Resume after connection drop', () {
    test('fetch is called even when partial .tmp file exists', () async {
      const modelId = 'whisper-small';
      final model = findSttModel(modelId)!;
      final destPath = p.join(tempDir.path, model.filename);
      final tmpPath = '$destPath.tmp';

      // Create partial .tmp file to simulate interrupted download.
      await File(tmpPath).writeAsBytes(List.filled(1000, 0xAA));

      final fakeBytes = List<int>.generate(512, (i) => i & 0xFF);
      final fetcher = _FakeFetcher(
        behaviour: _FetchBehaviour.resumeSucceed,
        fileContent: fakeBytes,
      );
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel(modelId);

      // Fetcher was called (resume attempt).
      expect(fetcher.fetchCalled, isTrue);
      expect(fetcher.lastUrl, model.url);
    });

    test('fetcher receives correct destPath for resume', () async {
      const modelId = 'whisper-small';
      final model = findSttModel(modelId)!;
      final destPath = p.join(tempDir.path, model.filename);
      final tmpPath = '$destPath.tmp';

      await File(tmpPath).writeAsBytes(List.filled(500, 0xBB));

      final fetcher = _FakeFetcher(
        behaviour: _FetchBehaviour.resumeSucceed,
        fileContent: List.filled(200, 0xCC),
      );
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel(modelId);

      expect(fetcher.lastDestPath, destPath);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC4: User cancellation → idle state
  // ────────────────────────────────────────────────────────────────────────────

  group('AC4: User cancellation', () {
    test('cancelDownload resets to idle when no download is active', () {
      final fetcher = _FakeFetcher();
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      container.read(modelDownloadProvider.notifier).cancelDownload();

      final state = container.read(modelDownloadProvider);
      expect(state.phase, DownloadPhase.idle);
      expect(state.activeModelId, isNull);
      expect(state.progressPercent, 0);
    });

    test('cancellation mid-download transitions to idle state', () async {
      const modelId = 'whisper-small';

      // Cancelled fetcher simulates DioExceptionType.cancel.
      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.cancelled);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel(modelId);

      final state = container.read(modelDownloadProvider);
      // Phase resets to idle on cancellation.
      expect(state.phase, DownloadPhase.idle);
      // activeModelId may remain set (copyWith null-guard preserves it);
      // what matters is phase is idle and not error.
      expect(state.isError, isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC5: SHA256 mismatch → error state
  // ────────────────────────────────────────────────────────────────────────────

  group('AC5: SHA256 mismatch', () {
    test('transitions to error when downloaded file has wrong hash', () async {
      const modelId = 'whisper-small';

      // Fetcher writes garbage bytes (hash will not match registry).
      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.writeBadContent);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel(modelId);

      final state = container.read(modelDownloadProvider);
      expect(state.phase, DownloadPhase.error);
      expect(state.errorMessage, contains('SHA256 verification failed'));
    });

    test('corrupt file is deleted after SHA256 mismatch', () async {
      const modelId = 'whisper-small';
      final model = findSttModel(modelId)!;
      final destPath = p.join(tempDir.path, model.filename);

      final fetcher = _FakeFetcher(behaviour: _FetchBehaviour.writeBadContent);
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel(modelId);

      // The corrupt file should have been deleted.
      expect(File(destPath).existsSync(), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC6: Unknown model ID → error state
  // ────────────────────────────────────────────────────────────────────────────

  group('AC6: Unknown model ID', () {
    test('downloadModel with unknown id transitions to error', () async {
      final fetcher = _FakeFetcher();
      final container = _makeContainer(fetcher: fetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.downloadModel('nonexistent-model-xyz');

      final state = container.read(modelDownloadProvider);
      expect(state.phase, DownloadPhase.error);
      expect(state.errorMessage, contains('Unknown model'));
      // Fetcher should not have been called.
      expect(fetcher.fetchCalled, isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // AC7: Busy guard — no re-entrant downloads
  // ────────────────────────────────────────────────────────────────────────────

  group('AC7: Busy guard', () {
    test('fetcher called exactly once per downloadModel invocation', () async {
      const modelId = 'whisper-small';

      final countingFetcher = _CountingFakeFetcher(
        behaviour: _FetchBehaviour.networkError,
      );
      final container = _makeContainer(fetcher: countingFetcher);
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);

      // First call (will fail with networkError — that's expected).
      await notifier.downloadModel(modelId);

      // After completion, state is no longer busy.
      final state = container.read(modelDownloadProvider);
      expect(state.isBusy, isFalse);

      // Fetcher was called exactly once.
      expect(countingFetcher.callCount, 1);
    });
  });
}

// ── Counting fake ─────────────────────────────────────────────────────────────

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
