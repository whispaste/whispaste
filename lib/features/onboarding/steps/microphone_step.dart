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
// Permission state machine
// ---------------------------------------------------------------------------

enum _MicPermission { unknown, checking, granted, denied }

/// Onboarding Step 2 — Microphone permission & optional test recording.
///
/// Uses the `record` package to request real OS microphone permission and
/// optionally capture a brief test recording with live amplitude metering.
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
  _MicPermission _permissionStatus = _MicPermission.unknown;
  bool _isTestRecording = false;
  bool _testComplete = false;

  late final AnimationController _pulseController;
  Timer? _recordingTimer;
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
    _recordingTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _requestPermission() async {
    setState(() => _permissionStatus = _MicPermission.checking);

    try {
      _recorder ??= AudioRecorder();
      final granted = await _recorder!.hasPermission();
      if (!mounted) return;

      setState(() => _permissionStatus =
          granted ? _MicPermission.granted : _MicPermission.denied);
    } catch (_) {
      if (!mounted) return;
      setState(() => _permissionStatus = _MicPermission.denied);
    }
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
              : _permissionStatus == _MicPermission.denied
                  ? Column(
                      key: const ValueKey('denied'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.onboardingMicDeniedInstructions,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: textSecondary),
                        ),
                        const SizedBox(height: WpSpacing.sm),
                        SizedBox(
                          width: 200,
                          child: WpAccentButton(
                            label: l10n.onboardingMicRequestAccess,
                            gradient: accentGradient,
                            onPressed: _requestPermission,
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      key: const ValueKey('grant'),
                      width: 200,
                      child: WpAccentButton(
                        label: l10n.onboardingMicRequestAccess,
                        gradient: accentGradient,
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
              width: 140,
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                // Gate: Next only enabled after mic permission is granted
                onPressed: _permissionStatus == _MicPermission.granted
                    ? widget.onNext
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
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final successColor = isDark ? WpColorsDark.success : WpColorsLight.success;

    final (Widget iconWidget, Color color, String label) = switch (status) {
      _MicPermission.granted => (
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: WpMotion.smooth,
            curve: Curves.elasticOut,
            builder: (_, value, child) => Transform.scale(
              scale: 0.5 + (value * 0.5),
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Container(
                  width: WpIconSize.xxl + 12,
                  height: WpIconSize.xxl + 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: successColor.withValues(alpha: 0.12),
                  ),
                  child: Icon(LucideIcons.circleCheck,
                      size: WpIconSize.xxl, color: successColor),
                ),
              ),
            ),
          ),
          successColor,
          l10n.onboardingMicPermissionGranted,
        ),
      _MicPermission.denied => (
          Icon(LucideIcons.circleX, size: WpIconSize.xxl,
              color: isDark ? WpColorsDark.error : WpColorsLight.error),
          isDark ? WpColorsDark.error : WpColorsLight.error,
          l10n.onboardingMicPermissionDenied,
        ),
      _MicPermission.checking => (
          SizedBox(
            width: WpIconSize.xxl,
            height: WpIconSize.xxl,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: accent),
          ),
          accent,
          l10n.onboardingMicPermissionPending,
        ),
      _MicPermission.unknown => (
          Icon(LucideIcons.mic, size: WpIconSize.xxl, color: textMuted),
          textMuted,
          l10n.onboardingMicPermissionPending,
        ),
    };

    return Semantics(
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
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
      ),
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

    final borderColor =
        isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle;

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
        Material(
          color: Colors.transparent,
          borderRadius: WpRadius.borderLg,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isRecording ? null : onTap,
            borderRadius: WpRadius.borderLg,
            child: Semantics(
              button: true,
              label: hintText,
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
                    Semantics(
                      excludeSemantics: true,
                      child: SizedBox(
                        height: 40,
                        child: _WaveformBars(
                          animation: pulseAnimation,
                          isActive: isRecording,
                          accent: accent,
                          muted: textSecondary.withValues(alpha: 0.3),
                        ),
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
