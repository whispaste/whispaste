/// Performance instrumentation — latency budgets + lightweight event markers.
///
/// ## Purpose
///
/// Two public artifacts live here:
///
/// 1. [PerfBudgets] — compile-time constants that document every latency budget
///    agreed in Phase 0 (spike-notes.md, PRD §4 Phase-D4). These are the
///    TARGETS against which real on-hardware measurements (issue 16, human
///    dogfooding gate) are evaluated. Having them as code constants means there
///    is exactly one place to update when a refined baseline replaces the
///    Phase-0 estimate.
///
/// 2. [PerfMarkers] — a lightweight singleton that stamps key timestamps and
///    logs deltas via [AppLogger]. No behaviour is changed; the log output is
///    what a human reads during dogfooding. Tests can verify the marker
///    lifecycle headlessly.
///
/// ## What is NOT here
///
/// Real latency numbers. `PerfMarkers` logs deltas to the console/Sentry log,
/// but the MEASUREMENT gate is issue 16 (human dogfooding on real hardware):
///   - Hotkey→overlay: needs a running app + stopwatch on real hardware.
///   - Cold-start: needs release build + wall-clock on real hardware.
///   - Frame-drop profiling: use Flutter DevTools Performance tab.
///
/// See also: [UiThreadWatchdog] — catches >500 ms main-thread stalls process-
/// wide; [PerfBudgets.watchdogThresholdMs] mirrors its private constant here
/// for cross-reference.
library;

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

// ---------------------------------------------------------------------------
// Latency budgets (Phase-0 — source of truth for issue-16 measurements)
// ---------------------------------------------------------------------------

/// Phase-0 performance budgets for WhisPaste hot-paths.
///
/// Sources:
///   - `spike-notes.md` §3 (Motion/Spring measurements, macOS 60 Hz).
///   - PRD §2 "Geschwindigkeit IST Premium".
///   - PRD §4 Phase-D4 AC "Hotkey→Overlay ~≤33 ms / gefühlt sofort;
///     0 dropped frames in Transitions + History-Scroll via
///     `ui_thread_watchdog`; Cold-Start-Ziel".
///   - PRD §8 open mini-point: "Cold-Start-Zielzahl nach IST-Messung".
///
/// All timing-AC values marked **HUMAN GATE** require on-hardware measurement
/// during dogfooding (issue 16). Only [transitionNormalMs] and
/// [signatureTransitionSoftCapMs]/[signatureTransitionHardCapMs] are verified
/// headlessly via widget tests.
abstract final class PerfBudgets {
  // ── Hotkey → overlay ───────────────────────────────────────────────────────

  /// Hotkey key-down → first overlay snapshot sent (recording phase visible).
  ///
  /// Target: ≤ 33 ms ("gefühlt sofort" — one frame at 30 Hz).
  /// PRD §4 Phase-D4 AC: "Hotkey→Overlay ~≤33 ms / gefühlt sofort".
  ///
  /// **HUMAN GATE (issue 16):** measure on real hardware with the app running.
  /// Instrumented via [PerfMarkers.markHotkeyPressed] /
  /// [PerfMarkers.markOverlayShown].
  static const int hotkeyOverlayMs = 33;

  // ── Navigation transitions ─────────────────────────────────────────────────

  /// Standard (non-signature) transition hard-cap — AnimatedSwitcher duration.
  ///
  /// Equals [WpMotion.normal] (200 ms). Verified headlessly: the transition
  /// must complete within this window (nav_transition_test.dart test-c).
  ///
  /// Source: spike-notes.md §3 "Nicht-Signatur-Motion ≤ 200–300 ms (easeOut)".
  static const int transitionNormalMs = 200;

  /// Signature transition (recording-arc capsule appear/dismiss) — soft-cap.
  ///
  /// Soft-Cap 300 ms: wahrgenommener "Snap" in the first ~250 ms; the spring
  /// can ring out to [signatureTransitionHardCapMs] but must feel settled here.
  /// Source: spike-notes.md §3.
  static const int signatureTransitionSoftCapMs = 300;

