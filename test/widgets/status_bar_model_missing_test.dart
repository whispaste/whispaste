/// Widget tests for the STT chip's missing-model and download states: an
/// idle "Standby" must not promise a dictation that cannot run yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/status_bar.dart';

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
          WpStatusBar(
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

  testWidgets('shows Standby while the model is on disk', (tester) async {
    await tester.pumpWidget(buildStatusBar());
    await tester.pump();

    expect(find.text('On device — ${l10n.sttStatusStandby}'), findsOneWidget);
  });

  testWidgets('says the model is missing instead of Standby', (tester) async {
    await tester.pumpWidget(buildStatusBar(modelMissing: true));
    await tester.pump();

    expect(
      find.text('On device — ${l10n.statusBarModelMissing}'),
      findsOneWidget,
    );
    expect(find.textContaining(l10n.sttStatusStandby), findsNothing);
  });

  testWidgets('a running download shows its progress', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(modelMissing: true, downloadPercent: 42),
    );
    await tester.pump();

    expect(
      find.text('On device — ${l10n.statusBarModelDownloading(42)}'),
      findsOneWidget,
    );
  });

  testWidgets('an active recording phase still takes priority', (tester) async {
    await tester.pumpWidget(
      buildStatusBar(modelMissing: true, phase: RecordingPhase.transcribing),
    );
    await tester.pump();

    expect(
      find.text('On device — ${l10n.statusBarTranscribing}'),
      findsOneWidget,
    );
  });
}
