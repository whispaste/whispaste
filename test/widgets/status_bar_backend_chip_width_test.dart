/// The far-right backend chip must keep **one width** across every reading
/// between 0 % and 100 % — it is a real layout participant of the status bar,
/// so a wider chip narrows the content span and shifts the centred chip group
/// (Ticket 10) sideways, un-damped. A measured 5.6 px snap at the 9↔10
/// boundary was the residual this file now pins shut.
///
/// Measured against the **real bundled UI face** (Hanken Grotesk since ADR
/// 0018), not the default test font:
/// every character in the test font has the same advance, which would make
/// the padding look sufficient on its own and hide both halves of the actual
/// rule. The negative control below is the point of this file — it fails
/// the moment the padding half is dropped (the UI face's digits are already
/// equal-width, see the fact check for the tabular half):
///
///   * padded with a plain space instead of U+2007, the blank is narrower
///     than a tabular digit and the column collapses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/recording_dock.dart';

import '../fixtures/test_helpers.dart';
import '../fixtures/dock_choice_fixtures.dart';

/// Readings that cross every digit boundary the chip can hit.
const List<double> _readings = <double>[0, 9, 9.6, 10, 99, 99.7, 100];

void main() {
  setUpAll(loadAppFonts);

  /// The production label style of the backend chip.
  TextStyle chipStyle() => wpDarkTheme().textTheme.labelSmall!.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  double textWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  Widget buildStatusBar(double? percent) {
    return makeTestable(
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          WpRecordingDock(
            sttModeLabel: 'On device',
            engine: dockTestEngine(label: 'On device'),
            sttState: SttServerState.ready,
            hotkeyLabel: 'Ctrl+Shift+D',
            backendKind: 'CPU',
            backendUtilizationPercent: percent,
          ),
        ],
      ),
    );
  }

  void setWindow(Size size) {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
    view.physicalSize = size;
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    setWindow(const Size(1280, 800));
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetDevicePixelRatio();
    view.resetPhysicalSize();
  });

  testWidgets('label renders at one width for every reading 0…100 %', (
    tester,
  ) async {
    final style = chipStyle();
    final reference = textWidth(
      backendUtilizationChipLabel('CPU', _readings.first),
      style,
    );

    for (final reading in _readings) {
      expect(
        textWidth(backendUtilizationChipLabel('CPU', reading), style),
        moreOrLessEquals(reference, epsilon: 0.01),
        reason: '$reading % must render exactly as wide as every other reading',
      );
    }
  });

  // Hanken Grotesk draws every digit at one advance even without the `tnum`
  // feature, so the negative control that held for Inter cannot fail any
  // more. It is kept as a fact check instead: if the UI face ever moves to
  // proportional default figures, this flips and the explicit tabularFigures
  // on the chip become load-bearing again.
  testWidgets('the UI face draws equal-width digits even without tabular '
      'figures', (tester) async {
    final proportional = wpDarkTheme().textTheme.labelSmall!;
    expect(
      textWidth(backendUtilizationChipLabel('CPU', 11), proportional),
      moreOrLessEquals(
        textWidth(backendUtilizationChipLabel('CPU', 99), proportional),
        epsilon: 0.01,
      ),
      reason:
          'the UI face now has proportional default digits — keep the '
          'fontFeatures on the chip and restore the negative control',
    );
  });

  testWidgets(
    'negative control — tabular figures alone are not enough: a '
    'plain space is narrower than a digit, and the digit count still varies',
    (tester) async {
      final style = chipStyle();
      String plainPadded(int percent) =>
          'CPU · ${percent.toString().padLeft(3)}%';

      expect(
        textWidth(plainPadded(9), style),
        isNot(
          moreOrLessEquals(textWidth(plainPadded(100), style), epsilon: 0.01),
        ),
        reason:
            'if this ever passes, U+2007 could be simplified to a plain space '
            '— it cannot today',
      );
    },
  );

  testWidgets('the dock row does not move when the reading crosses a '
      'digit boundary', (tester) async {
    Rect? dictate;
    Rect? engine;
    for (final reading in _readings) {
      await tester.pumpWidget(buildStatusBar(reading));
      await tester.pumpAndSettle();
      final nextDictate = tester.getRect(
        find.byKey(const ValueKey('dock-dictate')),
      );
      final nextEngine = tester.getRect(
        find.byKey(const ValueKey('dock-engine')),
      );
      dictate ??= nextDictate;
      engine ??= nextEngine;
      expect(
        nextDictate.topLeft,
        dictate.topLeft,
        reason: 'the Dictate button must not move at $reading %',
      );
      expect(
        nextEngine.topLeft,
        engine.topLeft,
        reason: 'the engine selector must not move at $reading %',
      );
    }
  });
}
