/// Regression for the Windows report (app-redesign run10): a model file that
/// is too small is deleted on the corruption path while the silent
/// re-download starts. The download then sees the file still present and
/// verifies it, and the file vanishes under it. A failing verification must
/// not turn that into an error: the model is fetched again.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/file_verification_service.dart';
import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;

/// Fetcher that writes the model file at once, as a completed download does.
class _WritingFetcher extends HttpModelFetcher {
  bool fetchCalled = false;

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    fetchCalled = true;
    await File(destPath).writeAsBytes(const [1, 2, 3]);
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

/// First check of an existing file: the file disappears while it is being
/// verified (the pending delete from the corruption path wins) and the check
/// reports a mismatch. Later checks accept the freshly fetched file.
class _RacingVerifier extends FileVerificationService {
  _RacingVerifier(this.racedPath);

  final String racedPath;
  int calls = 0;

  @override
  Future<VerificationResult> verifyStamped(
    File file,
    String expectedHash,
  ) async {
    calls++;
    if (calls == 1) {
      await File(racedPath).delete();
      return const VerificationMismatch(
        expectedHash: 'expected',
        actualHash: 'actual',
      );
    }
    return const VerificationOk();
  }
}

void main() {
  late Directory tempDir;
  final model = sttModels.first;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_existing_race_');
    sttDirOverride = tempDir.path;
  });

  tearDown(() async {
    sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  test(
    'a model file deleted during the existing-file check is fetched again',
    () async {
      final destPath = p.join(tempDir.path, model.filename);
      File(destPath).writeAsStringSync('truncated');

      final fetcher = _WritingFetcher();
      final verifier = _RacingVerifier(destPath);
      final container = ProviderContainer(
        overrides: [
          modelDownloadProvider.overrideWith(() {
            final notifier = ModelDownloadNotifier()
              ..fetcherOverride = fetcher
              ..verifierOverride = verifier;
            return notifier;
          }),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(modelDownloadProvider.notifier);
      await notifier.awaitInitialScan();
      await notifier.downloadModel(model.id);

      final state = container.read(modelDownloadProvider);
      expect(
        state.phase,
        isNot(DownloadPhase.error),
        reason: 'error: ${state.errorMessage}',
      );
      expect(fetcher.fetchCalled, isTrue);
      expect(verifier.calls, 2);
    },
  );
}
