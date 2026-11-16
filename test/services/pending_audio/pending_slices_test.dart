import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';
import 'package:whispaste/services/recording_store.dart';
import 'package:whispaste/services/transcription/slice_manifest.dart';
import 'package:whispaste/services/transcription/transcriber_exception.dart';

void main() {
  late Directory tmp;
  late String pendingDir;
  late String captureDir;
  late DateTime now;

  const id = '1781775015020-0020';
  const wavName = '$id.wav';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_pending_slices_test_');
    pendingDir = p.join(tmp.path, 'pending-audio');
    captureDir = p.join(tmp.path, 'capture');
    Directory(captureDir).createSync();
    now = DateTime(2026, 10, 26, 9, 30);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  PendingAudioQueue queue() => PendingAudioQueue(
    directory: () => pendingDir,
    save: (input) async => throw StateError('not used'),
    entryExists: (_) async => false,
    clock: () => now,
  );

  String captureWav({int length = 64}) {
    final path = p.join(captureDir, wavName);
    File(path).writeAsBytesSync(List.filled(length, 1));
    return path;
  }

  Future<void> park(
    PendingAudioQueue q, {
    List<String> completedParts = const [],
    int length = 64,
  }) => q.parkForRetry(
    captureWav(length: length),
    entryId: id,
    capturedAt: now,
    audioDuration: const Duration(seconds: 7),
    errorCode: 'cloud_server_error',
    expiresAt: now.add(const Duration(hours: 24)),
    completedParts: completedParts,
  );

  TranscriberException failure(List<String> parts) => TranscriberException(
    'boom',
    reason: TranscriberFailureReason.serverError,
    completedParts: parts,
  );

  test(
    'a park with finished slices writes a manifest beside the audio',
    () async {
      final q = queue();
      await park(q, completedParts: const ['eins', '']);

      expect(File(p.join(pendingDir, '$id.slices')).existsSync(), isTrue);
      expect(File(p.join(pendingDir, '$id.wav')).existsSync(), isTrue);
    },
  );

  test('a retry passes the finished slices to the transcriber', () async {
    final q = queue();
    await park(q, completedParts: const ['eins']);

    List<String>? seen;
    await q.retry(
      id,
      transcribe: (wav, completed) async {
        seen = completed;
        return 'Gerettet';
      },
      buildInput: (text, _) => throw StateError('save not reached'),
      retainAudio: false,
    );
    expect(seen, ['eins']);
  });

  test(
    'a failing retry rewrites the manifest with the newly finished slices',
    () async {
      final q = queue();
      await park(q, completedParts: const ['eins']);

      await q.retry(
        id,
        transcribe: (wav, completed) async => throw failure(['eins', 'zwei']),
        buildInput: (text, _) => throw StateError('save not reached'),
        retainAudio: false,
      );

      List<String>? seen;
      await q.retry(
        id,
        transcribe: (wav, completed) async {
          seen = completed;
          return '';
        },
        buildInput: (text, _) => throw StateError('save not reached'),
        retainAudio: false,
      );
      expect(seen, ['eins', 'zwei']);
    },
  );

  test('a manifest for different audio is ignored', () async {
    final q = queue();
    await park(q, completedParts: const ['eins'], length: 64);
    // The audio on disk no longer matches the manifest's length.
    File(p.join(pendingDir, wavName)).writeAsBytesSync(List.filled(128, 2));

    List<String>? seen;
    await q.retry(
      id,
      transcribe: (wav, completed) async {
        seen = completed;
        return '';
      },
      buildInput: (text, _) => throw StateError('save not reached'),
      retainAudio: false,
    );
    expect(seen, isEmpty);
  });

  test('a discard removes the manifest with the audio', () async {
    final q = queue();
    await park(q, completedParts: const ['eins']);

    await q.discard(id);

    expect(File(p.join(pendingDir, '$id.slices')).existsSync(), isFalse);
    expect(File(p.join(pendingDir, wavName)).existsSync(), isFalse);
  });

  test('a park takes the manifest the upload wrote beside the WAV', () async {
    final q = queue();
    final wav = captureWav();
    await SliceManifest.beside(wav).write(64, const ['eins', 'zwei']);

    await q.parkForRetry(
      wav,
      entryId: id,
      capturedAt: now,
      audioDuration: const Duration(seconds: 7),
      errorCode: 'cloud_server_error',
      expiresAt: now.add(const Duration(hours: 24)),
    );

    expect(File(SliceManifest.beside(wav).path).existsSync(), isFalse);
    expect(await SliceManifest(p.join(pendingDir, '$id.slices')).read(64), [
      'eins',
      'zwei',
    ]);
    late List<String> seen;
    await q.retry(
      id,
      transcribe: (_, completed) async {
        seen = completed;
        return '';
      },
      buildInput: (text, _) => throw StateError('save not reached'),
      retainAudio: false,
    );
    expect(seen, ['eins', 'zwei']);
  });

  test('a checkpoint of a retry is read by the next retry', () async {
    final q = queue();
    await park(q);
    final writer = SliceCheckpointWriter(
      manifest: q.sliceManifestFor(id),
      wavLength: 64,
      persisted: 0,
    );

    await q.retry(
      id,
      transcribe: (wav, completed) async {
        await writer(const ['eins'], 3);
        throw const TranscriberException(
          'boom',
          reason: TranscriberFailureReason.serverError,
        );
      },
      buildInput: (text, _) => throw StateError('save not reached'),
      retainAudio: false,
    );

    List<String>? seen;
    await q.retry(
      id,
      transcribe: (wav, completed) async {
        seen = completed;
        return '';
      },
      buildInput: (text, _) => throw StateError('save not reached'),
      retainAudio: false,
    );
    expect(seen, ['eins']);
  });

  test('a purge after the park window removes the manifest', () async {
    final q = queue();
    await park(q, completedParts: const ['eins']);

    await q.purgeExpired(now: now.add(const Duration(days: 8)));

    expect(File(p.join(pendingDir, '$id.slices')).existsSync(), isFalse);
    expect(File(p.join(pendingDir, wavName)).existsSync(), isFalse);
  });

  test('a successful retry removes the manifest with the audio', () async {
    final q = PendingAudioQueue(
      directory: () => pendingDir,
      save: (input) async => const SavedRecording(
        entryId: id,
        processedTranscript: 'ende',
        trimmedCount: 0,
      ),
      entryExists: (_) async => false,
      clock: () => now,
    );
    await park(q, completedParts: const ['eins']);

    await q.retry(
      id,
      transcribe: (wav, completed) async => 'ende',
      buildInput: (text, audio) => RecordingInput(
        transcript: text,
        audioDuration: audio,
        modelId: 'm',
        isLocal: false,
        languageCode: 'de',
        applyTextReplacements: false,
        historyMaxEntries: 10,
        wordCount: 1,
        processingDurationSec: 0,
        entryId: id,
        createdAt: now,
      ),
      retainAudio: false,
    );

    expect(File(p.join(pendingDir, '$id.slices')).existsSync(), isFalse);
  });
}
