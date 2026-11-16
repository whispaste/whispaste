/// Widget tests for the STT chip's missing-model and download states: an
/// idle "Standby" must not promise a dictation that cannot run yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Widget buildStatusBar({
    bool modelMissing = false,
    int? downloadPercent,
    RecordingPhase phase = RecordingPhase.idle,
  }) {
    return makeTestable(
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          WpRecordingDock(
            sttModeLabel: 'On device',
            sttState: SttServerState.stopped,
            sttModelMissing: modelMissing,
            sttModelDownloadPercent: downloadPercent,
            recordingPhase: phase,
          ),
        ],
      ),
    );
  }

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

  testWidgets('shows Ready while the model is on disk', (tester) async {
    await tester.pumpWidget(buildStatusBar());
    await tester.pump();

    expect(find.text(l10n.statusReady), findsOneWidget);
  });

  testWidgets('says the model is missing instead of Ready', (tester) async {
    await tester.pumpWidget(buildStatusBar(modelMissing: true));
    await tester.pump();

    expect(find.text(l10n.statusBarModelMissing), findsOneWidget);
    expect(find.text(l10n.statusReady), findsNothing);
  });

  testWidgets('a running download shows its progress', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(modelMissing: true, downloadPercent: 42),
    );
    await tester.pump();

    expect(find.text(l10n.statusBarModelDownloading(42)), findsOneWidget);
  });

  testWidgets('an active recording phase still takes priority', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(modelMissing: true, phase: RecordingPhase.transcribing),
    );
    await tester.pump();

    // The phase word is shown once: the status chip carries it, the inert
    // dictate button keeps its neutral label.
    expect(find.text(l10n.statusBarTranscribing), findsOneWidget);
  });

  testWidgets('an error names its cause and the next step in the tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(buildStatusBar(phase: RecordingPhase.error));
    await tester.pump();

    expect(find.text(l10n.sttStatusError), findsOneWidget);
    expect(
      find.byTooltip('${l10n.dockErrorCauseRecording} ${l10n.dockErrorAction}'),
      findsWidgets,
    );
  });
}
