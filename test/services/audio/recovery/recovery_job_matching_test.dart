/// Recovery only trusts the import jobs it enqueued itself. A finished job
/// with the same file name from another import must not count as recovered.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';

/// Stands in for the real queue: [ownStatus] is the status of the job that
/// the enqueue call creates, or null when no job appears in the state.
class _FakeQueue extends AudioImportQueueNotifier {
  _FakeQueue({required this.foreign, required this.ownStatus});

  final List<ImportJob> foreign;
  final ImportStatus? ownStatus;

  @override
  List<ImportJob> build() => foreign;

  @override
  Future<ImportEnqueueResult> addFiles(
    List<String> paths, {
    String? sliceManifestPath,
  }) async {
    final status = ownStatus;
    if (status != null) {
      state = [
        ...state,
        ImportJob(id: 'mine', fileName: 'x.wav', status: status),
      ];
    }
    return const ImportEnqueueResult(rejections: [], jobIds: ['mine']);
  }
}

Future<bool> _recover(ProviderContainer container) async =>
    (await container.read(recordingRecoveryProvider).transcribe('/rec/x.wav'))
        .succeeded;

void main() {
  const finishedForeign = ImportJob(
    id: 'other',
    fileName: 'x.wav',
    status: ImportStatus.done,
  );

  test(
    'a finished job with the same name does not count as recovered',
    () async {
      final container = ProviderContainer(
        overrides: [
          audioImportQueueProvider.overrideWith(
            () => _FakeQueue(foreign: [finishedForeign], ownStatus: null),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await _recover(container), isFalse);
    },
  );

  test('its own finished job counts as recovered', () async {
    final container = ProviderContainer(
      overrides: [
        audioImportQueueProvider.overrideWith(
          () => _FakeQueue(foreign: const [], ownStatus: ImportStatus.done),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await _recover(container), isTrue);
  });
}
