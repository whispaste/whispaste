// Motion-system tests for WpMotion.
//
// Covers:
//   AC1 — spring is a critically-damped approximation (no overshoot)
//   AC3 — reduced-motion: durationFor returns Duration.zero when
//          MediaQuery.disableAnimations is true
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';

void main() {
  group('WpMotion.spring — no overshoot', () {
    test('spring curve value never exceeds 1.0 (no bouncing)', () {
      for (var i = 0; i <= 200; i++) {
        final t = i / 200.0;
        final v = WpMotion.spring.transform(t);
        expect(
          v,
          lessThanOrEqualTo(1.0 + 1e-9),
          reason: 'spring must not overshoot at t=$t (value: $v)',
        );
      }
    });

    test('spring curve value never goes below 0.0', () {
      for (var i = 0; i <= 200; i++) {
        final t = i / 200.0;
        final v = WpMotion.spring.transform(t);
        expect(
          v,
          greaterThanOrEqualTo(-1e-9),
          reason: 'spring must not go negative at t=$t (value: $v)',
        );
      }
    });

    test('spring curve is monotonically non-decreasing', () {
      double prev = 0.0;
      for (var i = 0; i <= 200; i++) {
        final t = i / 200.0;
        final v = WpMotion.spring.transform(t);
        expect(
          v,
          greaterThanOrEqualTo(prev - 1e-9),
          reason: 'spring must not decrease at t=$t (prev=$prev, curr=$v)',
        );
        prev = v;
      }
    });

    test('spring curve reaches 1.0 at t=1.0', () {
      final v = WpMotion.spring.transform(1.0);
      expect(v, closeTo(1.0, 1e-9));
    });

    test('spring curve starts at 0.0 at t=0.0', () {
      final v = WpMotion.spring.transform(0.0);
      expect(v, closeTo(0.0, 1e-9));
    });
  });

  group('WpMotion.springDescription — Phase-0 Gentle 170/26', () {
    test('mass is 1', () {
      expect(WpMotion.springDescription.mass, equals(1.0));
    });

    test('stiffness is 170 (snap characteristic)', () {
      expect(WpMotion.springDescription.stiffness, equals(170.0));
    });

    test('damping is 26 (critically damped, ratio ≈ 1.0)', () {
      expect(WpMotion.springDescription.damping, equals(26.0));
    });

    test('damping ratio is approximately 1.0 (no overshoot)', () {
      // ratio = damping / (2 * sqrt(stiffness * mass))
      const d = WpMotion.springDescription;
      final ratio = d.damping / (2.0 * math.sqrt(d.stiffness * d.mass));
      // Accept ±2 % tolerance for the "critically damped" classification
      expect(ratio, closeTo(1.0, 0.02));
    });
  });

  group('WpMotion.durationFor — reduced-motion', () {
    testWidgets(
      'returns Duration.zero when MediaQuery.disableAnimations is true',
      (tester) async {
        late Duration result;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                result = WpMotion.durationFor(context, WpMotion.normal);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(result, equals(Duration.zero));
      },
    );

    testWidgets(
      'returns the original duration when disableAnimations is false',
      (tester) async {
        late Duration result;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: false),
            child: Builder(
              builder: (context) {
                result = WpMotion.durationFor(context, WpMotion.normal);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(result, equals(WpMotion.normal));
      },
    );

    testWidgets('reduces fast, smooth, and dramatic durations equally', (
      tester,
    ) async {
      final results = <Duration>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              results
                ..add(WpMotion.durationFor(context, WpMotion.fast))
                ..add(WpMotion.durationFor(context, WpMotion.smooth))
                ..add(WpMotion.durationFor(context, WpMotion.dramatic));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(results, everyElement(equals(Duration.zero)));
    });
  });
}
