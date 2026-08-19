import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/config/build_config.dart';
import '../../core/config/settings_provider.dart';
import '../../core/onboarding/onboarding_revision.dart';
import '../../core/onboarding/onboarding_surface.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/logging/app_logger.dart';
import '../../services/hotkey_service.dart';
import '../../services/paste/paste_capability_notifier.dart';
import '../../services/permissions/mic_permission_notifier.dart';
import '../../services/telemetry_service.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_hero_button.dart';
import 'onboarding_completion_gate.dart';
import 'onboarding_flow_migration.dart';
import 'steps/auto_paste_step.dart';
import 'steps/appearance_step.dart';
import 'steps/onboarding_headings.dart';
import 'steps/onboarding_page_fill.dart';
import 'steps/welcome_step.dart';
import 'steps/privacy_step.dart';
import 'steps/model_step.dart';
import 'steps/trigger_step.dart';
import 'steps/test_recording_step.dart';
import 'steps/ready_step.dart';

/// Widget keys exposed for testing — the shell-owned navigation actions.
@visibleForTesting
const kOnboardingNavRowKey = Key('onboardingNavRow');
@visibleForTesting
const kOnboardingBackButtonKey = Key('onboardingNavBackButton');
@visibleForTesting
const kOnboardingNextButtonKey = Key('onboardingNavNextButton');

/// The top bar's X. Closes the window during the first run and leaves the
/// review in a reopened one — one control, two meanings, so tests address it
/// by key rather than by icon.
@visibleForTesting
const kOnboardingReviewExitButtonKey = Key('onboardingTopBarCloseButton');

/// The revision run's named exit. Deliberately **not** in the navigation row:
/// it is not a third navigation action and not a per-step "skip" — it leaves
/// the whole flow, exactly like reaching the last step does
/// (`.scratch/onboarding-revisions/issues/04`). Living in the top bar is what
/// makes "every page has exactly two navigation actions" stay true by
/// construction rather than by a conditional.
@visibleForTesting
const kOnboardingRevisionExitButtonKey = Key('onboardingRevisionExitButton');

/// Height of the onboarding top bar's control row, and the hit target of the
/// close button that sits in it on the platforms that render one.
///
/// Pinned rather than derived so the bar keeps the exact same height on macOS,
/// where the button is omitted — everything below it must not shift.
///
/// **Deliberate exception to the 48-px hit-target floor** (`DESIGN.md`, "All
/// interactive elements meet the 48px minimum touch target"): the close X is
/// 32×32, the same reasoning that sanctions the status-bar theme toggle
/// (36×32, `lib/app.dart`) and the trigger-list remove button (28×28,
/// `replacements_page.dart`) — a single, rarely-used control in a one-off
/// flow, not a row action hit repeatedly, which is what the floor is for.
/// `WpButton`'s `dense` size (32 px, hit target equal to its visual box) is
/// the established precedent for this shape. The height is also load-bearing
/// in both directions: it *is* the top strip, and growing it pushes every
/// page's header down the fixed 1100×720 window (the 48 → 32 rebalance
/// documented in [_kOnboardingBottomGap] is exactly that trade, paid for
/// once already).
///
/// Note for whoever touches the constraints below: this passes
/// `test/widgets/wp_row_action_squeezed_icon_button_guard_test.dart` only
/// because the guard matches digit literals in `BoxConstraints`, and the
/// button passes this named constant instead. Inlining `32` there would trip
/// the guard — the fix is then to keep the constant, not to add this file to
/// the guard's allowlist, which would blind it to every future `IconButton`
/// here.
const double _kOnboardingTopBarHeight = 32;

/// Distance from the window edges to the exit *glyph* — the visible X — on
/// both axes.
///
/// One number for top and side on purpose: inside the old top strip the
/// glyph sat 6 px from the top edge (centred in the 32-px band) but 18 px
/// from the side (the strip's 12-px padding plus the button's own 6), which
/// on the frameless Windows/Linux window read as the X hugging the top edge
/// while floating off the corner. The exit controls float in their own
/// corner layer now (see `_buildExitControls`) precisely so this inset can
/// be symmetric without growing the strip or shifting the page below it.
const double _kOnboardingExitGlyphInset = WpSpacing.sm;

/// Where the exit button's *box* is positioned so its glyph lands on
/// [_kOnboardingExitGlyphInset]: the 32-px hit box extends
/// `(32 − WpIconSize.md) / 2 = 6 px` beyond the glyph on every side.
const double _kOnboardingExitBoxInset =
    _kOnboardingExitGlyphInset - (_kOnboardingTopBarHeight - WpIconSize.md) / 2;

