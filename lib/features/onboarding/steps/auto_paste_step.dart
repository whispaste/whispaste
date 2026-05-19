/// Onboarding Step 3 — Auto-Paste permission setup.
///
/// On macOS: walks the user through granting the Accessibility permission
/// so Auto-Paste can simulate ⌘V into the focused window. Watches the
/// shared [PasteCapabilityNotifier] for state, opens the macOS Settings
/// panel via the standard `x-apple.systempreferences:` deep link, and
/// polls for the capability to flip to [PasteCapabilityStatus.ready] while
/// the user toggles the setting in System Settings.
///
/// On Windows: Auto-Paste needs no extra permission in the 99% case, so
/// the step renders a minimal verify-only surface: "Ready to paste" with a
/// green checkmark, a one-line explanation, Next immediately enabled, and
/// no Skip button. The remaining edge case is UIPI/UAC-protected windows
/// (e.g. Auto-Paste running un-elevated while the focused target is an
/// elevated process) — there the probe surfaces as `permissionMissing`
/// and the step shows a non-blocking warn card plus an explicit Skip path
/// (analogue to the macOS Skip). Next stays enabled either way because the
/// edge case is non-blocking — the user decides whether to keep Auto-Paste
/// on or switch to clipboard-only.
///
/// On Linux: never rendered — [OnboardingOverlay] omits the step entirely
/// from its platform-dependent step list.
///
/// The Skip path persists `afterTranscription = clipboard` (the codebase's
/// representation of "Auto-Paste off, copy still happens") and advances
/// the onboarding overlay via [onNext]. Polling is stopped on dispose so
/// there is never a leftover timer once the user leaves the step.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/desktop_paste/desktop_paste_controller.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paster.dart';
import '../../../widgets/wp_accent_button.dart';

class AutoPasteStep extends ConsumerStatefulWidget {
  const AutoPasteStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<AutoPasteStep> createState() => _AutoPasteStepState();
}

class _AutoPasteStepState extends ConsumerState<AutoPasteStep> {
  static final _log = AppLogger('AutoPasteStep');

  /// Cached notifier reference so [dispose] can stop polling without
  /// touching `ref` — Riverpod forbids `ref` access after deactivation.
  PasteCapabilityNotifier? _cachedNotifier;

  /// Latest TCC repair attempt outcome, if any. Drives the inline banner
  /// that confirms a successful self-heal or surfaces an error so the user
  /// can retry. `null` means "no repair has run yet in this step".
  TccRepairResult? _lastRepairResult;

  /// Guard against double-tapping the repair button while the native call
  /// is still resolving. Re-enables once the result is bound to state.
  bool _repairInFlight = false;

  /// Guard against double-tapping the Grant CTA while the async sequence
  /// (`notifier.check(prompt: true)` → `startPolling` → settings deep-link)
  /// is still resolving. Re-enables once the chain completes — even on the
  /// error path — so the user can retry without re-mounting the step.
  bool _grantInFlight = false;

  /// Sticky latch: once the TCC-mismatch banner has surfaced for the first
  /// time in this step lifecycle, we don't want a duplicate
  /// `restart_hint.surfaced` breadcrumb every time the banner re-renders
  /// during the same mount. Re-set when the step is re-mounted via the
  /// fresh [State] instance.
  bool _restartHintEmitted = false;

  /// Latest outcome of the diagnostic test paste, or `null` if the user has
  /// not run it yet in this step mount. Drives the success / failure / no-
  /// frontmost banner inside the sub-step and the Next-gate.
  TestPasteOutcome? _testOutcome;

  /// `true` once the user has clicked "Continue without testing". Mirrors
  /// the success outcome for the Next-gate but keeps the sub-step hidden so
  /// the user doesn't see a confusing partial state after opting out.
  bool _userSkippedTest = false;

