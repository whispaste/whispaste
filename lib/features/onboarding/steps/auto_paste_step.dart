/// Content of the Auto-Paste onboarding page — the permission that lets a
/// transcript land at the cursor.
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
/// green checkmark and a one-line explanation. The remaining edge case is
/// UIPI/UAC-protected windows (e.g. Auto-Paste running un-elevated while
/// the focused target is an elevated process) — there the probe surfaces as
/// `permissionMissing` and the step shows a non-blocking warn card plus the
/// explicit Skip path (analogue to the macOS Skip).
///
/// On Linux: never rendered — the page is omitted from the step sequence
/// entirely (no paste controller is wired there), so Linux runs a six-step
/// flow rather than a seven-step one with a blank page in it. See
/// `onboardingIncludesAutoPasteStep`.
///
/// The Skip path persists `afterTranscription = clipboard` (the codebase's
/// representation of "Auto-Paste off, copy still happens"); page navigation
/// is owned by the onboarding shell, so Skip is a pure mode choice and no
/// longer advances the flow itself. Polling is stopped on dispose so there
/// is never a leftover timer once the user leaves the step.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/desktop_paste/desktop_paste_controller.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paster.dart';
import '../../../widgets/paste_capability_restart_banner.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_hero_button.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;

/// Edge of the square status badge, from DESIGN.md's Quiet Status Rule
/// ("a tinted 32px icon badge plus copy"). Not a [WpIconSize] value — the
/// 32 there is an *icon* grade, and this is the badge the 16-px icon sits in.
const double _kStatusBadgeSize = 32;

class AutoPasteStep extends ConsumerStatefulWidget {
  const AutoPasteStep({super.key});

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

