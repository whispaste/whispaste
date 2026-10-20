/// The recording pill is one flat colour (WP-75 flat pass): no fill gradient,
/// no glass sheen, no specular streak. Rasterised pixels inside the pill must
/// equal the preset's surface colour everywhere, on every background preset.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';
import 'package:whispaste/widgets/floating_overlay/overlay_painter.dart';

Future<Uint8List> _rasterize(WpOverlayPainter painter, Size window) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), window);
  final image = await recorder.endRecording().toImage(
    window.width.ceil(),
    window.height.ceil(),
  );
  final data = await image.toByteData();
  return data!.buffer.asUint8List();
}

List<int> _pixel(Uint8List rgba, int width, Offset at) {
  final i = (at.dy.round() * width + at.dx.round()) * 4;
  return [rgba[i], rgba[i + 1], rgba[i + 2]];
}

List<int> _rgb(Color c) => [
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
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
    test('pill fill is one flat colour on ${background.value}', () async {
      const variant = OverlaySizeVariant.normal;
      final spec = OverlayDesignSpec.sizeFor(variant);
      final window = OverlayDesignSpec.windowSizeFor(variant);
      final painter = WpFloatingOverlayView.painterFor(
        snapshot: FloatingOverlaySnapshot(
          visible: true,
          state: OverlayVisualState.recording,
          label: '',
          background: background,
        ),
        paintContent: false,
      );
      final rgba = await _rasterize(painter, window);
      final width = window.width.ceil();

      const left = OverlayDesignSpec.shadowPadding;
      const top = OverlayDesignSpec.shadowPadding;
      // Top-left, top-centre (where the old specular streak sat), and
      // bottom-right inside the pill: all three must show the same colour.
      final samples = [
        const Offset(left + 40, top + 12),
        Offset(left + spec.width / 2, top + 6),
        Offset(left + spec.width - 40, top + spec.height - 12),
      ];
      final expected = _rgb(background.surfaceStart);
      for (final at in samples) {
        _expectRgbNear(
          _pixel(rgba, width, at),
          expected,
          'pixel at $at on ${background.value}',
        );
      }
    });
  }
}
