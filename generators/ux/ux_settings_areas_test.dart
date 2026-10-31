/// Focused UX harness for the settings areas changed after 12f23c015 (shortcuts
/// with the quick-note block and push-to-talk reason, speech with the inline
/// benchmark, text insertion with the blocklist copy switch). Each view selects
/// one area and scrolls its target row into view, then captures the frame at the
/// sweep sizes, scales, themes and locales. Survey tool, asserts nothing. Tagged
/// `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_settings_areas_test.dart
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
import 'package:whispaste/features/settings/settings_areas.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const List<String> _themes = ['dark', 'navy'];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];

/// View name, area and the key of the row to scroll to (null = top).
const List<(String, SettingsArea, String?)> _views = [
  ('shortcuts-top', SettingsArea.shortcuts, null),
  ('shortcuts-quicknote', SettingsArea.shortcuts, 'quickNoteHotkeyBlock'),
  (
    'shortcuts-ptt',
    SettingsArea.shortcuts,
    'settings-row-general-hold-to-record',
  ),
  ('speech-top', SettingsArea.speech, null),
  ('speech-benchmark', SettingsArea.speech, 'settings-benchmark-run'),
  ('textinsert-top', SettingsArea.textInsert, null),
  (
    'textinsert-blocklist',
    SettingsArea.textInsert,
    'text-auto-paste-blocklist-copy-toggle',
  ),
];

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final theme in _themes) {
        for (final locale in _locales) {
          for (final (view, area, rowKey) in _views) {
            final name =
                'settings-${view}__${size.width.toInt()}x${size.height.toInt()}'
                '__s${scale.toString()}__${theme}_$locale';
            testWidgets('ux-settings-area: $name', (tester) async {
              debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
              final db = await openSeededUxDatabase(tester);
              addTearDown(() => tester.runAsync(db.close));

              final screen = UxScreen(
                id: 'settings-$view',
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
              container.read(settingsAreaProvider.notifier).select(area);
              await tester.pump(const Duration(milliseconds: 300));

              String? missing;
              if (rowKey != null) {
                final target = find.byKey(ValueKey(rowKey));
                final rawTarget = find.byKey(Key(rowKey));
                final hit = target.evaluate().isNotEmpty ? target : rawTarget;
                if (hit.evaluate().isNotEmpty) {
                  await tester.ensureVisible(hit.first);
                  await tester.pump(const Duration(milliseconds: 300));
                } else {
                  missing = 'row key not built: $rowKey';
                }
              }

              final error = tester.takeException();
              Directory(outDir).createSync(recursive: true);
              if (missing != null) {
                File(
                  '$outDir/exceptions.log',
                ).writeAsStringSync('$name: $missing\n', mode: FileMode.append);
              }
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
              await tester.pump(const Duration(seconds: 5));
              debugDefaultTargetPlatformOverride = null;
            });
          }
        }
      }
    }
  }
}
