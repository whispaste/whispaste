/// UX screenshot harness for the settings deep link. Sets the scroll target to
/// the overlay preview row (as the settings search does) and captures the page
/// while the target tint is visible, so the tint and the row's placement are
/// on record. It asserts nothing.
///
/// Tagged `ux-screens`, so the normal suite and CI skip it. Run on the Mac:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_deeplink_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import 'ux_fixtures.dart';

const _rowId = 'appearance-overlay-preview';

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';
  final screen = kUxScreens.firstWhere((s) => s.id == 'settings');
  const sizes = <Size>[kUxSizeMinimum, kUxSize1100];

  for (final size in sizes) {
    for (final locale in const ['de', 'he']) {
      final name =
          'deeplink-overlay-preview__${size.width.toInt()}x'
          '${size.height.toInt()}__s1.0__dark_$locale';
      testWidgets('ux-deeplink: $name', (tester) async {
        final db = await openSeededUxDatabase(tester);
        addTearDown(() => tester.runAsync(db.close));

        await pumpUxScreen(
          tester,
          screen: screen,
          db: db,
          size: size,
          scale: 1.0,
          theme: 'dark',
          locale: locale,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsPage)),
        );
        container.read(settingsScrollTargetProvider.notifier).set(_rowId);
        // Let the area switch, the scroll (300 ms) and the tint fade-in run,
        // but stay well inside the 1.5 s fade-out.
        // The area switch and the scroll chain need several frames; the capture
        // waits 900 ms, inside the tint's 1.5 s hold, so the tint is visible.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }

        final error = tester.takeException();
        if (error != null) {
          Directory(outDir).createSync(recursive: true);
          File(
            '$outDir/exceptions.log',
          ).writeAsStringSync('$name: $error\n', mode: FileMode.append);
        }

        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey(kUxCaptureKey)),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(outDir).createSync(recursive: true);
          File(
            '$outDir/$name.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}
