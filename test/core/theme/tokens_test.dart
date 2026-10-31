import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';

void main() {
  group('WpSpacing', () {
    test('values are monotonically increasing', () {
      final values = [
        WpSpacing.xxs,
        WpSpacing.xs,
        WpSpacing.sm,
        WpSpacing.md,
        WpSpacing.lg,
        WpSpacing.xl,
        WpSpacing.xxl,
        WpSpacing.xxxl,
      ];
      for (var i = 1; i < values.length; i++) {
        expect(
          values[i],
          greaterThan(values[i - 1]),
          reason: 'Spacing scale must be strictly increasing at index $i',
        );
      }
    });

    test('smallest spacing is positive', () {
      expect(WpSpacing.xxs, greaterThan(0));
    });
  });

  group('WpRadius', () {
    test('numeric values are monotonically increasing (sm → xl)', () {
      final values = [WpRadius.sm, WpRadius.md, WpRadius.lg, WpRadius.xl];
      for (var i = 1; i < values.length; i++) {
        expect(
          values[i],
          greaterThan(values[i - 1]),
          reason: 'Radius scale must be strictly increasing at index $i',
        );
      }
    });

    test('full radius is very large (pill shape)', () {
      expect(WpRadius.full, greaterThanOrEqualTo(9999));
    });

    test('BorderRadius helpers match their numeric counterparts', () {
      expect(WpRadius.borderSm, BorderRadius.circular(WpRadius.sm));
      expect(WpRadius.borderMd, BorderRadius.circular(WpRadius.md));
      expect(WpRadius.borderLg, BorderRadius.circular(WpRadius.lg));
      expect(WpRadius.borderXl, BorderRadius.circular(WpRadius.xl));
      expect(WpRadius.borderFull, BorderRadius.circular(WpRadius.full));
    });
  });

  group('WpIconSize', () {
    test('all named sizes exist and increase', () {
      final values = [
        WpIconSize.xs,
        WpIconSize.sm,
        WpIconSize.md,
        WpIconSize.lg,
        WpIconSize.xl,
        WpIconSize.xxl,
      ];
      for (var i = 1; i < values.length; i++) {
        expect(
          values[i],
          greaterThan(values[i - 1]),
          reason: 'Icon size scale must be strictly increasing at index $i',
        );
      }
    });

    test('smallest icon size is positive', () {
      expect(WpIconSize.xs, greaterThan(0));
    });
  });

  group('WpShadows', () {
    test('shadow definitions are not empty', () {
      expect(WpShadows.card, isNotEmpty);
      expect(WpShadows.elevated, isNotEmpty);
    });

    test('elevated shadow has greater blur than card', () {
      final cardMaxBlur = WpShadows.card
          .map((s) => s.blurRadius)
          .reduce((a, b) => a > b ? a : b);
      final elevatedMaxBlur = WpShadows.elevated
          .map((s) => s.blurRadius)
          .reduce((a, b) => a > b ? a : b);
      expect(elevatedMaxBlur, greaterThan(cardMaxBlur));
    });
  });

  group('WpLayout', () {
    test('sidebar width is reasonable for labelled and icon-only rails', () {
      expect(WpLayout.sidebarWidth, greaterThanOrEqualTo(200));
      expect(WpLayout.sidebarWidth, lessThanOrEqualTo(260));
      expect(WpLayout.sidebarWidthCompact, greaterThanOrEqualTo(48));
      expect(WpLayout.sidebarWidthCompact, lessThanOrEqualTo(120));
    });

    test('status bar height is compact', () {
      expect(WpLayout.dockAreaHeight, greaterThan(0));
      expect(WpLayout.dockAreaHeight, lessThanOrEqualTo(120));
    });

    test('app bar height is reasonable', () {
      expect(WpLayout.appBarHeight, greaterThanOrEqualTo(40));
      expect(WpLayout.appBarHeight, lessThanOrEqualTo(80));
    });
  });

  group('WpMotion', () {
    test('all durations are positive', () {
      expect(WpMotion.fast.inMilliseconds, greaterThan(0));
      expect(WpMotion.normal.inMilliseconds, greaterThan(0));
      expect(WpMotion.smooth.inMilliseconds, greaterThan(0));
      expect(WpMotion.dramatic.inMilliseconds, greaterThan(0));
    });

    test('durations increase: fast < normal < smooth < dramatic', () {
      expect(WpMotion.fast, lessThan(WpMotion.normal));
      expect(WpMotion.normal, lessThan(WpMotion.smooth));
      expect(WpMotion.smooth, lessThan(WpMotion.dramatic));
    });

    test('curves are defined', () {
      expect(WpMotion.defaultCurve, isNotNull);
      expect(WpMotion.spring, isNotNull);
      expect(WpMotion.smooth_, isNotNull);
    });
  });
}
