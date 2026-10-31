/// While a long recording is transcribed in slices, the dock's status chip
/// names the slice in progress ("part k of n"). A recording with one slice
/// keeps the plain processing word, and the chip stays readable at a narrow
/// window with large text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/transcription/slice_progress.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(1280, 800);
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetDevicePixelRatio();
    view.resetPhysicalSize();
  });

  Future<void> pumpTranscribing(
    WidgetTester tester, {
    SliceProgress? progress,
    double textScale = 1.0,
  }) {
    return tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                WpRecordingDock(
                  sttModeLabel: 'Cloud',
                  sttState: SttServerState.ready,
                  recordingPhase: RecordingPhase.transcribing,
                  sliceProgress: progress,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('names the slice in progress while a long recording runs', (
    tester,
  ) async {
    await pumpTranscribing(
      tester,
      progress: const SliceProgress(done: 1, total: 3),
    );
    await tester.pump();

    expect(find.text(l10n.transcribingSliceProgress(2, 3)), findsOneWidget);
    expect(find.text(l10n.statusBarTranscribing), findsNothing);
  });

  testWidgets('a recording with one slice keeps the plain processing word', (
    tester,
  ) async {
    await pumpTranscribing(
      tester,
      progress: const SliceProgress(done: 0, total: 1),
    );
    await tester.pump();

    expect(find.text(l10n.statusBarTranscribing), findsOneWidget);
  });
}