  @override
  void initState() {
    super.initState();
    _emitBreadcrumb('step.mounted');
    // Probe once on mount without prompting so the UI immediately reflects
    // the current OS state. The shared notifier handles in-flight coalescing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cachedNotifier = ref.read(pasteCapabilityNotifierProvider.notifier);
      _cachedNotifier!.check();
    });
  }

  @override
  void dispose() {
    // Polling lives in the shared notifier; stop it explicitly when the user
    // leaves the step so we don't keep a timer alive after navigation.
    // Use the cached reference because `ref` is unsafe in dispose().
    _cachedNotifier?.stopPolling();
    super.dispose();
  }

  Future<void> _openAccessibilitySettings() async {
    if (!Platform.isMacOS) return;
    final uri = Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    );
    try {
      await launchUrl(uri);
    } on Exception catch (e) {
      _log.warning('Could not open Accessibility settings', e);
    }
  }

  Future<void> _onGrantPressed() async {
    if (_grantInFlight) return;
    _emitBreadcrumb('grant.requested');
    setState(() => _grantInFlight = true);
    _emitBreadcrumb('grant.busy_state_armed');
    try {
      final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
      // First fire the prompted check so macOS gets a chance to surface its
      // own one-shot dialog. Then deep-link to the Accessibility pane so the
      // user sees the toggle row even if the OS dialog was suppressed.
      await notifier.check(prompt: true);
      // Arm polling BEFORE awaiting the settings launch — we want the poller
      // running the moment the user flips the toggle in System Settings, not
      // after the deep-link future resolves (which can stall on slow Settings
      // launches and in test environments where the channel isn't wired).
      notifier.startPolling(
        interval: const Duration(seconds: 1),
        timeout: const Duration(seconds: 30),
      );
      await _openAccessibilitySettings();
    } finally {
      if (mounted) {
        setState(() => _grantInFlight = false);
      }
    }
  }

  /// Runs the macOS TCC self-heal and — on success — chains into a fresh
  /// grant attempt so the user lands in the working sequence without having
  /// to click a second button. On failure the result is kept in
  /// [_lastRepairResult] so the inline banner can surface the error and let
  /// the user retry or skip.
  Future<void> _onRepairPressed() async {
    if (_repairInFlight) return;
    setState(() {
      _repairInFlight = true;
      _lastRepairResult = null;
    });
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    TccRepairResult result;
    try {
      result = await notifier.repair();
    } on Exception catch (e, st) {
      _log.warning('Repair call threw', e, st);
      result = const TccRepairResult(
        accessibilityCleared: -1,
        appleEventsCleared: -1,
        error: 'exception',
      );
    }
    if (!mounted) return;
    setState(() {
      _lastRepairResult = result;
      _repairInFlight = false;
    });
    _emitBreadcrumb(
      'repair.invoked',
      data: {'result_kind': result.isSupported ? 'success' : 'failure'},
    );
    // On success: smoothly chain into a second grant attempt so the user
    // ends up in the working flow without having to click "Grant" again.
    // The result still shows in the banner so they understand what just
    // happened ("Cleared N stale entries — now retrying permission").
    if (result.isSupported) {
      await _onGrantPressed();
    }
  }

  /// Runs the diagnostic test paste through the shared notifier and binds
  /// the outcome to local state so the sub-step banner can render the right
  /// branch. The skip latch resets implicitly because the user only sees
  /// this CTA while the sub-step is still visible.
  Future<void> _onRunTestPastePressed() async {
    final l10n = L10n.of(context);
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    final outcome = await notifier.runDiagnosticPaste(
      l10n.onboardingPasteDemoText,
    );
    if (!mounted) return;
    setState(() => _testOutcome = outcome);
  }

  /// "Continue without testing" handler — flips the skip latch and emits a
  /// dedicated Sentry breadcrumb so we can measure the opt-out rate.
  void _onSkipTestPressed() {
    _emitBreadcrumb('diagnostic_paste.skipped');
    setState(() => _userSkippedTest = true);
  }

  Future<void> _onSkipPressed() async {
    // Capture the failed-grant bit BEFORE persisting the skip so the
    // breadcrumb describes the state the user actually skipped from.
    final hadFailedGrantAttempt = ref
        .read(pasteCapabilityNotifierProvider)
        .hadFailedGrantAttempt;
    _emitBreadcrumb(
      'skipped',
      data: {'had_failed_grant_attempt': hadFailedGrantAttempt},
    );
    // Skip explicitly disables Auto-Paste rather than silently leaving the
    // user in a half-state. "clipboard" is the codebase's encoding for
    // "transcript goes to clipboard, no automated paste".
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(
            afterTranscription: AfterTranscriptionAction.clipboard.value,
          ),
        );
    widget.onNext();
  }

  /// Emits a Sentry breadcrumb under the shared onboarding Auto-Paste
  /// category. Always carries the host `platform` tag so funnel queries can
  /// slice across macOS / Windows / Linux. PII-free by construction.
  void _emitBreadcrumb(String message, {Map<String, Object?> data = const {}}) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: onboardingAutoPasteBreadcrumbCategory,
        level: SentryLevel.info,
        data: {'platform': _autoPastePlatformTag(), ...data},
      ),
    );
  }

  String _autoPastePlatformTag() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      _ => 'unknown',
    };
  }

  @override
  Widget build(BuildContext context) {
    // Branch on `defaultTargetPlatform` (not `Platform.isMacOS`) so widget
    // tests can simulate the Windows surface from a macOS / Linux test host
    // via `debugDefaultTargetPlatformOverride`. The macOS-only inner calls
    // (`_openAccessibilitySettings`) still guard with `Platform.isMacOS`,
    // which is fine: those code paths only fire from user-driven taps the
    // Windows branch never exposes.
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows) {
      return _WindowsBody(
        state: ref.watch(pasteCapabilityNotifierProvider),
        testOutcome: _testOutcome,
        userSkippedTest: _userSkippedTest,
        onRunTestPaste: _onRunTestPastePressed,
        onSkipTest: _onSkipTestPressed,
        onNext: widget.onNext,
        onBack: widget.onBack,
        onSkip: _onSkipPressed,
      );
    }
    final state = ref.watch(pasteCapabilityNotifierProvider);
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    _cachedNotifier = notifier;
    final showTccMismatchBanner = notifier.suspectedTccMismatch;
    // Sticky-latch the `restart_hint.surfaced` breadcrumb so it fires exactly
    // once per step mount the first time the banner becomes visible — repeat
    // rebuilds while the banner is up must not spam Sentry. The latch is an
    // instance field, so a re-mount (fresh State) naturally resets it.
    if (showTccMismatchBanner && !_restartHintEmitted) {
      _restartHintEmitted = true;
      _emitBreadcrumb('restart_hint.surfaced');
    }
    return _MacOsBody(
      state: state,
      notifier: notifier,
      repairInFlight: _repairInFlight,
      grantInFlight: _grantInFlight,
      lastRepairResult: _lastRepairResult,
      showTccMismatchBanner: showTccMismatchBanner,
      testOutcome: _testOutcome,
      userSkippedTest: _userSkippedTest,
      onGrant: _onGrantPressed,
      onRepair: _onRepairPressed,
      onSkip: _onSkipPressed,
      onRunTestPaste: _onRunTestPastePressed,
      onSkipTest: _onSkipTestPressed,
      onNext: widget.onNext,
      onBack: widget.onBack,
    );
  }
}

