/// Focused UX harness for the support page (482991f0d, 8c45274e7): the coffee
/// pair, "Weitere Wege" and the share row at the minimum and the 1100 px
/// window, text scale 1.0 and 2.0. The draw is pinned to Buy Me a Coffee
/// first, so every capture shows the same order. Survey tool, asserts nothing.
/// Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_support_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/features/help/support_page.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const List<String> _themes = ['navy'];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final theme in _themes) {
        for (final locale in _locales) {
          final name =
              'support__${size.width.toInt()}x${size.height.toInt()}'
              '__s${scale.toString()}__${theme}_$locale';
          testWidgets('ux-support: $name', (tester) async {
            debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            SharedPreferences.setMockInitialValues(<String, Object>{
              'support_coffee_bmc_first': true,
            });
            final db = await openSeededUxDatabase(tester);
            addTearDown(() => tester.runAsync(db.close));

            final screen = UxScreen(
              id: 'support',
              activePageId: 'help',
              build: () => const SupportPage(),
            );
            await pumpUxScreen(
              tester,
              screen: screen,
              db: db,
              size: size,
              scale: scale,
              theme: theme,
              locale: locale,
            );

            final error = tester.takeException();
            Directory(outDir).createSync(recursive: true);
            if (error != null) {
              File(
                '$outDir/exceptions.log',
              ).writeAsStringSync('$name: $error\n', mode: FileMode.append);
            }

            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey(kUxCaptureKey)),
              );
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File(
                '$outDir/$name.png',
              ).writeAsBytesSync(bytes!.buffer.asUint8List());
            });

            await tester.pumpWidget(const SizedBox());
            debugDefaultTargetPlatformOverride = null;
          });
        }
      }
    }
  }
}