  /// Signature transition — hard-cap (spring fully settled).
  ///
  /// 700 ms: spring-einschwingen (Gentle 170/26, ratio ≈ 1.0) reaches rest.
  /// Source: spike-notes.md §3.
  static const int signatureTransitionHardCapMs = 700;

  // ── Cold-start ─────────────────────────────────────────────────────────────

  /// Cold-start → first frame rendered.
  ///
  /// **Target not yet fixed (PRD §8 open mini-point).**
  /// Value -1 is a sentinel meaning "TBD after IST-Messung on real hardware".
  ///
  /// **HUMAN GATE (issue 16):** measure release build on each target platform
  /// (macOS, Windows, Linux) and replace -1 with the agreed target.
  /// Instrumented via [PerfMarkers.markColdStartBegin] /
  /// [PerfMarkers.markFirstFrame].
  static const int coldStartFirstFrameMs = -1; // TBD — issue 16

  // ── UI thread watchdog ─────────────────────────────────────────────────────

  /// Mirror of [UiThreadWatchdog._threshold] (500 ms).
  ///
  /// Timer-jitter above this triggers a warning log. Note: the watchdog
  /// detects STALLS (≥ 500 ms blocked main-thread work), not dropped frames
  /// (≥ 16.7 ms @ 60 Hz). Per-frame profiling requires DevTools.
  static const int watchdogThresholdMs = 500;

  // ── Frame budget ───────────────────────────────────────────────────────────

  /// Single-frame budget at 60 Hz (macOS baseline from spike-notes.md §1).
  ///
  /// The waveform animation timer ticks at ~33 ms (≈ 30 fps), intentionally
  /// below this ceiling to leave headroom for compositor compositing.
  static const double frameMs60Hz = 16.7;
}

// ---------------------------------------------------------------------------
// PerfMarkers — lightweight event-stamp singleton
// ---------------------------------------------------------------------------

/// Stamps timestamps at key performance milestones and logs deltas.
///
/// Designed to be zero-cost when the relevant paths are not triggered:
/// all methods are no-ops if the preceding marker was not set. The only
/// side effect is a log line via [AppLogger] — no timers, no allocations
/// beyond a single [DateTime?] field per tracked path.
///
/// ## Coverage
///
/// | Marker pair                                     | Budget constant                     |
/// |--------------------------------------------------|-------------------------------------|
/// | [markHotkeyPressed] → [markOverlayShown]         | [PerfBudgets.hotkeyOverlayMs]       |
/// | [markColdStartBegin] → [markFirstFrame]          | [PerfBudgets.coldStartFirstFrameMs] |
///
/// ## Wiring (for quick navigation)
///
/// - [markHotkeyPressed]: `HotkeyService._handleKeyDown` (accepted key-downs).
/// - [markOverlayShown]:  `FloatingOverlayService._handlePhaseUi` (recording case).
/// - [markColdStartBegin]: `main._runApp` (first line).
/// - [markFirstFrame]:    `main._runApp` post-frame callback after `runApp`.
class PerfMarkers {
  PerfMarkers._();

  static PerfMarkers? _instance;

  /// Singleton accessor.
  static PerfMarkers get instance => _instance ??= PerfMarkers._();

  static final _log = AppLogger('PerfMarkers');

  DateTime? _coldStartBegin;
  DateTime? _hotkeyPressedAt;

  // ── Cold-start ──────────────────────────────────────────────────────────

  /// Stamps the cold-start t₀ (first line of `_runApp`).
  ///
  /// Logs a debug line; the actual latency is logged by [markFirstFrame].
  void markColdStartBegin() {
    _coldStartBegin = DateTime.now();
    _log.debug('[PERF] cold-start begin (t₀)');
  }