// =============================================================================
// macOS body — full Grant/Repair/Skip flow.
// =============================================================================

class _MacOsBody extends StatelessWidget {
  const _MacOsBody({
    required this.state,
    required this.notifier,
    required this.repairInFlight,
    required this.grantInFlight,
    required this.lastRepairResult,
    required this.showTccMismatchBanner,
    required this.testOutcome,
    required this.userSkippedTest,
    required this.onGrant,
    required this.onRepair,
    required this.onSkip,
    required this.onRunTestPaste,
    required this.onSkipTest,
    required this.onNext,
    required this.onBack,
  });

  final PasteCapabilityState state;
  final PasteCapabilityNotifier notifier;
  final bool repairInFlight;
  final bool grantInFlight;
  final TccRepairResult? lastRepairResult;

  /// True when the parent has decided the TCC-mismatch banner should be
  /// visible (driven by [PasteCapabilityNotifier.suspectedTccMismatch]).
  /// Threaded as a flag rather than recomputed inline so the parent owns
  /// the single source of truth and can co-locate the sticky-latch
  /// breadcrumb emission with the render decision.
  final bool showTccMismatchBanner;

  /// Latest diagnostic paste outcome (or `null` before the user ran it).
  final TestPasteOutcome? testOutcome;

  /// `true` if the user clicked "Continue without testing".
  final bool userSkippedTest;

