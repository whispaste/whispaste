/// Proactive permission gate that runs on EVERY app start (not only during
/// first-run onboarding).
///
/// WhisPaste's two load-bearing permissions — microphone capture and the
/// Auto-Paste keystroke privilege — were previously only requested once, in
/// onboarding. After that, a missing permission surfaced reactively: a
/// recording silently failed, or a paste went nowhere. This gate probes both
/// permissions right after startup and, when one is missing, walks the user
/// through recovery with native always-on-top dialogs (visible even when
/// WhisPaste runs as a hidden tray app) and the minimum number of manual
/// steps the OS allows.
///
/// Platform truths this flow is built around (verified, do not "simplify"):
///
///  - **Microphone, first contact** (`.notDetermined`): asking triggers a
///    real OS dialog and a grant applies live in the running process — the
///    frictionless path, no Settings visit needed.
///  - **Microphone, after a denial**: there is no second OS dialog. The only
///    way back is the toggle in System Settings → Privacy & Security →
///    Microphone. Whether a re-grant applies live to an already-running
///    process is not guaranteed by any Apple contract, so after the poll
///    sees the grant this gate *verifies* capture actually works (a short
///    real stream probe) and only forces a relaunch when it doesn't —
///    never trusting a live refresh blindly, never restarting needlessly.
///    (macOS itself may additionally offer its own "Quit & Reopen" prompt
///    when the toggle flips; accepting that converges to the same state.)
///  - **Auto-Paste (macOS)**: the grant is a System-Settings toggle that
///    only the user can flip — there is no OS dialog API for it. On the
///    sandboxed MAS build the probed value (`CGPreflightPostEventAccess`)
///    never refreshes mid-process, so a relaunch is mandatory after the
///    grant (Apple DTS, forum thread 727984 — see
///    `paste_capability_notifier.dart`). The copy is deliberately honest
///    about the one unavoidable manual toggle; everything else (opening the
///    exact pane, detecting the grant, restarting) is automated by the
///    existing capability machinery this gate hands off to.
///
/// The gate itself is pure orchestration over injected hooks so the whole
/// decision tree is unit-testable without any platform channel.
library;

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/logging/app_logger.dart';

/// Sentry breadcrumb category for every startup-gate event.
const String startupPermissionGateBreadcrumbCategory =
    'startup.permission_gate';

/// How the microphone leg of the gate ended.
enum MicGateOutcome {
  /// Permission was already granted — nothing shown.
  alreadyGranted,

  /// Permission was `.notDetermined`; the OS dialog fired and the user
  /// granted it live. No Settings visit, no restart.
  grantedViaPrompt,

  /// Permission was denied, the user was walked through System Settings,
  /// the poll saw the grant AND a live capture probe confirmed audio works
  /// in this process — fully recovered without a restart.
  recoveredLive,

  /// The poll saw the grant but live capture still failed — the running
  /// process didn't pick it up, so the forced-restart dialog was shown
  /// (relaunch re-reads the grant).
  recoveredNeedsRestart,

  /// The user was sent to System Settings but the poll timed out without
  /// ever seeing the grant. Nothing more this session; the gate re-runs on
  /// the next start.
  unresolved,

  /// The user declined the guided recovery ("Not now") — nothing was
  /// opened, nothing polls. Per Apple's HIG every permission surface must
  /// be declinable; the gate simply re-offers on the next start.
  declined,
}

/// How the Auto-Paste leg of the gate ended.
enum AutoPasteGateOutcome {
  /// No gate needed: capability ready, platform without a TCC gate, or the
  /// user's after-transcription action doesn't paste at all.
  notNeeded,

  /// Permission missing on first contact — the guided grant alert was
  /// confirmed and the existing grant flow (request + exact Settings pane +
  /// poll + auto-restart where required) has taken over.
  grantFlowStarted,

