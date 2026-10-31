/// Focused UX harness for the floating button in its idle and recording state
/// (BTN-REC, UX-080). Each variant is drawn at its native window size
/// ([OverlayDesignSpec.buttonWindowSize]) on a frame of exactly that size, so
/// a ring that reaches the window edge is cut off in the PNG. Besides the PNG,
/// the outermost pixel ring is measured against the backdrop and written next
/// to it as `<name>.edge.txt`: a value above 0 means paint touches the edge.
/// Survey tool, asserts nothing. Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_rec_button_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/theme/colors_dark.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_button/floating_button_controller_interface.dart';
import 'package:whispaste/widgets/floating_button/floating_button_view.dart';

import '../../test/fixtures/test_helpers.dart';
import '../../test/ux_audit/ux_fixtures.dart';

/// Disc diameters the settings can hold (44 / 56 / 80).
const List<double> _diameters = [44, 56, 80];

const Key _captureKey = ValueKey('ux-rec-button-capture');

/// Backdrops the button sits on: the dark stage and a light desktop.
final Map<String, Color> _backdrops = {
  'dark': WpColorsDark.background,
  'light': const Color(0xFFFFFFFF),
};

final Map<String, FloatingButtonVisualState> _states = {
  'idle': FloatingButtonVisualState.idle,
  'recording': FloatingButtonVisualState.recording,
};

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final diameter in _diameters) {
    for (final state in _states.entries) {
      for (final backdrop in _backdrops.entries) {
        final name =
            'rec-button-${state.key}__d${diameter.toInt()}__${backdrop.key}';
        testWidgets('ux-rec-button: $name', (tester) async {
          final db = await openSeededUxDatabase(tester);
          addTearDown(() => tester.runAsync(db.close));

          final window = OverlayDesignSpec.buttonWindowSize(diameter);
          await tester.pumpWidget(
            makeTestable(
              Center(
                child: RepaintBoundary(
                  key: _captureKey,
                  child: ColoredBox(
                    color: backdrop.value,
                    child: SizedBox(
                      width: window.width,
                      height: window.height,
                      child: WpFloatingButtonView(
                        state: state.value,
                        diameter: diameter,
                      ),
                    ),
                  ),
                ),
              ),
              size: const Size(400, 300),
              locale: const Locale('de'),
              db: db,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          final error = tester.takeException();
          Directory(outDir).createSync(recursive: true);
          if (error != null) {
            File(
              '$outDir/exceptions.log',
            ).writeAsStringSync('$name: $error\n', mode: FileMode.append);
          }

          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(_captureKey),
            );
            final image = await boundary.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final raw = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            File(
              '$outDir/$name.png',
            ).writeAsBytesSync(png!.buffer.asUint8List());

            final w = image.width;
            final h = image.height;
            final bg = backdrop.value;
            final bgRgb = [
              (bg.r * 255).round(),
              (bg.g * 255).round(),
              (bg.b * 255).round(),
            ];
            var edgeMax = 0;
            final bytes = raw!.buffer.asUint8List();
            for (var y = 0; y < h; y++) {
              for (var x = 0; x < w; x++) {
                if (x != 0 && y != 0 && x != w - 1 && y != h - 1) continue;
                final i = (y * w + x) * 4;
                for (var c = 0; c < 3; c++) {
                  final d = (bytes[i + c] - bgRgb[c]).abs();
                  if (d > edgeMax) edgeMax = d;
                }
              }
            }
            final spec = OverlayDesignSpec.buttonSpecFor(
              OverlayDesignSpec.colorsFor(),
              ringed: true,
            );
            final outerEdge = -spec.borderInset + spec.borderWidth / 2;
            File('$outDir/$name.edge.txt').writeAsStringSync(
              'window ${w}x$h, disc $diameter, ring outer radius offset '
              '${outerEdge.toStringAsFixed(2)} px (spec), '
              'edge max delta $edgeMax (0 = nothing touches the window edge)\n',
            );
          });

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }
}
