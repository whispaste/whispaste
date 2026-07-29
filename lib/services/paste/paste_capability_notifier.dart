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
///   - [PasteCapabilityState.sentToOsGrantFlow] flips to `true` the moment
///     WhisPaste hands the user off to the OS grant flow in *this* process
///     (via [requestGrant] or [openAccessibilitySettings]) — from any
///     surface (onboarding, settings indicator, failed-paste notification).
///     It is the single signal that separates the two macOS
///     `permissionMissing` recoveries (see [PastePermissionAction]).
///
/// Why the grant-vs-restart split exists (Apple DTS, forum thread 727984):
/// on the sandboxed Mac App Store build the permission is the CoreGraphics
/// `PostEvent` TCC service, probed with `CGPreflightPostEventAccess()`. That
/// value is **cached at process start and never refreshes mid-run** — after
/// the user flips the switch in System Settings the running process keeps
/// reading `false` until it relaunches ("that's why, when you change these
/// values in System Settings, it offers to quit and relaunch the app").
/// So once we've sent the user to grant and the probe is still missing, the
/// correct recovery is a **restart**, not another trip to Settings. The
/// non-sandboxed Developer-ID build probes `AXIsProcessTrusted()`, which
/// *does* usually flip live under polling (matching Rectangle/Ice) — there
/// the poll resolves to `ready` before the restart affordance is ever shown.
/// Keeping [sentToOsGrantFlow] in memory (never persisted) is deliberate: a
/// fresh process re-reads the real on-disk TCC state, so the flag resetting
/// on relaunch is exactly right.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/logging/app_logger.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import 'paster.dart';

/// Deep-link target for macOS' Accessibility settings pane.
const String _accessibilitySettingsUri =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility';

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

/// The single recovery action a UI surface should offer for the current
/// capability state. Every entry point (onboarding, settings indicator,
/// failed-paste notification) resolves the *same* value from the *same*
/// state, so no two surfaces can ever disagree on grant-vs-restart.
enum PastePermissionAction {
  /// Nothing to do — capability is [PasteCapabilityStatus.ready] or
  /// [PasteCapabilityStatus.unsupported], the probe hasn't resolved yet, or
  /// a grant poll is still in flight (the "tick the box" hint owns the
  /// screen; showing a competing button there would violate the one-action
  /// rule).
  none,

  /// Permission is missing and WhisPaste has not yet handed the user to the
  /// OS grant flow this process — offer the "Erlauben" button.
  grant,

  /// Permission is missing *after* WhisPaste already handed the user to the
  /// OS grant flow — the running process can't pick up a fresh grant, so
  /// offer the "Neu starten" button. See [PasteCapabilityState] doc for the
  /// Apple-DTS rationale.
  restart,
}

/// Immutable snapshot of the capability surface.
class PasteCapabilityState {
  const PasteCapabilityState({
    this.capability,
    this.sentToOsGrantFlow = false,
    this.pollingPhase = PollingPhase.idle,
  });

  /// Latest probe result. `null` means "no probe has resolved yet".
  final PasteCapability? capability;

  /// Sticky (per-process) flag: `true` once WhisPaste has handed the user
  /// off to the OS grant flow — via [PasteCapabilityNotifier.requestGrant]
  /// or [PasteCapabilityNotifier.openAccessibilitySettings] — from any
  /// surface. Deliberately in-memory only: a relaunch clears it so the
  /// fresh process re-derives grant-vs-restart from a truthful probe.
  final bool sentToOsGrantFlow;

  /// Where the capability polling loop currently is. See [PollingPhase].
  final PollingPhase pollingPhase;

