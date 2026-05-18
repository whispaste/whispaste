import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import 'steps/auto_paste_step.dart';
import 'steps/welcome_step.dart';
import 'steps/microphone_step.dart';
import 'steps/model_step.dart';
import 'steps/ready_step.dart';

/// Full-screen onboarding overlay with frosted glass backdrop.
///
/// Sits on top of the main app shell in a [Stack]. Shows 4 steps with
/// animated transitions, stepper dots, and a skip button. On completion
/// (or skip) persists [AppSettings.onboardingCompleted] = true.
class OnboardingOverlay extends ConsumerStatefulWidget {
  const OnboardingOverlay({super.key});

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

/// Platform-dependent identifier for each onboarding step.
///
/// The set of steps the overlay renders varies by platform: Linux skips
/// the Auto-Paste permission step because the underlying capability is
/// not supported there, so we describe the flow as a list of these IDs
/// and let [_buildStep] map each one to its widget.
enum _OnboardingStepId { welcome, microphone, autoPaste, model, ready }

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  int _currentStep = 0;
  int _previousStep = 0;

  // ---------------------------------------------------------------------------
  // Step sequence
  // ---------------------------------------------------------------------------

  /// Returns the ordered step IDs for the current platform.
  ///
  /// Linux has no Accessibility-style permission for keystroke injection,
  /// so [AutoPasteStep] would have nothing to do and is omitted entirely.
  /// macOS and Windows both include it (Windows still gets the shared
  /// placeholder UI until slice 05).
  List<_OnboardingStepId> _onboardingSteps() {
    final isLinux = defaultTargetPlatform == TargetPlatform.linux;
    return [
      _OnboardingStepId.welcome,
      _OnboardingStepId.microphone,
      if (!isLinux) _OnboardingStepId.autoPaste,
      _OnboardingStepId.model,
      _OnboardingStepId.ready,
    ];
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  void _goNext() {
    final total = _onboardingSteps().length;
    if (_currentStep < total - 1) {
      setState(() {
        _previousStep = _currentStep;
        _currentStep++;
      });
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
    // button — only the "Start Dictating" CTA.
    final total = _onboardingSteps().length;
    if (_currentStep < total - 1) {
      _goNext();
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(onboardingCompleted: true));
  }

  // ---------------------------------------------------------------------------
  // Step builder
  // ---------------------------------------------------------------------------

  Widget _buildStep(_OnboardingStepId id) {
    return switch (id) {
      _OnboardingStepId.welcome => WelcomeStep(onNext: _goNext),
      _OnboardingStepId.microphone => MicrophoneStep(
        onNext: _goNext,
        onBack: _goBack,
      ),
      _OnboardingStepId.autoPaste => AutoPasteStep(
        onNext: _goNext,
        onBack: _goBack,
      ),
      _OnboardingStepId.model => ModelStep(onNext: _goNext, onBack: _goBack),
      _OnboardingStepId.ready => ReadyStep(
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
                            key: ValueKey<_OnboardingStepId>(
                              steps[safeCurrent],
                            ),
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
