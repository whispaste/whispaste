/// Single source of truth for the Auto-Paste capability surface.
///
/// Wraps [Paster.checkCapability] (probe) and
/// [DesktopPasteController.repairTccEntries] (macOS TCC self-heal) behind a
/// Riverpod [Notifier] so UI consumers — the settings indicator and the
/// onboarding Auto-Paste step — share one polling timer and one capability
/// state instead of each holding their own.
///
/// State shape ([PasteCapabilityState]):
///   - [PasteCapabilityState.capability] is the last result of a probe,
///     or `null` before the first probe runs.
///   - [PasteCapabilityState.hadFailedGrantAttempt] flips to `true` the
///     first time a `check(prompt: true)` resolves with
///     [PasteCapabilityStatus.permissionMissing]. Drives lazy reveal of the
///     macOS TCC repair button.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import 'paster.dart';

/// Sentry breadcrumb category shared by every onboarding Auto-Paste event.
/// Kept here (and re-used from the step widget) so all polling-lifecycle and
/// step-lifecycle breadcrumbs land under the same Sentry filter.
const String onboardingAutoPasteBreadcrumbCategory = 'onboarding.autopaste';

/// Explicit lifecycle phase of the capability polling loop.
///
/// Replaces the implicit `_pollTimer != null` view of the world with a state
/// the UI can switch on. The four states are mutually exclusive and cover
/// every observable transition that `startPolling` / `_disposePolling` can
/// drive:
///
///   - [idle]: never polled in this provider lifecycle, or explicitly
///     stopped (e.g. user navigated away).
///   - [awaitingGrant]: polling timer is armed and ticking; the UI should
///     render the "waiting for you to flip the toggle in System Settings"
///     guidance card.
///   - [succeeded]: a probe returned [PasteCapabilityStatus.ready] and the
///     loop self-stopped — the happy path.
///   - [timedOut]: the timeout elapsed without ever seeing `ready`. UI
///     consumers can offer a recovery affordance here (subsequent slices
///     drive the TCC-mismatch banner off this).
enum PollingPhase { idle, awaitingGrant, succeeded, timedOut }

/// Immutable snapshot of the capability surface.
class PasteCapabilityState {
  const PasteCapabilityState({
    this.capability,
    this.hadFailedGrantAttempt = false,
    this.pollingPhase = PollingPhase.idle,
  });

  /// Latest probe result. `null` means "no probe has resolved yet".
  final PasteCapability? capability;

  /// Sticky flag: `true` once a prompted check has come back as
  /// [PasteCapabilityStatus.permissionMissing]. Never resets — a successful
  /// follow-up grant still leaves the bit set, which is what the UI wants:
  /// the user has demonstrably hit the ad-hoc-signed edge case at least
  /// once and the repair button should stay reachable for the rest of the
  /// session.
  final bool hadFailedGrantAttempt;

  /// Where the capability polling loop currently is. See [PollingPhase].
  final PollingPhase pollingPhase;

  PasteCapabilityState copyWith({
    PasteCapability? capability,
    bool? hadFailedGrantAttempt,
    PollingPhase? pollingPhase,
  }) {
    return PasteCapabilityState(
      capability: capability ?? this.capability,
      hadFailedGrantAttempt:
          hadFailedGrantAttempt ?? this.hadFailedGrantAttempt,
      pollingPhase: pollingPhase ?? this.pollingPhase,
    );
  }
}

/// Riverpod notifier wrapping the Auto-Paste capability surface.
///
/// Polling lives here (not in widgets) so the timer is one cohesive thing
/// that always gets cancelled on dispose or self-stops at `ready`/timeout —
/// no per-widget timer leaks.
class PasteCapabilityNotifier extends Notifier<PasteCapabilityState> {
  static final _log = AppLogger('PasteCapability');

  Timer? _pollTimer;
  Timer? _pollTimeout;
  bool _checkInFlight = false;
  Stopwatch? _pollStopwatch;

  @override
  PasteCapabilityState build() {
    ref.onDispose(() {
      // Provider is being torn down — only the timer pair needs cancelling.
      // Writing to `state` inside an `onDispose` callback throws because the
      // notifier is already being disposed; `_disposePolling` therefore runs
      // in a no-state-write mode during teardown.
      _cancelTimers();
    });
    return const PasteCapabilityState();
  }

