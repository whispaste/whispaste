/// Tests for the full WhisPaste type scale.
///
/// Verifies:
/// 1. All required TextTheme roles are present in the dark and light themes
///    with the correct font size, weight, and tracking (AC1).
/// 2. Phase-2 ad-hoc TextStyles (Button-Label 16/700, Toast-Message 13/500)
///    are now served via theme roles instead of hard-coded values (AC2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/toast.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AC1: required roles present + correct metrics
  // ---------------------------------------------------------------------------

  group('TextTheme roles — dark theme', () {
    late TextTheme tt;

    setUpAll(() {
      tt = wpDarkTheme().textTheme;
    });

    // Previously-existing roles (regression guard)
    test('headlineLarge 22/700 ls:-0.60', () {
      expect(tt.headlineLarge!.fontSize, 22);
      expect(tt.headlineLarge!.fontWeight, FontWeight.w700);
      expect(tt.headlineLarge!.letterSpacing, closeTo(-0.6, 0.01));
    });

    test('headlineMedium 16/600 ls:-0.35', () {
      expect(tt.headlineMedium!.fontSize, 16);
      expect(tt.headlineMedium!.fontWeight, FontWeight.w600);
      expect(tt.headlineMedium!.letterSpacing, closeTo(-0.35, 0.01));
    });

    test('titleMedium 14/600', () {
      expect(tt.titleMedium!.fontSize, 14);
      expect(tt.titleMedium!.fontWeight, FontWeight.w600);
    });

    test('bodyLarge 13/400', () {
      expect(tt.bodyLarge!.fontSize, 13);
      expect(tt.bodyLarge!.fontWeight, FontWeight.w400);
    });

    test('labelSmall 11/500', () {
      expect(tt.labelSmall!.fontSize, 11);
      expect(tt.labelSmall!.fontWeight, FontWeight.w500);
    });

    // New roles (AC1)
    test('titleLarge 17/600 ls:-0.20 lh:1.3 — dialog / panel title', () {
      expect(tt.titleLarge!.fontSize, 17);
      expect(tt.titleLarge!.fontWeight, FontWeight.w600);
      expect(tt.titleLarge!.letterSpacing, closeTo(-0.2, 0.01));
      expect(tt.titleLarge!.height, closeTo(1.3, 0.01));
    });

    test('titleSmall 13/600 ls:-0.10 lh:1.4 — form field label', () {
      expect(tt.titleSmall!.fontSize, 13);
      expect(tt.titleSmall!.fontWeight, FontWeight.w600);
      expect(tt.titleSmall!.letterSpacing, closeTo(-0.1, 0.01));
      expect(tt.titleSmall!.height, closeTo(1.4, 0.01));
    });

    test('labelLarge 16/700 ls:-0.30 — button label (AC2 role)', () {
      expect(tt.labelLarge!.fontSize, 16);
      expect(tt.labelLarge!.fontWeight, FontWeight.w700);
      expect(tt.labelLarge!.letterSpacing, closeTo(-0.3, 0.01));
    });

    test('labelMedium 13/500 lh:1.4 — toast / snackbar message (AC2 role)', () {
      expect(tt.labelMedium!.fontSize, 13);
      expect(tt.labelMedium!.fontWeight, FontWeight.w500);
      expect(tt.labelMedium!.height, closeTo(1.4, 0.01));
    });
  });

  group('TextTheme roles — light theme (parity check)', () {
    late TextTheme tt;

    setUpAll(() {
      tt = wpLightTheme().textTheme;
    });

    test('labelLarge 16/700 present', () {
      expect(tt.labelLarge!.fontSize, 16);
      expect(tt.labelLarge!.fontWeight, FontWeight.w700);
    });

    test('labelMedium 13/500 present', () {
      expect(tt.labelMedium!.fontSize, 13);
      expect(tt.labelMedium!.fontWeight, FontWeight.w500);
    });

    test('titleLarge 17/600 present', () {
      expect(tt.titleLarge!.fontSize, 17);
      expect(tt.titleLarge!.fontWeight, FontWeight.w600);
    });

    test('titleSmall 13/600 present', () {
      expect(tt.titleSmall!.fontSize, 13);
      expect(tt.titleSmall!.fontWeight, FontWeight.w600);
    });
  });

  // ---------------------------------------------------------------------------
  // AC2: ad-hoc call sites now use theme roles
  // ---------------------------------------------------------------------------

  group('WpAccentButton uses textTheme.labelLarge', () {
    testWidgets('button label inherits size + weight from labelLarge', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpAccentButton(
            label: 'Start',
            gradient: const LinearGradient(
              colors: [Color(0xFF38D9F0), Color(0xFF0887A8)],
            ),
            onPressed: () {},
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('Start'));
      final resolvedStyle = textWidget.style!.copyWith();

      // Verify the style properties match labelLarge (16 / w700 / ls -0.3).
      expect(resolvedStyle.fontSize, 16);
      expect(resolvedStyle.fontWeight, FontWeight.w700);
      expect(resolvedStyle.letterSpacing, closeTo(-0.3, 0.01));
      // Color override: always white on gradient background.
      expect(resolvedStyle.color, Colors.white);
    });
  });

  group('WpToast uses textTheme.labelMedium', () {
    testWidgets('toast message inherits size + weight from labelMedium', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late BuildContext capturedContext;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return ElevatedButton(
                onPressed: () => WpToast.show(
                  ctx,
                  message: 'Saved',
                  type: WpToastType.success,
                ),
                child: const Text('trigger'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // The toast message Text is rendered in the overlay.
      final toastText = tester.widget<Text>(find.text('Saved'));
      final style = toastText.style!;

      // Verify it matches labelMedium (13 / w500) with compact height override.
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w500);
      // height override: 1.3 (compact toast card).
      expect(style.height, closeTo(1.3, 0.01));

      // capturedContext used only for type inference, avoid unused-var warning.
      expect(capturedContext, isNotNull);

      // Drain auto-dismiss timer + reverse animation so no ticker outlives the
      // test (mirrors the pattern in test/widgets/toast_test.dart).
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });
}
