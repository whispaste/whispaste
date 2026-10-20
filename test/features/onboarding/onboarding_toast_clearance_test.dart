/// An actionable toast rises above the onboarding navigation row instead of
/// covering the "Weiter" button, so the flow can still be advanced while the
/// toast is visible (UX-044).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';
import 'package:whispaste/widgets/toast.dart';

import '../../fixtures/test_helpers.dart';
import '../settings/widgets/settings_golden_board.dart';

class _MockSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

const _sizes = <Size>[Size(800, 716), Size(1100, 720), Size(1440, 900)];

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

  for (final size in _sizes) {
    testWidgets(
      'Weiter advances the flow with an actionable toast up at $size',
      (tester) async {
        await _pump(tester, size);

        final context = tester.element(find.byType(OnboardingOverlay));
        WpToast.show(
          context,
          message: 'Die Aufnahme konnte nicht eingefügt werden.',
          type: WpToastType.error,
          action: WpToastAction(
            label: 'Erneut versuchen',
            onPressed: () {},
            testId: 'clearance-toast-action',
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final next = tester.getRect(find.byKey(kOnboardingNextButtonKey));
        final toastAction = tester.getRect(
          find.byKey(const ValueKey('clearance-toast-action')),
        );
        expect(
          toastAction.overlaps(next),
          isFalse,
          reason: 'The toast action must sit above the navigation row.',
        );

        await tester.tap(find.byKey(kOnboardingNextButtonKey));
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.textContaining('Schritt 2 von'),
          findsOneWidget,
          reason: 'Weiter must stay tappable while the toast is visible.',
        );

        // Drain the 10 s actionable timer so no timer outlives the test.
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