  final Future<void> Function() onGrant;
  final Future<void> Function() onRepair;
  final Future<void> Function() onSkip;
  final Future<void> Function() onRunTestPaste;
  final VoidCallback onSkipTest;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final cap = state.capability;
    final isReady = cap?.status == PasteCapabilityStatus.ready;

    // Lazy reveal: Repair only makes sense once the user has tried to grant
    // permission AND the OS still reports it as missing — the classic
    // ad-hoc-signed-Sequoia stale-TCC symptom. Before that, the button is
    // pure noise.
    final showRepair =
        state.hadFailedGrantAttempt &&
        cap?.status == PasteCapabilityStatus.permissionMissing;

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final successColor = isDark ? WpColorsDark.success : WpColorsLight.success;
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;
    final warningColor = isDark ? WpColorsDark.warning : WpColorsLight.warning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Title ----------------------------------------------------------
        Text(
          l10n.onboardingPasteTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingPasteSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
        ),
        const SizedBox(height: WpSpacing.xl),

        // -- Permission status card ----------------------------------------
        _PermissionStatusCard(
          status: cap?.status,
          isPolling: notifier.isPolling,
          isDark: isDark,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          successColor: successColor,
          errorColor: errorColor,
          l10n: l10n,
        ),

        // -- Polling hint card --------------------------------------------
        // Only visible while we are actively awaiting the user's grant —
        // hidden once polling self-stops on success/timeout, and obviously
        // hidden before the user ever clicked Grant.
        if (state.pollingPhase == PollingPhase.awaitingGrant) ...[
          const SizedBox(height: WpSpacing.sm),
          _PollingHintCard(
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            l10n: l10n,
          ),
        ],
        // -- TCC-mismatch banner -----------------------------------------
        // Surfaces the ad-hoc-signed-Sequoia "permission granted in System
        // Settings but `AXIsProcessTrusted()` still returns false" symptom
        // with two actionable recovery options (Repair / restart WhisPaste).
        // Visually slots into the same row as the polling-hint card — the
        // two are mutually exclusive (timedOut vs awaitingGrant phases).
        if (showTccMismatchBanner) ...[
          const SizedBox(height: WpSpacing.sm),
          _TccMismatchBanner(
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            warningColor: warningColor,
            l10n: l10n,
          ),
        ],
        const SizedBox(height: WpSpacing.lg),

