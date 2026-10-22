/// Briefing B3, criterion 3: with "do not keep audio" set, no decoded temp
/// file and no recovery file survives the processing, a cancel, or a restart.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';

Uint8List _toneWav() => encodePcm16MonoWav(Int16List(4000));

void main() {
  late Directory tmp;
  late String workDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp-b3-retention-');
    workDir = '${tmp.path}/work';
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  File writeSource(String name) =>
      File('${tmp.path}/$name')..writeAsBytesSync(_toneWav());

  List<FileSystemEntity> leftovers() => Directory(workDir).existsSync()
      ? Directory(workDir).listSync(recursive: true)
      : <FileSystemEntity>[];

  test(
    'with audio retention off, a job cancelled mid-decode leaves no scratch',
    () async {
      final source = writeSource('cancel.wav');
      late AudioImportQueue queue;
      queue = AudioImportQueue(
        workDir: workDir,
        keepAudio: () => false,
        decode: ({required inputPath, required outputWavPath}) async {
          // The job id is the name of the job folder that holds the WAV.
          final id = p.basename(p.dirname(outputWavPath));
          await File(outputWavPath).writeAsBytes(_toneWav());
          queue.cancel(id);
        },
        transcribe: (_, {onProgress}) async => 'hallo',
        save:
            ({
              required fileName,
              required transcript,
              required durationSec,
              required audioPath,
            }) async => 'entry',
      );

      await queue.enqueue([source.path]);

      expect(queue.jobs.single.status, ImportStatus.cancelled);
      expect(leftovers(), isEmpty);
    },
  );

  test(
    'a restart removes scratch left by an interrupted run, retention off',
    () async {
      // What a killed process leaves behind: a job folder with the source
      // copy, a half-written WAV and a raw decoder output.
      final job = Directory('$workDir/imp-crashed')
        ..createSync(recursive: true);
      File('${job.path}/source.wav').writeAsBytesSync(_toneWav());
      File('${job.path}/audio.wav').writeAsBytesSync(Uint8List(100));
      File('${job.path}/audio.wav.raw').writeAsBytesSync(Uint8List(100));

      final queue = AudioImportQueue(
        workDir: workDir,
        keepAudio: () => false,
        decode: ({required inputPath, required outputWavPath}) async {},
        transcribe: (_, {onProgress}) async => 'hallo',
        save:
            ({
              required fileName,
              required transcript,
              required durationSec,
              required audioPath,
            }) async => 'entry',
      );

      await queue.clearScratch();

      expect(leftovers(), isEmpty);
    },
  );
}
