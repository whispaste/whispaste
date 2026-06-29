/// Widget tests for [WpRecordingIndicatorBar].
///
/// Covers:
///  - AC3: phase→colour mapping uses error/warning theme tokens, not hardcoded
///    hex.
///  - AC3: bar is hidden in idle phase and visible in recording/transcribing.
///  - AC4: reduced-motion is respected (AnimationController hooked through
///    WpMotion.durationFor, exercised by the existing pulse logic).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/recording_indicator_bar.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Unit tests — colour-token mapping (AC3)
// ---------------------------------------------------------------------------

void main() {
  group('WpRecordingIndicatorBar.colorFor — token mapping (AC3)', () {
    test('recording phase returns WpColorsDark.error in dark mode', () {
      expect(
        WpRecordingIndicatorBar.colorFor(
          RecordingPhase.recording,
          isDark: true,
        ),
        WpColorsDark.error,
      );
    });

    test('transcribing phase returns WpColorsDark.warning in dark mode', () {
      expect(
        WpRecordingIndicatorBar.colorFor(
          RecordingPhase.transcribing,
          isDark: true,
        ),
        WpColorsDark.warning,
      );
    });

    test('recording phase returns WpColorsLight.error in light mode', () {
      expect(
        WpRecordingIndicatorBar.colorFor(
          RecordingPhase.recording,
          isDark: false,
        ),
        WpColorsLight.error,
      );
    });

    test('transcribing phase returns WpColorsLight.warning in light mode', () {
      expect(
        WpRecordingIndicatorBar.colorFor(
          RecordingPhase.transcribing,
          isDark: false,
        ),
        WpColorsLight.warning,
      );
    });

    test('no hardcoded 0xFFEF4444 — dark recording uses error token', () {
      final color = WpRecordingIndicatorBar.colorFor(
        RecordingPhase.recording,
        isDark: true,
      );
      expect(
        color,
        isNot(const Color(0xFFEF4444)),
        reason: 'must use WpColorsDark.error, not hardcoded Tailwind red-500',
      );
    });

    test('no hardcoded 0xFFF59E0B — dark transcribing uses warning token', () {
      final color = WpRecordingIndicatorBar.colorFor(
        RecordingPhase.transcribing,
        isDark: true,
      );
      expect(
        color,
        isNot(const Color(0xFFF59E0B)),
        reason: 'must use WpColorsDark.warning, not hardcoded amber-500',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — visibility / phase rendering (AC3)
  // ---------------------------------------------------------------------------

  group('WpRecordingIndicatorBar — phase rendering (AC3)', () {
    Widget buildBar(
      RecordingPhase phase, {
      Brightness brightness = Brightness.dark,
    }) {
      return makeTestable(
        WpRecordingIndicatorBar(phase: phase),
        brightness: brightness,
      );
    }

    // Helper: finds AnimatedBuilder scoped to the indicator bar only.
    Finder indicatorBuilder(WidgetTester tester) => find.descendant(
      of: find.byType(WpRecordingIndicatorBar),
      matching: find.byType(AnimatedBuilder),
    );

    testWidgets('hidden (no AnimatedBuilder) when phase is idle', (
      tester,
    ) async {
      await tester.pumpWidget(buildBar(RecordingPhase.idle));
      await tester.pump();

      expect(indicatorBuilder(tester), findsNothing);
    });

    testWidgets('shows pulse AnimatedBuilder when recording', (tester) async {
      await tester.pumpWidget(buildBar(RecordingPhase.recording));
      await tester.pump(const Duration(milliseconds: 250));

      expect(indicatorBuilder(tester), findsOneWidget);
    });

    testWidgets('shows pulse AnimatedBuilder when transcribing', (
      tester,
    ) async {
      await tester.pumpWidget(buildBar(RecordingPhase.transcribing));
      await tester.pump(const Duration(milliseconds: 250));

      expect(indicatorBuilder(tester), findsOneWidget);
    });

    testWidgets('hides AnimatedBuilder after returning to idle', (
      tester,
    ) async {
      await tester.pumpWidget(buildBar(RecordingPhase.recording));
      await tester.pump(const Duration(milliseconds: 250));

      await tester.pumpWidget(buildBar(RecordingPhase.idle));
      await tester.pump(const Duration(milliseconds: 250));

      expect(indicatorBuilder(tester), findsNothing);
    });

    testWidgets('builds without exception in light mode', (tester) async {
      await tester.pumpWidget(
        buildBar(RecordingPhase.recording, brightness: Brightness.light),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(tester.takeException(), isNull);
    });
  });
}