/// Air under the step counter, i.e. between the last thing on screen and the
/// window's bottom edge — the counterpart to the empty top bar above the
/// header.
///
/// Both numbers were measured at the fixed 1100×720 window and were 68 px
/// above the header (a 48-px top-bar strip plus the scroll view's 20-px top
/// padding) against 16 px below the counter: the page looked pinned to the
/// bottom of a window with a dead band at the top. The fix splits the
/// difference from both ends — the top bar dropped its own `xs` padding
/// (48 → 32, the strip is now exactly the close button's hit target) and this
/// gap grew from `md` to `xxl` — which lands on 52 px above and 32 px below.
///
/// The two moves were deliberately equal and opposite (−16 / +16), which is
/// what kept the scroll viewport at exactly 551 px through that rebalance.
///
/// That 551 px no longer holds, and deliberately so. The footer stack was the
/// binding constraint behind the flow's one P0 finding: on Try & Go at text
/// scale 1.3 the microphone-bypass button — the only way past the page without
/// a working microphone — sat below the fold, and the footer is what pushed it
/// there. It cost ~85 px at scale 1.0 and *grew* with the text scale it was
/// squeezing the page at, taking the viewport from 551 to 539 px exactly when
/// the page needed it most. Two changes answer that: the step counter moved
/// onto the dots' own line (it restates them, so it never needed a line of its
/// own), and this gap came down `xxl` → `lg`. Together they return ~35 px of
/// viewport at scale 1.0 and ~39 px at 1.3, to every page.
///
/// So the number to re-measure against is no longer 551: the height table in
/// `onboarding_overlay_test.dart` is stale by construction until it is
/// re-measured wholesale (that table's own instruction, and the reason it is
/// flagged rather than patched row by row).
///
/// Still not 1 : 1 with the top gap: the top gap is empty, while these 20 px
/// sit under a footer stack that already carries visual weight — a reading
/// start wants more air above it than trailing meta-text wants below it.
const double _kOnboardingBottomGap = WpSpacing.lg;

/// Identifier for each page of the first-run onboarding flow.
///
/// Seven pages on macOS and Windows, six on Linux: [autoPaste] is the one
/// piece of platform variance, and it is a *sequence-level* decision (see
/// [buildOnboardingStepIds]) rather than a page that renders empty where it
/// does not apply.
enum OnboardingStepId {
  /// 1 — Welcome: demo beats and language selection. Deliberately carries no
  /// microphone affordance: the permission is requested when the user leaves
  /// this page (see `_goNext`) and the *visible* microphone status lives on
  /// [tryAndGo], where the microphone is actually used.
  welcome,

  /// 2 — Privacy: informed telemetry/crash-report opt-out.
  privacy,

  /// 3 — Model: the two-way on-device engine choice and its download.
  model,

  /// 4 — Hotkey: which key starts a recording, and whether it is held or
  /// pressed to toggle. Its own page since the seven-step flow — merged with
  /// [model] it had ~11 px of slack, which the confirmed-conflict branch
  /// (warn box plus a full inline recorder) blew through by ~360 px.
  hotkey,

  /// 5 — Appearance: the autostart toggle. Carried the light/dark/system
  /// theme choice as well until the light theme was removed (2026-08-11);
  /// the name is kept because the position is persisted by index and
  /// renaming would buy nothing a reader does not get from this line.
  appearance,

  /// 6 — Auto-Paste: the permission that lets a transcript land at the
  /// cursor. **Not part of the sequence on Linux** (no paste controller is
  /// wired there) or under the Auto-Paste kill switch.
  autoPaste,

  /// 7 — Try & Go: guided test recording, quick-start hints, completion CTA.
  tryAndGo,
}

