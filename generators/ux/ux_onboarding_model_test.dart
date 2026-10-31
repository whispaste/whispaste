/// Focused UX harness for the onboarding model step (UX-081): the idle page and
/// the download-error page, at the two guard window sizes, text scales 1.0,
/// 1.3 and 2.0, in de and he. The error page is the one with the fixed
/// spacing per language that UX-081 asks to measure. Survey tool, asserts
/// nothing: layout exceptions go to exceptions.log, PNGs to the output dir.
/// Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_onboarding_model_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;

import '../../test/ux_audit/ux_fixtures.dart';

const List<double> _scales = [1.0, 1.3, 2.0];
const List<String> _locales = ['de', 'he'];
const List<Size> _sizes = [kUxSizeMinimum, kUxSize1100];
const String _theme = 'dark'; // the onboarding stage, see DESIGN.md

const UxOnboardingStep _model = UxOnboardingStep('onboarding-1-welcome', 0);

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final locale in _locales) {
        for (final failed in [false, true]) {
          final state = failed ? 'model-error' : 'model-idle';
          final name =
              'onboarding-model-${state}__${size.width.toInt()}x${size.height.toInt()}'
              '__s${scale.toString()}__stage_$locale';
          testWidgets('ux-onboarding-model: $name', (tester) async {
            final db = await openSeededUxDatabase(tester);
            addTearDown(() => tester.runAsync(db.close));

            final errors = await pumpUxOnboarding(
              tester,
              step: _model,
              db: db,
              size: size,
              scale: scale,
              theme: _theme,
              locale: locale,
              downloadFailed: failed,
              openModelFromStart: true,
            );

            final error = tester.takeException();
            Directory(outDir).createSync(recursive: true);
            final log = [
              for (final e in errors) '$name: $e',
              if (error != null) '$name: $error',
            ];
            if (log.isNotEmpty) {
              File(
                '$outDir/exceptions.log',
              ).writeAsStringSync('${log.join('\n')}\n', mode: FileMode.append);
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
