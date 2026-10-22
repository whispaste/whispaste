/// The import row while a file is transcribed: a determinate bar with the
/// percentage when the engine reports one, otherwise an indeterminate bar and
/// the time since the step started. Checked at 800 px with large text and in
/// a right-to-left locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/widgets/audio_import_panel.dart';
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
      const SingleChildScrollView(child: AudioImportPanel()),
      size: size,
      locale: locale,
      overrides: [
        audioImportQueueProvider.overrideWith(() => _FakeQueue([job])),
        audioImportClockProvider.overrideWithValue(() => _now),
      ],
    ),
  );
  await tester.pump();
}

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

  testWidgets('keeps the layout at 800 px with text scale 1.3', (tester) async {
    await _mount(
      tester,
      job: _transcribing(elapsed: const Duration(hours: 1, minutes: 2)),
      size: const Size(800, 900),
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Running for 1:02:00'), findsOneWidget);
  });

  testWidgets('lays out right-to-left in Hebrew', (tester) async {
    await _mount(
      tester,
      job: _transcribing(progress: 0.5),
      locale: const Locale('he'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('50%'), findsOneWidget);
  });
}
