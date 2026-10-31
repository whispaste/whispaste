/// ticket: the appearance bundle that travels in the overlay snapshot.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';

void main() {
  test('defaults equal today\'s look', () {
    const d = OverlayAppearance.defaults;
    expect(d.form, OverlayForm.pill);
    expect(d.waveStyle, OverlayWaveStyle.bars);
    expect(d.waveFluid, isTrue);
    expect(d.showTimer, isTrue);
    expect(d.showCancel, isTrue);
    expect(d.opacity, OverlayOpacity.full);
  });

  test('unknown persisted strings fall back to the defaults', () {
    final a = OverlayAppearance.fromValues(
      form: 'hexagon',
      waveStyle: 'spiral',
      opacity: '42',
    );
    expect(a, OverlayAppearance.defaults);
  });

  test('map form round-trips every field', () {
    const a = OverlayAppearance(
      form: OverlayForm.roundedRect,
      waveStyle: OverlayWaveStyle.dots,
      waveFluid: false,
      showTimer: false,
      showCancel: false,
      opacity: OverlayOpacity.subtle,
    );
    expect(OverlayAppearance.fromMap(a.toMap()), a);
  });

  test('a map without the keys reads as the defaults (older sender)', () {
    expect(OverlayAppearance.fromMap(const {}), OverlayAppearance.defaults);
  });

  test('opacity travels as the percentage string', () {
    expect(
      const OverlayAppearance(
        opacity: OverlayOpacity.reduced,
      ).toMap()['opacity'],
      '80',
    );
  });
}