  Future<void> _onGrantPressed() async {
    if (_grantInFlight) return;
    _emitBreadcrumb('grant.requested');
    setState(() => _grantInFlight = true);
    _emitBreadcrumb('grant.busy_state_armed');
    try {
      final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.requestGrant();
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

  Future<void> _onSkipPressed() async {
    // Capture the grant-handoff bit BEFORE persisting the skip so the
    // breadcrumb describes the state the user actually skipped from.
    final sentToOsGrantFlow = ref
        .read(pasteCapabilityNotifierProvider)
        .sentToOsGrantFlow;
    _emitBreadcrumb(
      'skipped',
      data: {'sent_to_os_grant_flow': sentToOsGrantFlow},
    );
    // Skip explicitly disables Auto-Paste rather than silently leaving the
    // user in a half-state. "clipboard" is the codebase's encoding for
    // "transcript goes to clipboard, no automated paste". Navigation stays
    // with the onboarding shell — this is a mode choice, not an advance.
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(
            afterTranscription: AfterTranscriptionAction.clipboard.value,
          ),
        );
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
    // via `debugDefaultTargetPlatformOverride`. The macOS-only inner call
    // (`PasteCapabilityNotifier.requestGrant`) still guards with
    // `Platform.isMacOS`, which is fine: those code paths only fire from
    // user-driven taps the Windows branch never exposes.
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows) {
      return _WindowsBody(
        state: ref.watch(pasteCapabilityNotifierProvider),
        onSkip: _onSkipPressed,
      );
    }
    final state = ref.watch(pasteCapabilityNotifierProvider);
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    _cachedNotifier = notifier;
    final showTccMismatchBanner = notifier.needsRestart;
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
      onGrant: _onGrantPressed,
      onRepair: _onRepairPressed,
      onSkip: _onSkipPressed,
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
    required this.onGrant,
    required this.onRepair,
    required this.onSkip,
  });

  final PasteCapabilityState state;
  final PasteCapabilityNotifier notifier;
  final bool repairInFlight;
  final bool grantInFlight;
  final TccRepairResult? lastRepairResult;

  /// True when the parent has decided the restart banner should be visible
  /// (driven by [PasteCapabilityNotifier.needsRestart]). Threaded as a flag
  /// rather than recomputed inline so the parent owns the single source of
  /// truth and can co-locate the sticky-latch breadcrumb emission with the
  /// render decision.
  final bool showTccMismatchBanner;

  final Future<void> Function() onGrant;
  final Future<void> Function() onRepair;
  final Future<void> Function() onSkip;

  /// Phase the UI is currently rendering. Derived from `state.capability`
  /// and `state.pollingPhase` so the build is a pure function of state.
  _AutoPastePhase get _phase {
    final cap = state.capability;
    if (cap == null) return _AutoPastePhase.checking;
    if (cap.status == PasteCapabilityStatus.ready) {
      return _AutoPastePhase.granted;
    }
    if (cap.status == PasteCapabilityStatus.unsupported) {
      // Defensive — the parent step list excludes this body on Linux so the
      // user never sees it; render the intro layout as a fallback.
      return _AutoPastePhase.intro;
    }
    if (showTccMismatchBanner) return _AutoPastePhase.troubleshoot;
    if (state.pollingPhase == PollingPhase.awaitingGrant) {
      return _AutoPastePhase.waiting;
    }
    return _AutoPastePhase.intro;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    const textPrimary = WpColors.textPrimary;
    const textSecondary = WpColors.textSecondary;
    const textMuted = WpColors.textMuted;
    const accentGradient = WpColors.accentWarmGradient;
    const successColor = WpColors.success;
    const warningColor = WpColors.warning;
    const errorColor = WpColors.error;

    final phase = _phase;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No title here: Auto-Paste has its own page now and the page owns
        // the heading (see the overlay's page composition) — the same two
        // strings this block used to carry as a section label.
        //
        // -- Phase body — exactly one card + one primary CTA per phase ----
        ..._buildPhase(
          phase: phase,
          l10n: l10n,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textMuted: textMuted,
          accentGradient: accentGradient,
          successColor: successColor,
          warningColor: warningColor,
          errorColor: errorColor,
        ),
      ],
    );
  }

  List<Widget> _buildPhase({
    required _AutoPastePhase phase,
    required L10n l10n,
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required LinearGradient accentGradient,
    required Color successColor,
    required Color warningColor,
    required Color errorColor,
  }) {
    // -- One page, five states of it -------------------------------------
    //
    // The five branches used to be five *pages*: `checking` was a lone status
    // line with no explanation and no control (the state a first run lands in
    // first, and the one it is most likely to be photographed in), `intro`
    // opened with a full-width CTA and no statement of where the permission
    // actually stood, `waiting` swapped the status card out for a different
    // card entirely, and `troubleshoot` stacked 492 px against `checking`'s
    // 189. Nothing was wrong with any one of them; there was simply no state
    // the page had been designed *to*, so every branch had invented its own
    // shape and the user re-read the page on each transition.
    //
    // There is one shape now, and only its contents change:
    //
    //   status card   — where the permission stands, always, with the same
    //                   badge geometry the Settings surface uses
    //   action        — the phase's single primary control, if it has one
    //   why           — what happens if the answer is no; constant while the
    //                   permission is missing, because that is exactly the
    //                   question the user is weighing in every one of those
    //                   states
    //   skip          — the way out, in every state that has one
    //
    // `granted` is the one deliberate exception and reads as a terminal: no
    // why (the caveat no longer applies) and no skip (there is nothing left
    // to skip). Everything else differs only in what the card says, which is
    // what makes the transitions read as one page updating rather than as
    // four pages taking turns.
    final skip = Align(
      alignment: AlignmentDirectional.centerStart,
      child: WpButton(
        label: l10n.onboardingPasteSkip,
        variant: WpButtonVariant.ghost,
        tone: WpButtonTone.neutral,
        onPressed: onSkip,
      ),
    );

    final why = Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Text(
        l10n.onboardingPasteWhyMac,
        textAlign: TextAlign.start,
        style: TextStyle(
          fontSize: WpTypography.small,
          color: textMuted,
          height: 1.4,
        ),
      ),
    );

    // Card contents per phase. `permissionMissing` is amber, not red: the
    // Quiet Status Rule reserves red for actual failures, and a permission
    // the user has simply not been asked for yet is not one — it is the
    // normal opening state of this page.
    final (
      IconData icon,
      Color color,
      Color tint,
      String title,
    ) = switch (phase) {
      _AutoPastePhase.checking => (
        LucideIcons.loaderCircle,
        textSecondary,
        WpColors.mutedActiveFill,
        l10n.onboardingPasteChipPending,
      ),
      _AutoPastePhase.granted => (
        LucideIcons.circleCheck,
        successColor,
        WpColors.successActiveFill,
        l10n.onboardingPasteChipReady,
      ),
      _AutoPastePhase.waiting => (
        LucideIcons.squareCheckBig,
        warningColor,
        WpColors.warningActiveFill,
        l10n.onboardingPasteWaitingForGrantTitle,
      ),
      _AutoPastePhase.intro || _AutoPastePhase.troubleshoot => (
        LucideIcons.shieldAlert,
        warningColor,
        WpColors.warningActiveFill,
        l10n.onboardingPasteChipAction,
      ),
    };

    // The detail line is what turned a 640-px card holding three words into a
    // card holding its own explanation — the `waiting` phase's step-by-step
    // hint used to need a second card of its own for this (`_PollingHintCard`,
    // now gone), which is precisely how the page ended up with two different
    // card shapes for one job.
    // `null` on the phases whose title already says the whole thing —
    // `granted` in particular: the page header above this card already runs
    // [AppLocalizations.onboardingPasteSubtitle], so repeating it here would
    // print the same sentence twice on one screen, in the future tense, for a
    // permission the user has just granted.
    final String? detail = switch (phase) {
      _AutoPastePhase.waiting => l10n.onboardingPasteWaitingForGrantHint,
      _ => null,
    };

    final card = _PermissionStatusCard(
      icon: icon,
      color: color,
      tint: tint,
      title: title,
      detail: detail,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
    );

    final actions = switch (phase) {
      _AutoPastePhase.intro => <Widget>[
        SizedBox(
          width: double.infinity,
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpHeroButton.build
          child: WpHeroButton(
            label: l10n.onboardingPasteGrantCta,
            gradient: accentGradient,
            onPressed: grantInFlight ? null : onGrant,
          ),
        ),
      ],
      _AutoPastePhase.troubleshoot => <Widget>[
        WpPasteCapabilityRestartBanner(
          onRestart: () => notifier.restartForGrant(),
        ),
        // `sm`, not the page's `md`: these three are one recovery stack —
        // the problem, the fix, and the fallback with its outcome — so they
        // group tighter than the blocks the page separates with `md`. It is
        // also the only branch where that matters, because it is the only
        // one that stacks four things at once.
        const SizedBox(height: WpSpacing.sm),
        // Secondary fallback: reset the entry instead of restarting.
        // Surfaces the existing repair flow without giving it equal weight.
        WpButton(
          label: l10n.pasteCapabilityRepairButton,
          variant: WpButtonVariant.secondary,
          tone: WpButtonTone.neutral,
          icon: LucideIcons.wrench,
          isLoading: repairInFlight,
          onPressed: onRepair,
        ),
        if (lastRepairResult != null) ...[
          const SizedBox(height: WpSpacing.sm),
          _RepairResultBanner(
            result: lastRepairResult!,
            errorColor: errorColor,
            successColor: successColor,
            textSecondary: textSecondary,
            l10n: l10n,
            onRestart: () => notifier.restartForGrant(),
          ),
        ],
      ],
      _ => const <Widget>[],
    };

    // One gap value between blocks (`md`) against one inside the card
    // (`xxs`) — 4:1, which is what makes the card read as one object and the
    // page as four. It used to run `sm` against `xs`, 1.5:1, close enough
    // that the Skip button looked like part of the block above it.
    if (phase == _AutoPastePhase.granted) return [card];
    return [
      // `troubleshoot` is the one phase whose leading block is not the card:
      // [WpPasteCapabilityRestartBanner] is already a status object — it
      // states what went wrong and carries the single action that fixes it —
      // so putting "action needed" in a card directly above it says the same
      // thing twice and costs the page 86 px it does not have (that branch
      // stacks banner + repair + result + skip and was the tallest state on
      // the page before any of this). The shape is unchanged: one status
      // object, then the action, then why, then the way out.
      if (phase != _AutoPastePhase.troubleshoot) ...[
        card,
        const SizedBox(height: WpSpacing.md),
      ],
      ...actions,
      if (actions.isNotEmpty) const SizedBox(height: WpSpacing.md),
      // …and the one phase that drops the why-line. Its job is to help a user
      // decide *whether* to grant; in `troubleshoot` that decision is behind
      // them — they granted, macOS did not take it, and the page's whole
      // content is now the recovery. Keeping it there also costs the tallest
      // branch on the page 81 px it does not have: with the line in, German
      // at text scale 1.3 ran 631 px against the 567 px the fixed window
      // offers (measured; see the troubleshoot fold tests, which now run at
      // every scale in `foldTextScales` rather than at 1.0 only).
      if (phase != _AutoPastePhase.troubleshoot) ...[
        why,
        const SizedBox(height: WpSpacing.md),
      ],
      skip,
    ];
  }
}

