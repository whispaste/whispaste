/// Survey of every onboarding step in the small work areas 1024x600 and
/// 1280x680 (UX-090 / UX-091 follow-up). Text scales 1.5 and 1.6 sit on both
/// sides of the compact-header threshold (kOnboardingCompactTextScale = 1.6),
/// 2.0 is the largest scale. Asserts nothing: per case it logs whether the
/// Next button stays inside the viewport, whether the compact header is in
/// use, whether the motion clip is shown, and any layout exception. PNGs go to
/// the output dir. Tagged `ux-screens`, never in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_onboarding_small_work_area_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/features/onboarding/onboarding_overlay.dart'
    show kOnboardingNextButtonKey;
import 'package:whispaste/features/onboarding/steps/onboarding_page_fill.dart'
    show kOnboardingCompactSubtitleKey;

import '../../test/ux_audit/ux_fixtures.dart';

const String _theme = 'navy';

const List<Size> _sizes = [Size(1024, 600), Size(1280, 680)];

/// (scale, locale) pairs: 1.5 and 1.6 around the compact threshold, 2.0 largest.
const List<(double, String)> _variants = [
  (1.5, 'de'),
  (1.6, 'de'),
  (2.0, 'de'),
  (2.0, 'he'),
];

void _log(String outDir, String file, String line) {
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$file').writeAsStringSync('$line\n', mode: FileMode.append);
}

void _case({
  required String outDir,
  required UxOnboardingStep step,
  required Size size,
  required double scale,
  required String locale,
}) {
  final name =
      '${step.id}__${size.width.toInt()}x${size.height.toInt()}'
      '__s${scale.toString()}__${_theme}_$locale';

  testWidgets('ux-onboarding-small: $name', (tester) async {
    final db = await openSeededUxDatabase(tester);
    addTearDown(() => tester.runAsync(db.close));

    final errors = await pumpUxOnboarding(
      tester,
      step: step,
      db: db,
      size: size,
      scale: scale,
      theme: _theme,
      locale: locale,
      passSpeechGate: true,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    var nextBottom = '-';
    var fits = '-';
    final nextFinder = find.byKey(kOnboardingNextButtonKey);
    if (nextFinder.evaluate().isNotEmpty) {
      final bottom = tester.getRect(nextFinder).bottom;
      nextBottom = bottom.toStringAsFixed(0);
      fits = bottom <= size.height ? 'yes' : 'NO';
    }
    final compact =
        find.byKey(kOnboardingCompactSubtitleKey).evaluate().isNotEmpty
        ? 'compact'
        : 'full';
    final scrollables = find.byType(Scrollable).evaluate().length;

    final error = tester.takeException();
    for (final e in [
      for (final e in errors) '$name: $e',
      if (error != null) '$name: $error',
    ]) {
      _log(outDir, 'exceptions.log', e);
    }
    _log(
      outDir,
      'small-area-measure.log',
      '$name | header=$compact | nextBottom=$nextBottom of '
          '${size.height.toInt()} | fits=$fits | scrollables=$scrollables',
    );

    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey(kUxCaptureKey)),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final step in kUxOnboardingSteps) {
    for (final size in _sizes) {
      for (final (scale, locale) in _variants) {
        _case(
          outDir: outDir,
          step: step,
          size: size,
          scale: scale,
          locale: locale,
        );
      }
    }
  }
}
