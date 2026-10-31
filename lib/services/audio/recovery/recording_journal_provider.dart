/// The app's single recording journal, shared by the recorder and startup
/// recovery. Kept out of `recording_journal.dart` so that library stays free of
/// Flutter imports (the kill test runs it in a plain Dart process).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../path_service.dart';
import 'recording_journal.dart';
import 'transcription_journal.dart';

final recordingJournalProvider = Provider<RecordingJournal>(
  (ref) => RecordingJournal(p.join(appDataDir(), 'recordings', 'journal')),
);

final transcriptionJournalProvider = Provider<TranscriptionJournal>(
  (ref) => TranscriptionJournal(ref.watch(recordingJournalProvider)),
);
