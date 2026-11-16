// Waveform bar reduction for the sizes that draw fewer bars (nano).
//
// Business rule: a size with fewer bars shows the same level curve at a
// coarser resolution. Each bar is the mean of the samples it covers.
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';

void main() {
  test('same count keeps every level, clamped to [0, 1]', () {
    final levels = [0.0, 0.5, 1.4, -0.2];
    expect(resampleWaveformLevels(levels, 4), [0.0, 0.5, 1.0, 0.0]);
  });

  test('reduces to the requested count and stays in range', () {
    final levels = List<double>.generate(
      OverlayDesignSpec.waveform.barCount,
      (i) => (i % 5) / 4,
    );
    final out = resampleWaveformLevels(levels, 12);
    expect(out, hasLength(12));
    for (final v in out) {
      expect(v, inInclusiveRange(0.0, 1.0));
    }
  });

  test('a constant curve stays constant', () {
    final out = resampleWaveformLevels(List.filled(22, 0.6), 12);
    for (final v in out) {
      expect(v, closeTo(0.6, 1e-9));
    }
  });

  test('missing samples count as silence', () {
    expect(resampleWaveformLevels(const [], 3), [0.0, 0.0, 0.0]);
    expect(resampleWaveformLevels(const [1.0], 0), isEmpty);
  });
}