/// Discrete UI phases of the macOS Auto-Paste onboarding step. Derived from
/// `PasteCapabilityState` so the build method stays declarative — exactly
/// one branch renders at a time and each branch shows a single primary CTA.
enum _AutoPastePhase {
  /// Initial probe still resolving — show only a soft "one moment" card.
  checking,

  /// Permission is granted; render a success card and let the user advance.
  granted,

  /// Default missing-permission state: big "Continue" CTA + Skip.
  intro,

  /// `_onGrantPressed` armed polling; show the "tick the box" hint card
  /// while the OS settings pane is open.
  waiting,

  /// Polling timed out with the suspected TCC-cache mismatch; surface the
  /// big "Restart WhisPaste" CTA (inside the banner) with the reset button
  /// as a secondary fallback.
  troubleshoot,
}

// =============================================================================
// Windows body — minimal verify in the 99% case, non-blocking UIPI warn
// for the rare edge where the probe reports permissionMissing.
// =============================================================================

class _WindowsBody extends StatelessWidget {
  const _WindowsBody({required this.state, required this.onSkip});

  final PasteCapabilityState state;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final cap = state.capability;
    // UIPI/UAC edge: the SendInput bridge cannot deliver keystrokes into an
    // elevated target window when WhisPaste itself runs un-elevated. We
    // surface this as a non-blocking warning — the user keeps the choice
    // between leaving Auto-Paste on or skipping to clipboard-only mode.
    final isUipiEdge = cap?.status == PasteCapabilityStatus.permissionMissing;

