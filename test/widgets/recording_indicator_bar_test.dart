/// Widget tests for [WpRecordingIndicatorBar].
///
/// Covers:
///  - Ticket 15 / AC4: the main window's recording surface carries the
///    recording *cyan* — both in-flight phases resolve to
///    `WpColors.recordingAccent`, never a status hue and never the generic
///    actions accent.
///  - Ticket 15 / AC3: the bar paints no gradient of its own.
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
// Unit tests — colour-token mapping (AC3, Ticket 15 AC4)
// ---------------------------------------------------------------------------

void main() {
  group('WpRecordingIndicatorBar.colorFor — token mapping', () {
    test('recording resolves to the recording family, not a status hue', () {
      expect(
        WpRecordingIndicatorBar.colorFor(RecordingPhase.recording),
        WpColors.recordingAccent,
        reason:
            'Ticket 15 AC4: cyan carries the recording/listening state. This '
            'used to be `error` red, which spends the colour the Quiet Status '
            'Rule reserves for real failures on a bar reporting a healthy '
            'pipeline.',
      );
    });

    test('transcribing resolves to the same recording family', () {
      expect(
        WpRecordingIndicatorBar.colorFor(RecordingPhase.transcribing),
        WpColors.recordingAccent,
        reason:
            '`recordingAccent` means "a recording *or its transcription* is '
            'in flight" — both phases are that. The phase detail is the '
            'status-bar chip\'s job, not this 3px bar\'s.',
      );
    });

    test('neither phase reaches for the generic actions accent', () {
      // *The Two-Accent-Two-Jobs Rule*: `accent` means "you can act on this".
      // The bar cannot be pressed, so it must not wear it — the two families
      // are separated by weight, not hue, and this is exactly the seam where
      // that separation would otherwise quietly collapse.
      for (final phase in [
        RecordingPhase.recording,
        RecordingPhase.transcribing,
      ]) {
        expect(WpRecordingIndicatorBar.colorFor(phase), isNot(WpColors.accent));
      }
    });

    test('the two status hues are gone from the bar entirely', () {
      for (final phase in RecordingPhase.values) {
        final color = WpRecordingIndicatorBar.colorFor(phase);
        expect(color, isNot(WpColors.error));
        expect(color, isNot(WpColors.warning));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — visibility / phase rendering (AC3)
  // ---------------------------------------------------------------------------

  group('WpRecordingIndicatorBar — phase rendering (AC3)', () {
    Widget buildBar(RecordingPhase phase) {
      return makeTestable(WpRecordingIndicatorBar(phase: phase));
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

    // Removed 2026-08-11 (dark-only build): 'builds without exception in
    // light mode' pumped the bar with Brightness.light. The app now ships a
    // single dark theme only, so there is no light mode left to build.
  });

  // ---------------------------------------------------------------------------
  // Regression: starting a recording under disableAnimations must not throw.
  //
  // On Linux, the GTK/AT-SPI embedder reports
  // `PlatformDispatcher.accessibilityFeatures.disableAnimations == true`
  // regardless of the desktop's actual "enable animations" preference.
  // `WpMotion.durationFor` honours that by handing this bar's pulse
  // controller a `Duration.zero`. `_syncPulse` used to call
  // `_pulse.repeat(reverse: true)` unconditionally, which asserts its period
  // is > 0 — the assertion threw inside `didUpdateWidget`, itself called
  // from `Element.updateChildren`, aborting that rebuild pass partway
  // through and desyncing the Element/RenderObject child lists for
  // everything built after this bar in the tree. Repeated recording toggles
  // repeated the throw, each one leaving another stale render subtree
  // behind — the observed Linux-only duplicated ("zweigeteilte") History
  // pane.
  // ---------------------------------------------------------------------------

  group('WpRecordingIndicatorBar — reduced motion (disableAnimations)', () {
    Widget buildReducedMotionBar(RecordingPhase phase) {
      return makeTestable(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: WpRecordingIndicatorBar(phase: phase),
          ),
        ),
      );
    }

    testWidgets('starting a recording under disableAnimations does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(buildReducedMotionBar(RecordingPhase.idle));
      await tester.pump();

      await tester.pumpWidget(buildReducedMotionBar(RecordingPhase.recording));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'toggling recording on/off repeatedly under disableAnimations never '
      'throws',
      (tester) async {
        for (var i = 0; i < 3; i++) {
          await tester.pumpWidget(
            buildReducedMotionBar(RecordingPhase.recording),
          );
          await tester.pump();
          await tester.pumpWidget(buildReducedMotionBar(RecordingPhase.idle));
          await tester.pump();
        }

        expect(tester.takeException(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Ticket 15 / AC3 — no component paints its own gradient
  // -------------------------------------------------------------------------

  group('WpRecordingIndicatorBar — paints no gradient of its own', () {
    testWidgets('the active bar carries a flat fill, not a LinearGradient', (
      tester,
    ) async {
      for (final phase in [
        RecordingPhase.recording,
        RecordingPhase.transcribing,
      ]) {
        await tester.pumpWidget(
          makeTestable(WpRecordingIndicatorBar(phase: phase)),
        );
        await tester.pump(const Duration(milliseconds: 250));

        final decorations = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(WpRecordingIndicatorBar),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((d) => d.decoration)
            .whereType<BoxDecoration>();

        expect(
          decorations.where((d) => d.gradient != null),
          isEmpty,
          reason:
              'Ticket 15 AC3 — the bar used to fade its own hue out towards '
              'both ends with a three-stop LinearGradient, which is a second '
              'light source three pixels tall over the one ambient the app '
              'stands on. The pulse carries the signal; the alpha animates, '
              'the hue does not.',
        );
      }
    });
  });
}
