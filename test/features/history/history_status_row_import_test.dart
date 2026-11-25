/// The import target of the history status row counts only imports that
/// still need the user; a finished import must not leave "1 import" above
/// the search.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/widgets/history_status_row.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';

import '../../fixtures/test_helpers.dart';

class _FakeQueue extends AudioImportQueueNotifier {
  _FakeQueue(this.jobs);

  final List<ImportJob> jobs;

  @override
  List<ImportJob> build() => jobs;
}

Future<void> _pump(WidgetTester tester, List<ImportJob> jobs) async {
  await tester.pumpWidget(
    makeTestable(
      const HistoryStatusRow(),
      overrides: [
        audioImportQueueProvider.overrideWith(() => _FakeQueue(jobs)),
        interruptedRecordingsProvider.overrideWith(
          (ref) async =>
              const RecordingJournalScan(recordings: [], skippedCorrupt: 0),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

const _summary = ValueKey('history-import-summary');

void main() {
  testWidgets('finished and cancelled imports leave no status target', (
    tester,
  ) async {
    await _pump(tester, const [
      ImportJob(id: 'a', fileName: 'a.wav', status: ImportStatus.done),
      ImportJob(id: 'b', fileName: 'b.wav', status: ImportStatus.cancelled),
    ]);
    expect(find.byKey(_summary), findsNothing);
  });

  testWidgets('waiting, running and failed imports keep it', (tester) async {
    for (final status in [
      ImportStatus.queued,
      ImportStatus.transcribing,
      ImportStatus.failed,
    ]) {
      await _pump(tester, [
        const ImportJob(id: 'a', fileName: 'a.wav', status: ImportStatus.done),
        ImportJob(id: 'b', fileName: 'b.wav', status: status),
      ]);
      expect(find.byKey(_summary), findsOneWidget, reason: '$status');
    }
  });
}
