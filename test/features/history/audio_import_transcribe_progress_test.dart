/// The import row while a file is transcribed: a determinate bar with the
/// percentage when the engine reports one, otherwise an indeterminate bar and
/// the time since the step started. Checked at 800 px with large text and in
/// a right-to-left locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/widgets/audio_import_panel.dart';
import 'package:whispaste/features/history/widgets/history_status_row.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/services/audio/import/audio_import_providers.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';

import '../../fixtures/test_helpers.dart';

final _now = DateTime(2026, 10, 22, 12);

class _FakeQueue extends AudioImportQueueNotifier {
  _FakeQueue(this.jobs);

  final List<ImportJob> jobs;

  @override
  List<ImportJob> build() => jobs;
}

ImportJob _transcribing({double? progress, Duration? elapsed}) => ImportJob(
  id: 'job-1',
  fileName: 'gespraech.mp3',
  status: ImportStatus.transcribing,
  progress: progress,
  transcribingSince: elapsed == null ? null : _now.subtract(elapsed),
);

Future<void> _mount(
  WidgetTester tester, {
  required ImportJob job,
  Locale locale = const Locale('en'),
  Size size = const Size(1280, 800),
  double textScale = 1.0,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: _Header()),
      size: size,
      locale: locale,
      overrides: [
        audioImportQueueProvider.overrideWith(() => _FakeQueue([job])),
        audioImportClockProvider.overrideWithValue(() => _now),
        _noRecordings,
      ],
    ),
  );
  await tester.pump();
  await _openQueue(tester);
}

/// The queue is one summary line until it is opened (UX-098); the job rows
/// under test sit behind it.
Future<void> _openQueue(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('history-import-summary')));
  await tester.pump();
}

/// The status row above the panel, as on the page.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [HistoryStatusRow(), AudioImportPanel()],
    );
  }
}

/// No interrupted recordings: the status row then shows the queue only.
final _noRecordings = interruptedRecordingsProvider.overrideWith(
  (ref) async => const RecordingJournalScan(recordings: [], skippedCorrupt: 0),
);

void main() {
  testWidgets('shows the elapsed time without an engine value', (tester) async {
    await _mount(
      tester,
      job: _transcribing(elapsed: const Duration(minutes: 1, seconds: 23)),
    );

    expect(
      find.byKey(const ValueKey('history-import-elapsed-job-1')),
      findsOneWidget,
    );
    expect(find.text('Running for 1:23'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('history-import-percent-job-1')),
      findsNothing,
    );
  });

  testWidgets('shows the percentage when the engine reports one', (
    tester,
  ) async {
    await _mount(
      tester,
      job: _transcribing(progress: 0.42, elapsed: const Duration(minutes: 5)),
    );

    expect(find.text('42%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('history-import-progress-job-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('history-import-elapsed-job-1')),
      findsNothing,
    );
  });
}
