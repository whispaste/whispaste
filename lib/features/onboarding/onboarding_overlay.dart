import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/config/build_config.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/logging/app_logger.dart';
import '../../services/paste/paste_capability_notifier.dart';
import '../../services/telemetry_service.dart';
import 'steps/auto_paste_step.dart';
import 'steps/welcome_step.dart';
import 'steps/microphone_step.dart';
import 'steps/model_step.dart';
import 'steps/ready_step.dart';

/// Identifier for each step in the first-run onboarding flow.
///
/// The set of steps rendered by [OnboardingOverlay] varies by platform and
/// build variant:
/// - [autoPaste] is included only on macOS Developer-ID builds where
///   [kAutoPasteSupported] is `true` (the user must grant Accessibility/TCC).
/// - MAS builds and non-macOS platforms omit [autoPaste] entirely.
enum OnboardingStepId { welcome, microphone, autoPaste, model, ready }

/// Returns the ordered list of onboarding step IDs for the given platform and
/// build configuration.
///
/// Extracted as a top-level function so unit tests can assert the exact step
/// sequence without pumping the full widget tree or touching global state.
/// Wire [kAutoPasteSupported] at the call site; pass it as a parameter here
/// so tests can inject both `true` and `false` without a real MAS compile.
///
/// [autoPaste] is included when [platform] is [TargetPlatform.macOS] **and**
/// [autoPasteSupported] is `true`. MAS builds pass `false`; non-macOS
/// platforms never reach the macOS branch regardless.
@visibleForTesting
List<OnboardingStepId> buildOnboardingStepIds({
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) {
  final isMacOs = platform == TargetPlatform.macOS;
  return [
    OnboardingStepId.welcome,
    OnboardingStepId.microphone,
    if (isMacOs && autoPasteSupported) OnboardingStepId.autoPaste,
    OnboardingStepId.model,
    OnboardingStepId.ready,
  ];
}

/// Full-screen onboarding overlay with frosted glass backdrop.
///
/// Sits on top of the main app shell in a [Stack]. Shows 4–5 steps with
/// animated transitions, stepper dots, and a skip button. Step count is
/// platform- and build-variant-dependent (see [buildOnboardingStepIds]):
/// macOS Developer-ID renders 5 steps; macOS MAS, Windows, and Linux
/// render 4 (Auto-Paste step omitted). On completion (or skip) persists
/// [AppSettings.onboardingCompleted] = true.
class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({super.key});

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  static final _log = AppLogger('Onboarding');

  int _currentStep = 0;
  int _previousStep = 0;

  /// Cached notifier reference so [dispose] can stop polling without
  /// touching `ref` — Riverpod forbids `ref` access after deactivation.
  /// The overlay owns the provider scope, so sudden window-close (X tapped,
  /// app quit) tears down the widget tree without giving the AutoPasteStep
  /// a chance to run its own dispose; defending here guarantees no zombie
  /// polling timer survives the overlay.
  PasteCapabilityNotifier? _cachedPasteNotifier;

  @override
  void initState() {
    super.initState();
    // Funnel entry: the first step is reached without a _goNext call.
    _trackStep('step', _onboardingSteps().first);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the notifier as soon as the provider scope is reachable so the
    // dispose path never needs to touch `ref`.
    _cachedPasteNotifier ??= ref.read(pasteCapabilityNotifierProvider.notifier);
  }

  @override
  void dispose() {
    // Defensive cleanup: the AutoPasteStep also stops polling in its own
    // dispose, but the overlay owns the provider scope and is the last line
    // of defence against sudden tear-downs (window close, app quit) that
    // skip individual step disposals.
    _cachedPasteNotifier?.stopPolling();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Step sequence
  // ---------------------------------------------------------------------------

  /// Returns the ordered step IDs for the current platform and build variant.
  ///
  /// Delegates to [buildOnboardingStepIds], wiring [defaultTargetPlatform] and
  /// [kAutoPasteSupported] from the build environment. MAS builds have
  /// [kAutoPasteSupported] == `false` at compile time, so the Auto-Paste step
  /// is omitted without any runtime branching on a separate flag.
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
      setState(() {
        _previousStep = _currentStep;
        _currentStep++;
      });
      _trackStep('step', steps[_currentStep]);
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() {
        _previousStep = _currentStep;
        _currentStep--;
      });
    }
  }

  void _skip() {
    // Skip advances to the next step rather than completing the entire
    // onboarding immediately. This lets users skip individual steps while
    // still seeing the remaining ones. On the last step there is no skip
    // button — only the "Let's go" CTA.
    final steps = _onboardingSteps();
    if (_currentStep < steps.length - 1) {
      _trackStep('skip', steps[_currentStep]);
      _goNext();
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    _trackStep('complete', OnboardingStepId.ready);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(onboardingCompleted: true));
  }

  // ---------------------------------------------------------------------------
  // Step builder
  // ---------------------------------------------------------------------------

  Widget _buildStep(OnboardingStepId id) {
    return switch (id) {
      OnboardingStepId.welcome => WelcomeStep(onNext: _goNext),
      OnboardingStepId.microphone => MicrophoneStep(
        onNext: _goNext,
        onBack: _goBack,
      ),
      OnboardingStepId.autoPaste => AutoPasteStep(
        onNext: _goNext,
        onBack: _goBack,
      ),
      OnboardingStepId.model => ModelStep(onNext: _goNext, onBack: _goBack),
      OnboardingStepId.ready => ReadyStep(
        onComplete: _complete,
        onBack: _goBack,
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
    // Clamp in case a platform flip during widget-test setup leaves the
    // current index out of bounds (e.g. resizing the list from 5 to 4).
    final safeCurrent = _currentStep.clamp(0, totalSteps - 1);
    final direction = _currentStep >= _previousStep ? 1.0 : -1.0;
    return BlockSemantics(
      child: Stack(
        children: [
          // -- Frosted glass backdrop ----------------------------------------
          // The entire overlay is draggable so users can move the window
          // during onboarding (title bar is hidden behind the overlay).
          Positioned.fill(
            child: GestureDetector(
              onTap: () {},
              onPanStart: (_) => windowManager.startDragging(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
          ),

          // -- Centered content ----------------------------------------------
          Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WpSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top bar — close (X) left, skip right. The row
                      // background acts as a drag handle so the window
                      // stays movable even above the content card.
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) => windowManager.startDragging(),
                        child: Row(
                          children: [
                            // Close button — always visible
                            IconButton(
                              onPressed: () => windowManager.close(),
                              icon: Icon(
                                LucideIcons.x,
                                size: 18,
                                color: isDark
                                    ? WpColorsDark.textMuted
                                    : WpColorsLight.textMuted,
                              ),
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
                            // Skip button — visible on every step except the
                            // final one (which has its own primary CTA).
                            if (safeCurrent < totalSteps - 1)
                              Semantics(
                                button: true,
                                label: l10n.onboardingSkip,
                                child: TextButton(
                                  onPressed: _skip,
                                  child: Text(
                                    l10n.onboardingSkip,
                                    style: TextStyle(
                                      color: isDark
                                          ? WpColorsDark.textMuted
                                          : WpColorsLight.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: WpSpacing.xs),

                      // Content card
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? WpColorsDark.surfaceElevated
                              : WpColorsLight.surfaceElevated,
                          borderRadius: WpRadius.borderXl,
                          border: Border.all(
                            color: isDark
                                ? WpColorsDark.borderSubtle
                                : WpColorsLight.borderSubtle,
                          ),
                          boxShadow: WpShadows.elevated,
                        ),
                        padding: const EdgeInsets.all(WpSpacing.xxl),
                        child: AnimatedSwitcher(
                          duration: WpMotion.smooth,
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

                      const SizedBox(height: WpSpacing.lg),

                      // Stepper dots (pill-style active indicator)
                      _StepperDots(
                        currentStep: safeCurrent,
                        totalSteps: totalSteps,
                      ),

                      // Step counter text ("Step X of Y")
                      const SizedBox(height: WpSpacing.xs),
                      Text(
                        l10n.onboardingStepOf(safeCurrent + 1, totalSteps),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? WpColorsDark.textMuted
                              : WpColorsLight.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
            duration: WpMotion.fast,
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
