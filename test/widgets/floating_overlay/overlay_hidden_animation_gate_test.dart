/// Locks the visibility gate on the overlay's two perpetual animations
/// (accent-dot pulse + liquid-glass drift).
///
/// Companion to `detachFromEmbedderAppLifecycle()` in the overlay render
/// entrypoint (live fix, 2026-09-01). Detaching the render engine from the
/// embedder's app lifecycle is what stops a bogus `AppLifecycleState.hidden`
/// from freezing the overlay invisible — but it also removes the accidental
/// brake that used to stop these tickers, so from now on nothing but this
/// gate keeps an ordered-out panel from being repainted every vsync for the
/// rest of the app session.
///
/// `transientCallbackCount` is the honest seam: a running
/// [AnimationController] holds exactly one transient (ticker) callback, and
/// each of those is a `scheduleFrame()` per vsync in the real engine.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap({required bool visible}) =>
    FloatingOverlaySnapshot(
      visible: visible,
      state: OverlayVisualState.recording,
      label: 'Recording',
      elapsed: '0:03',
    );

Widget _wrap(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  testWidgets('hidden overlay schedules no perpetual animation frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(WpFloatingOverlayView(snapshot: _snap(visible: false))),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester.binding.transientCallbackCount,
      0,
      reason:
          'a hidden overlay must not keep the dot pulse or the liquid-glass '
          'drift ticking — the render engine no longer adopts the embedder '
          'lifecycle, so nothing else would ever stop them repainting the '
          'ordered-out panel',
    );
  });

  testWidgets('re-shown overlay resumes the perpetual animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(WpFloatingOverlayView(snapshot: _snap(visible: false))),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.pumpWidget(
      _wrap(WpFloatingOverlayView(snapshot: _snap(visible: true))),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason:
          'the pulse and drift must come back with the panel, or a re-shown '
          'overlay would render as a still frame',
    );

    // Settle the perpetual animations so the test binding can tear down.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
