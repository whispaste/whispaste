/// Focused UX harness for the still clips (decision 7b): beats 2 (speech model)
/// and 4 (auto-paste) inside the onboarding overlay. The hotkey page has no
/// clip,
/// where the fill-column height budget decides whether the clip is shown.
/// Sizes include one below the 716 px design minimum, which the work-area cap
/// now allows on small displays. Survey tool, asserts nothing: per case it
/// logs whether the step is reached, whether the clip is shown and its size,
/// and whether the Next button stays inside the viewport. Layout exceptions go
/// to exceptions.log, PNGs to the output dir. Tagged `ux-screens`, never in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_onboarding_motion_wire_test.dart
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
import 'package:whispaste/features/onboarding/steps/onboarding_motion_clip.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const String _theme = 'navy';

const List<Size> _sizes = [
  kUxSizeMinimum, // 800x716, design minimum
  kUxSize1100, // 1100x720
  Size(1100, 800), // requested check size
  Size(800, 640), // below the minimum, as a small work area allows
];

const List<double> _scalesMotion = [1.0, 2.0];

/// (step, beat, open the speech model from the start page): the speech model
/// is beat 2 (reached from the start page), access beat 4.
const List<(UxOnboardingStep, int, bool)> _cases = [
  (UxOnboardingStep('onboarding-1-welcome', 0), 2, true),
  (UxOnboardingStep('onboarding-2-access', 1), 4, false),
];

void _log(String outDir, String file, String line) {
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$file').writeAsStringSync('$line\n', mode: FileMode.append);
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 800)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void _case({
  required String outDir,
  required UxOnboardingStep step,
  required int beat,
  required bool openModel,
  required Size size,
  required double scale,
  required String locale,
}) {
  final name =
      '${step.id}-beat$beat'
      '__${size.width.toInt()}x${size.height.toInt()}'
      '__s${scale.toString()}__${_theme}_$locale';

  testWidgets('ux-motion-wire: $name', (tester) async {
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
      openModelFromStart: openModel,
    );
    await _settleImages(tester);

    final reached = find
        .byWidgetPredicate((w) => w is OnboardingMotionStep && w.beat == beat)
        .evaluate()
        .isNotEmpty;

    final clipFinder = find.byWidgetPredicate(
      (w) => w is OnboardingMotionClip && w.beat == beat,
    );
    final clipShown = clipFinder.evaluate().isNotEmpty;
    var clipSize = '-';
    if (clipShown) {
      final s = tester.getSize(clipFinder);
      clipSize = '${s.width.toStringAsFixed(0)}x${s.height.toStringAsFixed(0)}';
    }

    var nextBottom = '-';
    var fits = '-';
    final nextFinder = find.byKey(kOnboardingNextButtonKey);
    if (nextFinder.evaluate().isNotEmpty) {
      final bottom = tester.getRect(nextFinder).bottom;
      nextBottom = bottom.toStringAsFixed(0);
      fits = bottom <= size.height ? 'yes' : 'NO';
    }

    final error = tester.takeException();
    final log = [
      for (final e in errors) '$name: $e',
      if (error != null) '$name: $error',
    ];
    for (final line in log) {
      _log(outDir, 'exceptions.log', line);
    }
    _log(
      outDir,
      'motion-wire-measure.log',
      '$name | reached=$reached | clip=$clipShown $clipSize | '
          'nextBottom=$nextBottom of ${size.height.toInt()} | fits=$fits',
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

  for (final (step, beat, openModel) in _cases) {
    for (final size in _sizes) {
      for (final scale in _scalesMotion) {
        for (final locale in const ['de', 'he']) {
          _case(
            outDir: outDir,
            step: step,
            beat: beat,
            openModel: openModel,
            size: size,
            scale: scale,
            locale: locale,
          );
        }
      }
    }
    // Text scale 1.3 at the two guard sizes.
    for (final size in const [kUxSizeMinimum, kUxSize1100]) {
      _case(
        outDir: outDir,
        step: step,
        beat: beat,
        openModel: openModel,
        size: size,
        scale: 1.3,
        locale: 'de',
      );
    }
  }
}
