/// Copy-step progress of an import is reported at most once per whole percent.
///
/// The copy reads in 64 KiB chunks. Reporting every chunk rebuilds the whole
/// import list (and the UI watching it) about 16 000 times for a 1 GB file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

const _chunkBytes = 64 * 1024;
const _chunkCount = 256;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('copy-progress-');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('copy progress is reported at most once per percent', () async {
    final source = File('${tmp.path}/long.wav')
      ..writeAsBytesSync(Uint8List(_chunkBytes * _chunkCount));
    final copyUpdates = <double>[];
    final queue = AudioImportQueue(
      workDir: '${tmp.path}/work',
      keepAudio: () => false,
      decode: ({required inputPath, required outputWavPath}) async {
        File(outputWavPath).writeAsBytesSync(encodePcm16MonoWav(Int16List(4)));
      },
      transcribe: (_, {onProgress, sliceManifestPath}) async => 'text',
      save:
          ({
            required fileName,
            required transcript,
            required durationSec,
            required audioPath,
          }) async => 'entry',
      openSource: (_) => Stream<List<int>>.fromIterable(
        List<List<int>>.generate(_chunkCount, (_) => Uint8List(_chunkBytes)),
      ),
      onChanged: (jobs) {
        final job = jobs.single;
        if (job.status == ImportStatus.copying && job.progress != null) {
          copyUpdates.add(job.progress!);
        }
      },
    );

    await queue.enqueue([source.path]);

    expect(queue.jobs.single.status, ImportStatus.done);
    // At most one update per whole percent (plus the initial 0 report).
    expect(copyUpdates.length, lessThanOrEqualTo(101));
    // Still shows progress: the last report is close to complete.
    expect(copyUpdates.last, greaterThanOrEqualTo(0.99));
    // Never moves backwards.
    for (var i = 1; i < copyUpdates.length; i++) {
      expect(copyUpdates[i], greaterThanOrEqualTo(copyUpdates[i - 1]));
    }
  });
}