  PasteCapabilityState copyWith({
    PasteCapability? capability,
    bool? sentToOsGrantFlow,
    PollingPhase? pollingPhase,
  }) {
    return PasteCapabilityState(
      capability: capability ?? this.capability,
      sentToOsGrantFlow: sentToOsGrantFlow ?? this.sentToOsGrantFlow,
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

  /// The single recovery action every UI surface must offer for the current
  /// state. Pure function of [PasteCapabilityState]; see
  /// [PastePermissionAction] for what each value means and the Apple-DTS
  /// rationale for the grant-vs-restart split.
  ///
  ///   - not `permissionMissing` (ready / unsupported / unprobed) → [none].
  ///   - `permissionMissing` while a grant poll is still armed
  ///     ([PollingPhase.awaitingGrant]) → [none] (the "tick the box" hint
  ///     owns the screen).
  ///   - `permissionMissing`, poll not armed, user already sent to the OS
  ///     grant flow this process → [restart].
  ///   - `permissionMissing`, poll not armed, not yet sent → [grant].
  PastePermissionAction get requiredAction {
    if (state.capability?.status != PasteCapabilityStatus.permissionMissing) {
      return PastePermissionAction.none;
    }
    if (state.pollingPhase == PollingPhase.awaitingGrant) {
      return PastePermissionAction.none;
    }
    return state.sentToOsGrantFlow
        ? PastePermissionAction.restart
        : PastePermissionAction.grant;
  }

  /// Convenience: the current [requiredAction] is [PastePermissionAction.restart].
  /// The single flag every surface keys its restart affordance off — the
  /// former `suspectedTccMismatch` heuristic, minus the fragile
  /// timeout-only trigger that collapsed to `false` the moment polling was
  /// stopped (navigating away, re-mounting) and re-showed "Erlauben" for a
  /// permission the user had already granted.
  bool get needsRestart => requiredAction == PastePermissionAction.restart;

  /// Runs one capability probe through the [Paster].
  ///
  /// Calls that overlap are coalesced — a second [check] entered while the
  /// first is still in flight returns immediately without firing a
  /// duplicate probe. Never mutates [PasteCapabilityState.sentToOsGrantFlow]:
  /// that bit is owned by the grant-handoff entry points ([requestGrant] /
  /// [openAccessibilitySettings]), not by probing.
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
      state = state.copyWith(capability: result);
    } finally {
      _checkInFlight = false;
    }
  }

  /// Runs the "request Auto-Paste permission" sequence: fires the
  /// OS-prompted check, arms the awaiting-grant poller, then deep-links to
  /// the Accessibility settings pane so the user sees the toggle row even if
  /// macOS suppressed its own dialog (e.g. a prior prompt already fired once
  /// this process).
  ///
  /// The single call every UI entry point shares — onboarding's Auto-Paste
  /// step, the Settings capability indicator, and the After-Transcription
  /// dropdown's activation trigger — so the sequence can't drift between
  /// them.
  ///
  /// Deliberately does **not** call [repair] first: [repair] is destructive
  /// (`tccutil reset`-equivalent) and the common case this fires for is a
  /// grant that already exists but is stale in *this process's* view — a
  /// symptom [restart], not [repair], fixes. Wiping a working grant on every
  /// call would force a needless re-grant for that case. Escalate to
  /// [repair] only from the collapsed troubleshoot escape once a restart
  /// alone didn't clear it.
  Future<void> requestGrant({
    Duration pollInterval = const Duration(seconds: 1),
    Duration pollTimeout = const Duration(seconds: 30),
  }) async {
    // Mark the handoff up front: from here on, a still-missing probe means
    // "restart", not "grant again" (see [requiredAction]).
    _markSentToOsGrantFlow();
    await check(prompt: true);
    // Arm polling BEFORE awaiting the settings launch — we want the poller
    // running the moment the user flips the toggle in System Settings, not
    // after the deep-link future resolves (which can stall on slow Settings
    // launches and in test environments where the channel isn't wired).
    startPolling(interval: pollInterval, timeout: pollTimeout);
    if (!Platform.isMacOS) return;
    try {
      await launchUrl(Uri.parse(_accessibilitySettingsUri));
    } on Exception catch (e) {
      _log.warning('Could not open Accessibility settings: $e');
    }
  }

