/// UX probe: onboarding step "Erscheinungsbild" (the background swatch row).
/// Advances the real onboarding overlay to the appearance step, measures the
/// swatch targets (WCAG 2.5.8) and writes a PNG and a report per variant.
///
/// Tagged `ux-screens` (not part of the normal suite). Run on the Mac:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens test/ux_audit/ux_onboarding_appearance_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/features/onboarding/steps/appearance_step.dart';

import '../features/settings/widgets/settings_golden_board.dart';
import '../fixtures/test_helpers.dart';

class _MockSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

const _sizes = <Size>[Size(800, 716), Size(1100, 720)];

/// Pumps the onboarding, advances to the appearance step (index 4 = 5th step)
/// and returns whether the step was reached.
Future<bool> _pumpToAppearance(
  WidgetTester tester,
  Size size, {
  required String theme,
  required String locale,
  required double scale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  WpColors.activate(kSettingsGoldenSets[theme]!);
  addTearDown(() => WpColors.activate(kSettingsGoldenSets['dark']!));

  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: const OnboardingOverlay(),
        ),
      ),
      size: size,
      locale: Locale(locale),
      overrides: [settingsProvider.overrideWith(_MockSettings.new)],
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));

  for (var i = 0; i < 4; i++) {
    await tester.tap(find.byKey(kOnboardingNextButtonKey));
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pump(const Duration(milliseconds: 400));
  return find.byKey(kAppearanceStepOverlayColorsKey).evaluate().isNotEmpty;
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? '.scratch/ux-review/screens';

  for (final size in _sizes) {
    for (final theme in const ['dark', 'navy']) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            'onboarding-appearance_${size.width.toInt()}x${size.height.toInt()}'
            '_s${scale.toString()}_$theme';
        testWidgets('ux-onboarding-appearance $name', (tester) async {
          final reached = await _pumpToAppearance(
            tester,
            size,
            theme: theme,
            locale: 'de',
            scale: scale,
          );

          final report = StringBuffer()
            ..writeln('variant: $name')
            ..writeln('appearance step reached: $reached');

          if (reached) {
            final row = find.byKey(kAppearanceStepOverlayColorsKey);
            final targets = find.descendant(
              of: row,
              matching: find.byType(InkWell),
            );
            report.writeln('swatch row: ${tester.getRect(row)}');
            for (var i = 0; i < targets.evaluate().length; i++) {
              final r = tester.getRect(targets.at(i));
              report.writeln(
                'target $i: ${r.width.toStringAsFixed(0)}x'
                '${r.height.toStringAsFixed(0)} px at ${r.topLeft}',
              );
            }
          }

          await tester.runAsync(() async {
            final layer =
                tester.binding.renderViews.first.debugLayer! as OffsetLayer;
            final image = await layer.toImage(Offset.zero & size);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            Directory(outDir).createSync(recursive: true);
            File(
              '$outDir/$name.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            File('$outDir/$name.txt').writeAsStringSync(report.toString());
          });

          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }
}
