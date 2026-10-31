/// ticket: the appearance options reach the painter, and every wave style and
/// content toggle paints without error.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

FloatingOverlaySnapshot _snapshot({
  OverlayAppearance appearance = OverlayAppearance.defaults,
  OverlayBackground background = OverlayBackground.marine,
  OverlayWave wave = OverlayWave.cyan,
}) => FloatingOverlaySnapshot(
  visible: true,
  state: OverlayVisualState.recording,
  label: 'Recording',
  elapsed: '0:05',
  background: background,
  wave: wave,
  appearance: appearance,
);

void main() {
  test('snapshot map carries the appearance and rebuilds it', () {
    const appearance = OverlayAppearance(
      form: OverlayForm.roundedRect,
      waveStyle: OverlayWaveStyle.line,
      showCancel: false,
    );
    final map = _snapshot(appearance: appearance).toMap();
    expect(map['form'], 'rounded-rect');
    expect(map['waveStyle'], 'line');
    expect(FloatingOverlaySnapshot.fromMap(map).appearance, appearance);
  });

  test('the rendered opacity is the gate result, not the request', () {
    // Marine with the dark cyan wave: 60 % would fall below 3:1, so the gate
    // lifts it to 80 % (overlay_customization_test covers the table).
    final snap = _snapshot(
      appearance: const OverlayAppearance(opacity: OverlayOpacity.subtle),
    );
    expect(snap.effectiveOpacity, OverlayOpacity.reduced);
  });

  test('painter receives the fill opacity and the form', () {
    final painter = WpFloatingOverlayView.painterFor(
      snapshot: _snapshot(
        appearance: const OverlayAppearance(
          form: OverlayForm.roundedRect,
          opacity: OverlayOpacity.reduced,
        ),
      ),
    );
    expect(painter.form, OverlayForm.roundedRect);
    expect(painter.fillOpacity, closeTo(0.8, 1e-9));
  });
}