  /// Opens the macOS Accessibility settings pane and records the grant
  /// handoff — the entry point for surfaces that only need to send the user
  /// to Settings without arming the full [requestGrant] poll (e.g. the
  /// failed-paste OS notification's click action). Setting the handoff bit
  /// here is what makes the *next* surface the user sees resolve to
  /// [PastePermissionAction.restart] instead of showing "Erlauben" again.
  Future<void> openAccessibilitySettings() async {
    _markSentToOsGrantFlow();
    if (!Platform.isMacOS) return;
    try {
      await launchUrl(Uri.parse(_accessibilitySettingsUri));
    } on Exception catch (e) {
      _log.warning('Could not open Accessibility settings: $e');
    }
  }

  /// Re-probe when WhisPaste regains focus — the user has just come back
  /// from System Settings, so this is the moment to resolve the grant.
  ///
  /// On the Developer-ID build `AXIsProcessTrusted()` flips live, so the
  /// probe promotes the state straight to `ready`. On the Mac App Store
  /// build `CGPreflightPostEventAccess()` stays cached-`false` (see class
  /// doc) — there this call's job is to stop the now-pointless grant poll so
  /// [requiredAction] surfaces the [PastePermissionAction.restart] affordance
  /// immediately, instead of stranding the user on the "tick the box"
  /// spinner until the poll times out.
  Future<void> recheckOnForeground() async {
    if (state.capability?.status == PasteCapabilityStatus.ready) return;
    await check();
    if (state.sentToOsGrantFlow &&
        state.capability?.status == PasteCapabilityStatus.permissionMissing) {
      // Leaves awaitingGrant → idle, so requiredAction resolves to restart.
      _disposePolling();
    }
  }

  void _markSentToOsGrantFlow() {
    if (state.sentToOsGrantFlow) return;
    state = state.copyWith(sentToOsGrantFlow: true);
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

  /// Runs the diagnostic paste flow — the explicit "prove Auto-Paste works"
  /// step in onboarding. Delegates to the platform desktop paste controller
  /// and emits PII-free Sentry breadcrumbs around the call so funnels can
  /// slice on `requested → success | failure(reason)`.
  ///
  /// Returns [TestPasteOutcomeUnsupported] when no controller is registered
  /// (Linux, test environments without a real channel).
  Future<TestPasteOutcome> runDiagnosticPaste(String demoText) async {
    _emitBreadcrumb('diagnostic_paste.requested');
    final controller = ref.read(desktopPasteControllerProvider);
    if (controller == null) {
      _emitBreadcrumb(
        'diagnostic_paste.failure',
        data: {'reason': 'unsupported'},
      );
      return const TestPasteOutcomeUnsupported();
    }
    final outcome = await controller.diagnosticPaste(demoText);
    switch (outcome) {
      case TestPasteOutcomeSuccess():
        _emitBreadcrumb('diagnostic_paste.success');
      case TestPasteOutcomeNoFrontmost():
        _emitBreadcrumb(
          'diagnostic_paste.failure',
          data: {'reason': 'no_frontmost'},
        );
      case TestPasteOutcomeFailure(:final reason):
        _emitBreadcrumb('diagnostic_paste.failure', data: {'reason': reason});
      case TestPasteOutcomeUnsupported():
        _emitBreadcrumb(
          'diagnostic_paste.failure',
          data: {'reason': 'unsupported'},
        );
    }
    return outcome;
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
      // Evaluate the recovery action AFTER pollingPhase has been promoted so
      // the getter sees the same world the UI will see one frame later. On
      // the success branch this is structurally `none` (status != missing).
      final restartNeeded = needsRestart;
      _emitBreadcrumb(
        reason == _PollEnd.success ? 'polling.success' : 'polling.timeout',
        data: reason == _PollEnd.timeout
            ? {'elapsed_ms': elapsedMs, 'needs_restart': restartNeeded}
            : {'elapsed_ms': elapsedMs},
      );
      // Mirror-event: when the timeout lands on the "already granted, needs a
      // relaunch" state, emit a dedicated breadcrumb so Sentry funnels can
      // slice on it directly without re-deriving it from the generic payload.
      if (reason == _PollEnd.timeout && restartNeeded) {
        _emitBreadcrumb(
          'polling.timeout_needs_restart',
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
