/// Crash-recovery journal for live recordings.
///
/// A recording writes one small JSON file here when it starts and removes it
/// when it stops cleanly. A file left behind therefore marks a recording that
/// was interrupted (crash, kill, power loss). With audio retention on, the
/// journal also names the WAV that [WavFileWriter] has been appending to all
/// along, so the audio up to the interruption can be recovered. With retention
/// off the journal holds no audio path and recovery can only report the state.
///
/// Corrupt or unreadable journal files are skipped and counted, so one bad file
/// never hides the others (see [RecordingJournalScan.skippedCorrupt]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Journal format version, written into every file.
const int kRecordingJournalVersion = 1;

/// True when [wavPath] is a regular `.wav` file directly inside [audioDir].
/// A journal file is untrusted input: anything else (other folders, `..`
/// escapes, symlinks, other extensions) must never be read, imported or
/// deleted on its behalf.
bool isContainedAudioPath(String? wavPath, String audioDir) {
  if (wavPath == null || wavPath.isEmpty) return false;
  if (p.extension(wavPath).toLowerCase() != '.wav') return false;
  if (FileSystemEntity.typeSync(wavPath, followLinks: false) !=
      FileSystemEntityType.file) {
    return false;
  }
  try {
    final parent = Directory(p.dirname(wavPath)).resolveSymbolicLinksSync();
    final root = Directory(audioDir).resolveSymbolicLinksSync();
    return p.canonicalize(parent) == p.canonicalize(root);
  } on FileSystemException {
    return false;
  }
}

/// One interrupted recording found at startup.
class InterruptedRecording {
  const InterruptedRecording({
    required this.id,
    required this.startedAt,
    required this.wavPath,
    required this.journalPath,
  });

  final String id;
  final DateTime startedAt;

  /// WAV written during the recording. Null when audio retention was off.
  final String? wavPath;

  /// The journal file that describes this recording.
  final String journalPath;
}

/// Result of [RecordingJournal.scan].
class RecordingJournalScan {
  const RecordingJournalScan({
    required this.recordings,
    required this.skippedCorrupt,
  });

  final List<InterruptedRecording> recordings;

  /// Journal files that could not be read or validated. They are left on disk
  /// and reported, not deleted.
  final int skippedCorrupt;

  static const empty = RecordingJournalScan(recordings: [], skippedCorrupt: 0);
}

class RecordingJournal {
  RecordingJournal(this.directory);

  /// Folder that holds one `<id>.json` file per live recording.
  final String directory;

  /// Records that a recording with [id] has started.
  Future<void> begin({
    required String id,
    required DateTime startedAt,
    required String? wavPath,
  }) async {
    final dir = Directory(directory);
    await dir.create(recursive: true);
    final target = File(_journalPath(id));
    final tmp = File('${target.path}.tmp');
    final body = jsonEncode({
      'version': kRecordingJournalVersion,
      'id': id,
      'startedAt': startedAt.toIso8601String(),
      'wavPath': wavPath,
    });
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(target.path);
  }

  /// Removes the journal for [id] after a clean stop. Missing files are fine.
  Future<void> end(String id) async {
    final file = File(_journalPath(id));
    if (await file.exists()) await file.delete();
  }

  /// Lists the journals left behind by recordings that did not stop cleanly.
  Future<RecordingJournalScan> scan() async {
    final dir = Directory(directory);
    if (!await dir.exists()) return RecordingJournalScan.empty;

    final recordings = <InterruptedRecording>[];
    var skipped = 0;
    await for (final entity in dir.list(followLinks: false)) {
      // Symlinks are never followed: a link is not a journal file.
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final parsed = await _parse(entity);
      if (parsed == null) {
        skipped++;
      } else {
        recordings.add(parsed);
      }
    }
    recordings.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return RecordingJournalScan(
      recordings: recordings,
      skippedCorrupt: skipped,
    );
  }

  String _journalPath(String id) => p.join(directory, '$id.json');

  Future<InterruptedRecording?> _parse(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final id = decoded['id'];
      final startedAt = decoded['startedAt'];
      final wavPath = decoded['wavPath'];
      if (id is! String || id.isEmpty) return null;
      if (startedAt is! String) return null;
      if (wavPath != null && wavPath is! String) return null;
      final parsedAt = DateTime.tryParse(startedAt);
      if (parsedAt == null) return null;
      return InterruptedRecording(
        id: id,
        startedAt: parsedAt,
        wavPath: wavPath as String?,
        journalPath: file.path,
      );
    } on Object {
      // Any read or decode failure marks this one file as corrupt; the rest of
      // the scan continues.
      return null;
    }
  }
}

/// Writes the journal entry of one live recording without holding up the
/// caller. [beginInBackground] returns at once, so the recorder can start the
/// microphone while the file is written. [endAndWait] waits for that pending
/// write first, so begin and end can never reorder.
class RecordingJournalWriter {
  RecordingJournalWriter({required this.journal, this.onError});

  final RecordingJournal journal;

  /// Receives write failures. A failed journal write must not stop a recording.
  final void Function(Object error)? onError;

  String? _id;
  Future<void>? _pending;

  void beginInBackground({
    required String id,
    required DateTime startedAt,
    required String? wavPath,
  }) {
    _id = id;
    _pending = journal
        .begin(id: id, startedAt: startedAt, wavPath: wavPath)
        .catchError((Object error) => onError?.call(error));
  }

  Future<void> endAndWait() async {
    final id = _id;
    final pending = _pending;
    _id = null;
    _pending = null;
    if (id == null) return;
    await pending;
    try {
      await journal.end(id);
    } on Object catch (error) {
      onError?.call(error);
    }
  }
}
