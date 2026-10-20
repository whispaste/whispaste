/// Riverpod wiring for the audio import queue: the real decode, transcribe and
/// save steps, and the retention rule for the imported audio.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/settings_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/data/database.dart';
import '../../../core/recording/recording_state.dart';
import '../../../features/history/data/history_title.dart';
import '../../path_service.dart';
import '../../audio_service.dart';
import '../../text_transforms.dart';
import '../../transcription/transcriber.dart';
import 'audio_file_decoder.dart';
import '../user_audio_dirs.dart';
import 'audio_import_queue.dart';

/// Scratch directory for in-flight import jobs, inside the app container.
String importWorkDir() => p.join(importsRootDir(), 'work');

/// True while a dictation holds the transcriber: recording, transcribing or
/// refining. Imports yield to it so the hotkey path never queues behind a
/// long file.
bool dictationBusy(RecordingState state) =>
    state.isRecording || state.isTranscribing || state.isRefining;

/// Completes at once if no dictation is running, otherwise once it ends.
Future<void> waitForDictationIdle(ProviderContainer container) async {
  if (!dictationBusy(container.read(recordingProvider))) return;
  final idle = Completer<void>();
  final sub = container.listen<RecordingState>(recordingProvider, (_, next) {
    if (!dictationBusy(next) && !idle.isCompleted) idle.complete();
  });
  try {
    await idle.future;
  } finally {
    sub.close();
  }
}

final _log = AppLogger('AudioImport');

/// Owns the single import queue of the app and mirrors its jobs into state.
class AudioImportQueueNotifier extends Notifier<List<ImportJob>> {
  late final AudioImportQueue _queue;

  @override
  List<ImportJob> build() {
    _queue = AudioImportQueue(
      workDir: importWorkDir(),
      keepAudio: () =>
          ref.read(settingsProvider).value?.privacy.retainRecentAudio ?? false,
      decode: ({required inputPath, required outputWavPath}) =>
          decodeAudioFileToSttWav(
            inputPath: inputPath,
            outputWavPath: outputWavPath,
          ),
      transcribe: _transcribe,
      save: _save,
      onChanged: (jobs) => state = jobs,
      onCleanupError: (error) => _log.warning(
        'Could not remove import scratch files: ${describeImportError(error)}',
      ),
    );
    // The queue lives in memory, so scratch files from an earlier run have no
    // job left to belong to.
    unawaited(_queue.clearScratch());
    return const [];
  }

  /// Adds the files the user picked. The result says why each refused path
  /// was refused and which jobs were created; the accepted files run in the
  /// background.
  Future<ImportEnqueueResult> addFiles(List<String> paths) =>
      _queue.enqueue(paths);

  void cancel(String id) => _queue.cancel(id);

  Future<void> retry(String id) => _queue.retry(id);

  Future<String> _transcribe(List<int> wavBytes) async {
    await waitForDictationIdle(ref.container);
    final transcriber = ref.read(transcriberProvider);
    await transcriber.prepare();
    try {
      final text = await transcriber.transcribe(wavBytes);
      return collapseTranscriptWhitespace(text);
    } finally {
      transcriber.release();
    }
  }

  /// Creates the history entry for a finished import. Audio is kept only when
  /// [audioPath] is given (audio retention is on); then it moves into the
  /// retained-audio directory and joins the same rotating cap as dictations.
  Future<String> _save({
    required String fileName,
    required String transcript,
    required double durationSec,
    required String? audioPath,
  }) async {
    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    final id = 'import-${now.microsecondsSinceEpoch}';

    String? retained;
    if (audioPath != null) {
      final dir = Directory(retainedAudioDir());
      await userAudioDirs.ensure(dir.path);
      retained = p.join(dir.path, '$id.wav');
      await File(audioPath).copy(retained);
    }

    await db.insertHistoryEntry(
      HistoryEntriesCompanion(
        id: Value(id),
        content: Value(transcript),
        title: Value(
          deriveHistoryTitle(transcript).isEmpty
              ? p.basenameWithoutExtension(fileName)
              : deriveHistoryTitle(transcript),
        ),
        timestamp: Value(now),
        durationSec: Value(durationSec),
        source: const Value('import'),
        isLocal: const Value(true),
      ),
    );

    if (retained != null) {
      final size = await File(retained).length();
      await db.insertAudioAttachment(
        entryId: id,
        filePath: retained,
        sizeBytes: size,
      );
      final evicted = await db.enforceAudioAttachmentCap();
      final audio = ref.read(audioServiceProvider.notifier);
      for (final path in evicted) {
        await audio.cleanupFile(path);
      }
    }
    return id;
  }
}

final audioImportQueueProvider =
    NotifierProvider<AudioImportQueueNotifier, List<ImportJob>>(
      AudioImportQueueNotifier.new,
    );

/// How long a tray request for the file picker stays valid. A locked history
/// keeps the request until it is unlocked, but not beyond this.
const audioImportPickRequestTtl = Duration(seconds: 60);

/// Wall clock for the request lifetime, a seam so tests can pin "now".
final audioImportClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Asks the history page to open the file picker, e.g. from the tray's
/// "Transcribe file…" entry. The state is the time of the request, or null
/// when none is pending. The request clears itself when its lifetime ends,
/// so a waiting gate notices the expiry without a rebuild of its own.
class AudioImportPickRequestNotifier extends Notifier<DateTime?> {
  // Two time sources on purpose. The Timer only ends the state, so a waiting
  // gate sees the expiry without a rebuild. Validity is judged against the
  // clock instead, because a Timer can fire late (e.g. after sleep) and must
  // not decide alone; the clock is injectable, so tests can pin "now".
  Timer? _expiry;

  @override
  DateTime? build() {
    ref.onDispose(() => _expiry?.cancel());
    return null;
  }

  void request() {
    _expiry?.cancel();
    state = ref.read(audioImportClockProvider)();
    _expiry = Timer(audioImportPickRequestTtl, () => state = null);
  }

  /// True once per request while it is still valid. Clears the request
  /// either way, so an expired one is dropped on the next look.
  bool takeRequest() {
    final requestedAt = state;
    _expiry?.cancel();
    _expiry = null;
    state = null;
    return requestedAt != null && _isValid(requestedAt);
  }

  bool _isValid(DateTime requestedAt) =>
      ref.read(audioImportClockProvider)().difference(requestedAt) <
      audioImportPickRequestTtl;
}

final audioImportPickRequestProvider =
    NotifierProvider<AudioImportPickRequestNotifier, DateTime?>(
      AudioImportPickRequestNotifier.new,
    );

/// True while a tray request is pending. It turns false when the request
/// expires, through the notifier's own timer.
final audioImportRequestPendingProvider = Provider<bool>(
  (ref) => ref.watch(audioImportPickRequestProvider) != null,
);

/// True while the system file dialog is open. Kept in the provider rather
/// than in the panel, so a remounted panel sees it too.
class AudioImportPickerOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// False when a dialog is already open.
  bool tryOpen() {
    if (state) return false;
    state = true;
    return true;
  }

  void close() => state = false;
}

final audioImportPickerOpenProvider =
    NotifierProvider<AudioImportPickerOpenNotifier, bool>(
      AudioImportPickerOpenNotifier.new,
    );
