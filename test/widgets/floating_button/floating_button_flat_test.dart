/// The floating record button's disc is one flat colour (WP-75 flat pass),
/// no tint gradient, on every background preset.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

/// `toByteData()` returns premultiplied RGBA, so a disc drawn at alpha
/// `discFillOpacity` stores each channel scaled by that alpha.
List<int> _premultiplied(Color c, int alpha) => [
  (c.r * 255 * alpha / 255).round(),
  (c.g * 255 * alpha / 255).round(),
  (c.b * 255 * alpha / 255).round(),
];

/// Rounding in rasterised, partly transparent pixels can move a channel by a
/// few steps, so compare each channel within a small tolerance.
void _expectRgbNear(List<int> actual, List<int> expected, String reason) {
  for (var k = 0; k < 3; k++) {
    expect(
      (actual[k] - expected[k]).abs() <= 3,
      isTrue,
      reason: '$reason: channel $k is ${actual[k]}, expected ${expected[k]}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final background in OverlayBackground.values) {
    test('disc is one flat colour on ${background.value}', () async {
      const diameter = 56.0;
      final size = OverlayDesignSpec.buttonWindowSize(diameter);
      final painter = WpFloatingButtonView.painterFor(
        state: FloatingButtonVisualState.idle,
        diameter: diameter,
        background: background,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), size);
      final image = await recorder.endRecording().toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final data = await image.toByteData();
      final rgba = data!.buffer.asUint8List();
      final width = size.width.ceil();

      const c = OverlayDesignSpec.shadowPadding + diameter / 2;
      // Points left and right of centre: inside the rim (radius 20 from the
      // centre) and outside the mic glyph.
      const samples = [Offset(c - 16, c), Offset(c + 16, c)];
      for (final at in samples) {
        final i = (at.dy.round() * width + at.dx.round()) * 4;
        expect(
          rgba[i + 3],
          // The painted shadow beneath the 95 percent disc shows through by a few
          // steps (UX-048 strengthened it on the dark presets). The RGB check
          // below stays strict, so the disc is still one flat colour.
          closeTo(OverlayDesignSpec.button.discFillOpacity * 255, 6),
          reason: 'disc alpha at $at on ${background.value}',
        );
        _expectRgbNear(
          [rgba[i], rgba[i + 1], rgba[i + 2]],
          _premultiplied(background.surfaceStart, rgba[i + 3]),
          'disc at $at on ${background.value}',
        );
      }
    });
  }
}
