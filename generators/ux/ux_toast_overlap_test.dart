/// UX probe: an actionable toast (minimum 10 s, bottom-right, 56 px above the
/// window edge) over the real onboarding overlay. Measures the rectangles of
/// the toast and the onboarding "next" button, taps the button once with and
/// once without the toast, and writes the numbers and a PNG to the output dir.
///
/// Tagged `ux-screens` (not part of the normal suite). Run on the Mac:
///
///   UX_SCREENS_DIR=OUT_DIR flutter test --tags=ux-screens generators/ux/ux_toast_overlap_test.dart
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
import 'package:whispaste/widgets/toast.dart';
import 'package:whispaste/widgets/wp_touch_target.dart';

import '../../test/features/settings/widgets/settings_golden_board.dart';
import '../../test/fixtures/test_helpers.dart';

class _MockSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

const _sizes = <Size>[Size(800, 716), Size(1100, 720), Size(1440, 900)];

/// Pumps the onboarding at [size]; returns after the first frames.
Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  WpColors.activate(kSettingsGoldenSets['dark']!);
  await tester.pumpWidget(
    makeTestable(
      const OnboardingOverlay(),
      size: size,
      locale: const Locale('de'),
      overrides: [settingsProvider.overrideWith(_MockSettings.new)],
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async => loadAppFonts());

  final outDir =
      Platform.environment['UX_SCREENS_DIR'] ?? 'internal-notes';

  // Control: without a toast the next button moves the flow on.
  testWidgets('ux-toast-overlap control 1100x720', (tester) async {
    await _pump(tester, const Size(1100, 720));
    await tester.tap(find.byKey(kOnboardingNextButtonKey));
    await tester.pump(const Duration(milliseconds: 600));
    final moved = find.textContaining('Schritt 2 von').evaluate().isNotEmpty;
    Directory(outDir).createSync(recursive: true);
    File('$outDir/toast-overlap_control.txt').writeAsStringSync(
      'control (no toast): next button advanced the flow = $moved\n',
    );
    expect(moved, isTrue);
  });

  for (final size in _sizes) {
    final name = 'toast-overlap_${size.width.toInt()}x${size.height.toInt()}';
    testWidgets('ux-toast-overlap $name', (tester) async {
      await _pump(tester, size);

      final context = tester.element(find.byType(OnboardingOverlay));
      WpToast.show(
        context,
        message: 'Die Aufnahme konnte nicht eingefügt werden.',
        type: WpToastType.error,
        action: WpToastAction(
          label: 'Erneut versuchen',
          onPressed: () {},
          testId: 'ux-toast-action',
        ),
      );
      // Two pumps: the first frame starts the animation ticker, the second
      // one advances it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final next = tester.getRect(find.byKey(kOnboardingNextButtonKey));
      final toast = tester.getRect(
        find.byWidgetPredicate((w) => w is Positioned && w.bottom == 56),
      );
      final close = tester.getRect(
        find
            .descendant(
              of: find.byType(WpTouchTarget).last,
              matching: find.byType(InkWell),
            )
            .first,
      );
      final action = tester.getRect(
        find.byKey(const ValueKey('ux-toast-action')),
      );
      final overlap = toast.overlaps(next) ? toast.intersect(next) : Rect.zero;

      // Tap the centre of the next button while the toast is up.
      await tester.tap(find.byKey(kOnboardingNextButtonKey));
      await tester.pump(const Duration(milliseconds: 600));
      final movedWithToast = find
          .textContaining('Schritt 2 von')
          .evaluate()
          .isNotEmpty;

      final report = StringBuffer()
        ..writeln('window: $size')
        ..writeln('onboarding next button: $next')
        ..writeln('toast card: $toast')
        ..writeln(
          'close target: $close (${close.width.toStringAsFixed(0)}x${close.height.toStringAsFixed(0)} px)',
        )
        ..writeln(
          'action button: $action, gap to close target: ${(close.left - action.right).toStringAsFixed(1)} px',
        )
        ..writeln(
          'overlap: $overlap (height ${overlap.height.toStringAsFixed(1)} px '
          'of ${next.height.toStringAsFixed(1)} px button)',
        )
        ..writeln(
          'tap on next button with toast advanced the flow = $movedWithToast',
        );

      await tester.runAsync(() async {
        final view = tester.binding.renderViews.first;
        final layer = view.debugLayer! as OffsetLayer;
        final image = await layer.toImage(Offset.zero & size);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(outDir).createSync(recursive: true);
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        File('$outDir/$name.txt').writeAsStringSync(report.toString());
      });

      // Let the 10 s actionable timer run out, then tear down cleanly.
      await tester.pump(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
