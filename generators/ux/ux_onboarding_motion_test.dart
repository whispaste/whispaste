/// Focused UX harness for the onboarding still clips (decision 7b): the Start
/// page and the access page's clip in the three themes (hell, dunkel, marine),
/// at text scales 1.0 and 2.0 in de. Survey tool, asserts nothing: layout
/// exceptions and whether the access page was reached go to the log files;
/// PNGs go to the output dir. Tagged `ux-screens`, never run in CI.
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_onboarding_motion_test.dart
@Tags(<String>['ux-screens'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/features/onboarding/steps/access_mic_step.dart';

import '../../test/ux_audit/ux_fixtures.dart';

const List<double> _scales = [1.0, 2.0];
const String _locale = 'de';

/// Theme name in the harness → onboarding beat variant (hell/dunkel/marine).
const Map<String, String> _themes = {
  'light': 'hell',
  'dark': 'dunkel',
  'navy': 'marine',
};

const UxOnboardingStep _welcome = UxOnboardingStep('onboarding-1-welcome', 0);
// Access is the fourth page in the current flow (welcome, speech, hotkey,
// access). Paging there needs the earlier pages to pass their Next gate.
const UxOnboardingStep _access = UxOnboardingStep('onboarding-2-access', 1);

Future<void> _settleImages(WidgetTester tester) async {
  // Image.asset decodes on the real event loop; give it time before capture.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 800)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void _log(String outDir, String file, String line) {
  Directory(outDir).createSync(recursive: true);
  File('$outDir/$file').writeAsStringSync('$line\n', mode: FileMode.append);
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  for (final theme in _themes.keys) {
    for (final scale in _scales) {
      for (final step in [_welcome, _access]) {
        final name =
            '${step.id}__${kUxOnboardingSize.width.toInt()}x'
            '${kUxOnboardingSize.height.toInt()}__s${scale.toString()}__'
            '${theme}_$_locale';
        testWidgets('ux-onboarding-still: $name', (tester) async {
          final db = await openSeededUxDatabase(tester);
          addTearDown(() => tester.runAsync(db.close));

          final errors = await pumpUxOnboarding(
            tester,
            step: step,
            db: db,
            size: kUxOnboardingSize,
            scale: scale,
            theme: theme,
            locale: _locale,
            passSpeechGate: true,
          );
          await _settleImages(tester);

          if (step == _access) {
            final reached = find.byType(AccessMicStep).evaluate().isNotEmpty;
            _log(outDir, 'access-reached.log', '$name: reached=$reached');
          }
          final error = tester.takeException();
          final log = [
            for (final e in errors) '$name: $e',
            if (error != null) '$name: $error',
          ];
          for (final line in log) {
            _log(outDir, 'exceptions.log', line);
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
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }
}
