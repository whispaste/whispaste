/// Focused UX harness for the overlay and floating-button settings (WP-95):
/// selects the Appearance area and captures views of it: the top (as the
/// user first sees it), the shared colours (dark and light background), a
/// locked-colour state (a wave that is disabled on its background, focused so
/// its reason shows, UX-052), the overlay options and the floating button.
/// Survey tool, asserts nothing beyond its own setup. Tagged `ux-screens`,
/// never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_overlay_settings_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import 'ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const List<String> _themes = ['dark', 'navy'];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];

/// View name to the settings row that is scrolled into view (null = top).
const Map<String, String?> _views = {
  'top': null,
  'preview': 'appearance-overlay-preview',
  'colours': 'appearance-overlay-wave',
  'colours-light': 'appearance-overlay-wave',
  'colours-locked': 'appearance-overlay-wave',
  'options': 'appearance-overlay-form',
  'button': 'appearance-button-size',
};

/// Views that first switch the overlay background to the light Gletscher preset.
const Set<String> _lightViews = {'colours-light'};

/// The first background with a wave that is disabled on it, and that wave's
/// replacement as the selected one (the same choice a user's pick makes). The
/// locked view is built from this pair, so it cannot come out blank silently.
(OverlayBackground, OverlayWave) _lockedPair() {
  for (final background in OverlayBackground.values) {
    for (final wave in OverlayWave.values) {
      if (!wave.isValidOn(background)) {
        return (background, OverlayWave.cyan.validOn(background));
      }
    }
  }
  throw StateError('no wave is disabled on any background; nothing to show');
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final theme in _themes) {
        for (final locale in _locales) {
          for (final view in _views.entries) {
            final name =
                'overlay-wp95-${view.key}__${size.width.toInt()}x${size.height.toInt()}'
                '__s${scale.toString()}__${theme}_$locale';
            testWidgets('ux-overlay: $name', (tester) async {
              // The test default is Android; the floating button exists on
              // macOS and Windows only. Reset before the test ends (Flutter
              // checks foundation variables at the end of the body).
              debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
              final db = await openSeededUxDatabase(tester);
              addTearDown(() => tester.runAsync(db.close));

              final screen = UxScreen(
                id: 'overlay-wp95',
                activePageId: 'settings',
                build: () => const SettingsPage(),
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

              final container = ProviderScope.containerOf(
                tester.element(find.byType(SettingsPage)),
              );
              // The overlay lives in the Appearance area; select it through
              // the same provider the navigation uses.
              container
                  .read(settingsAreaProvider.notifier)
                  .select(SettingsArea.appearance);
              if (view.key == 'colours-locked') {
                final (background, wave) = _lockedPair();
                container
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWith(
                        overlayBackground: background.value,
                        overlayWave: wave.value,
                      ),
                    );
              }
              if (_lightViews.contains(view.key)) {
                container
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWith(
                        overlayBackground: OverlayBackground.gletscher.value,
                      ),
                    );
              }
              await tester.pump(const Duration(milliseconds: 300));

              final row = view.value;
              if (row != null) {
                final target = find.byKey(ValueKey('settings-row-$row'));
                if (target.evaluate().isNotEmpty) {
                  await tester.ensureVisible(target);
                  await tester.pump(const Duration(milliseconds: 300));
                }
              }

              if (view.key == 'colours-locked') {
                // Focus the disabled wave (a tap focuses it and never selects)
                // so its reason is on screen in the capture.
                final (background, _) = _lockedPair();
                final disabled = OverlayWave.values.firstWhere(
                  (w) => !w.isValidOn(background),
                );
                await tester.tap(
                  find.bySemanticsIdentifier('overlay-wave-${disabled.value}'),
                );
                await tester.pump(const Duration(milliseconds: 300));
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
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                Directory(outDir).createSync(recursive: true);
                File(
                  '$outDir/$name.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
              });

              await tester.pumpWidget(const SizedBox());
              await tester.pump(const Duration(seconds: 5));
              debugDefaultTargetPlatformOverride = null;
            });
          }
        }
      }
    }
  }
}