  /// A grant-driven restart already ran and the permission is STILL
  /// missing — the honest manual-grant loop-exit alert was shown instead of
  /// forcing another restart cycle.
  manualAlertShown,

  /// The user declined the guided grant alert ("Not now") — no Settings
  /// pane, no grant flow. Re-offered on the next start while Auto-Paste
  /// stays enabled.
  declined,
}

/// Combined result, mainly for tests and breadcrumbs.
class StartupGateResult {
  const StartupGateResult({required this.mic, required this.autoPaste});

  final MicGateOutcome mic;
  final AutoPasteGateOutcome autoPaste;
}

/// Status of the Auto-Paste capability as the gate needs to see it, already
/// collapsed by the caller from `PasteCapabilityNotifier` state + settings.
enum AutoPasteGateStatus {
  /// Ready, unsupported platform, or the user's resolved after-transcription
  /// action never pastes — no gate required.
  notNeeded,

  /// Permission missing, first contact this boot chain.
  missing,

  /// Permission missing although a grant-driven restart already ran
  /// (`PasteCapabilityNotifier.restartWasIneffective`).
  missingAfterIneffectiveRestart,
}

/// Microphone-side seams. All UI hooks resolve when the user has acted (or
/// immediately for fire-and-forget presenters on platforms without a
/// confirm signal).
class MicGateHooks {
  const MicGateHooks({
    required this.checkPermission,
    required this.verifyCapture,
    required this.showGrantAlert,
    required this.openSettings,
    required this.showRestartAlert,
  });

  /// `request: false` must be a pure status read (never prompts).
  /// `request: true` may fire the one-time OS dialog on `.notDetermined`;
  /// after a denial the OS returns `false` silently — both verified against
  /// `record_macos` 2.1.1 (`AVCaptureDevice.authorizationStatus` switch).
  final Future<bool> Function({required bool request}) checkPermission;

  /// Opens a short real capture stream and reports whether audio flows in
  /// THIS process. Only invoked on the recovery path (never on a clean
  /// start — no surprise orange-dot mic indicator at every launch).
  final Future<bool> Function() verifyCapture;

  /// Presents the "microphone access missing" dialog. Resolves `true` when
  /// the user confirms the guided fix, `false` when they decline ("Not
  /// now") — declining must abort the whole recovery (no Settings pane, no
  /// polling).
  final Future<bool> Function() showGrantAlert;

  /// Deep-links to the OS microphone privacy pane.
  final Future<void> Function() openSettings;

  /// Presents the forced-restart dialog (confirm relaunches natively).
  final Future<void> Function() showRestartAlert;
}

/// Auto-Paste-side seams.
class AutoPasteGateHooks {
  const AutoPasteGateHooks({
    required this.readStatus,
    required this.showGrantAlert,
    required this.startGrantFlow,
    required this.showManualGrantAlert,
  });

  /// Collapses capability + settings into the gate's view. Expected to have
  /// hydrated the cross-process restart marker and run a first probe before
  /// resolving.
  final Future<AutoPasteGateStatus> Function() readStatus;

  /// Presents the "one switch missing for auto-insert" dialog. Resolves
  /// `true` on confirm, `false` on decline ("Not now") — declining must
  /// abort the grant flow entirely.
  final Future<bool> Function() showGrantAlert;

  /// Hands off to `PasteCapabilityNotifier.requestGrant()` — fires the OS
  /// request (registers the correct Settings toggle), opens the exact pane,
  /// arms the grant poll. The existing app-level restart watch takes it
  /// from there (forced-restart modal on MAS, live flip on Developer-ID).
  final Future<void> Function() startGrantFlow;

  /// Presents the honest "the restart didn't help — re-check System
  /// Settings" loop-exit dialog.
  final Future<void> Function() showManualGrantAlert;
}

/// Orchestrates one startup pass over both permissions. Construct fresh per
/// run; [run] is single-shot.
class StartupPermissionGate {
  StartupPermissionGate({
    required this.mic,
    this.autoPaste,
    this.micPollInterval = const Duration(seconds: 2),
    this.micPollTimeout = const Duration(minutes: 2),
  });