  /// Whether [startPolling] currently has an active timer.
  ///
  /// Backwards-compatible convenience derived from
  /// [PasteCapabilityState.pollingPhase] — older UI sites can keep reading
  /// this boolean while new code switches on the explicit phase.
  bool get isPolling => state.pollingPhase == PollingPhase.awaitingGrant;

  /// Heuristic: did the polling loop just time out in a way that matches the
  /// ad-hoc-signed-Sequoia "TCC cache is stale" signature?
  ///
  /// Pure function of [PasteCapabilityState] — no fields of its own. `true`
  /// exactly when all three of:
  ///   - [PasteCapabilityState.hadFailedGrantAttempt] is `true` (the user
  ///     has demonstrably tried to grant via the OS dialog at least once),
  ///   - the latest capability probe still reports
  ///     [PasteCapabilityStatus.permissionMissing],
  ///   - the polling loop ended in [PollingPhase.timedOut] (not
  ///     `succeeded`, not still `awaitingGrant`).
  /// Any single falsification collapses the conjunction back to `false`.
  ///
  /// Drives the `_TccMismatchBanner` reveal in the onboarding Auto-Paste
  /// step and replaces the placeholder `false` in the `polling.timeout`
  /// Sentry breadcrumb's `suspected_tcc_mismatch` data field.
  bool get suspectedTccMismatch =>
      state.hadFailedGrantAttempt &&
      state.capability?.status == PasteCapabilityStatus.permissionMissing &&
      state.pollingPhase == PollingPhase.timedOut;

  /// Runs one capability probe through the [Paster].
  ///
  /// When [prompt] is `true` and the result is
  /// [PasteCapabilityStatus.permissionMissing], flips
  /// [PasteCapabilityState.hadFailedGrantAttempt] to `true`. Calls that
  /// overlap are coalesced — a second [check] entered while the first is
  /// still in flight returns immediately without firing a duplicate probe.
  Future<void> check({bool prompt = false}) async {
    if (_checkInFlight) return;
    _checkInFlight = true;
    try {
      final paster = ref.read(pasterProvider);
      if (paster == null) {
        state = state.copyWith(
          capability: const PasteCapability(
            status: PasteCapabilityStatus.unsupported,
          ),
        );
        return;
      }
      final result = await paster.checkCapability(promptIfMissing: prompt);
      _log.info(
        'capability check: prompt=$prompt status=${result.status.name} '
        'canPrompt=${result.canPrompt} detail=${result.detail}',
      );

      final flippedFailedGrant =
          prompt && result.status == PasteCapabilityStatus.permissionMissing;
      state = state.copyWith(
        capability: result,
        hadFailedGrantAttempt:
            state.hadFailedGrantAttempt || flippedFailedGrant,
      );
    } finally {
      _checkInFlight = false;
    }
  }

  /// Repeatedly runs [check] (without prompting) until the capability turns
  /// [PasteCapabilityStatus.ready] **or** the supplied [timeout] elapses,
  /// whichever happens first. Self-stops in both cases; no caller needs to
  /// remember to call [stopPolling] in the happy path.
  ///
  /// Restarting while already polling cancels the previous timer pair first
  /// so we never accumulate parallel pollers.
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {
    _disposePolling();
    _pollStopwatch = Stopwatch()..start();
    _emitBreadcrumb(
      'polling.started',
      data: {
        'interval_ms': interval.inMilliseconds,
        'timeout_ms': timeout.inMilliseconds,
      },
    );
    // Flip into `awaitingGrant` BEFORE arming the timers so any observer
    // that wakes up on the same microtask already sees the new phase.
    state = state.copyWith(pollingPhase: PollingPhase.awaitingGrant);
    _pollTimer = Timer.periodic(interval, (_) async {
      await check();
      if (state.capability?.status == PasteCapabilityStatus.ready) {
        _disposePolling(reason: _PollEnd.success);
      }
    });
    _pollTimeout = Timer(
      timeout,
      () => _disposePolling(reason: _PollEnd.timeout),
    );
  }

  /// Cancels the active polling pair if any. Safe to call multiple times and
  /// before [startPolling] has ever run.
  void stopPolling() => _disposePolling();

