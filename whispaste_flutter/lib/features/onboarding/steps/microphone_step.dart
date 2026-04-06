import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Permission state machine
// ---------------------------------------------------------------------------

enum _MicPermission { unknown, checking, granted, denied }

/// Onboarding Step 2 — Microphone permission & optional test recording.
///
/// This is a UI-only widget. Actual audio permission / recording is wired
/// later — the "Grant Access" tap simulates a brief delay then marks
/// permission as granted so users can proceed through onboarding.
class MicrophoneStep extends ConsumerStatefulWidget {
  const MicrophoneStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  ConsumerState<MicrophoneStep> createState() => _MicrophoneStepState();
}

class _MicrophoneStepState extends ConsumerState<MicrophoneStep>
    with SingleTickerProviderStateMixin {
  _MicPermission _permissionStatus = _MicPermission.unknown;
  bool _isTestRecording = false;
  bool _testComplete = false;

  // Pulse animation for the simulated recording visualizer.
  late final AnimationController _pulseController;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _requestPermission() async {
    setState(() => _permissionStatus = _MicPermission.checking);

    // Simulate OS permission dialog delay — real integration later.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() => _permissionStatus = _MicPermission.granted);
  }

  void _startTestRecording() {
    if (_isTestRecording) return;
    setState(() {
      _isTestRecording = true;
      _testComplete = false;
    });
    _pulseController.repeat(reverse: true);

    _recordingTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _pulseController.stop();
      _pulseController.value = 0;
      setState(() {
        _isTestRecording = false;
        _testComplete = true;
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final surfaceVariant =
        isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Title -----------------------------------------------------------
        Text(
          l10n.onboardingMicTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),

        // -- Subtitle --------------------------------------------------------
        Text(
          l10n.onboardingMicSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // -- Permission status indicator -------------------------------------
        AnimatedSwitcher(
          duration: WpMotion.smooth,
          switchInCurve: WpMotion.smooth_,
          switchOutCurve: WpMotion.smooth_,
          child: _PermissionIndicator(
            key: ValueKey(_permissionStatus),
            status: _permissionStatus,
            isDark: isDark,
          ),
        ),
        const SizedBox(height: WpSpacing.md),

        // -- Grant access button (hidden once granted) -----------------------
        AnimatedSwitcher(
          duration: WpMotion.smooth,
          child: _permissionStatus == _MicPermission.granted
              ? const SizedBox.shrink(key: ValueKey('hidden'))
              : SizedBox(
                  key: const ValueKey('grant'),
                  width: 200,
                  child: _AccentButton(
                    label: l10n.onboardingMicRequestAccess,
                    gradient: accentGradient,
                    textColor: textPrimary,
                    onPressed: _permissionStatus == _MicPermission.checking
                        ? null
                        : _requestPermission,
                  ),
                ),
        ),
        const SizedBox(height: WpSpacing.lg),

        // -- Mic test area (visible after permission granted) ----------------
        AnimatedSize(
          duration: WpMotion.smooth,
          curve: WpMotion.smooth_,
          child: _permissionStatus == _MicPermission.granted
              ? _MicTestArea(
                  isDark: isDark,
                  accent: accent,
                  surfaceVariant: surfaceVariant,
                  textSecondary: textSecondary,
                  isRecording: _isTestRecording,
                  testComplete: _testComplete,
                  pulseAnimation: _pulseController,
                  onTap: _startTestRecording,
                  l10n: l10n,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // -- Navigation row --------------------------------------------------
        Row(
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 120,
              child: _AccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                textColor: textPrimary,
                onPressed: widget.onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Permission status indicator — icon + label with animated transitions
// =============================================================================

class _PermissionIndicator extends StatelessWidget {
  const _PermissionIndicator({
    super.key,
    required this.status,
    required this.isDark,
  });

  final _MicPermission status;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final (IconData icon, Color color, String label) = switch (status) {
      _MicPermission.granted => (
          LucideIcons.circleCheck,
          isDark ? WpColorsDark.success : WpColorsLight.success,
          l10n.onboardingMicPermissionGranted,
        ),
      _MicPermission.denied => (
          LucideIcons.circleX,
          isDark ? WpColorsDark.error : WpColorsLight.error,
          l10n.onboardingMicPermissionDenied,
        ),
      _MicPermission.checking => (
          LucideIcons.clock,
          isDark ? WpColorsDark.warning : WpColorsLight.warning,
          l10n.onboardingMicPermissionPending,
        ),
      _MicPermission.unknown => (
          LucideIcons.clock,
          isDark ? WpColorsDark.warning : WpColorsLight.warning,
          l10n.onboardingMicPermissionPending,
        ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: WpIconSize.xxl, color: color),
        const SizedBox(height: WpSpacing.sm),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Mic test area — rounded container with animated level bars
// =============================================================================

class _MicTestArea extends StatelessWidget {
  const _MicTestArea({
    required this.isDark,
    required this.accent,
    required this.surfaceVariant,
    required this.textSecondary,
    required this.isRecording,
    required this.testComplete,
    required this.pulseAnimation,
    required this.onTap,
    required this.l10n,
  });

  final bool isDark;
  final Color accent;
  final Color surfaceVariant;
  final Color textSecondary;
  final bool isRecording;
  final bool testComplete;
  final AnimationController pulseAnimation;
  final VoidCallback onTap;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final hintText = isRecording
        ? l10n.onboardingMicTestRecording
        : testComplete
            ? l10n.onboardingMicTestDone
            : l10n.onboardingMicTestHint;

    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.onboardingMicTestTitle,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        GestureDetector(
          onTap: isRecording ? null : onTap,
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.lg,
              vertical: WpSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: surfaceVariant,
              borderRadius: WpRadius.borderLg,
              border: Border.all(
                color: isRecording ? accent : borderColor,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Waveform bars
                SizedBox(
                  height: 40,
                  child: _WaveformBars(
                    animation: pulseAnimation,
                    isActive: isRecording,
                    accent: accent,
                    muted: textSecondary.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(height: WpSpacing.sm),
                AnimatedSwitcher(
                  duration: WpMotion.fast,
                  child: Text(
                    hintText,
                    key: ValueKey(hintText),
                    style: TextStyle(
                      fontSize: 13,
                      color: isRecording ? accent : textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Waveform bars — simple animated level visualization
// =============================================================================

class _WaveformBars extends StatelessWidget {
  const _WaveformBars({
    required this.animation,
    required this.isActive,
    required this.accent,
    required this.muted,
  });

  final AnimationController animation;
  final bool isActive;
  final Color accent;
  final Color muted;

  static const _barCount = 16;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_barCount, (i) {
            // Vary heights using a seeded pattern so bars look organic.
            final phase = (i / _barCount) * math.pi * 2;
            final base = 0.25 + 0.15 * math.sin(phase * 1.7 + i);
            final animatedHeight = isActive
                ? base +
                    (1.0 - base) *
                        animation.value *
                        (0.5 + 0.5 * math.sin(phase + animation.value * 3))
                : base;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: WpMotion.fast,
                width: 3,
                height: 40 * animatedHeight.clamp(0.15, 1.0),
                decoration: BoxDecoration(
                  color: isActive ? accent : muted,
                  borderRadius: WpRadius.borderFull,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// =============================================================================
// Full-width accent gradient CTA button (mirrors welcome_step.dart)
// =============================================================================

class _AccentButton extends StatefulWidget {
  const _AccentButton({
    required this.label,
    required this.gradient,
    required this.textColor,
    required this.onPressed,
  });

  final String label;
  final LinearGradient gradient;
  final Color textColor;
  final VoidCallback? onPressed;

  @override
  State<_AccentButton> createState() => _AccentButtonState();
}

class _AccentButtonState extends State<_AccentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;
    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: !isDisabled && _hovered ? 1.02 : 1.0,
          duration: WpMotion.fast,
          curve: WpMotion.defaultCurve,
          child: AnimatedOpacity(
            duration: WpMotion.fast,
            opacity: isDisabled ? 0.5 : 1.0,
            child: AnimatedContainer(
              duration: WpMotion.fast,
              curve: WpMotion.defaultCurve,
              padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
              decoration: BoxDecoration(
                gradient: widget.gradient,
                borderRadius: WpRadius.borderMd,
              ),
              alignment: Alignment.center,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: widget.textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