/// Returns the ordered list of onboarding step IDs for this build.
///
/// Seven steps on macOS/Windows, six on Linux — [autoPaste] is omitted from
/// the sequence entirely where it cannot apply, rather than rendered as a page
/// with nothing on it. The predicate itself lives in
/// [onboardingIncludesAutoPasteStep] because the resume-position migration
/// needs exactly the same answer; splitting it would let the two drift.
///
/// Pure function, no widget tree, no global state: [platform] and
/// [autoPasteSupported] stay injected so unit tests can assert the whole
/// matrix directly.
@visibleForTesting
List<OnboardingStepId> buildOnboardingStepIds({
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) {
  return [
    OnboardingStepId.welcome,
    OnboardingStepId.privacy,
    OnboardingStepId.model,
    OnboardingStepId.hotkey,
    OnboardingStepId.appearance,
    if (onboardingIncludesAutoPasteStep(
      platform: platform,
      autoPasteSupported: autoPasteSupported,
    ))
      OnboardingStepId.autoPaste,
    OnboardingStepId.tryAndGo,
  ];
}

/// Full-window, edge-to-edge onboarding flow.
///
/// Sits on top of the main app shell in a [Stack] and covers it with the same
/// ambient frame gradient the rest of the app uses — no blur, no dimmed
/// scrim, no floating card.
/// Seven pages (six on Linux) with animated transitions, a shell-owned
/// Back/Next navigation
/// row (Next becomes the completion CTA on the last page), stepper dots, and
/// a step counter. The whole surface doubles as a window drag area (the
/// title bar is hidden during onboarding). On completion persists
/// [AppSettings.onboarding]`.onboardingCompleted` = true.
class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({
    super.key,
    this.manualReview = false,
    this.revisionRun = false,
  });

  /// Whether this is a review the user reopened from Settings rather than the
  /// first run.
  ///
  /// A review shows the same five steps prefilled with the same live settings
  /// — the difference is entirely in what it is allowed to write and how it
  /// ends. It never touches the persisted resume position (that belongs to
  /// the first run and only to it), never re-writes `onboardingCompleted`
  /// (already `true`, and writing it is precisely the accident this mode has
  /// to be incapable of), always starts at step 1, and always offers a
  /// visible way out — the first run deliberately has none, because there
  /// closing the window means quitting the app.
  final bool manualReview;

  /// Whether this is an onboarding revision run
  /// (`.scratch/onboarding-revisions/issues/03`) rather than the first run
  /// or a manually reopened review.
  ///
  /// Shares most of a review's shape — same five steps prefilled from live
  /// settings, always starts at step 1, never re-writes `onboardingCompleted`
  /// — but differs in what its ending does: completion and the visible exit
  /// (`.scratch/onboarding-revisions/issues/04`, not built by this flag) both
  /// stamp `onboardingContentVersion` via [OnboardingRevisionRunNotifier.
  /// complete], because a revision run is offered at most once per version,
  /// while a review — already caught up by definition — never touches that
  /// field. Mutually exclusive with [manualReview] by construction: the two
  /// session flags that drive them are only ever set one at a time.
  final bool revisionRun;

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  static final _log = AppLogger('Onboarding');

  /// Max content width — wider than the old 600-px card so the merged pages
  /// (side-by-side engine cards + hotkey block) breathe, but still bounded
  /// for readable line lengths on large windows.
  static const double _contentMaxWidth = 720;

  /// The reading measure of every settings-shaped page — one width for the
  /// heading *and* the body underneath it.
  ///
  /// These pages ran two widths at once: the page heading capped its subtitle
  /// at 560 px while the body ran the full 720, so the right edge jumped
  /// 148 px between a page's own head and its own content. Appearance showed
  /// the same break inside its body — three 200-px tiles with `lg` between
  /// them come to exactly 640, sitting under a 720-px autostart row.
  ///
  /// 640 is the width both of those already wanted: it is the tile row's own
  /// measure, so Appearance stops breaking against itself, and it is close
  /// enough to the 560 the headings were tuned for that no subtitle gains a
  /// line. Head and body now end on the same x-edge, and there is one number
  /// to reason about instead of two.
  ///
  /// Deliberately applied here rather than to [_contentMaxWidth]: Try & Go
  /// derives its two column widths from the 720-px frame ((720 − 32) × 6/9 and
  /// × 3/9), and narrowing the frame would re-wrap the left column and undo
  /// the height relief that got its escape hatch back above the fold. Try & Go
  /// is not a reading-measure page — it is two columns — so the cap does not
  /// apply to it by construction rather than by exception.
  static const double _readingMeasure = 640;

  /// Page 1 runs a wider frame than the settings-shaped pages behind it — its
  /// composition is a text column *beside* a large media panel, and at 720
  /// the two halves squeeze each other. The width itself is owned by
  /// [kOnboardingWelcomeFrameWidth], because the recorded clip dimensions are
  /// derived from it.
  double _frameWidthFor(OnboardingStepId id) => switch (id) {
    OnboardingStepId.welcome => kOnboardingWelcomeFrameWidth,
    // Two columns, not a reading measure — see [_readingMeasure].
    OnboardingStepId.tryAndGo => _contentMaxWidth,
    _ => _readingMeasure,
  };

  int _currentStep = 0;
  int _previousStep = 0;

  /// Guards [_hydrateStepFromSettings] so it only ever jumps the step once —
  /// further settings changes (e.g. the user picking a microphone) must not
  /// re-trigger a step jump.
  bool _stepHydrated = false;

  /// Cached notifier references so [dispose] can stop polling without
  /// touching `ref` — Riverpod forbids `ref` access after deactivation.
  /// The overlay owns the provider scope, so sudden window-close (X tapped,
  /// app quit) tears down the widget tree without giving individual steps a
  /// chance to run their own dispose; defending here guarantees no zombie
  /// polling timer survives the overlay — neither the Auto-Paste capability
  /// poller nor the microphone permission poller.
  PasteCapabilityNotifier? _cachedPasteNotifier;
  MicPermissionNotifier? _cachedMicNotifier;

  @override
  void initState() {
    super.initState();
    if (widget.manualReview) {
      // A review starts at the beginning, every time. The persisted resume
      // position belongs to an interrupted *first* run and means nothing
      // here — reading it would drop a returning user into the middle of the
      // flow for no reason they could reconstruct, and the write-back on the
      // next navigation would corrupt a genuinely interrupted first run's
      // position for good.
      _stepHydrated = true;
      _trackStep('review_step', _onboardingSteps().first);
      return;
    }
    if (widget.revisionRun) {
      // Same reasoning as a review's early return above — a revision run
      // always begins at step one — plus one more: by the time this mounts,
      // OnboardingRevisionRunNotifier.start() has already reset the shared
      // position field to 0, so reading it here would be redundant even if
      // it weren't skipped.
      _stepHydrated = true;
      _trackStep('revision_step', _onboardingSteps().first);
      return;
    }
    // Resume where the user left off — most relevantly after a required app
    // restart mid-onboarding (e.g. granting the Auto-Paste permission).
    // Without this, onboardingCompleted is still false post-restart and the
    // overlay would otherwise always rebuild at step 0, forcing the user
    // back through every prior step. `fireImmediately` covers the common
    // case where settings already finished loading by the time this overlay
    // mounts; the listener itself covers the case where they're still
    // in-flight (settingsProvider starts as AsyncLoading with no value yet).
    ref.listenManual(
      settingsProvider,
      (_, next) => _hydrateStepFromSettings(next.value),
      fireImmediately: true,
    );
    if (!_stepHydrated) {
      // Settings weren't loaded synchronously — track the tentative first
      // step; _hydrateStepFromSettings corrects both the step and this
      // telemetry once settings resolve.
      _trackStep('step', _onboardingSteps().first);
    }
  }

  void _hydrateStepFromSettings(AppSettings? loaded) {
    if (_stepHydrated || loaded == null) return;
    _stepHydrated = true;
    final steps = _onboardingSteps();
    final onboarding = loaded.onboarding;
    final int saved;
    if (onboarding.onboardingFlowVersion < kOnboardingFlowVersion &&
        !onboarding.onboardingCompleted) {
      // The persisted position was written against an older sequence — the
      // pre-redesign 7/8-step flow or the six-step one (an interrupted first
      // run that got this update mid-way). Which of the two decides the
      // translation table, so the stored version is threaded in rather than
      // assumed. Applied exactly once, then the flow version is stamped so
      // the translation can never re-run.
      saved = migrateLegacyOnboardingStepIndex(
        legacyIndex: onboarding.onboardingCurrentStep,
        fromVersion: onboarding.onboardingFlowVersion,
        platform: defaultTargetPlatform,
        autoPasteSupported: kAutoPasteSupported,
      );
      // Deferred: with fireImmediately:true this whole method can run
      // synchronously from initState (when settings already have a value at
      // mount time), and writing another provider mid-build throws "Tried to
      // modify a provider while the widget tree was building" (Sentry
      // FLUTTER_WHISPASTE-C7). Scheduling the write lets the current build
      // finish first.
      final migratedStep = saved;
      Future(() {
        if (!mounted) return;
        ref
            .read(settingsProvider.notifier)
            .updateSettings(
              (s) => s.copyWithSections(
                onboarding: s.onboarding.copyWith(
                  onboardingCurrentStep: migratedStep,
                  onboardingFlowVersion: kOnboardingFlowVersion,
                ),
              ),
            );
      });
    } else {
      saved = onboarding.onboardingCurrentStep.clamp(0, steps.length - 1);
    }
    if (saved == _currentStep) return;
    if (mounted) {
      setState(() {
        _previousStep = saved;
        _currentStep = saved;
      });
    } else {
      _previousStep = saved;
      _currentStep = saved;
    }
    _trackStep('step', steps[saved]);
  }

  /// Persists [step] as the current onboarding position so a mid-flow app
  /// restart resumes here instead of restarting the whole flow.
  ///
  /// No-op in a review or a revision run: the resume position is first-run
  /// state, and paging through either must not overwrite where an
  /// interrupted first run got to — nor leave any trace of the run itself.
  /// A revision run's own position starts at 0 (`start()`) and ends at 0
  /// (`complete()`); nothing in between needs to survive a restart.
  void _persistCurrentStep(int step) {
    if (widget.manualReview || widget.revisionRun) return;
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(onboardingCurrentStep: step),
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the notifiers as soon as the provider scope is reachable so the
    // dispose path never needs to touch `ref`.
    _cachedPasteNotifier ??= ref.read(pasteCapabilityNotifierProvider.notifier);
    _cachedMicNotifier ??= ref.read(micPermissionNotifierProvider.notifier);
  }

  @override
  void dispose() {
    // Defensive cleanup: individual steps also stop polling in their own
    // dispose, but the overlay owns the provider scope and is the last line
    // of defence against sudden tear-downs (window close, app quit) that
    // skip individual step disposals.
    _cachedPasteNotifier?.stopPolling();
    _cachedMicNotifier?.stopPolling();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Step sequence
  // ---------------------------------------------------------------------------

  /// Returns the ordered step IDs. Delegates to [buildOnboardingStepIds],
  /// wiring [defaultTargetPlatform] and [kAutoPasteSupported] from the build
  /// environment — the sequence itself is platform-invariant, but keeping
  /// the injection makes that a tested property instead of an assumption.
  List<OnboardingStepId> _onboardingSteps() {
    return buildOnboardingStepIds(
      platform: defaultTargetPlatform,
      autoPasteSupported: kAutoPasteSupported,
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  /// Fire-and-forget categorical onboarding telemetry (step id only — no PII).
  /// Feeds the per-step abandonment funnel (PRD US30). Never throws.
  void _trackStep(String action, OnboardingStepId step) {
    try {
      ref
          .read(telemetryProvider)
          .trackEvent(category: 'onboarding', action: action, name: step.name);
    } catch (e) {
      // Telemetry must never break onboarding — log and move on.
      _log.debug('Telemetry onboarding event skipped: $e');
    }
  }

  void _goNext() {
    final steps = _onboardingSteps();
    if (_currentStep < steps.length - 1) {
      if (_currentStep == 0 &&
          // Not in a review or a revision run: an OS permission dialog is the
          // loudest thing this app can do, and merely paging through the
          // introduction is not the "clearly needs it" moment that justifies
          // one. The microphone status and its own request affordance are on
          // the Try & Go step, where the microphone is actually used. A
          // revision run additionally must never re-request on a returning
          // user's behalf — it shows status, it does not ask again (parent
          // PRD, "Out of Scope").
          !widget.manualReview &&
          !widget.revisionRun &&
          ref.read(micPermissionNotifierProvider).status ==
              MicPermissionStatus.unknown) {
        // The user never triggered the mic request themselves — fire it now,
        // on *leaving* page 1 (never on appear: the OS dialog is a central
        // modal that would wreck the demo moment). `unknown` proves request()
        // has never run this process, so the dialog budget is unspent and
        // this call is guaranteed to show the real one-time OS dialog, never
        // the deep-link recovery path. Fire-and-forget: navigation must not
        // wait for the dialog.
        unawaited(ref.read(micPermissionNotifierProvider.notifier).request());
      }
      setState(() {
        _previousStep = _currentStep;
        _currentStep++;
      });
      _persistCurrentStep(_currentStep);
      // A returning user re-reading a page is not a first-run step. Mixing
      // the two would quietly inflate the per-step funnel these events exist
      // to measure — and read as a first run that never ends, because
      // neither a review nor a revision run emits a plain 'complete'.
      _trackStep(
        widget.manualReview
            ? 'review_step'
            : widget.revisionRun
            ? 'revision_step'
            : 'step',
        steps[_currentStep],
      );
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() {
        _previousStep = _currentStep;
        _currentStep--;
      });
      _persistCurrentStep(_currentStep);
    }
  }

  /// Leaves a review and hands the window back to the Settings page the user
  /// started from.
  ///
  /// Flipping the ephemeral flag is the whole of it: the overlay unmounts on
  /// the next frame and the app shell underneath was never navigated away
  /// from. Nothing persisted is touched — in particular not
  /// `onboardingCompleted`, which is already `true` and whose only other
  /// possible value would mean "this user never set the app up".
  void _exitManualReview() {
    _trackStep('review_exit', _onboardingSteps()[_safeStep()]);
    ref.read(onboardingManuallyOpenProvider.notifier).close();
  }

  /// Leaves a revision run early — the visible counterpart to reading it to
  /// the end.
  ///
  /// Both endings are the *same* ending: [OnboardingRevisionRunNotifier.complete]
  /// stamps the target version either way, because a revision run is offered
  /// at most once per version (parent PRD, "Abbruch stempelt ebenfalls").
  /// That is precisely why this route is confirmed and the confirmation says
  /// out loud what stays unconfigured: it is a one-way door, and a one-way
  /// door the user walks through by accident is the failure mode here — not
  /// one extra tap.
  ///
  /// Dismissing the dialog (Esc, barrier tap, "Cancel") returns `false` and
  /// leaves the user exactly where they were, on the step they were reading.
  Future<void> _exitRevisionRun() async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.onboardingRevisionExitConfirmTitle,
      message: l10n.onboardingRevisionExitConfirmBody,
      confirmLabel: l10n.onboardingRevisionExitConfirmAction,
    );
    if (!confirmed || !mounted) return;
    // Its own action name, not 'revision_complete': the funnel's whole point
    // here is telling "read to the end" apart from "left on step 2".
    _trackStep('revision_exit', _onboardingSteps()[_safeStep()]);
    await ref.read(onboardingRevisionRunProvider.notifier).complete();
  }

  int _safeStep() => _currentStep.clamp(0, _onboardingSteps().length - 1);

  Future<void> _complete() async {
    if (widget.manualReview) {
      // The last step's action in a review *is* the exit — same destination,
      // just reached by reading to the end rather than leaving early.
      _exitManualReview();
      return;
    }
    if (widget.revisionRun) {
      // Same shared ending [_exitRevisionRun] calls — reaching the last step
      // and leaving early are not different outcomes, per the parent PRD
      // ("Abbruch stempelt ebenfalls"). Only the tracked action differs, so
      // the funnel can still tell the two apart.
      _trackStep('revision_complete', OnboardingStepId.tryAndGo);
      await ref.read(onboardingRevisionRunProvider.notifier).complete();
      return;
    }
    _trackStep('complete', OnboardingStepId.tryAndGo);
    // US17: a freshly set-up user is, by construction, caught up on the
    // onboarding content they were just shown — stamping the target version
    // here, in the same write as `onboardingCompleted`, is what keeps them
    // from walking straight into a revision run on their very next start.
    final registry = ref.read(onboardingRevisionRegistryProvider);
    final targetVersion = targetOnboardingContentVersion(
      registry,
      currentOnboardingPlatform(),
    );
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(
              onboardingCompleted: true,
              onboardingCurrentStep: 0,
              onboardingContentVersion: targetVersion,
            ),
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Page builder — merged page contents; navigation stays with the shell.
  // ---------------------------------------------------------------------------

  /// Every page hands its leftover height to its body block
  /// ([OnboardingPageFill] plus the page's own [OnboardingPageBody]).
  ///
  /// Including page 1: its brand lockup is that page's header, and it has to
  /// start at the same height as every other page's heading. Centring the
  /// page as a whole — which is what page 1 used to do — made the lockup's
  /// position depend on how tall the rest of the page was, so the logo sat
  /// visibly lower than page 2's title. Including the tight pages costs
  /// nothing: the fill can never shrink a gap below its minimum, so the
  /// hotkey page's conflict branch simply keeps its minimum gaps.
  /// Try & Go used to be the one exclusion (its heading was the left
  /// column's first block); since the page adopted the shared
  /// [OnboardingPage] header treatment there is no exception left.
  Widget _buildStep(OnboardingStepId id, double availableHeight) {
    return OnboardingPageFill(
      availableHeight: availableHeight,
      child: _buildStepContent(id),
    );
  }

  /// The Hotkey page. Split out of the page switch because it is the one page
  /// whose composition depends on live state: a confirmed conflict changes
  /// both what the page says and how much room the block below it needs.
  Widget _buildHotkeyPage(L10n l10n) {
    final hasConflict =
        ref.watch(hotkeyRegistrationStatusProvider) ==
        HotkeyRegistrationStatus.conflict;
    return OnboardingPage(
      header: OnboardingPageHeading(
        title: l10n.onboardingTriggerTitle,
        // Title only while a conflict is on screen. The warn box below
        // states the problem and the remedy, so the generic explainer would
        // be the page's third voice — and dropping it, together with the
        // tighter gap under it, is what buys the conflict branch (warn box
        // plus a full inline recorder) the room to fit the fixed window
        // instead of scrolling. Measured, see the fixed-window group in
        // `onboarding_overlay_test.dart`.
        subtitle: hasConflict ? null : l10n.onboardingTriggerSubtitle,
      ),
      // The flow's one documented deviation from [kOnboardingHeaderGap]: the
      // conflict branch measures 538 px in German against the 551 px the
      // fixed window offers, so the canonical 32 px gap would push it into
      // scrolling by 20 px. 12 px is what it can afford, and the missing
      // subtitle above it is what makes the tighter gap read as intentional
      // rather than cramped. Re-measure German before touching either.
      headerGap: hasConflict ? WpSpacing.sm : kOnboardingHeaderGap,
      body: const TriggerStep(),
    );
  }

  Widget _buildStepContent(OnboardingStepId id) {
    final l10n = L10n.of(context);
    return switch (id) {
      OnboardingStepId.welcome => WelcomeStep(revisionRun: widget.revisionRun),
      OnboardingStepId.privacy => const PrivacyStep(),
      // Every settings-shaped page from here on is one [OnboardingPage]: a
      // fixed [OnboardingPageHeading], [kOnboardingHeaderGap] under it, and a
      // body centred in the height that is left. The page owns the heading and
      // that gap, the step widget owns only its own content. That keeps the
      // step widgets bare-mountable in their own tests, and it is why none of
      // them carries a title of its own any more — a page heading plus a
      // near-identical section label directly under it was the same string
      // twice at two sizes.
      OnboardingStepId.model => OnboardingPage(
        header: OnboardingPageHeading(
          title: l10n.onboardingModelTitle,
          subtitle: l10n.onboardingModelSubtitle,
        ),
        body: const ModelStep(),
      ),
      OnboardingStepId.hotkey => _buildHotkeyPage(l10n),
      OnboardingStepId.appearance => OnboardingPage(
        header: OnboardingPageHeading(
          title: l10n.onboardingAppearancePageTitle,
          subtitle: l10n.onboardingAppearancePageSubtitle,
        ),
        body: const AppearanceStep(),
      ),
      OnboardingStepId.autoPaste => OnboardingPage(
        header: OnboardingPageHeading(
          title: l10n.onboardingPasteTitle,
          subtitle: defaultTargetPlatform == TargetPlatform.windows
              ? l10n.onboardingPasteSubtitleWin
              : l10n.onboardingPasteSubtitle,
        ),
        body: const AutoPasteStep(),
      ),
      // Two columns, not a stack: as one column the page measured 739 px of
      // content against a 551-px viewport (188 px of forced scrolling in the
      // fixed 1100x720 window) and repeated the same mistake page 1 had —
      // ignoring the width the window already has. Side by side the guided
      // test recording (the thing to do) and the quick-start card (the thing
      // to read) each keep their own rhythm and the page fits without
      // scrolling. `start` cross-alignment keeps both column tops on the same
      // line; the plain Row mirrors for free under RTL.
      //
      // One [OnboardingPage] like every other step: the page owns the
      // heading and the header gap, the two columns are the body. The
      // heading used to be the first block of the left column, which crammed
      // title, subtitle and the whole recording apparatus into one 6/9-wide
      // strip while the page's own header line stayed empty — the one page
      // of the flow that didn't share the family's header treatment, and it
      // read exactly that way. The subtitle now wraps on the page's full
      // measure (capped at 640 like every heading) instead of the left
      // column's, which pays for most of the header gap this adds.
      //
      // 6 : 3, not the 5 : 4 this started on. The split is a height decision
      // wearing a width parameter: the two columns are wildly unequal in what
      // they carry (the left one runs status line → record button → sandbox
      // field → caption → completion gate; the right one is three short
      // instruction rows) but 5 : 4 gave them near-equal width, so the left
      // column wrapped everything and ran far past the bottom of the right
      // one. 7 : 2 was measured too and is *worse*: past 6 : 3 the right
      // column starts wrapping faster than the left one unwraps, and since
      // the row's height is the taller of the two, the win flips. The
      // binding heights live in `onboarding_overlay_test.dart`'s
      // fixed-window group — re-measure there before touching the split.
      OnboardingStepId.tryAndGo => OnboardingPage(
        header: OnboardingPageHeading(
          title: l10n.onboardingTestRecordingTitle,
          subtitle: l10n.onboardingTestRecordingSubtitle,
        ),
        body: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: TestRecordingStep()),
            SizedBox(width: WpSpacing.xxl),
            Expanded(flex: 3, child: ReadyStep()),
          ],
        ),
      ),
    };
  }

  /// The top strip: a pure drag handle with a fixed height.
  ///
  /// The window runs with `TitleBarStyle.hidden`, so this strip is what
  /// stands in for the title bar as the window's drag area. It is
  /// unconditional and keeps its fixed height in every mode — nothing below
  /// it may shift. The exit controls that used to live inside it (the
  /// close/leave X and the revision run's labelled exit) float in
  /// [_buildExitControls]'s corner layer now; see that method for the
  /// per-platform and per-mode rules of when an exit is drawn at all.
  Widget _buildTopBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      // Tight, not a floor: relaxing this to a minHeight pushes every page's
      // header down the window, which the welcome screenshot golden catches
      // immediately. The strip carries no controls any more — the exit
      // controls float in [_buildExitControls]'s corner layer so their
      // insets never depend on this strip's geometry — so the strip is a
      // pure drag handle with the fixed height nothing below may shift for.
      child: const SizedBox(
        height: _kOnboardingTopBarHeight,
        width: double.infinity,
      ),
    );
  }

  /// The floating exit controls — the revision run's labelled exit and the
  /// close/leave X — as a corner layer above the page (see the [Stack] in
  /// [build]).
  ///
  /// A layer and not children of the 32-px top strip, for one measured
  /// reason: inside the strip the X's glyph sat 6 px from the top edge
  /// (centred in the 32-px band) but 18 px from the side (the strip's 12-px
  /// padding plus the button's own 6), which on the frameless Windows/Linux
  /// window read as the X hugging the top while floating off the corner.
  /// The layer gives the glyph the same [_kOnboardingExitGlyphInset] on both
  /// axes, and — because it overlays instead of occupying — moves nothing
  /// below it. The strip keeps its height and stays the drag handle.
  ///
  /// Returns `null` when no exit control is drawn (the macOS first run: the
  /// native traffic lights are the close affordance there and the custom X
  /// would duplicate them).
  Widget? _buildExitControls(L10n l10n, Color textMuted) {
    // One condition, read twice: the X and the gap that precedes it. Held
    // apart they drifted — the gap hung off `revisionRun` alone and stayed
    // behind on macOS, where the X is not drawn, leaving the revision run's
    // exit button 4 px short of where the review's X sits.
    final showExitIcon =
        widget.manualReview || defaultTargetPlatform != TargetPlatform.macOS;
    if (!showExitIcon && !widget.revisionRun) return null;
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The revision run's named exit, on every step of the flow. A ghost
        // button in the neutral tone: visible and reachable, but never
        // competing with the accent "Next" — leaving is the rarer intent,
        // and the gradient hero button below stays the one obvious way
        // forward.
        if (widget.revisionRun) ...[
          WpButton(
            key: kOnboardingRevisionExitButtonKey,
            label: l10n.onboardingRevisionExit,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            size: WpButtonSize.dense,
            icon: LucideIcons.logOut,
            onPressed: _exitRevisionRun,
          ),
          // Only a separator, never a trailing margin: it exists to keep the
          // labelled exit off the X, so it is drawn under exactly the
          // condition the X is.
          if (showExitIcon) const SizedBox(width: WpSpacing.xxs),
        ],
        if (showExitIcon)
          IconButton(
            key: kOnboardingReviewExitButtonKey,
            onPressed: widget.manualReview
                ? _exitManualReview
                : () => windowManager.close(),
            icon: Icon(
              LucideIcons.x,
              // `md`, the floor DESIGN.md sets for an interactive icon; 18
              // was off the scale in both directions. The 32-px constraints
              // below set the button's own box.
              size: WpIconSize.md,
              color: textMuted,
            ),
            tooltip: widget.manualReview
                ? l10n.onboardingReviewExit
                : MaterialLocalizations.of(context).closeButtonTooltip,
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: _kOnboardingTopBarHeight,
              minHeight: _kOnboardingTopBarHeight,
            ),
          ),
      ],
    );
    // A review's (and revision run's) exit sits at the physical right on
    // every platform and in every locale. The physical left is where macOS
    // draws the native traffic lights under TitleBarStyle.hidden — they do
    // not move for Hebrew — and those two modes carry the exit on macOS too,
    // so a *logical* placement would land on top of them in RTL. Only the
    // first run keeps the ambient direction, its X being drawn only where
    // the whole title bar is gone and that leading corner is free.
    return widget.manualReview || widget.revisionRun
        ? Positioned(
            top: _kOnboardingExitBoxInset,
            right: _kOnboardingExitBoxInset,
            child: controls,
          )
        : PositionedDirectional(
            top: _kOnboardingExitBoxInset,
            start: _kOnboardingExitBoxInset,
            child: controls,
          );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final steps = _onboardingSteps();
    final totalSteps = steps.length;
    final safeCurrent = _currentStep.clamp(0, totalSteps - 1);
    final isLastStep = safeCurrent == totalSteps - 1;
    final direction = _currentStep >= _previousStep ? 1.0 : -1.0;
    // Page content and the nav row below it share one frame width, so the
    // Back/Next actions always sit on the same margins as the page above.
    // Animated, not switched: page 1 runs a wider frame than the rest, and
    // snapping from 860 to 720 while the 300 ms cross-fade was still running
    // read as the frame jumping out from under the incoming page. Both call
    // sites take the same interpolated value, so content and nav row can
    // never drift apart mid-transition.
    final targetFrameWidth = _frameWidthFor(steps[safeCurrent]);
    Widget frame({required Widget child}) => TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetFrameWidth),
      duration: WpMotion.durationFor(context, WpMotion.smooth),
      curve: WpMotion.smooth_,
      builder: (context, width, child) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
      child: child,
    );

    // Two independent completion gates (PRD "Zwei Abschluss-Gates"):
    //  1. Residual safety gate (moved from the old ReadyStep): a confirmed
    //     hotkey conflict disables the completion CTA so the user is never
    //     sent into a non-functional hotkey. `unknown` stays enabled —
    //     background registration must not block on a transient first-mount
    //     race.
    //  2. Microphone gate: a successful test recording with recognised
    //     speech (non-empty sandbox transcript) — or the explicit
    //     "continue without a microphone" escape hatch, which bypasses ONLY
    //     this condition, never the hotkey one.
    final hotkeyStatus = ref.watch(hotkeyRegistrationStatusProvider);
    final testRecordingSucceeded = ref.watch(
      onboardingTestRecordingSucceededProvider,
    );
    final micBypassed = ref.watch(onboardingMicBypassProvider);
    final completionEnabled =
        hotkeyStatus != HotkeyRegistrationStatus.conflict &&
        (testRecordingSucceeded || micBypassed);

    const textMuted = WpColors.textMuted;
    const accentGradient = WpColors.accentWarmGradient;

    return BlockSemantics(
      // The whole surface doubles as a window drag area: the title bar is
      // hidden during onboarding, and interactive children win the gesture
      // arena over the pan recognizer, so dragging any empty region moves
      // the window.
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: DecoratedBox(
          // Same ambient frame gradient as the rest of the app — deliberately
          // no blur and no dimmed scrim (and therefore no Windows
          // frameless-window blur fallback either).
          decoration: const BoxDecoration(gradient: WpColors.frameGradient),
          // A Stack, because the exit controls (revision exit + close X) are
          // a floating corner layer rather than children of the top strip —
          // the one way their glyph can sit symmetrically in the corner
          // without growing the 32-px strip or shifting the page below it
          // (see [_buildExitControls]).
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopBar(),

                  // -- Page content — scrolls when the window shrinks. ----------
                  //
                  // The LayoutBuilder is what lets a page know how much room it
                  // has: inside the scroll view the height is unbounded, so the
                  // measurement has to happen above it and be handed down (see
                  // [OnboardingPageFill]).
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final availableHeight =
                            constraints.maxHeight - WpSpacing.lg * 2;
                        // Every page anchors to the top: each one carries its own
                        // fixed header and centres its body underneath
                        // ([OnboardingPageBody]), so nothing here needs a
                        // per-page anchor any more — page 1 used to be centred as
                        // a whole and that is exactly what pushed its logo below
                        // the other pages' headings.
                        //
                        // The Align itself is load-bearing and not decoration: it
                        // hands the scroll view *loose* constraints. That is what
                        // lets the page shrink-wrap (so a window smaller than the
                        // fixed one actually reports a scroll extent) and what
                        // lets `frame`'s maxWidth cap bind at all — under the
                        // tight width it would otherwise receive, the
                        // ConstrainedBox is enforced away and page 1's 860-px
                        // frame would silently run the full window width.
                        return Align(
                          alignment: Alignment.topCenter,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.xl,
                              vertical: WpSpacing.lg,
                            ),
                            child: frame(
                              child: AnimatedSwitcher(
                                duration: WpMotion.durationFor(
                                  context,
                                  WpMotion.smooth,
                                ),
                                switchInCurve: WpMotion.smooth_,
                                switchOutCurve: WpMotion.smooth_,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: Offset(0.05 * direction, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: KeyedSubtree(
                                  key: ValueKey<OnboardingStepId>(
                                    steps[safeCurrent],
                                  ),
                                  child: _buildStep(
                                    steps[safeCurrent],
                                    availableHeight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // -- Shell-owned navigation: exactly two actions per page. ----
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.xl,
                    ),
                    child: frame(
                      child: Row(
                        key: kOnboardingNavRowKey,
                        children: [
                          WpButton(
                            key: kOnboardingBackButtonKey,
                            label: l10n.onboardingBack,
                            variant: WpButtonVariant.ghost,
                            tone: WpButtonTone.neutral,
                            onPressed: safeCurrent > 0 ? _goBack : null,
                          ),
                          const Spacer(),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 140),
                            // loam-ignore: a11y-interactive-semantics – semantics provided in WpHeroButton.build
                            child: WpHeroButton(
                              key: kOnboardingNextButtonKey,
                              label: isLastStep
                                  ? ((widget.manualReview || widget.revisionRun)
                                        ? l10n.onboardingReviewDone
                                        : l10n.onboardingStartUsing)
                                  : l10n.onboardingNext,
                              gradient: accentGradient,
                              // The two completion gates guard the *first* run
                              // from ending in a half-configured app. A review or
                              // a revision run opens on an app that already
                              // works, so gating its way out on a fresh test
                              // recording would only trap a returning user who
                              // came to look at a page — and would make the
                              // no-data-loss promise (a full run with zero user
                              // input must be completable) impossible to keep.
                              onPressed: isLastStep
                                  ? ((completionEnabled ||
                                            widget.manualReview ||
                                            widget.revisionRun)
                                        ? _complete
                                        : null)
                                  : _goNext,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // -- Stepper dots + step counter, on ONE line. ----------------
                  //
                  // These two say the same thing: N dots with the current one
                  // filled, and then "Step N of M" spelled out directly beneath.
                  // Both earn their place — the dots are the glanceable shape of
                  // the flow, the counter is the part a screen reader and a
                  // text-scaled UI can actually read — but stacked they cost two
                  // lines to say it once, and the second line came out of the
                  // page above. Side by side they read as one caption and cost
                  // one line. See `_kOnboardingBottomGap` for why this stack was
                  // the binding constraint on Try & Go rather than a cosmetic.
                  const SizedBox(height: WpSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StepperDots(
                        currentStep: safeCurrent,
                        totalSteps: totalSteps,
                      ),
                      const SizedBox(width: WpSpacing.sm),
                      Text(
                        l10n.onboardingStepOf(safeCurrent + 1, totalSteps),
                        style: const TextStyle(
                          fontSize: WpTypography.small,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: _kOnboardingBottomGap),
                ],
              ),
              ?_buildExitControls(l10n, textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Stepper dots — active dot expands to pill shape for clear indication.
// =============================================================================

class _StepperDots extends StatelessWidget {
  const _StepperDots({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    const accent = WpColors.accent;
    const muted = WpColors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalSteps, (index) {
        final isActive = index == currentStep;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
          child: AnimatedContainer(
            duration: WpMotion.durationFor(context, WpMotion.fast),
            curve: WpMotion.defaultCurve,
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: WpRadius.borderFull,
              color: isActive ? accent : muted.withValues(alpha: 0.35),
            ),
          ),
        );
      }),
    );
  }
}
