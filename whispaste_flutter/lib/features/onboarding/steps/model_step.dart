import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/model_download_card.dart';

/// Onboarding Step 3 — STT model selection & download.
///
/// Embeds the existing [SttModelManager] widget which handles model listing,
/// downloading, progress display, and deletion. Provides a cloud-provider
/// escape hatch for users who prefer not to download a local model.
class ModelStep extends ConsumerWidget {
  const ModelStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Text(
          l10n.onboardingModelTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),

        // Subtitle
        Text(
          l10n.onboardingModelSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.xl),

        // Model download manager — constrain height to avoid unbounded layout
        const SizedBox(
          height: 260,
          child: SingleChildScrollView(
            child: SttModelManager(),
          ),
        ),
        const SizedBox(height: WpSpacing.sm),

        // Hint: can change later
        Text(
          l10n.onboardingModelChangeLater,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: textMuted),
        ),
        const SizedBox(height: WpSpacing.xxs),

        // Cloud option link
        GestureDetector(
          onTap: onNext,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(
              l10n.onboardingModelUseCloud,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: accent,
                decoration: TextDecoration.underline,
                decorationColor: accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Navigation buttons — Back (text) + Next (filled)
        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            _NextButton(
              label: l10n.onboardingNext,
              gradient: accentGradient,
              onPressed: onNext,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Gradient-filled "Next" button — matches WelcomeStep CTA style
// ---------------------------------------------------------------------------
class _NextButton extends StatefulWidget {
  const _NextButton({
    required this.label,
    required this.gradient,
    required this.onPressed,
  });

  final String label;
  final LinearGradient gradient;
  final VoidCallback onPressed;

  @override
  State<_NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<_NextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _hovered ? 1.02 : 1.0,
          duration: WpMotion.fast,
          curve: WpMotion.defaultCurve,
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xl,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: WpRadius.borderMd,
            ),
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
