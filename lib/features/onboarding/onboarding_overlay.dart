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
import 'onboarding_flow_migration.dart';
import 'steps/auto_paste_step.dart';
import 'steps/autostart_toggle.dart';
import 'steps/welcome_step.dart';
import 'steps/privacy_step.dart';
import 'steps/mic_permission_chip.dart';
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

/// Identifier for each page of the five-step first-run onboarding flow.
///
/// The sequence is identical on every platform and build variant — platform
/// variance (Auto-Paste visibility) lives *inside* the
/// [autostartAndAutoPaste] page, never in the sequence itself.
enum OnboardingStepId {
  /// 1 — Welcome: demo beats, language selection and the microphone
  /// permission status chip (macOS/Windows; Linux shows no chip).
  welcome,

  /// 2 — Privacy: informed telemetry/crash-report opt-out.
  privacy,

  /// 3 — Model & Hotkey: engine choice/download plus hotkey configuration.
  modelAndHotkey,

  /// 4 — Autostart & Auto-Paste: autostart toggle; Auto-Paste status on
  /// macOS and Windows (Linux shows only the autostart toggle — no paste
  /// controller is wired there).
  autostartAndAutoPaste,

  /// 5 — Try & Go: guided test recording, quick-start hints, completion CTA.
  tryAndGo,
}

/// Returns the ordered list of onboarding step IDs.
///
/// The five-step sequence is deliberately identical for every [platform] and
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
    OnboardingStepId.autostartAndAutoPaste,
    OnboardingStepId.tryAndGo,
  ];
}

/// Full-window, edge-to-edge onboarding flow.
///
/// Sits on top of the main app shell in a [Stack] and covers it with a flat
/// theme-background surface — no blur, no dimmed scrim, no floating card.
/// Five pages with animated transitions, a shell-owned Back/Next navigation
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

  Widget _buildStep(OnboardingStepId id) {
    // Auto-Paste status visibility is the single piece of platform variance
    // in the flow — a content decision inside page 4, driven by
    // defaultTargetPlatform so widget tests can simulate every platform.
    // Also gated on kAutoPasteSupported: the deliberate App Review Guideline
    // 2.4.5 kill switch (see build_config.dart) must still be able to hide
    // Auto-Paste everywhere, onboarding included, if it's ever flipped.
    final showAutoPaste =
        kAutoPasteSupported &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows);
    return switch (id) {
      OnboardingStepId.welcome => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const WelcomeStep(),
          // Mic permission chip — macOS/Windows only. The chip self-gates on
          // Linux too; the condition here just avoids dangling spacing.
          if (defaultTargetPlatform != TargetPlatform.linux) ...[
            const SizedBox(height: WpSpacing.lg),
            const MicPermissionChip(),
          ],
        ],
      ),
      OnboardingStepId.privacy => const PrivacyStep(),
      OnboardingStepId.modelAndHotkey => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ModelStep(),
          SizedBox(height: WpSpacing.xxl),
          TriggerStep(),
        ],
      ),
      OnboardingStepId.autostartAndAutoPaste => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OnboardingAutostartToggle(),
          if (showAutoPaste) ...[
            const SizedBox(height: WpSpacing.xxl),
            const AutoPasteStep(),
          ],
        ],
      ),
      OnboardingStepId.tryAndGo => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TestRecordingStep(),
          SizedBox(height: WpSpacing.xxl),
          ReadyStep(),
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

    // Residual safety gate (moved from the old ReadyStep): a confirmed
    // hotkey conflict disables the completion CTA so the user is never sent
    // into a non-functional hotkey. `unknown` stays enabled — background
    // registration must not block on a transient first-mount race.
    final hotkeyStatus = ref.watch(hotkeyRegistrationStatusProvider);
    final completionEnabled = hotkeyStatus != HotkeyRegistrationStatus.conflict;

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
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.xl,
                      vertical: WpSpacing.lg,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
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
                          key: ValueKey<OnboardingStepId>(steps[safeCurrent]),
                          child: _buildStep(steps[safeCurrent]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // -- Shell-owned navigation: exactly two actions per page. ----
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
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