    const textPrimary = WpColors.textPrimary;
    const textSecondary = WpColors.textSecondary;
    const successColor = WpColors.success;
    const warningColor = WpColors.warning;

    // Same object as the macOS body renders, on purpose: this is one page in
    // the flow, and it had two private card classes of its own here — a
    // 20-px-icon verify card and a warn card — that said the same kind of
    // thing in a third and fourth shape. Windows now shows the page's status
    // card with a Windows status in it, so the two platforms differ in what
    // they say rather than in how the page is built. The explanation moves
    // *into* the card as its secondary line, which is where the macOS body
    // puts the waiting hint and what stops a full-width card from carrying
    // three words.
    final card = isUipiEdge
        ? _PermissionStatusCard(
            icon: LucideIcons.triangleAlert,
            color: warningColor,
            tint: WpColors.warningActiveFill,
            // Titleless on purpose — see [_PermissionStatusCard.title]. UIPI
            // is a caveat about *some* target windows, not a task: Auto-Paste
            // works in every non-elevated app, and the correct default here is
            // to do nothing. "Action needed" would be a lie with a button-less
            // card under it.
            title: null,
            detail: l10n.onboardingPasteWhyWinUipi,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          )
        : _PermissionStatusCard(
            icon: LucideIcons.circleCheck,
            color: successColor,
            tint: WpColors.successActiveFill,
            title: l10n.onboardingPasteChipReady,
            detail: l10n.onboardingPasteWhyWin,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No title — the page owns the heading (see the macOS body).
        card,
        // Skip only in the UIPI edge — it sets afterTranscription=clipboard
        // and uses the macOS wording (`onboardingPasteSkip`) so the option is
        // recognisable across platforms. The 99 % branch has nothing to skip:
        // Auto-Paste already works there, and offering the opt-out would only
        // invite a mis-tap.
        if (isUipiEdge) ...[
          const SizedBox(height: WpSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: WpButton(
              label: l10n.onboardingPasteSkip,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              onPressed: onSkip,
            ),
          ),
        ],
      ],
    );
  }
}

