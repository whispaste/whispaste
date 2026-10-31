/// UX probe: the two overlay swatch rows (background and wave) in isolation,
/// at text scale 1.0 and 2.0, German and Hebrew, dark theme. The settings
/// harness does not show them (they sit below the fold), so this renders the
/// real widgets directly. Writes one PNG per variant into UX_SCREENS_DIR.
///
/// Tagged `ux-screens` (not part of the normal suite). Run on the Mac:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_swatch_labels_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/settings/widgets/overlay_theme_swatches.dart';

import '../../test/features/settings/widgets/settings_golden_board.dart';

const _canvas = Size(440, 230);

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final locale in const ['de', 'he']) {
    for (final scale in const [1.0, 2.0]) {
      final name = 'swatch-labels_${locale}_s${scale.toString()}';
      testWidgets('ux-swatch-labels $name', (tester) async {
        tester.view.physicalSize = _canvas;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        WpColors.activate(kSettingsGoldenSets['dark']!);
        addTearDown(() => WpColors.activate(kSettingsGoldenSets['dark']!));

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: wpDarkTheme(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: Locale(locale),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              backgroundColor: kSettingsGoldenSets['dark']!.background,
              body: Center(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      WpOverlayBackgroundSwatches(
                        value: OverlayBackground.marine,
                        onChanged: (_) {},
                      ),
                      const SizedBox(height: 16),
                      WpOverlayWaveSwatches(
                        value: OverlayWave.cyan,
                        background: OverlayBackground.marine,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        await tester.runAsync(() async {
          final layer =
              tester.binding.renderViews.first.debugLayer! as OffsetLayer;
          final image = await layer.toImage(Offset.zero & _canvas);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(outDir).createSync(recursive: true);
          File(
            '$outDir/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
