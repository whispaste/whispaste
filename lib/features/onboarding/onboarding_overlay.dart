import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/config/build_config.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/logging/app_logger.dart';
import '../../services/hotkey_service.dart';
import '../../services/paste/paste_capability_notifier.dart';
import '../../services/permissions/mic_permission_notifier.dart';
import '../../services/telemetry_service.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_hero_button.dart';
import 'onboarding_completion_gate.dart';
import 'onboarding_flow_migration.dart';
import 'steps/appearance_step.dart';
import 'steps/auto_paste_step.dart';
import 'steps/autostart_toggle.dart';
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

/// Height of the onboarding top bar's control row, and the hit target of the
/// close button that sits in it on the platforms that render one.
///
/// Pinned rather than derived so the bar keeps the exact same height on macOS,
/// where the button is omitted — everything below it must not shift.
const double _kOnboardingTopBarHeight = 32;

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
/// The two moves are deliberately equal and opposite (−16 / +16), so the
/// scroll viewport stays at exactly 551 px and every page height measured in
/// `onboarding_overlay_test.dart` keeps its meaning. Changing one without the
/// other is what would silently make a page scroll.
///
/// Not 1 : 1: the top gap is empty, while these 32 px sit under a three-row
/// footer stack (nav row, dots, counter) that already carries visual weight —
/// a reading start wants more air above it than trailing meta-text wants
/// below it.
const double _kOnboardingBottomGap = WpSpacing.xxl;

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

  /// 5 — Appearance: the light/dark/system theme choice plus the autostart
  /// toggle — the two things that decide how the app presents itself before
  /// it is ever used.
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
/// Sits on top of the main app shell in a [Stack] and covers it with a flat
/// theme-background surface — no blur, no dimmed scrim, no floating card.
/// Seven pages (six on Linux) with animated transitions, a shell-owned
/// Back/Next navigation
/// row (Next becomes the completion CTA on the last page), stepper dots, and
/// a step counter. The whole surface doubles as a window drag area (the
/// title bar is hidden during onboarding). On completion persists
/// [AppSettings.onboarding]`.onboardingCompleted` = true.
class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({super.key});

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  static final _log = AppLogger('Onboarding');

  /// Max content width — wider than the old 600-px card so the merged pages
  /// (side-by-side engine cards + hotkey block) breathe, but still bounded
  /// for readable line lengths on large windows.
  static const double _contentMaxWidth = 720;

  /// Page 1 runs a wider frame than the settings-shaped pages behind it — its
  /// composition is a text column *beside* a large media panel, and at 720
  /// the two halves squeeze each other. The width itself is owned by
  /// [kOnboardingWelcomeFrameWidth], because the recorded clip dimensions are
  /// derived from it. Every page behind it deliberately keeps 720: their
  /// density was measured against that width and must not silently change.
  double _frameWidthFor(OnboardingStepId id) => id == OnboardingStepId.welcome
      ? kOnboardingWelcomeFrameWidth
      : _contentMaxWidth;

  /// Whether the page hands its leftover height to its body block
  /// ([OnboardingPageFill] plus the page's own [OnboardingPageBody]).
  ///
  /// Every page does, including page 1: its brand lockup is that page's
  /// header, and it has to start at the same height as every other page's
  /// heading. Centring the page as a whole — which is what page 1 used to do —
  /// made the lockup's position depend on how tall the rest of the page was,
  /// so the logo sat visibly lower than page 2's title. Including the tight
  /// pages costs nothing: the fill can never shrink a gap below its minimum,
  /// so the hotkey page's conflict branch (13 px of slack in German) simply
  /// keeps its minimum gaps.
  ///
  /// [OnboardingStepId.tryAndGo] is the one exclusion. It is not a header
  /// over a body but two side-by-side columns of unequal height, and its
  /// heading is the first block of the *left* column (bounded to that
  /// column's measure), already sitting at the same height as every other
  /// page's. With ~22 px of slack, centring the pair as one block would move
  /// that heading off the shared line to buy 11 px nobody can see.
  bool _fillsViewport(OnboardingStepId id) => id != OnboardingStepId.tryAndGo;

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
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              onboarding: s.onboarding.copyWith(
                onboardingCurrentStep: saved,
                onboardingFlowVersion: kOnboardingFlowVersion,
              ),
            ),
          );
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
  void _persistCurrentStep(int step) {
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
      _trackStep('step', steps[_currentStep]);
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

  Future<void> _complete() async {
    _trackStep('complete', OnboardingStepId.tryAndGo);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            onboarding: s.onboarding.copyWith(
              onboardingCompleted: true,
              onboardingCurrentStep: 0,
            ),
          ),
        );
  }

  // ---------------------------------------------------------------------------
  // Page builder — merged page contents; navigation stays with the shell.
  // ---------------------------------------------------------------------------

  Widget _buildStep(OnboardingStepId id, double availableHeight) {
    final page = _buildStepContent(id);
    return _fillsViewport(id)
        ? OnboardingPageFill(availableHeight: availableHeight, child: page)
        : page;
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
      OnboardingStepId.welcome => const WelcomeStep(),
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
      // Theme choice and autostart under one heading: both answer "how does
      // this app present itself before I ever use it". The heading names both
      // halves in order, which is what keeps the settings row from reading as
      // a second, unrelated screen glued below the tiles — it needs no
      // section label of its own, since its own label and subtitle already
      // say what it is.
      OnboardingStepId.appearance => OnboardingPage(
        header: OnboardingPageHeading(
          title: l10n.onboardingAppearancePageTitle,
          subtitle: l10n.onboardingAppearancePageSubtitle,
        ),
        // The one page whose body has an internal gap: `xl` between the theme
        // tiles and the autostart row, deliberately one step under the header
        // gap so the two halves still read as one page.
        body: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppearanceStep(),
            SizedBox(height: WpSpacing.xl),
            OnboardingAutostartToggle(),
          ],
        ),
      ),
      OnboardingStepId.autoPaste => OnboardingPage(
        header: OnboardingPageHeading(
          title: l10n.onboardingPasteTitle,
          subtitle: l10n.onboardingPasteSubtitle,
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
      // The one page that is not a header over a centred body: its heading is
      // the first block of the left column, which puts it on the same line as
      // every other page's heading already. See [_fillsViewport].
      OnboardingStepId.tryAndGo => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: TestRecordingStep()),
          SizedBox(width: WpSpacing.xxl),
          Expanded(flex: 4, child: ReadyStep()),
        ],
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    final background = isDark
        ? WpColorsDark.background
        : WpColorsLight.background;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;

    return BlockSemantics(
      // The whole surface doubles as a window drag area: the title bar is
      // hidden during onboarding, and interactive children win the gesture
      // arena over the pan recognizer, so dragging any empty region moves
      // the window.
      child: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: ColoredBox(
          // Flat, opaque, edge-to-edge page surface — deliberately no blur
          // and no dimmed scrim (and therefore no Windows frameless-window
          // blur fallback either).
          color: background,
          child: Column(
            children: [
              // -- Top bar: close (X); doubles as an explicit drag handle. --
              //
              // The window runs with `TitleBarStyle.hidden`, which means two
              // different things per platform: macOS keeps the native traffic
              // lights in exactly this corner (only the bar's chrome is gone),
              // while Windows/Linux get a fully frameless window with no
              // native close control at all. So the custom X is the *only*
              // close affordance there and would be a second, overlapping one
              // on macOS. The bar itself is unconditional and keeps its fixed
              // height either way — it is still the drag handle, and nothing
              // below it may shift.
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: Padding(
                  // Horizontal only. The strip's own vertical padding used to
                  // add 16 px to a band that is empty on macOS and carries a
                  // single 32-px icon button elsewhere, which is what pushed
                  // every page's header 68 px down the window — see
                  // [_kOnboardingBottomGap].
                  padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
                  child: SizedBox(
                    height: _kOnboardingTopBarHeight,
                    child: Row(
                      children: [
                        if (defaultTargetPlatform != TargetPlatform.macOS)
                          IconButton(
                            onPressed: () => windowManager.close(),
                            icon: Icon(
                              LucideIcons.x,
                              size: 18,
                              color: textMuted,
                            ),
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                            splashRadius: 16,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: _kOnboardingTopBarHeight,
                              minHeight: _kOnboardingTopBarHeight,
                            ),
                          ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),

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
                padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
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
                              ? l10n.onboardingStartUsing
                              : l10n.onboardingNext,
                          gradient: accentGradient,
                          onPressed: isLastStep
                              ? (completionEnabled ? _complete : null)
                              : _goNext,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // -- Stepper dots + step counter. -----------------------------
              const SizedBox(height: WpSpacing.md),
              _StepperDots(currentStep: safeCurrent, totalSteps: totalSteps),
              const SizedBox(height: WpSpacing.xs),
              Text(
                l10n.onboardingStepOf(safeCurrent + 1, totalSteps),
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: textMuted,
                ),
              ),
              const SizedBox(height: _kOnboardingBottomGap),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final muted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

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
