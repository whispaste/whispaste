import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';
import 'package:whispaste/services/recording/pipeline_step_runner.dart';
import 'package:whispaste/services/recording_store.dart';

// A save that outlives the pipeline's save timeout (DEV-144): the orchestrator
// parks the audio on StepTimeout, and the save then completes in the
// background. The next start must find the entry and keep the audio.
const _entryId = '1781775015000-0042';
final _capturedAt = DateTime(2026, 10, 18, 9, 30, 15);

RecordingInput _input() => RecordingInput(
  transcript: 'Ein Diktat mit langsamem Speichern',
  audioDuration: const Duration(seconds: 4),
  modelId: 'parakeet-tdt',
  isLocal: true,
  languageCode: 'de',
  applyTextReplacements: false,
  historyMaxEntries: 0,
  wordCount: 5,
  processingDurationSec: 1,
  entryId: _entryId,
  createdAt: _capturedAt,
);

void main() {
  late Directory tmp;
  late String pendingDir;
  late String retainedDir;
  late HistoryDatabase db;
  late DriftRecordingStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_pending_timeout_');
    pendingDir = p.join(tmp.path, 'pending-audio');
    retainedDir = p.join(tmp.path, 'retained');
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    store = DriftRecordingStore(db);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  PendingAudioQueue queue({
    required bool retainAudio,
    Future<void> Function(String, String)? retain,
  }) => PendingAudioQueue(
    directory: () => pendingDir,
    save: store.save,
    entryExists: (id) async => (await db.getEntry(id)) != null,
    retainAudio: retain,
    // Fixed clock: the fixture's capture time must stay inside the 7-day
    // expiry window, whatever the real date is.
    clock: () => _capturedAt,
  );

  /// Moves the WAV into the retained folder, as the app does for a live save.
  Future<void> keepForRetention(String entryId, String wavPath) async {
    Directory(retainedDir).createSync(recursive: true);
    File(wavPath).renameSync(p.join(retainedDir, p.basename(wavPath)));
  }

  test('a save that times out is parked, then completes; the next start keeps '
      'its WAV in retention instead of deleting it', () async {
    final wav = p.join(tmp.path, 'whispaste_timeout.wav')..isEmpty;
    File(wav).writeAsBytesSync(List.filled(64, 1));
    // The save waits on [gate], which the test opens only after the timeout has
    // fired. A zero timeout therefore always loses the race, with no wall-clock
    // dependency, and [saveDone] lets the test wait for the background save.
    final gate = Completer<void>();
    final saveDone = Completer<void>();
    const runner = PipelineStepRunner(
      timeout: Duration.zero,
      breadcrumbSink: _ignoreBreadcrumb,
    );

    final result = await runner.run<String?>('save_history', () async {
      await gate.future;
      final saved = await store.save(_input());
      saveDone.complete();
      return saved.processedTranscript;
    });
    expect(result, isA<StepTimeout<String?>>());
    await queue(retainAudio: true).park(wav, _input());
    expect(File(wav).existsSync(), isFalse);

    gate.complete();
    await saveDone.future;
    expect(await db.getEntry(_entryId), isNotNull);

    final parked = p.join(pendingDir, '$_entryId.wav');
    expect(File(parked).existsSync(), isTrue);
    await queue(
      retainAudio: true,
      retain: keepForRetention,
    ).recoverAll(retainAudio: true);

    expect(File(parked).existsSync(), isFalse);
    expect(
      File(p.join(retainedDir, '$_entryId.wav')).existsSync(),
      isTrue,
      reason: 'the WAV must survive the next start',
    );
  });

  test(
    'with retention off the WAV of a late save is deleted, as before',
    () async {
      final wav = p.join(tmp.path, 'whispaste_timeout_off.wav');
      File(wav).writeAsBytesSync(List.filled(64, 1));
      await queue(retainAudio: false).park(wav, _input());
      await store.save(_input());

      await queue(retainAudio: false).recoverAll(retainAudio: false);

      expect(File(p.join(pendingDir, '$_entryId.wav')).existsSync(), isFalse);
      expect(Directory(retainedDir).existsSync(), isFalse);
    },
  );

  test('with audio not kept, a parked dictation leaves no WAV behind and '
      'its save retry runs from the text alone', () async {
    final wav = p.join(tmp.path, 'whispaste_no_keep.wav');
    File(wav).writeAsBytesSync(List.filled(64, 1));

    await queue(retainAudio: false).park(wav, _input(), keepAudio: false);

    expect(File(wav).existsSync(), isFalse, reason: 'temp WAV must be gone');
    final wavs = Directory(pendingDir).existsSync()
        ? Directory(pendingDir).listSync().where((e) => e.path.endsWith('.wav'))
        : const <FileSystemEntity>[];
    expect(wavs, isEmpty, reason: 'no parked WAV may survive');

    final result = await queue(
      retainAudio: false,
    ).recoverAll(retainAudio: false);

    expect(result.saved, 1);
    expect(await db.getEntry(_entryId), isNotNull);
    expect(Directory(pendingDir).listSync(), isEmpty);
  });
}

void _ignoreBreadcrumb(Object? _) {}