        // -- Grant CTA -- only shown until permission is ready --------------
        if (!isReady) ...[
          SizedBox(
            width: double.infinity,
            child: WpAccentButton(
              label: l10n.onboardingPasteGrantCta,
              gradient: accentGradient,
              // Disable while the async grant chain (prompted check →
              // startPolling → settings deep-link) is still resolving so a
              // user mashing the button doesn't queue up duplicate flows.
              onPressed: grantInFlight ? null : onGrant,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(
            l10n.onboardingPasteWhyMac,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: textMuted, height: 1.4),
          ),
          // -- Lazy Repair -- only after a prompted grant attempt failed ----
          if (showRepair) ...[
            const SizedBox(height: WpSpacing.md),
            _RepairPanel(
              busy: repairInFlight,
              lastResult: lastRepairResult,
              onRepair: repairInFlight ? null : onRepair,
              isDark: isDark,
              textSecondary: textSecondary,
              textMuted: textMuted,
              errorColor: errorColor,
              successColor: successColor,
              l10n: l10n,
            ),
          ],
          const SizedBox(height: WpSpacing.sm),
          // Skip — sets afterTranscription=clipboard and advances.
          TextButton(
            onPressed: onSkip,
            child: Text(
              l10n.onboardingPasteSkip,
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
          ),
        ],

        // -- Test-paste sub-step — the explicit "prove Auto-Paste works"
        // gate. Visible exactly while the user is in the ready state and
        // has not yet either passed the test or opted out via the skip
        // link. After success the sub-step keeps the demo field visible
        // (so the user can see what got pasted) but swaps the CTA row for
        // the green confirmation banner.
        if (isReady && !userSkippedTest) ...[
          const SizedBox(height: WpSpacing.lg),
          _TestPasteSubStep(
            outcome: testOutcome,
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            accentGradient: accentGradient,
            successColor: successColor,
            errorColor: errorColor,
            warningColor: warningColor,
            l10n: l10n,
            onRun: onRunTestPaste,
            onSkip: onSkipTest,
          ),
        ],

        const SizedBox(height: WpSpacing.lg),

        // -- Navigation row -------------------------------------------------
        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                // Gate: ready + (test passed OR user explicitly skipped).
                // Before the user resolves the sub-step, Next stays
                // disabled so we don't ship Auto-Paste users out of
                // onboarding without ever proving the bridge works.
                onPressed:
                    (isReady &&
                        (testOutcome is TestPasteOutcomeSuccess ||
                            userSkippedTest))
                    ? onNext
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Windows body — minimal verify in the 99% case, non-blocking UIPI warn
// for the rare edge where the probe reports permissionMissing.
// =============================================================================

class _WindowsBody extends StatelessWidget {
  const _WindowsBody({
    required this.state,
    required this.testOutcome,
    required this.userSkippedTest,
    required this.onRunTestPaste,
    required this.onSkipTest,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final PasteCapabilityState state;

  /// Latest diagnostic paste outcome (or `null` before the user ran it).
  final TestPasteOutcome? testOutcome;

  /// `true` if the user clicked "Continue without testing".
  final bool userSkippedTest;

  final Future<void> Function() onRunTestPaste;
  final VoidCallback onSkipTest;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final cap = state.capability;
    // UIPI/UAC edge: the SendInput bridge cannot deliver keystrokes into an
    // elevated target window when WhisPaste itself runs un-elevated. We
    // surface this as a non-blocking warning — the user keeps the choice
    // between leaving Auto-Paste on or skipping to clipboard-only mode.
    final isUipiEdge = cap?.status == PasteCapabilityStatus.permissionMissing;

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final successColor = isDark ? WpColorsDark.success : WpColorsLight.success;
    final warningColor = isDark ? WpColorsDark.warning : WpColorsLight.warning;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Title ---------------------------------------------------------
        Text(
          l10n.onboardingPasteTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingPasteSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
        ),
        const SizedBox(height: WpSpacing.xl),

        if (isUipiEdge) ...[
          // -- UIPI warn card (non-blocking) ------------------------------
          _WindowsWarnCard(
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            warningColor: warningColor,
            message: l10n.onboardingPasteWhyWinUipi,
          ),
          const SizedBox(height: WpSpacing.sm),
          // Skip — sets afterTranscription=clipboard and advances. Same
          // wording as the macOS skip (`onboardingPasteSkip`) so the option
          // is recognisable across platforms.
          TextButton(
            onPressed: onSkip,
            child: Text(
              l10n.onboardingPasteSkip,
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
          ),
        ] else ...[
          // -- Verify card (default, 99% case) ----------------------------
          _WindowsVerifyCard(
            isDark: isDark,
            textPrimary: textPrimary,
            successColor: successColor,
            label: l10n.pasteCapabilityReady,
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(
            l10n.onboardingPasteWhyWin,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: textMuted, height: 1.4),
          ),
          // -- Test-paste sub-step — the explicit "prove Auto-Paste works"
          // gate. Visible exactly while the user is in the ready state and
          // has not yet either passed the test or opted out via skip.
          if (!userSkippedTest) ...[
            const SizedBox(height: WpSpacing.lg),
            _TestPasteSubStep(
              outcome: testOutcome,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textMuted: textMuted,
              accentGradient: accentGradient,
              successColor: successColor,
              errorColor: isDark ? WpColorsDark.error : WpColorsLight.error,
              warningColor: warningColor,
              l10n: l10n,
              onRun: onRunTestPaste,
              onSkip: onSkipTest,
            ),
          ],
        ],

        const SizedBox(height: WpSpacing.lg),

        // -- Navigation row -----------------------------------------------
        // Next-gate:
        //   - UIPI edge: explicitly non-blocking; Next stays enabled so the
        //     user can keep Auto-Paste on and still advance.
        //   - Verify (ready) branch: gated on the test-paste sub-step —
        //     either the diagnostic paste succeeded or the user opted out
        //     via "Continue without testing".
        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed:
                    (isUipiEdge ||
                        testOutcome is TestPasteOutcomeSuccess ||
                        userSkippedTest)
                    ? onNext
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Minimal Windows verify-state card: green checkmark + "Ready to paste".
/// No actions inside the card; the surrounding column wires up Next.
class _WindowsVerifyCard extends StatelessWidget {
  const _WindowsVerifyCard({
    required this.isDark,
    required this.textPrimary,
    required this.successColor,
    required this.label,
  });

  final bool isDark;
  final Color textPrimary;
  final Color successColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleCheck, size: 22, color: successColor),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-blocking Windows warn card surfacing the UIPI/UAC edge case. Uses
/// the warning palette (not the error palette) because the situation is
/// recoverable — Auto-Paste still works for non-elevated target apps and
/// the clipboard path is always available as a fallback.
class _WindowsWarnCard extends StatelessWidget {
  const _WindowsWarnCard({
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.warningColor,
    required this.message,
  });

  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color warningColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 20, color: warningColor),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionStatusCard extends StatelessWidget {
  const _PermissionStatusCard({
    required this.status,
    required this.isPolling,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.successColor,
    required this.errorColor,
    required this.l10n,
  });

  final PasteCapabilityStatus? status;
  final bool isPolling;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color successColor;
  final Color errorColor;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _resolve();
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ),
          if (isPolling)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  (IconData, Color, String) _resolve() {
    if (status == null) {
      return (
        LucideIcons.loaderCircle,
        textSecondary,
        l10n.pasteCapabilityCheckTitle,
      );
    }
    return switch (status!) {
      PasteCapabilityStatus.ready => (
        LucideIcons.circleCheck,
        successColor,
        l10n.pasteCapabilityReady,
      ),
      PasteCapabilityStatus.permissionMissing => (
        LucideIcons.shieldAlert,
        errorColor,
        l10n.pasteCapabilityPermissionMissing,
      ),
      PasteCapabilityStatus.unsupported => (
        LucideIcons.info,
        textSecondary,
        l10n.pasteCapabilityUnsupported,
      ),
    };
  }
}

/// Lazy self-heal panel: surfaces the TCC repair button plus a contextual
/// banner explaining why it might help, and renders the post-call outcome
/// inline (success count / error copy) so the user never has to chase a
/// disappearing snackbar to understand what happened.
class _RepairPanel extends StatelessWidget {
  const _RepairPanel({
    required this.busy,
    required this.lastResult,
    required this.onRepair,
    required this.isDark,
    required this.textSecondary,
    required this.textMuted,
    required this.errorColor,
    required this.successColor,
    required this.l10n,
  });

  final bool busy;
  final TccRepairResult? lastResult;
  final VoidCallback? onRepair;
  final bool isDark;
  final Color textSecondary;
  final Color textMuted;
  final Color errorColor;
  final Color successColor;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pasteCapabilityRepairHint,
            style: TextStyle(fontSize: 12, color: textMuted, height: 1.4),
          ),
          const SizedBox(height: WpSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRepair,
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.wrench, size: 14),
              label: Text(l10n.pasteCapabilityRepairButton),
            ),
          ),
          if (lastResult != null) ...[
            const SizedBox(height: WpSpacing.sm),
            _RepairResultBanner(
              result: lastResult!,
              errorColor: errorColor,
              successColor: successColor,
              textSecondary: textSecondary,
              l10n: l10n,
            ),
          ],
        ],
      ),
    );
  }
}

