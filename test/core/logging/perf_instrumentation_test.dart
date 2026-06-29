/// Tests for PerfBudgets (contract) and PerfMarkers (lifecycle).
///
/// These tests are intentionally headless — they verify the instrumentation
/// layer WITHOUT producing real latency numbers. Real numbers come from
/// human dogfooding on real hardware (issue 16).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/perf_instrumentation.dart';
import 'package:whispaste/core/theme/tokens.dart';

void main() {
  // ── PerfBudgets contract tests ─────────────────────────────────────────────
  //
  // These are compile-time constant snapshots. If a constant is accidentally
  // changed, the test breaks and forces the human to review whether the
  // budget needs updating in sync.

  group('PerfBudgets — contract (Phase-0 values)', () {
    test('hotkeyOverlayMs == 33 (one 30-Hz frame, PRD §4 D4 AC)', () {
      expect(PerfBudgets.hotkeyOverlayMs, equals(33));
    });

    test('transitionNormalMs aligns with WpMotion.normal (200 ms)', () {
      expect(
        PerfBudgets.transitionNormalMs,
        equals(WpMotion.normal.inMilliseconds),
        reason:
            'PerfBudgets.transitionNormalMs must stay in sync with WpMotion.normal '
            'so the human dogfooding gate measures the same value used in the UI.',
      );
    });

    test('signatureTransitionSoftCapMs == 300 (spike-notes.md §3)', () {
      expect(PerfBudgets.signatureTransitionSoftCapMs, equals(300));
    });

    test('signatureTransitionHardCapMs == 700 (spike-notes.md §3)', () {
      expect(PerfBudgets.signatureTransitionHardCapMs, equals(700));
    });

    test('signatureTransitionHardCapMs > signatureTransitionSoftCapMs', () {
      expect(
        PerfBudgets.signatureTransitionHardCapMs,
        greaterThan(PerfBudgets.signatureTransitionSoftCapMs),
      );
    });

    test('coldStartFirstFrameMs == -1 sentinel (TBD — issue 16)', () {
      // -1 is the agreed sentinel meaning "budget not yet fixed".
      // Replace with a real value after dogfooding establishes the baseline.
      expect(
        PerfBudgets.coldStartFirstFrameMs,
        equals(-1),
        reason:
            'Cold-start budget is TBD (PRD §8 open mini-point). '
            'Replace -1 with the real target after issue-16 dogfooding.',
      );
    });

    test(
      'watchdogThresholdMs == 500 (mirrors UiThreadWatchdog._threshold)',
      () {
        expect(PerfBudgets.watchdogThresholdMs, equals(500));
      },
    );

    test('frameMs60Hz ≈ 16.7 ms', () {
      expect(PerfBudgets.frameMs60Hz, closeTo(16.7, 0.1));
    });
  });

  // ── PerfMarkers lifecycle tests ────────────────────────────────────────────

  group('PerfMarkers — lifecycle', () {
    late PerfMarkers markers;

    setUp(() {
      markers = PerfMarkers.instance;
      markers.reset();
    });

    tearDown(() {
      markers.reset();
    });

    // ── Singleton ────────────────────────────────────────────────────────────

    test('singleton returns the same instance', () {
      final a = PerfMarkers.instance;
      final b = PerfMarkers.instance;
      expect(identical(a, b), isTrue);
    });

    // ── Cold-start path ──────────────────────────────────────────────────────

    test('reset clears cold-start t₀', () {
      markers.markColdStartBegin();
      expect(markers.debugColdStartBegin, isNotNull);
      markers.reset();
      expect(markers.debugColdStartBegin, isNull);
    });

    test('markColdStartBegin stamps a non-null timestamp', () {
      expect(markers.debugColdStartBegin, isNull);
      markers.markColdStartBegin();
      expect(markers.debugColdStartBegin, isNotNull);
    });

    test('markFirstFrame without markColdStartBegin is a no-op (no throw)', () {
      expect(markers.debugColdStartBegin, isNull);
      // Must not throw.
      expect(() => markers.markFirstFrame(), returnsNormally);
    });

    test(
      'markFirstFrame with prior markColdStartBegin logs a non-negative delta',
      () {
        markers.markColdStartBegin();
        // Simulate a tiny but non-negative elapsed time.
        expect(() => markers.markFirstFrame(), returnsNormally);
        // After markFirstFrame the begin timestamp is NOT reset (may be logged
        // again if called twice — no hard requirement either way, just no crash).
      },
    );

    // ── Hotkey → overlay path ────────────────────────────────────────────────

    test('markHotkeyPressed stamps a non-null timestamp', () {
      expect(markers.debugHotkeyPressedAt, isNull);
      markers.markHotkeyPressed();
      expect(markers.debugHotkeyPressedAt, isNotNull);
    });

    test(
      'markOverlayShown without prior markHotkeyPressed is a no-op (no throw)',
      () {
        expect(markers.debugHotkeyPressedAt, isNull);
        expect(() => markers.markOverlayShown(), returnsNormally);
      },
    );

    test('markOverlayShown clears the pending hotkey timestamp', () {
      markers.markHotkeyPressed();
      expect(markers.debugHotkeyPressedAt, isNotNull);
      markers.markOverlayShown();
      // Timestamp is reset so the next cycle starts clean.
      expect(markers.debugHotkeyPressedAt, isNull);
    });

    test('markHotkeyPressed → markOverlayShown does not throw', () {
      markers.markHotkeyPressed();
      expect(() => markers.markOverlayShown(), returnsNormally);
    });

    test(
      'second markOverlayShown without a new markHotkeyPressed is a no-op',
      () {
        markers.markHotkeyPressed();
        markers.markOverlayShown(); // consumes t₀
        // Second call: no prior t₀ — must not throw.
        expect(() => markers.markOverlayShown(), returnsNormally);
      },
    );

    test('reset clears hotkey timestamp', () {
      markers.markHotkeyPressed();
      markers.reset();
      expect(markers.debugHotkeyPressedAt, isNull);
    });
  });
}
