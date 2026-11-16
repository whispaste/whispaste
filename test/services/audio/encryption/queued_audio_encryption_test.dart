/// Parked and imported audio is encrypted at rest as well (#1021): the
/// queues seal their WAV and read it back through the vault.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/audio/encryption/recording_cipher.dart';
import 'package:whispaste/services/audio/encryption/recording_vault.dart';
import 'package:whispaste/services/audio/import/audio_file_decoder.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';

final _dataKey = List<int>.generate(32, (i) => i);

Uint8List _toneWav() {
  final pcm = Int16List(4000);
  for (var i = 0; i < pcm.length; i++) {
    pcm[i] = i % 36 < 18 ? 3000 : -3000;
  }
  return encodePcm16MonoWav(pcm);
}

bool _sealed(String path) => isSealedRecording(File(path).readAsBytesSync());

void main() {
  late Directory tmp;
  late RecordingVault vault;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp1021-queues-');
    vault = RecordingVault(dataKey: () async => _dataKey);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('parked dictations', () {
    const id = '1781775015020-0020';
    final now = DateTime(2026, 11, 10, 9);

    PendingAudioQueue queue() => PendingAudioQueue(
      directory: () => p.join(tmp.path, 'pending-audio'),
      save: (_) async => throw StateError('not used'),
      entryExists: (_) async => false,
      clock: () => now,
      sealAudio: (path) => unawaited(vault.protect(path)),
      readAudio: vault.read,
    );

    test('a parked WAV is sealed and a retry gets the plain audio and its '
        'finished slices', () async {
      final plain = _toneWav();
      final capture = File(p.join(tmp.path, 'capture.wav'))
        ..writeAsBytesSync(plain);
      final q = queue();

      await q.parkForRetry(
        capture.path,
        entryId: id,
        capturedAt: now,
        audioDuration: const Duration(seconds: 1),
        errorCode: 'cloud_server_error',
        expiresAt: now.add(const Duration(hours: 24)),
        completedParts: const ['eins'],
      );
      final parked = p.join(tmp.path, 'pending-audio', '$id.wav');
      // Writes run in order: this waits for the seal the park started.
      expect(await vault.protect(parked), ProtectOutcome.alreadySealed);
      expect(_sealed(parked), isTrue);
      expect(await recordingPlainLength(parked), plain.length);

      List<int>? audio;
      List<String>? completed;
      await q.retry(
        id,
        transcribe: (wav, parts) async {
          audio = wav;
          completed = parts;
          return '';
        },
        buildInput: (text, _) => throw StateError('save not reached'),
        retainAudio: false,
      );
      expect(audio, plain);
      expect(completed, ['eins']);
    });
  });

  group('imported audio', () {
    late String workDir;
    late int decodes;

    setUp(() {
      workDir = p.join(tmp.path, 'work');
      decodes = 0;
    });

    AudioImportQueue queue({
      required ImportTranscribeStep transcribe,
      List<String?>? savedAudio,
    }) => AudioImportQueue(
      workDir: workDir,
      keepAudio: () => true,
      decode: ({required inputPath, required outputWavPath}) {
        decodes++;
        return decodeAudioFileToSttWav(
          inputPath: inputPath,
          outputWavPath: outputWavPath,
        );
      },
      transcribe: transcribe,
      save:
          ({
            required fileName,
            required transcript,
            required durationSec,
            required audioPath,
          }) async {
            if (audioPath != null) {
              expect(_sealed(audioPath), isTrue);
            }
            savedAudio?.add(audioPath);
            return 'entry-1';
          },
      sealAudio: vault.protect,
      readAudio: vault.read,
    );

    test('the decoded WAV is sealed before transcription, the plain copy is '
        'removed, and a retry reuses the sealed WAV', () async {
      final source = File(p.join(tmp.path, 'memo.wav'))
        ..writeAsBytesSync(_toneWav());
      final transcribed = <int>[];
      var calls = 0;
      final saved = <String?>[];
      final q = queue(
        savedAudio: saved,
        transcribe: (wav, {onProgress, sliceManifestPath}) async {
          transcribed.add(wav.length);
          if (++calls == 1) throw Exception('engine not ready');
          return 'hallo';
        },
      );

      await q.enqueue([source.path]);
      final job = q.jobs.single;
      expect(job.status, ImportStatus.failed);
      final jobDir = Directory(p.join(workDir, job.id));
      final kept = jobDir.listSync().map((e) => p.basename(e.path)).toList();
      expect(kept, ['audio.wav']);
      final wav = p.join(jobDir.path, 'audio.wav');
      expect(_sealed(wav), isTrue);
      final plainLength = await recordingPlainLength(wav);

      await q.retry(job.id);

      expect(q.jobs.single.status, ImportStatus.done);
      expect(decodes, 1);
      expect(transcribed, [plainLength, plainLength]);
      expect(saved, hasLength(1));
    });
  });
}
