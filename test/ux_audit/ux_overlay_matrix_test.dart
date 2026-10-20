/// UX probe: the full overlay preset matrix (4 backgrounds x 4 waves x 4
/// states) that the golden suite does not cover (it renders 3 presets, and the
/// amber preset only in two states). Writes one PNG per state and page tone
/// into UX_SCREENS_DIR: rows = background, columns = wave.
///
/// Tagged `ux-screens` (not part of the normal suite). Run on the Mac:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_overlay_matrix_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/widgets/floating_overlay/floating_overlay_view.dart';

const _labels = <OverlayVisualState, String>{
  OverlayVisualState.recording: 'Aufnahme',
  OverlayVisualState.transcribing: 'Übertragung',
  OverlayVisualState.done: 'Fertig',
  OverlayVisualState.error: 'Fehler',
};

const _pages = <String, (Color, Color)>{
  // page background, page label colour
  'dunkel': (Color(0xFF0B1426), Color(0xFFE6ECF5)),
  'hell': (Color(0xFFF2F5F9), Color(0xFF1B2433)),
};

const _cellWidth = 300.0;
const _labelWidth = 150.0;

FloatingOverlaySnapshot _snap(
  OverlayVisualState state, {
  required OverlayBackground background,
  required OverlayWave wave,
}) {
  return FloatingOverlaySnapshot(
    visible: true,
    state: state,
    size: OverlaySizeVariant.normal,
    background: background,
    wave: wave,
    label: _labels[state]!,
    elapsed: state == OverlayVisualState.recording ? '1:30' : '',
    errorMessage: state == OverlayVisualState.error ? 'Netzwerk-Fehler' : null,
    doneMessage: state == OverlayVisualState.done ? 'Eingefügt' : null,
    progress: state == OverlayVisualState.recording ? 0.4 : 0.0,
  );
}

Widget _pill(FloatingOverlaySnapshot snapshot) {
  final windowSize = OverlayDesignSpec.windowSizeFor(snapshot.size);
  final bars = List<double>.generate(
    OverlayDesignSpec.waveform.barCount,
    (i) => (i % 7) / 7.0,
  );
  return SizedBox(
    width: windowSize.width,
    height: windowSize.height,
    child: CustomPaint(
      size: windowSize,
      painter: WpFloatingOverlayView.painterFor(
        snapshot: snapshot,
        waveformBars: bars,
        dotPulse: 1.0,
      ),
    ),
  );
}

Widget _matrix(OverlayVisualState state, Color page, Color ink) {
  TextStyle style(double size, {bool bold = false}) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    color: ink,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    decoration: TextDecoration.none,
  );

  return Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: page,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: _labelWidth),
                for (final wave in OverlayWave.values)
                  SizedBox(
                    width: _cellWidth,
                    child: Text(wave.value, style: style(14, bold: true)),
                  ),
              ],
            ),
            for (final background in OverlayBackground.values)
              Row(
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Text(background.value, style: style(14, bold: true)),
                  ),
                  for (final wave in OverlayWave.values)
                    SizedBox(
                      width: _cellWidth,
                      height: 90,
                      child: Center(
                        child: _pill(
                          // Dev's rule: a wave that is not valid on this
                          // background is shown as its valid substitute.
                          _snap(
                            state,
                            background: background,
                            wave: wave.validOn(background),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';

  for (final entry in _pages.entries) {
    for (final state in OverlayVisualState.values) {
      final name = 'overlay-matrix_${entry.key}_${state.name}';
      testWidgets('ux-overlay-matrix $name', (tester) async {
        tester.view.physicalSize = const Size(1400, 470);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_matrix(state, entry.value.$1, entry.value.$2));
        await tester.pump();

        await tester.runAsync(() async {
          final view = tester.binding.renderViews.first;
          final layer = view.debugLayer! as OffsetLayer;
          final image = await layer.toImage(
            Offset.zero & const Size(1400, 470),
          );
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(outDir).createSync(recursive: true);
          File(
            '$outDir/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
}
