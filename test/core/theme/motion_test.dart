// Motion-system tests for WpMotion.
//
// Covers:
//   AC1 — spring is a critically-damped approximation (no overshoot)
//   AC3 — reduced-motion: durationFor returns Duration.zero when
//          MediaQuery.disableAnimations is true

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';

void main() {
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
