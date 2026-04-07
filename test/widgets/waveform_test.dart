import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/waveform.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpWaveform', () {
    testWidgets('renders without errors at zero level', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 0.0),
      ));
      expect(find.byType(WpWaveform), findsOneWidget);
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('renders at full level', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 1.0),
      ));
      expect(find.byType(WpWaveform), findsOneWidget);
    });

    testWidgets('respects custom bar count', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 0.5, barCount: 16),
      ));
      expect(find.byType(WpWaveform), findsOneWidget);
    });

    testWidgets('inactive state renders without animation', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 0.5, isActive: false),
      ));
      expect(find.byType(WpWaveform), findsOneWidget);
    });

    testWidgets('custom colors are accepted', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveform(
          audioLevel: 0.5,
          color: Colors.red,
          inactiveColor: Colors.grey,
        ),
      ));
      expect(find.byType(WpWaveform), findsOneWidget);
    });

    testWidgets('handles level transition gracefully', (tester) async {
      // Start at silence
      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 0.0, isActive: true),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // Jump to peak
      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 1.0, isActive: true),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(WpWaveform), findsOneWidget);
    });

    testWidgets('transitions from active to inactive', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 0.8, isActive: true),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(makeTestable(
        const WpWaveform(audioLevel: 0.8, isActive: false),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(WpWaveform), findsOneWidget);
    });
  });

  group('WpWaveformBadge', () {
    testWidgets('renders compact variant', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveformBadge(audioLevel: 0.5),
      ));
      expect(find.byType(WpWaveformBadge), findsOneWidget);
      expect(find.byType(WpWaveform), findsOneWidget);
    });

    testWidgets('supports inactive state', (tester) async {
      await tester.pumpWidget(makeTestable(
        const WpWaveformBadge(audioLevel: 0.3, isActive: false),
      ));
      expect(find.byType(WpWaveformBadge), findsOneWidget);
    });
  });
}
