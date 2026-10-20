/// The dock's done chip names what actually happened to the transcript:
/// copied to the clipboard, pasted at the cursor, both, or neither. A
/// clipboard-only outcome must not claim "Pasted".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_helpers.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/wp_status_dot.dart';

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

  Future<void> pumpDone(
    WidgetTester tester,
    String? doneMessage, {
    bool pasteFailed = false,
  }) {
    return tester.pumpWidget(
      makeTestable(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            WpRecordingDock(
              sttModeLabel: 'On device',
              sttState: SttServerState.ready,
              recordingPhase: RecordingPhase.done,
              doneMessage: doneMessage,
              donePasteFailed: pasteFailed,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('shows the copy label it is given, not "Pasted"', (tester) async {
    await pumpDone(tester, doneMessageFor('clipboard', l10n));
    await tester.pump();

    expect(find.text(l10n.overlayDone), findsOneWidget);
    expect(find.text(l10n.overlayDonePasted), findsNothing);
  });

  testWidgets('a failed paste is never shown as "Pasted"', (tester) async {
    await pumpDone(tester, doneMessageFor('paste', l10n, pasteFailed: true));
    await tester.pump();

    expect(find.text(l10n.overlayDonePasteFailed), findsOneWidget);
    expect(find.text(l10n.overlayDonePasted), findsNothing);
  });

  testWidgets('a failed paste gets no green success dot (XP-5-07)', (
    tester,
  ) async {
    await pumpDone(
      tester,
      doneMessageFor('paste', l10n, pasteFailed: true),
      pasteFailed: true,
    );
    await tester.pump();

    final dot = tester.widget<WpStatusDot>(find.byType(WpStatusDot));
    expect(dot.tone, isNot(WpStatusTone.success));
  });

  testWidgets('a pasted run keeps the green success dot', (tester) async {
    await pumpDone(tester, doneMessageFor('paste', l10n));
    await tester.pump();

    final dot = tester.widget<WpStatusDot>(find.byType(WpStatusDot));
    expect(dot.tone, WpStatusTone.success);
  });

  testWidgets('a quick note is named as a note, not as pasted', (tester) async {
    await pumpDone(
      tester,
      doneMessageFor('paste', l10n, target: RecordingTarget.quickNote),
    );
    await tester.pump();

    expect(find.text(l10n.overlayDoneQuickNote), findsOneWidget);
    expect(find.text(l10n.overlayDonePasted), findsNothing);
  });

  testWidgets('falls back to "Done" when no outcome is given', (tester) async {
    await pumpDone(tester, null);
    await tester.pump();

    expect(find.text(l10n.overlayDoneReady), findsOneWidget);
  });
}
