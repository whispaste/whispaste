/// Focused UX harness for the recording dock (dictate keycap, dropdowns for
/// Smart Mode, speech engine, language, and the Mehr popup). The dock is laid
/// out at the full window width at the bottom of a neutral frame, the way the
/// app shell places it, and captured at the sweep sizes, scales, themes and
/// locales. Choices come from test fixtures (fixed labels), so this checks
/// layout and popups, not the production choice texts. Survey tool, asserts
/// nothing. Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_dock_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/services/microphone_selection_service.dart'
    show micDefaultLabel;
import 'package:whispaste/widgets/recording_dock.dart';

import '../features/settings/widgets/settings_golden_board.dart'
    show kSettingsGoldenSets;
import '../fixtures/dock_choice_fixtures.dart';
import '../fixtures/test_helpers.dart';
import 'ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const List<String> _themes = ['dark', 'navy'];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];

/// View name and the dock control to open before the capture (null = closed).
const List<(String, String?)> _views = [
  ('idle', null),
  ('smart-open', 'dock-smart-mode'),
  ('engine-open', 'dock-engine'),
  ('language-open', 'dock-language'),
  ('mehr-open', 'dock-overflow'),
];

WpRecordingDock _dock() => WpRecordingDock(
  sttModeLabel: 'Whisper · small',
  engine: dockTestEngine(label: 'Whisper · small'),
  sttState: SttServerState.ready,
  smartMode: dockTestSmartMode(label: 'Aus'),
  hotkeyLabel: 'Strg+Umschalt+D',
  onHotkeyTap: () {},
  microphoneLabel: micDefaultLabel,
  microphoneOptions: const [micDefaultLabel, 'USB-Mikrofon'],
  onMicrophoneChanged: (_) {},
  afterActionLabel: 'Kopieren',
  afterAction: AfterTranscriptionAction.clipboard,
  onAfterActionChanged: (_) {},
  language: dockTestLanguage(label: 'DE'),
  onSttTap: () {},
  backendKind: 'GPU',
  backendUtilizationPercent: 2,
  onSupportTap: () {},
);

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final theme in _themes) {
        for (final locale in _locales) {
          for (final (view, control) in _views) {
            final name =
                'dock-${view}__${size.width.toInt()}x${size.height.toInt()}'
                '__s${scale.toString()}__${theme}_$locale';
            testWidgets('ux-dock: $name', (tester) async {
              final db = await openSeededUxDatabase(tester);
              addTearDown(() => tester.runAsync(db.close));

              final set = kSettingsGoldenSets[theme]!;
              WpColors.activate(set);
              addTearDown(
                () => WpColors.activate(kSettingsGoldenSets['dark']!),
              );
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);

              await tester.pumpWidget(
                makeTestable(
                  Theme(
                    data: wpThemeFor(set),
                    child: Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: RepaintBoundary(
                          key: const ValueKey(kUxCaptureKey),
                          child: ColoredBox(
                            color: set.background,
                            child: SizedBox.expand(
                              // The dock menus are pushed as routes on the nearest Navigator; host one
                              // inside the capture boundary, or open menus are not in the PNG.
                              child: Navigator(
                                onGenerateRoute: (_) => PageRouteBuilder<void>(
                                  pageBuilder: (_, _, _) => Align(
                                    alignment: Alignment.bottomCenter,
                                    child: SizedBox(
                                      width: size.width,
                                      child: _dock(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  size: size,
                  locale: Locale(locale),
                  db: db,
                ),
              );
              await tester.pump(const Duration(milliseconds: 300));

              String? missing;
              if (control != null) {
                final target = find.byKey(ValueKey(control));
                if (target.evaluate().isNotEmpty) {
                  await tester.tap(target.first);
                  await tester.pumpAndSettle();
                  if (find
                      .byKey(const ValueKey('dock-menu-panel'))
                      .evaluate()
                      .isEmpty) {
                    missing = 'popup not open after tap: $control';
                  }
                } else {
                  missing = 'control not built: $control';
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
            });
          }
        }
      }
    }
  }
}