  /// Asks the platform desktop paste controller to wipe the stale TCC
  /// entries that cause the ad-hoc-signed-Sequoia "permission granted but
  /// `AXIsProcessTrusted()` returns `false`" symptom. Returns a
  /// [TccRepairResult.unsupported] when there is no controller (e.g. test
  /// env or Linux).
  Future<TccRepairResult> repair() async {
    final controller = ref.read(desktopPasteControllerProvider);
    if (controller == null) return TccRepairResult.unsupported();
    final result = await controller.repairTccEntries();
    _log.info(
      'TCC repair: ax cleared=${result.accessibilityCleared} '
      'ae cleared=${result.appleEventsCleared} '
      'error=${result.error ?? "none"}',
    );
    return result;
  }

  /// Cancels the active timer pair without touching `state`. Safe to call
  /// from `onDispose` where state mutation would assert.
  void _cancelTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollTimeout?.cancel();
    _pollTimeout = null;
    _pollStopwatch = null;
  }

  void _disposePolling({_PollEnd reason = _PollEnd.cancelled}) {
    final wasActive = _pollTimer != null || _pollTimeout != null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollTimeout?.cancel();
    _pollTimeout = null;
    // Drive the explicit phase from the disposal reason so UI consumers
    // can react without poking at the (private) timer fields. `cancelled`
    // collapses to `idle` because "no one is waiting on anything" — there
    // is no observable polling outcome to surface.
    final nextPhase = switch (reason) {
      _PollEnd.success => PollingPhase.succeeded,
      _PollEnd.timeout => PollingPhase.timedOut,
      _PollEnd.cancelled => PollingPhase.idle,
    };
    if (state.pollingPhase != nextPhase) {
      state = state.copyWith(pollingPhase: nextPhase);
    }
    // Only surface a Sentry event when polling actually ended — repeated
    // stopPolling() calls (re-mounts, defensive disposal) must not spam
    // breadcrumbs. `cancelled` is an internal signal we don't ship to Sentry.
    if (wasActive && reason != _PollEnd.cancelled) {
      final elapsedMs = _pollStopwatch?.elapsedMilliseconds ?? 0;
      // Evaluate the TCC-mismatch heuristic AFTER pollingPhase has been
      // promoted to `timedOut` so the getter sees the same world the UI
      // will see one frame later. On the success branch the heuristic is
      // structurally false (status != permissionMissing) — no extra cost.
      final mismatch = suspectedTccMismatch;
      _emitBreadcrumb(
        reason == _PollEnd.success ? 'polling.success' : 'polling.timeout',
        data: reason == _PollEnd.timeout
            ? {'elapsed_ms': elapsedMs, 'suspected_tcc_mismatch': mismatch}
            : {'elapsed_ms': elapsedMs},
      );
      // Mirror-event: when the timeout coincides with the ad-hoc-signed
      // TCC-cache symptom, emit a dedicated breadcrumb so Sentry funnels
      // can slice on the suspected cause directly without re-deriving the
      // conjunction from the generic timeout payload.
      if (reason == _PollEnd.timeout && mismatch) {
        _emitBreadcrumb(
          'polling.timeout_with_mismatch',
          data: {'elapsed_ms': elapsedMs},
        );
      }
    }
    _pollStopwatch = null;
  }

  /// Emits a breadcrumb under the shared onboarding Auto-Paste category and
  /// always tags the host platform so funnel queries stay slice-able. Data
  /// values are status/numeric only — no PII.
  void _emitBreadcrumb(String message, {Map<String, Object?> data = const {}}) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: onboardingAutoPasteBreadcrumbCategory,
        level: SentryLevel.info,
        data: {'platform': _platformTag(), ...data},
      ),
    );
  }
}

/// Outcome marker for [PasteCapabilityNotifier._disposePolling]. Only
/// `success` and `timeout` are reported to Sentry — `cancelled` covers the
/// "the user navigated away" / "we re-armed polling" cases where surfacing a
/// breadcrumb would only add noise.
enum _PollEnd { cancelled, success, timeout }

/// Stable, PII-free platform tag for breadcrumbs.
String _platformTag() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

final pasteCapabilityNotifierProvider =
    NotifierProvider<PasteCapabilityNotifier, PasteCapabilityState>(
      PasteCapabilityNotifier.new,
    );
