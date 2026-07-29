/// Marketing-Asset-Generator für die Store-Composites — KEIN Vergleichstest.
///
/// Rendert den echten [OverlayPainter] (recording, normal + compact,
/// dark + light) auf transparentem Canvas und schreibt die PNGs nach
/// `tools/appstore-screens/assets/overlay-recording-*.png`. Diese Dateien
/// bettet die Screenshot-Pipeline (render-hero-device.cjs / generate.cjs)
/// per <img> in die Store-Bilder ein — so zeigt das Marketing exakt den
/// per-Pixel-Alpha-Output der App statt eines CSS-Nachbaus.
///
/// Der eingefrorene Frame ist bewusst ein Liquid-Peak-Moment (glassPhase 0.3,
/// liquidMotion 1.0, liquidLevel 0.8 — dieselben Parameter wie
/// `overlay_liquid_glass_golden_test.dart`): sichtbar gewölbte Silhouette +
/// gedrifteter Specular-Streak, damit die "flüssige" Qualität des Overlays
/// auch im statischen Bild ablesbar ist.
///
/// Läuft nur auf Anforderung (sonst skipped, damit normale Testläufe keine
/// Repo-Dateien anfassen):
///   CAPTURE_OVERLAY_ASSETS=1 flutter test \
///     test/screenshots/overlay_pill_asset_capture_test.dart
@Tags(<String>['golden'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

/// 2× damit die Browser-Composites (Hero @1x, Panorama @2x DPR) beim
/// Herunterskalieren scharf bleiben statt vom 1×-Asset hochzurechnen.
const double _pixelRatio = 2.0;

void main() {
  final capture = Platform.environment['CAPTURE_OVERLAY_ASSETS'] == '1';

  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

  group('overlay pill store-asset capture', () {
    for (final isDark in [true, false]) {
      for (final size in [
        OverlaySizeVariant.normal,
        OverlaySizeVariant.compact,
      ]) {
        final theme = isDark ? 'dark' : 'light';
        final suffix = size == OverlaySizeVariant.compact ? '-compact' : '';
        final fileName = 'overlay-recording-$theme$suffix.png';

        testWidgets('capture $fileName', (tester) async {
          final snapshot = FloatingOverlaySnapshot(
            visible: true,
            state: OverlayVisualState.recording,
            isDark: isDark,
            size: size,
            label: 'Recording',
            elapsed: '1:30',
            progress: 0.4,
          );
          final windowSize = OverlayDesignSpec.windowSizeFor(size);
          final bars = List<double>.generate(
            OverlayDesignSpec.waveform.barCount,
            (i) => (i % 7) / 7.0,
          );
          const key = ValueKey('pill-capture');

          await tester.pumpWidget(
            Center(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: windowSize.width,
                    height: windowSize.height,
                    child: CustomPaint(
                      size: windowSize,
                      painter: FloatingOverlayView.painterFor(
                        snapshot: snapshot,
                        waveformBars: bars,
                        dotPulse: 1.0,
                        glassPhase: 0.3,
                        liquidMotion: 1.0,
                        liquidLevel: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final boundary =
              tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: _pixelRatio);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final outFile = File('tools/appstore-screens/assets/$fileName');
            outFile.writeAsBytesSync(bytes!.buffer.asUint8List());
            // ignore: avoid_print
            print(
              'PILL_ASSET_WRITTEN=${outFile.absolute.path} '
              '(${image.width}x${image.height})',
            );
          });
        }, skip: !capture);
      }
    }
  });
}