  static final _log = AppLogger('StartupPermissionGate');

  final MicGateHooks mic;

  /// `null` on platforms/builds where Auto-Paste has no permission gate.
  final AutoPasteGateHooks? autoPaste;

  final Duration micPollInterval;
  final Duration micPollTimeout;

  /// Runs the microphone leg first (recording is the core function), then
  /// the Auto-Paste leg — strictly sequential so the two native dialogs can
  /// never compete for the single always-on-top alert slot.
  Future<StartupGateResult> run() async {
    final micOutcome = await _runMicGate();
    _breadcrumb('mic.outcome', {'outcome': micOutcome.name});
    final autoPasteOutcome = await _runAutoPasteGate();
    _breadcrumb('autopaste.outcome', {'outcome': autoPasteOutcome.name});
    return StartupGateResult(mic: micOutcome, autoPaste: autoPasteOutcome);
  }

  Future<MicGateOutcome> _runMicGate() async {
    try {
      if (await mic.checkPermission(request: false)) {
        return MicGateOutcome.alreadyGranted;
      }
      // `.notDetermined` (fresh install, or TCC wiped by an OS update): this
      // fires the real OS dialog — the zero-friction path. After a denial
      // this resolves `false` without any UI (verified, see [MicGateHooks]).
      if (await mic.checkPermission(request: true)) {
        return MicGateOutcome.grantedViaPrompt;
      }

      // Denied. The OS will never show its own dialog again — guide the
      // user to the one toggle only they can flip, then detect it for them.
      // Declinable per HIG; a decline ends the leg with no side effects.
      if (!await mic.showGrantAlert()) {
        return MicGateOutcome.declined;
      }
      await mic.openSettings();

      final granted = await _pollForMicGrant();
      if (!granted) return MicGateOutcome.unresolved;

      // The grant is on disk — but whether the RUNNING process honors it is
      // not contractually guaranteed on macOS. Verify with a real capture
      // probe instead of assuming either way.
      if (await mic.verifyCapture()) {
        return MicGateOutcome.recoveredLive;
      }
      await mic.showRestartAlert();
      return MicGateOutcome.recoveredNeedsRestart;
    } catch (e) {
      // The gate must never take the app down — worst case is the old
      // reactive behavior (failure surfaces at first recording).
      _log.warning('mic gate failed (non-fatal): $e');
      return MicGateOutcome.unresolved;
    }
  }

  Future<bool> _pollForMicGrant() async {
    final deadline = DateTime.now().add(micPollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(micPollInterval);
      if (await mic.checkPermission(request: false)) return true;
    }
    return false;
  }

  Future<AutoPasteGateOutcome> _runAutoPasteGate() async {
    final hooks = autoPaste;
    if (hooks == null) return AutoPasteGateOutcome.notNeeded;
    try {
      switch (await hooks.readStatus()) {
        case AutoPasteGateStatus.notNeeded:
          return AutoPasteGateOutcome.notNeeded;
        case AutoPasteGateStatus.missingAfterIneffectiveRestart:
          await hooks.showManualGrantAlert();
          return AutoPasteGateOutcome.manualAlertShown;
        case AutoPasteGateStatus.missing:
          if (!await hooks.showGrantAlert()) {
            return AutoPasteGateOutcome.declined;
          }
          await hooks.startGrantFlow();
          return AutoPasteGateOutcome.grantFlowStarted;
      }
    } catch (e) {
      _log.warning('auto-paste gate failed (non-fatal): $e');
      return AutoPasteGateOutcome.notNeeded;
    }
  }

  void _breadcrumb(String message, Map<String, Object?> data) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: startupPermissionGateBreadcrumbCategory,
        level: SentryLevel.info,
        data: data,
      ),
    );
  }
}
