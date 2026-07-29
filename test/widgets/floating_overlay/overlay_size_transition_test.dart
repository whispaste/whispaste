/// Regression test for the overlay-size-switch bug (2026-07-28 live report):
/// "Sobald ich eine andere Overlay-Art auswähle, wird sie auch nicht mehr
/// sauber angezeigt."
///
/// Root cause: [FloatingOverlayView.didUpdateWidget] recomputes the animated
/// pill-width target (`_pillFromWidth` / `_pillToWidth`) only when
/// `snapshot.visible` or `snapshot.state` changes — never when only
/// `snapshot.size` changes. The Settings-page live preview
/// (`OverlayRealPreview`) keeps `visible: true` and `state: recording`
/// constant while the user cycles the size radio buttons, so a pure
/// size-only snapshot update slips through both branches: the window
/// (`SizedBox`/`CustomPaint` `size:`) resizes immediately in `build()`
/// (it reads `widget.snapshot.size` directly), but the pill painted inside
/// it keeps the *previous* size's target width — e.g. switching normal→mini
/// paints a 330px-wide pill inside a 166px-wide window; switching mini→normal
/// paints a 150px-wide pill adrift inside a 346px window. Either way the
/// capsule renders overflowing or looking broken/"gone" — matching the
/// user's report.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';

FloatingOverlaySnapshot _snap(OverlaySizeVariant size) =>
    FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.recording,
      isDark: false,
      size: size,
      label: 'Recording',
      elapsed: '0:07',
      progress: 0.2,
    );

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

/// Reads the [OverlayPainter] currently driving the single (steady-state)
/// `CustomPaint` in the tree.
OverlayPainter _currentPainter(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<OverlayPainter>()
      .toList();
  // Steady state (no crossfade in flight) renders exactly one OverlayPainter.
  expect(
    painters,
    hasLength(1),
    reason: 'expected steady-state single painter, not a crossfade stack',
  );
  return painters.single;
}

void main() {
  testWidgets('a size-only snapshot update (same state/visible) re-targets the '
      'painted pill width to the NEW size — not the stale previous size', (
    tester,
  ) async {
    // Mirrors the Settings page's OverlayRealPreview: visible=true and
    // state=recording never change while the user cycles the size radio.
    await tester.pumpWidget(
      _wrap(FloatingOverlayView(snapshot: _snap(OverlaySizeVariant.normal))),
    );
    await tester.pump();

    final normalPainter = _currentPainter(tester);
    expect(normalPainter.pillWidth, OverlaySizeSpec.normal.width);

    // Switch to mini — visible and state are unchanged, only size differs.
    await tester.pumpWidget(
      _wrap(FloatingOverlayView(snapshot: _snap(OverlaySizeVariant.mini))),
    );
    await tester.pump();

    final miniPainter = _currentPainter(tester);
    // BUG (pre-fix): this still reports OverlaySizeSpec.normal.width (330)
    // — the stale pill target from before the size change — even though
    // the surrounding window/canvas has already shrunk to mini's 166×44.
    expect(
      miniPainter.pillWidth,
      OverlaySizeSpec.mini.width,
      reason:
          'pill width must re-target to the mini size immediately on a '
          'size-only snapshot change, matching the new (already-resized) '
          'window — otherwise the pill overflows/looks broken inside it',
    );

    // Switch back to normal — same check in the other direction.
    await tester.pumpWidget(
      _wrap(FloatingOverlayView(snapshot: _snap(OverlaySizeVariant.normal))),
    );
    await tester.pump();

    final backToNormalPainter = _currentPainter(tester);
    expect(backToNormalPainter.pillWidth, OverlaySizeSpec.normal.width);
  });

  testWidgets(
    'a size-only snapshot update also re-targets the window/canvas size '
    'consistently with the pill width (no cross-size mismatch)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(FloatingOverlayView(snapshot: _snap(OverlaySizeVariant.normal))),
      );
      await tester.pump();

      await tester.pumpWidget(
        _wrap(FloatingOverlayView(snapshot: _snap(OverlaySizeVariant.mini))),
      );
      await tester.pump();

      final painter = _currentPainter(tester);
      final customPaint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((w) => w.painter == painter);
      final canvasSize = customPaint.size;
      final expectedWindow = OverlayDesignSpec.windowSizeFor(
        OverlaySizeVariant.mini,
      );

      expect(canvasSize, expectedWindow);
      expect(
        painter.pillWidth! <= canvasSize.width,
        isTrue,
        reason:
            'the painted pill must never be wider than the canvas/window it '
            'is painted into — pillWidth=${painter.pillWidth}, '
            'canvasWidth=${canvasSize.width}',
      );
    },
  );
}
