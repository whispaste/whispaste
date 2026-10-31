/// The far-right backend chip must keep **one width** across every reading
/// between 0 % and 100 % — it is a real layout participant of the status bar,
/// so a wider chip narrows the content span and shifts the centred chip group
/// (Ticket 10) sideways, un-damped. A measured 5.6 px snap at the 9↔10
/// boundary was the residual this file now pins shut.
///
/// Measured against the **real bundled Inter**, not the default test font:
/// every character in the test font has the same advance, which would make
/// the padding look sufficient on its own and hide both halves of the actual
/// rule. The two negative controls below are the point of this file — they
/// fail the moment either half is dropped:
///
///   * without [FontFeature.tabularFigures], Inter's proportional digits
///     (833 units for `1`, 1292 for `0`) make equal-length labels differ;
///   * padded with a plain space instead of U+2007, the blank (546 units) is
///     narrower than a tabular digit (1327) and the column collapses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/status_bar.dart';

import '../fixtures/test_helpers.dart';

/// Readings that cross every digit boundary the chip can hit.
const List<double> _readings = <double>[0, 9, 9.6, 10, 99, 99.7, 100];

void main() {
  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

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
          WpStatusBar(
            sttModeLabel: 'On device',
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

  testWidgets('negative control — padding alone is not enough: without '
      'tabular figures, Inter renders equal-length labels at unequal widths', (
    tester,
  ) async {
    final proportional = wpDarkTheme().textTheme.labelSmall!;
    expect(
      textWidth(backendUtilizationChipLabel('CPU', 11), proportional),
      isNot(
        moreOrLessEquals(
          textWidth(backendUtilizationChipLabel('CPU', 99), proportional),
          epsilon: 0.01,
        ),
      ),
      reason:
          'if this ever passes, the fontFeatures on the chip have become '
          'redundant — verify before deleting them',
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

  testWidgets('the centred chip group does not move when the reading crosses a '
      'digit boundary', (tester) async {
    Rect? reference;

    for (final reading in _readings) {
      await tester.pumpWidget(buildStatusBar(reading));
      await tester.pumpAndSettle();

      final group = tester.getRect(find.byType(AnimatedSize));
      reference ??= group;
      expect(
        group.center.dx,
        moreOrLessEquals(reference.center.dx, epsilon: 0.01),
        reason: 'the chip group must not shift at $reading %',
      );
      expect(
        group.width,
        moreOrLessEquals(reference.width, epsilon: 0.01),
        reason: 'the content span must not change width at $reading %',
      );
    }
  });
}