  /// Stamps the first-frame callback and logs the cold-start latency.
  ///
  /// **HUMAN GATE (issue 16):** the number produced here is load-bearing
  /// evidence for the cold-start AC. Budget target is TBD
  /// ([PerfBudgets.coldStartFirstFrameMs] = sentinel -1 until fixed).
  void markFirstFrame() {
    final begin = _coldStartBegin;
    if (begin == null) return;
    final elapsedMs = DateTime.now().difference(begin).inMilliseconds;
    const budget = PerfBudgets.coldStartFirstFrameMs;
    final note = budget < 0
        ? 'budget TBD (PRD §8 open — fix after issue-16 measurement)'
        : (elapsedMs <= budget ? 'OK' : 'OVER BUDGET (≤${budget}ms)');
    _log.info('[PERF] cold-start → first-frame: ${elapsedMs}ms [$note]');
  }

  // ── Hotkey → overlay ────────────────────────────────────────────────────

  /// Stamps t₀ for hotkey→overlay latency when a hotkey key-down is accepted.
  ///
  /// Called inside `HotkeyService._handleKeyDown` BEFORE dispatching to the
  /// recording trigger handler, so the stamp captures the earliest possible
  /// Dart-layer moment of the hotkey event.
  void markHotkeyPressed() {
    _hotkeyPressedAt = DateTime.now();
    _log.debug('[PERF] hotkey pressed (t₀ for hotkey→overlay)');
  }

  /// Stamps t₁ when the overlay recording-snapshot is sent to the native
  /// controller and logs the delta.
  ///
  /// Called inside `FloatingOverlayService._handlePhaseUi` after
  /// `_sendSnapshot` for the recording phase.
  ///
  /// **HUMAN GATE (issue 16):** the number produced here is load-bearing
  /// evidence for the hotkey→overlay AC.
  /// Budget: [PerfBudgets.hotkeyOverlayMs] = 33 ms.
  ///
  /// A log line with `[PERF] hotkey→overlay: Xms` must appear during
  /// dogfooding; X ≤ 33 satisfies the AC.
  void markOverlayShown() {
    final pressedAt = _hotkeyPressedAt;
    _hotkeyPressedAt = null; // reset — next press gets a clean t₀
    if (pressedAt == null) return;
    final elapsedMs = DateTime.now().difference(pressedAt).inMilliseconds;
    const budget = PerfBudgets.hotkeyOverlayMs;
    final status = elapsedMs <= budget ? 'OK' : 'OVER BUDGET';
    _log.info(
      '[PERF] hotkey→overlay: ${elapsedMs}ms '
      '(budget: ≤${budget}ms) [$status]',
    );
  }

  // ── Hotkey → text (end-to-end latency KPI) ─────────────────────────────

  /// Returns the currently pending hotkey-press timestamp (t₀) without
  /// consuming it.
  ///
  /// Unlike [markOverlayShown] (which resets the marker after computing the
  /// hotkey→overlay latency), this is a non-destructive peek. It lets
  /// `RecordingOrchestrator.startRecording` capture the same t₀ for the
  /// hotkey→text end-to-end latency KPI (local-only, see
  /// `.scratch/experience-perf-polish/issues/07-latenz-kpi-erfassung.md`)
  /// without interfering with the hotkey→overlay pairing above — both
  /// latencies are derived independently from the same key-down event.
  DateTime? get pendingHotkeyPressedAt => _hotkeyPressedAt;

  // ── Test helpers ─────────────────────────────────────────────────────────

  /// Returns the currently-pending hotkey timestamp, or null if none.
  ///
  /// Exposed for unit tests that verify the mark→log lifecycle without
  /// reading private log output.
  @visibleForTesting
  DateTime? get debugHotkeyPressedAt => _hotkeyPressedAt;

  /// Returns the cold-start t₀, or null if not yet stamped.
  @visibleForTesting
  DateTime? get debugColdStartBegin => _coldStartBegin;

  /// Resets all pending markers. Call in test [setUp]/[tearDown] to prevent
  /// cross-test state leakage since the singleton persists across tests.
  @visibleForTesting
  void reset() {
    _coldStartBegin = null;
    _hotkeyPressedAt = null;
  }
}
