import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:record/record.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_accent_button.dart';

// ---------------------------------------------------------------------------
// Mic step state machine
// ---------------------------------------------------------------------------

enum _MicPhase {
  idle, // Initial — show "Grant access" button
  requesting, // Checking OS permission
  denied, // Permission was denied
  verifying, // Permission granted → auto-testing mic capture
  ready, // Mic confirmed working
}

/// Onboarding Step 2 — Microphone permission with automatic verification.
///
/// Grants OS permission and immediately auto-tests the mic with a brief
/// amplitude capture. The user sees one seamless flow: tap → verify → done.
class MicrophoneStep extends StatefulWidget {
  const MicrophoneStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<MicrophoneStep> createState() => _MicrophoneStepState();
}

class _MicrophoneStepState extends State<MicrophoneStep>
    with SingleTickerProviderStateMixin {
  _MicPhase _phase = _MicPhase.idle;

  late final AnimationController _pulseController;
  Timer? _verifyTimer;
  AudioRecorder? _recorder;

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
    _verifyTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _grantAndVerify() async {
    setState(() => _phase = _MicPhase.requesting);

    try {
      _recorder ??= AudioRecorder();
      final granted = await _recorder!.hasPermission();
      if (!mounted) return;

      if (!granted) {
        setState(() => _phase = _MicPhase.denied);
        return;
      }

      // Permission granted — auto-verify with 2s amplitude capture.
      setState(() => _phase = _MicPhase.verifying);
      _pulseController.repeat(reverse: true);

      _verifyTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _pulseController.stop();
        _pulseController.value = 0;
        setState(() => _phase = _MicPhase.ready);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _MicPhase.denied);
    }
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
    final successColor = isDark ? WpColorsDark.success : WpColorsLight.success;

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

        Text(
          l10n.onboardingMicSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // -- Unified mic status area ----------------------------------------
        AnimatedSwitcher(
          duration: WpMotion.smooth,
          switchInCurve: WpMotion.smooth_,
          switchOutCurve: WpMotion.smooth_,
          child: _buildStatusArea(
            isDark: isDark,
            accent: accent,
            surfaceVariant: surfaceVariant,
            textSecondary: textSecondary,
            successColor: successColor,
            l10n: l10n,
          ),
        ),
        const SizedBox(height: WpSpacing.lg),

        // -- Action button (Grant / Retry) -----------------------------------
        AnimatedSwitcher(
          duration: WpMotion.smooth,
          child: _phase == _MicPhase.idle || _phase == _MicPhase.denied
              ? Column(
                  key: ValueKey(_phase),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_phase == _MicPhase.denied) ...[
                      Text(
                        l10n.onboardingMicDeniedInstructions,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: textSecondary),
                      ),
                      const SizedBox(height: WpSpacing.sm),
                    ],
                    SizedBox(
                      width: 220,
                      child: WpAccentButton(
                        label: l10n.onboardingMicRequestAccess,
                        gradient: accentGradient,
                        onPressed: _grantAndVerify,
                      ),
                    ),
                  ],
                )
              : _phase == _MicPhase.requesting
                  ? const SizedBox.shrink(key: ValueKey('requesting'))
                  : const SizedBox.shrink(key: ValueKey('done')),
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
              width: 140,
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: _phase == _MicPhase.ready ? widget.onNext : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusArea({
    required bool isDark,
    required Color accent,
    required Color surfaceVariant,
    required Color textSecondary,
    required Color successColor,
    required L10n l10n,
  }) {
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    switch (_phase) {
      case _MicPhase.idle:
        return Column(
          key: const ValueKey('idle'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mic, size: WpIconSize.xxl, color: textMuted),
            const SizedBox(height: WpSpacing.sm),
            Text(
              l10n.onboardingMicPermissionPending,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
          ],
        );

      case _MicPhase.requesting:
        return Column(
          key: const ValueKey('requesting'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: WpIconSize.xxl,
              height: WpIconSize.xxl,
              child:
                  CircularProgressIndicator(strokeWidth: 2.5, color: accent),
            ),
            const SizedBox(height: WpSpacing.sm),
            Text(
              l10n.onboardingMicPermissionPending,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        );

      case _MicPhase.denied:
        final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;
        return Column(
          key: const ValueKey('denied'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleX, size: WpIconSize.xxl, color: errorColor),
            const SizedBox(height: WpSpacing.sm),
            Text(
              l10n.onboardingMicPermissionDenied,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: errorColor,
              ),
            ),
          ],
        );

      case _MicPhase.verifying:
        return Container(
          key: const ValueKey('verifying'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.lg,
            vertical: WpSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: accent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                excludeSemantics: true,
                child: SizedBox(
                  height: 40,
                  child: _WaveformBars(
                    animation: _pulseController,
                    isActive: true,
                    accent: accent,
                    muted: textSecondary.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: WpSpacing.sm),
              Text(
                l10n.onboardingMicTestRecording,
                style: TextStyle(fontSize: 13, color: accent),
              ),
            ],
          ),
        );

      case _MicPhase.ready:
        return TweenAnimationBuilder<double>(
          key: const ValueKey('ready'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: WpMotion.smooth,
          curve: Curves.elasticOut,
          builder: (_, value, child) => Transform.scale(
            scale: 0.5 + (value * 0.5),
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: WpIconSize.xxl + 12,
                height: WpIconSize.xxl + 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: successColor.withValues(alpha: 0.12),
                ),
                child: Icon(LucideIcons.circleCheck,
                    size: WpIconSize.xxl, color: successColor),
              ),
              const SizedBox(height: WpSpacing.sm),
              Text(
                l10n.onboardingMicPermissionGranted,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: successColor,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              Text(
                l10n.onboardingMicTestDone,
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ],
          ),
        );
    }
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
              child: Container(
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
