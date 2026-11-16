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
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snap({
  required bool visible,
  OverlayVisualState state = OverlayVisualState.recording,
  bool fluid = true,
}) => FloatingOverlaySnapshot(
  visible: visible,
  state: state,
  label: 'Recording',
  elapsed: '0:03',
  appearance: OverlayAppearance(waveFluid: fluid),
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

  // North-star review #25: the drift repaints every vsync, so it runs only
  // while something on screen reads its phase.
  testWidgets('recording without the fluid outline settles to no frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        WpFloatingOverlayView(snapshot: _snap(visible: true, fluid: false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('transcribing keeps the drift for its spinner and ripple', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        WpFloatingOverlayView(snapshot: _snap(visible: true, fluid: false)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _wrap(
        WpFloatingOverlayView(
          snapshot: _snap(
            visible: true,
            fluid: false,
            state: OverlayVisualState.transcribing,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching the fluid outline on starts the drift', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        WpFloatingOverlayView(snapshot: _snap(visible: true, fluid: false)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _wrap(WpFloatingOverlayView(snapshot: _snap(visible: true))),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