/// Step-by-step guidance card surfaced only while
/// [PasteCapabilityNotifier] is in the [PollingPhase.awaitingGrant] phase.
///
/// Explains *what* the app is doing (polling for the OS to flip the
/// Accessibility toggle) and *what the user has to do* (find WhisPaste in
/// the System Settings pane that just opened, switch it on). Without this
/// card the polling spinner reads as "something is loading" — opaque from
/// the user's perspective and a known onboarding drop-off point.
///
/// Surface/border colours mirror [_PermissionStatusCard] so the two cards
/// read as a unit; the info icon distinguishes the role (status vs. hint).
class _PollingHintCard extends StatelessWidget {
  const _PollingHintCard({
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.l10n,
  });

  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 20, color: textSecondary),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.onboardingPasteWaitingForGrantTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                Text(
                  l10n.onboardingPasteWaitingForGrantHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recovery banner for the ad-hoc-signed-Sequoia "permission granted but
/// `AXIsProcessTrusted()` still returns false" symptom. Surfaced only when
/// [PasteCapabilityNotifier.suspectedTccMismatch] is `true` — i.e. the
/// polling loop timed out after a failed grant attempt while the capability
/// is still reported as `permissionMissing`.
///
/// Warning palette (not error) because the situation is recoverable: the
/// banner guides the user through two concrete recovery steps — pressing
/// Repair below to clear stale TCC entries, or quitting and restarting
/// WhisPaste so macOS picks up the current app signature. Surface/border
/// styling matches the other cards in the step so the layout reads as a
/// unit; only the icon colour distinguishes the warning role.
class _TccMismatchBanner extends StatelessWidget {
  const _TccMismatchBanner({
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.warningColor,
    required this.l10n,
  });

  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color warningColor;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 20, color: warningColor),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.onboardingPasteTccMismatchTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                Text(
                  l10n.onboardingPasteTccMismatchBody,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RepairResultBanner extends StatelessWidget {
  const _RepairResultBanner({
    required this.result,
    required this.errorColor,
    required this.successColor,
    required this.textSecondary,
    required this.l10n,
  });

  final TccRepairResult result;
  final Color errorColor;
  final Color successColor;
  final Color textSecondary;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final ok = result.isSupported;
    final color = ok ? successColor : errorColor;
    final icon = ok ? LucideIcons.circleCheck : LucideIcons.circleAlert;
    // Special-case "supported but nothing actually cleared": the generic
    // pluralised "0 entries removed" copy reads as a no-op, while the
    // honest message is "we couldn't clean anything — your reliable next
    // step is restarting WhisPaste". Route the user there explicitly.
    final nothingCleared =
        ok &&
        result.accessibilityCleared == 0 &&
        result.appleEventsCleared == 0;
    final String message;
    if (!ok) {
      message = l10n.pasteCapabilityRepairFailed;
    } else if (nothingCleared) {
      message = l10n.pasteCapabilityRepairNothingToClear;
    } else {
      message = l10n.pasteCapabilityRepairDone(
        result.accessibilityCleared.clamp(0, 999) +
            result.appleEventsCleared.clamp(0, 999),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: WpSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// Onboarding sub-step that exercises the Auto-Paste pipeline against a
/// real input field so the user has *evidence* the bridge works before
/// finishing onboarding. Renders three branches off the latest
/// [TestPasteOutcome]:
///
///   - `null` (not run yet): demo TextField + "Run test paste" CTA +
///     "Continue without testing" link.
///   - [TestPasteOutcomeSuccess]: green confirmation banner; the demo
///     field stays around so the user can see the pasted text.
///   - [TestPasteOutcomeNoFrontmost] / [TestPasteOutcomeFailure]: warn
///     banner with retry CTA. `failure(not_trusted)` additionally surfaces
///     a hint about the permission edge case.
///   - [TestPasteOutcomeUnsupported]: the parent normally hides the
///     sub-step entirely in this case (Linux defensive). Falls through to
///     a minimal warn banner if it ever does render — the user can still
///     opt out via the skip link.
class _TestPasteSubStep extends StatefulWidget {
  const _TestPasteSubStep({
    required this.outcome,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accentGradient,
    required this.successColor,
    required this.errorColor,
    required this.warningColor,
    required this.l10n,
    required this.onRun,
    required this.onSkip,
  });

  final TestPasteOutcome? outcome;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final LinearGradient accentGradient;
  final Color successColor;
  final Color errorColor;
  final Color warningColor;
  final L10n l10n;
  final Future<void> Function() onRun;
  final VoidCallback onSkip;

  @override
  State<_TestPasteSubStep> createState() => _TestPasteSubStepState();
}

class _TestPasteSubStepState extends State<_TestPasteSubStep> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    // Hand focus to the demo field on mount so the native Cmd+V / Ctrl+V
    // synthesis lands in this app's text input rather than e.g. the host
    // shell. Wrapped in addPostFrameCallback so the focus request hits a
    // mounted, rendered field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.outcome;
    final surface =
        (widget.isDark
                ? WpColorsDark.surfaceVariant
                : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = widget.isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.l10n.onboardingPasteTestTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: widget.textPrimary,
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            widget.l10n.onboardingPasteTestSubtitle,
            style: TextStyle(
              fontSize: 12,
              color: widget.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          ..._buildOutcomeBranch(outcome),
        ],
      ),
    );
  }

  /// Renders the CTA row / outcome banner appropriate for the current
  /// [TestPasteOutcome]. Split out so the build method stays readable and
  /// each branch can declare its own widgets without indentation
  /// gymnastics.
  List<Widget> _buildOutcomeBranch(TestPasteOutcome? outcome) {
    if (outcome is TestPasteOutcomeSuccess) {
      return [
        _OutcomeBanner(
          icon: LucideIcons.circleCheck,
          color: widget.successColor,
          message: widget.l10n.onboardingPasteTestSuccess,
          textColor: widget.textSecondary,
        ),
      ];
    }
    if (outcome is TestPasteOutcomeNoFrontmost) {
      return [
        _OutcomeBanner(
          icon: LucideIcons.triangleAlert,
          color: widget.warningColor,
          message: widget.l10n.onboardingPasteTestNoFrontmost,
          textColor: widget.textSecondary,
        ),
        const SizedBox(height: WpSpacing.sm),
        _runAndSkipRow(),
      ];
    }
    if (outcome is TestPasteOutcomeFailure) {
      final showNotTrustedHint = outcome.reason == 'not_trusted';
      return [
        _OutcomeBanner(
          icon: LucideIcons.circleAlert,
          color: widget.errorColor,
          message: widget.l10n.onboardingPasteTestFailure,
          textColor: widget.textSecondary,
        ),
        if (showNotTrustedHint) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            widget.l10n.onboardingPasteTccMismatchBody,
            style: TextStyle(
              fontSize: 11,
              color: widget.textMuted,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: WpSpacing.sm),
        _runAndSkipRow(),
      ];
    }
    // outcome == null or unsupported → initial CTA row.
    return [_runAndSkipRow()];
  }

  Widget _runAndSkipRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpAccentButton(
          label: widget.l10n.onboardingPasteTestRunCta,
          gradient: widget.accentGradient,
          onPressed: widget.onRun,
        ),
        const SizedBox(height: WpSpacing.xs),
        TextButton(
          onPressed: widget.onSkip,
          child: Text(
            widget.l10n.onboardingPasteTestSkip,
            style: TextStyle(color: widget.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Small banner widget used inside [_TestPasteSubStep] to render the
/// outcome of a diagnostic test paste. Style mirrors the other inline
/// banners in this step (icon + text on the surface-variant background).
class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({
    required this.icon,
    required this.color,
    required this.message,
    required this.textColor,
  });

  final IconData icon;
  final Color color;
  final String message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: WpSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 12, color: textColor, height: 1.4),
          ),
        ),
      ],
    );
  }
}
