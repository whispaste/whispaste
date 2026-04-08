import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/brand_logo.dart';
import '../../../widgets/brand_wordmark.dart';
import '../../../widgets/wp_accent_button.dart';

/// Onboarding Step 1 — Welcome screen with language & theme selection.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final surfaceVariant =
        isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Brand logo
        const WpBrandLogo(size: 64, withBackground: true),
        const SizedBox(height: WpSpacing.md),

        // Brand wordmark
        const WpBrandWordmark(height: 36),
        const SizedBox(height: WpSpacing.xl),

        // Tagline
        Text(
          l10n.onboardingWelcomeHint,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Language selector
        Text(
          l10n.onboardingLanguageTitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PillButton(
              label: 'English 🇬🇧',
              isActive: settings.locale == 'en',
              accent: accent,
              surfaceVariant: surfaceVariant,
              textSecondary: textSecondary,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(locale: 'en')),
            ),
            const SizedBox(width: WpSpacing.sm),
            _PillButton(
              label: 'Deutsch 🇩🇪',
              isActive: settings.locale == 'de',
              accent: accent,
              surfaceVariant: surfaceVariant,
              textSecondary: textSecondary,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(locale: 'de')),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingLanguageSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.lg),
        Text(
          l10n.onboardingThemeTitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PillButton(
              label: '☀️ ${l10n.onboardingThemeLight}',
              isActive: settings.themeMode == ThemeMode.light,
              accent: accent,
              surfaceVariant: surfaceVariant,
              textSecondary: textSecondary,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(themeMode: ThemeMode.light)),
            ),
            const SizedBox(width: WpSpacing.sm),
            _PillButton(
              label: '🌙 ${l10n.onboardingThemeDark}',
              isActive: settings.themeMode == ThemeMode.dark,
              accent: accent,
              surfaceVariant: surfaceVariant,
              textSecondary: textSecondary,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(themeMode: ThemeMode.dark)),
            ),
            const SizedBox(width: WpSpacing.sm),
            _PillButton(
              label: '🖥️ ${l10n.onboardingThemeSystem}',
              isActive: settings.themeMode == ThemeMode.system,
              accent: accent,
              surfaceVariant: surfaceVariant,
              textSecondary: textSecondary,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(themeMode: ThemeMode.system)),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Get Started button
        SizedBox(
          width: double.infinity,
          child: WpAccentButton(
            label: l10n.onboardingGetStarted,
            gradient: accentGradient,
            onPressed: onNext,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pill-shaped toggle button — focusable via Material + InkWell
// ---------------------------------------------------------------------------
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.isActive,
    required this.accent,
    required this.surfaceVariant,
    required this.textSecondary,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final Color accent;
  final Color surfaceVariant;
  final Color textSecondary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: WpRadius.borderFull,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: WpRadius.borderFull,
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.lg,
              vertical: WpSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isActive ? accent : surfaceVariant,
              borderRadius: WpRadius.borderFull,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
