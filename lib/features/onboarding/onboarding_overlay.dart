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
import '../../widgets/wp_accent_button.dart';
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

/// Identifier for each page of the six-step first-run onboarding flow.
///
/// The sequence is identical on every platform and build variant — platform
/// variance (Auto-Paste visibility) lives *inside* the
/// [autostartAndAutoPaste] page, never in the sequence itself.
enum OnboardingStepId {
  /// 1 — Welcome: demo beats and language selection. Deliberately carries no
  /// microphone affordance: the permission is requested when the user leaves
  /// this page (see `_goNext`) and the *visible* microphone status lives on
  /// [tryAndGo], where the microphone is actually used.
  welcome,

  /// 2 — Privacy: informed telemetry/crash-report opt-out.
  privacy,

  /// 3 — Model & Hotkey: engine choice/download plus hotkey configuration.
  modelAndHotkey,

  /// 4 — Appearance: the light/dark/system theme choice.
  appearance,

  /// 5 — Autostart & Auto-Paste: autostart toggle; Auto-Paste status on
  /// macOS and Windows (Linux shows only the autostart toggle — no paste
  /// controller is wired there).
  autostartAndAutoPaste,

  /// 6 — Try & Go: guided test recording, quick-start hints, completion CTA.
  tryAndGo,
}

