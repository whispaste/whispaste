/// A failed import transcription keeps the error code of the engine, so the
/// startup recovery can tell a repeatable failure from a permanent one.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/transcription/transcriber_exception.dart';

Uint8List _toneWav() {
  final pcm = Int16List(4000);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = (3000 * (i % 36 < 18 ? 1 : -1)).toInt();
  }
  return encodePcm16MonoWav(pcm);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp-import-code-');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  Future<AudioImportQueue> failWith(Object error) async {
    final source = File('${tmp.path}/a.wav')..writeAsBytesSync(_toneWav());
    final queue = AudioImportQueue(
      workDir: '${tmp.path}/work',
      keepAudio: () => false,
      decode: ({required inputPath, required outputWavPath}) =>
          decodeAudioFileToSttWav(
            inputPath: inputPath,
            outputWavPath: outputWavPath,
          ),
      transcribe: (_, {onProgress, sliceManifestPath}) async => throw error,
      save:
          ({
            required fileName,
            required transcript,
            required durationSec,
            required audioPath,
          }) async => 'entry',
    );
    await queue.enqueue([source.path]);
    return queue;
  }

  test('a failed job carries the code of a classified engine error', () async {
    final queue = await failWith(
      const TranscriberException(
        'key rejected',
        reason: TranscriberFailureReason.authError,
      ),
    );

    expect(queue.jobs.single.failure, ImportFailure.transcriptionFailed);
    expect(queue.jobs.single.transcriptionErrorCode, 'cloud_auth_error');
  });

  test('an unclassified error is recorded as a server failure', () async {
    final queue = await failWith(StateError('engine down'));

    expect(queue.jobs.single.transcriptionErrorCode, 'stt_server_failed');
  });
}
