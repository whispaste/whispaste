import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/model_download_card.dart';
import '../../../widgets/wp_accent_button.dart';

/// Onboarding Step 3 — STT model selection & download.
///
/// Embeds the existing [SttModelManager] widget which handles model listing,
/// downloading, progress display, and deletion. Provides a cloud-provider
/// escape hatch for users who prefer not to download a local model.
class ModelStep extends StatelessWidget {
  const ModelStep({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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

        // Model download manager — use ConstrainedBox instead of fixed height
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: const SingleChildScrollView(
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

        // Cloud option link — with proper tap target and accessibility
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onNext,
            borderRadius: WpRadius.borderSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xs,
              ),
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
            SizedBox(
              width: 140,
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
