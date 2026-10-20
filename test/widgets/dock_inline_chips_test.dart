/// Regression guard for the recording dock: at desktop widths the Smart Mode,
/// language and speech-recognition chips stay inline and do not collapse into
/// Mehr while there is room for them. Overflow is only allowed when the row is
/// genuinely narrow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/dock_choice_fixtures.dart';
import '../fixtures/test_helpers.dart';
import '../screenshots/screenshot_shell.dart';

WpRecordingDock _dock() => WpRecordingDock(
  sttModeLabel: 'Auf dem Gerät',
  smartMode: dockTestSmartMode(label: 'Aus'),
  language: dockTestLanguage(label: 'Deutsch'),
  engine: dockTestEngine(label: 'Auf dem Gerät'),
  recordingPhase: RecordingPhase.idle,
  microphoneLabel: 'Built-in',
  microphoneOptions: const ['Built-in'],
  afterActionLabel: 'Copy',
  afterAction: null,
  hotkeyLabel: 'Win+Shift+D',
);

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width + 24, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: width + 24, child: _dock()),
      ),
      size: Size(width + 24, 800),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
}

void main() {
  for (final width in [1440.0, 1100.0]) {
    testWidgets('at ${width.toInt()} px all three chips are visible inline', (
      tester,
    ) async {
      await _pump(tester, width);

      for (final key in const [
        'dock-smart-mode',
        'dock-language',
        'dock-engine',
      ]) {
        expect(
          find.byKey(ValueKey(key)),
          findsOneWidget,
          reason: '$key moved into Mehr although the row has room',
        );
      }
      expect(find.byKey(const ValueKey('dock-menu-panel')), findsNothing);
    });
  }

  testWidgets('at 800 px overflow into Mehr is still allowed', (tester) async {
    await _pump(tester, 800);

    // Priority order still applies: at least one droppable chip has moved.
    final inline = [
      'dock-smart-mode',
      'dock-language',
      'dock-engine',
    ].where((key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty).length;
    expect(inline, lessThan(3));
    expect(find.byKey(const ValueKey('dock-overflow')), findsOneWidget);
  });

  testWidgets('the store screenshot shell shows the same three dropdowns as '
      'the app dock at 1440 px', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        const WpScreenshotShell(
          activePageId: 'history',
          child: SizedBox.expand(),
        ),
        size: const Size(1440, 900),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    for (final key in const [
      'dock-smart-mode',
      'dock-language',
      'dock-engine',
    ]) {
      expect(
        find.byKey(ValueKey(key)),
        findsOneWidget,
        reason: '$key missing from the store screenshot dock',
      );
    }
  });
}