/// Returns the ordered list of onboarding step IDs.
///
/// The six-step sequence is deliberately identical for every [platform] and
/// [autoPasteSupported] value — both parameters stay injected so the seam
/// (pure function, no widget tree, no global state) is preserved and unit
/// tests can assert the invariance explicitly instead of trusting it.
@visibleForTesting
List<OnboardingStepId> buildOnboardingStepIds({
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) {
  return const [
    OnboardingStepId.welcome,
    OnboardingStepId.privacy,
    OnboardingStepId.modelAndHotkey,
    OnboardingStepId.appearance,
    OnboardingStepId.autostartAndAutoPaste,
    OnboardingStepId.tryAndGo,
  ];
}

/// Full-window, edge-to-edge onboarding flow.
///
/// Sits on top of the main app shell in a [Stack] and covers it with a flat
/// theme-background surface — no blur, no dimmed scrim, no floating card.
/// Six pages with animated transitions, a shell-owned Back/Next navigation
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
  /// derived from it. Pages 2–6 deliberately keep 720: their density was
  /// measured against that width and must not silently change.
  double _frameWidthFor(OnboardingStepId id) => id == OnboardingStepId.welcome
      ? kOnboardingWelcomeFrameWidth
      : _contentMaxWidth;

  /// Page 1 is a brand moment and stays optically centred in its area. The
  /// settings-shaped pages behind it anchor to the top instead — and the ones
  /// that fill the viewport ([_fillsViewport]) are the full height of their
  /// area anyway, so for those this only decides where their own scroll
  /// content sits once a window smaller than the fixed one makes them scroll.
  ///
  /// Both this and [_frameWidthFor] are animated on a page change rather than
  /// switched (see `build`): changing width and anchor instantly while the
  /// 300 ms cross-fade is still running made the frame visibly jump.
  Alignment _contentAlignmentFor(OnboardingStepId id) =>
      id == OnboardingStepId.welcome ? Alignment.center : Alignment.topCenter;

  /// Whether the page distributes the viewport's leftover height between its
  /// blocks instead of stacking them at the top ([OnboardingPageFill]).
  ///
  /// Pages 2–5 do, because they have room to distribute: measured against the
  /// 511-px content area of the fixed window (551 px viewport minus the
  /// scroll view's padding), page 2 leaves 206 px over, page 4 259 and page 5
  /// 304. Page 3 leaves only 51 (27 in Hebrew), but it costs nothing to
  /// include — the fill can never shrink a gap below its minimum.
  ///
  /// Page 1 is excluded: it is a centred brand composition, not a stack of
  /// blocks. Page 6 is excluded because it is two side-by-side columns of
  /// unequal height with 30 px of slack in Hebrew — distributing that would
  /// pull the two columns' rhythms apart for a gain nobody can see.
  bool _fillsViewport(OnboardingStepId id) =>
      id != OnboardingStepId.welcome && id != OnboardingStepId.tryAndGo;

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
      // The persisted position was written against the legacy 7/8-step flow
      // (an interrupted first run that got this update mid-way). Translate
      // it into the functionally corresponding new page exactly once, then
      // stamp the flow version so the translation can never re-run.
      saved = migrateLegacyOnboardingStepIndex(
        legacyIndex: onboarding.onboardingCurrentStep,
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

  Widget _buildStepContent(OnboardingStepId id) {
    final l10n = L10n.of(context);
    // Auto-Paste status visibility is the single piece of platform variance
    // in the flow — a content decision inside page 5, driven by
    // defaultTargetPlatform so widget tests can simulate every platform.
    // Also gated on kAutoPasteSupported: the deliberate App Review Guideline
    // 2.4.5 kill switch (see build_config.dart) must still be able to hide
    // Auto-Paste everywhere, onboarding included, if it's ever flipped.
    final showAutoPaste =
        kAutoPasteSupported &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    return switch (id) {
      OnboardingStepId.welcome => const WelcomeStep(),
      OnboardingStepId.privacy => const PrivacyStep(),
      // Tightest height budget in the flow (measured at the fixed 1100x720
      // window with real Inter metrics, GPU-fallback notice visible — the
      // worst case): 540 px of content in German, 524 in Hebrew, against a
      // 551-px viewport. Splitting the theme choice onto its own page paid
      // for the page heading this page never had plus `md` gaps between the
      // two blocks; German keeps 11 px of slack, so do not add to this page
      // or raise a gap without re-measuring both locales
      // (`onboarding_overlay_test.dart`, fixed-window group).
      OnboardingStepId.modelAndHotkey => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title only, deliberately: both blocks below already carry a
          // section label *with* its own explanatory line, so a third
          // explanation here would be the page's third voice — and the 31 px
          // it costs is most of this page's remaining slack.
          OnboardingPageHeading(title: l10n.onboardingSetupPageTitle),
          const SizedBox(height: WpSpacing.md),
          // The flex weights are small everywhere on this page: there are
          // only ~51 px to hand out (27 in Hebrew), so this turns a thin dead
          // strip under the hotkey block into slightly looser gaps rather
          // than into a visible rearrangement.
          const OnboardingFlexGap(flex: 2),
          const ModelStep(),
          const SizedBox(height: WpSpacing.md),
          const OnboardingFlexGap(flex: 3),
          const TriggerStep(),
          const OnboardingFlexGap(flex: 2),
        ],
      ),
      OnboardingStepId.appearance => const AppearanceStep(),
      OnboardingStepId.autostartAndAutoPaste => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The thinnest page in the flow: 207 px of blocks in a 511-px area,
          // and on Linux (no Auto-Paste) a single settings row. It is also
          // the only settings-shaped page without an
          // [OnboardingPageHeading] — the flow has no string to head it with,
          // and inventing one is a copy decision, not a layout one. So the
          // 304 px go where they can: the autostart row stays fixed at the
          // top, and the gap between the two blocks stays clearly the smaller
          // share. That split is not free choice — the Auto-Paste block heads
          // itself with a section label precisely so the page does not read as
          // two fused screens (see `auto_paste_step.dart`), and a gap above it
          // as large as the page's tail undoes exactly that.
          const OnboardingAutostartToggle(),
          if (showAutoPaste) ...[
            const SizedBox(height: WpSpacing.xxl),
            const OnboardingFlexGap(flex: 2),
            const AutoPasteStep(),
          ],
          const OnboardingFlexGap(flex: 5),
        ],
      ),
      // Two columns, not a stack: as one column the page measured 739 px of
      // content against a 551-px viewport (188 px of forced scrolling in the
      // fixed 1100x720 window) and repeated the same mistake page 1 had —
      // ignoring the width the window already has. Side by side the guided
      // test recording (the thing to do) and the quick-start card (the thing
      // to read) each keep their own rhythm and the page fits without
      // scrolling. `start` cross-alignment keeps both column tops on the same
      // line; the plain Row mirrors for free under RTL.
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
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
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
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.sm,
                    vertical: WpSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => windowManager.close(),
                        icon: Icon(LucideIcons.x, size: 18, color: textMuted),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        splashRadius: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      const Spacer(),
                    ],
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
                    return AnimatedAlign(
                      alignment: _contentAlignmentFor(steps[safeCurrent]),
                      duration: WpMotion.durationFor(context, WpMotion.smooth),
                      curve: WpMotion.smooth_,
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
                      TextButton(
                        key: kOnboardingBackButtonKey,
                        onPressed: safeCurrent > 0 ? _goBack : null,
                        child: Text(
                          l10n.onboardingBack,
                          style: TextStyle(color: textSecondary),
                        ),
                      ),
                      const Spacer(),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 140),
                        // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
                        child: WpAccentButton(
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
              const SizedBox(height: WpSpacing.md),
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