/// Where the Auto-Paste permission stands, in the shape DESIGN.md's Quiet
/// Status Rule prescribes: a neutral card, a 32-px icon badge tinted to 12 %
/// of the status hue, a 13-px title and an optional secondary line — the same
/// object `paste_capability_indicator.dart` renders in Settings, so the
/// permission looks the same in both places the user meets it.
///
/// It replaces a card that was a bare 20-px icon plus one 14/600 label on a
/// full-width surface. That is what made the page read as empty rather than
/// as quiet: the card was the width of the page and carried three words, and
/// the badge — the element the rule makes responsible for *carrying* status —
/// was not there at all. Width is not the fix (the page's head and body have
/// to end on the same edge, so the card stays full-bleed); content is.
class _PermissionStatusCard extends StatelessWidget {
  const _PermissionStatusCard({
    required this.icon,
    required this.color,
    required this.tint,
    required this.title,
    required this.detail,
    required this.textPrimary,
    required this.textSecondary,
  });

  final IconData icon;

  /// Status hue for the glyph, and [tint] its 12 % rung for the badge fill.
  /// Passed rather than derived: the phase that owns the state also owns what
  /// the state *means*, and deriving a colour from an icon here would put
  /// that decision in two places.
  final Color color;
  final Color tint;

  /// `null` turns the card into a *statement* card: no status label, just the
  /// badge and [detail]. The Windows UIPI edge needs exactly that — the state
  /// there is a caveat, not a task, and every status label this app owns
  /// ("action needed", "pending", "ready") would either demand work the user
  /// cannot do or claim a readiness that branch does not have. A titleless
  /// card keeps that honest without a new string in three locales.
  final String? title;

  /// Secondary line. `null` on the phases whose title already says the whole
  /// thing — a card padded out with a restatement is the same emptiness with
  /// more words in it.
  final String? detail;

  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final surface = (WpColors.surfaceVariant).withValues(alpha: 0.5);
    const border = WpColors.borderSubtle;

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
          Container(
            width: _kStatusBadgeSize,
            height: _kStatusBadgeSize,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: WpRadius.borderSm,
            ),
            child: Center(
              child: Icon(icon, size: WpIconSize.sm, color: color),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: WpTypography.body,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                if (detail != null) ...[
                  if (title != null) const SizedBox(height: WpSpacing.xxs),
                  Text(
                    detail!,
                    // Metadata under a title (12 px), but body when it *is*
                    // the message — the 13-px Baseline Rule steps down for a
                    // second line, not for the only line on the card.
                    style: TextStyle(
                      fontSize: title == null
                          ? WpTypography.body
                          : WpTypography.small,
                      color: textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // No spinner, deliberately. The card carried an (unused) polling
          // indicator, and wiring it up to `checking`/`waiting` is the
          // obvious way to show "something is happening" — but a
          // never-ending animation on an onboarding page is an animation the
          // golden capture and every `pumpAndSettle` in the flow's tests wait
          // on forever, and it is louder than this app's motion register
          // allows for a state that resolves in milliseconds. Progress is
          // carried by the badge glyph and the copy instead: `checking`
          // shows the loader mark and says the access is pending, `waiting`
          // shows a checkbox mark and says which box to tick.
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
    required this.onRestart,
  });

  final TccRepairResult result;
  final Color errorColor;
  final Color successColor;
  final Color textSecondary;
  final L10n l10n;

  /// Routed through [PasteCapabilityNotifier.restartForGrant] so the
  /// cross-process restart marker is set before the relaunch — same as every
  /// other grant-driven restart surface.
  final VoidCallback onRestart;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: WpIconSize.sm, color: color),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        // Offer the restart shortcut whenever the repair didn't actually
        // clear anything — that's the case where macOS won't re-evaluate
        // trust without a fresh process, so the only reliable recovery is
        // relaunching WhisPaste.
        if (nothingCleared) ...[
          const SizedBox(height: WpSpacing.sm),
          WpButton(
            label: l10n.pasteCapabilityRestartButton,
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.neutral,
            icon: LucideIcons.rotateCw,
            onPressed: onRestart,
          ),
        ],
      ],
    );
  }
}
