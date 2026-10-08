/// Deleting a model on Windows failed with a sharing violation (errno 32,
/// Sentry 133414579) when the STT engine was still loading that very file.
/// [ModelDownloadNotifier.deleteModel] must release the engine first, ride
/// out a short-lived lock, and surface a persistent one to the user instead
/// of throwing.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;

const _inUse = FileSystemException(
  'Cannot delete file',
  'ggml-small-q5_1.bin',
  OSError('El proceso no tiene acceso al archivo', 32),
);

void main() {
  late Directory tempDir;
  final model = sttModels.first;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_delete_model_');
    sttDirOverride = tempDir.path;
    File(p.join(tempDir.path, model.filename)).writeAsStringSync('weights');
  });

  tearDown(() async {
    sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  Future<void> noEngine(String _) async {}

  Future<(ProviderContainer, ModelDownloadNotifier)> makeNotifier({
    Future<void> Function(File file)? deleteFile,
  }) async {
    final notifier = ModelDownloadNotifier()
      ..deleteFileOverride = deleteFile
      ..retryWaitOverride = (_) async {};
    final container = ProviderContainer(
      overrides: [modelDownloadProvider.overrideWith(() => notifier)],
    );
    addTearDown(container.dispose);
    container.read(modelDownloadProvider);
    await notifier.refresh();
    expect(container.read(modelDownloadProvider).downloadedModels, {model.id});
    return (container, notifier);
  }

  test('releases the engine before touching the file', () async {
    bool? fileExistedAtRelease;
    String? releasedId;
    final (container, notifier) = await makeNotifier();

    await notifier.deleteModel(
      model.id,
      releaseEngine: (id) async {
        releasedId = id;
        fileExistedAtRelease = File(
          p.join(tempDir.path, model.filename),
        ).existsSync();
      },
    );

    expect(releasedId, model.id);
    expect(fileExistedAtRelease, isTrue);
    expect(File(p.join(tempDir.path, model.filename)).existsSync(), isFalse);
    expect(container.read(modelDownloadProvider).downloadedModels, isEmpty);
  });

  test('a short-lived lock is retried until the delete succeeds', () async {
    var attempts = 0;
    final (container, notifier) = await makeNotifier(
      deleteFile: (file) async {
        if (attempts++ == 0) throw _inUse;
        await file.delete();
      },
    );

    await notifier.deleteModel(model.id, releaseEngine: noEngine);

    expect(attempts, 2);
    expect(container.read(modelDownloadProvider).downloadedModels, isEmpty);
    expect(container.read(modelDownloadProvider).isError, isFalse);
  });

  test('a persistent lock keeps the model and tells the user', () async {
    final (container, notifier) = await makeNotifier(
      deleteFile: (_) async => throw _inUse,
    );

    await notifier.deleteModel(model.id, releaseEngine: noEngine);

    final state = container.read(modelDownloadProvider);
    expect(state.downloadedModels, {model.id});
    expect(state.isError, isTrue);
    expect(state.errorMessage, modelDeleteInUseError);
  });
}
