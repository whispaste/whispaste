import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_segmented_selector.dart';

/// Widget keys exposed for testing.
@visibleForTesting
const kAppearanceThemeSelectorKey = Key('appearanceThemeSelector');
@visibleForTesting
const kAppearanceMaxDurationHintKey = Key('appearanceMaxDurationHint');

/// Appearance block of the Model & Hotkey onboarding page: the theme choice
/// (light/dark/system) plus the recording-duration side note.
///
/// The theme choice moved here from page 1 — the pre-rendered demo loops
/// there cannot follow a live theme switch. Layout follows the Conductor
/// settings-row pattern: label + short description on the leading side, the
/// control on the trailing side, no card frame. The selection writes straight
/// to [settingsProvider] and takes effect immediately; there is nothing to
/// confirm, so the step stays walkable without any input.
///
/// The duration note is purely informational (no toggle, no slider): it tells
/// the user that recordings auto-stop after
/// `BehaviorSettings.maxRecordDuration` seconds and where in Settings that
/// limit lives. When the limit is 0 ("unlimited") the note disappears — there
/// is no cutoff to warn about.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final surfaceVariant =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;

    final themeMode = settings.interface_.themeMode;
    final maxSeconds = settings.behavior.maxRecordDuration;

    void selectThemeMode(ThemeMode mode) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              interface_: s.interface_.copyWith(themeMode: mode),
            ),
          );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Theme row — label + description leading, selector trailing
        // (Conductor settings-row pattern; mirrors for free in RTL).
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.onboardingAppearanceTitle,
                    style: TextStyle(
                      fontSize: WpTypography.subheading,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  Text(
                    l10n.onboardingAppearanceDescription,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      color: textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: WpSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: WpSegmentedSelector(
                key: kAppearanceThemeSelectorKey,
                items: [
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _SegmentButton.build (wp_segmented_selector.dart)
                  WpSegmentItem(
                    icon: const Icon(LucideIcons.sun),
                    label: l10n.onboardingThemeLight,
                    isActive: themeMode == ThemeMode.light,
                    onTap: () => selectThemeMode(ThemeMode.light),
                  ),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _SegmentButton.build (wp_segmented_selector.dart)
                  WpSegmentItem(
                    icon: const Icon(LucideIcons.moon),
                    label: l10n.onboardingThemeDark,
                    isActive: themeMode == ThemeMode.dark,
                    onTap: () => selectThemeMode(ThemeMode.dark),
                  ),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _SegmentButton.build (wp_segmented_selector.dart)
                  WpSegmentItem(
                    icon: const Icon(LucideIcons.monitor),
                    label: l10n.onboardingThemeSystem,
                    isActive: themeMode == ThemeMode.system,
                    onTap: () => selectThemeMode(ThemeMode.system),
                  ),
                ],
                activeGradient: accentGradient,
                borderColor: borderColor,
                surfaceColor: surfaceVariant,
                textSecondary: textSecondary,
                height: 36,
              ),
            ),
          ],
        ),

        // Recording-duration side note — muted single line, no control.
        // Suppressed when the limit is 0 (= unlimited, nothing to warn about).
        if (maxSeconds > 0) ...[
          const SizedBox(height: WpSpacing.xs),
          Row(
            key: kAppearanceMaxDurationHintKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(LucideIcons.info, size: 14, color: textMuted),
              ),
              const SizedBox(width: WpSpacing.xs),
              Expanded(
                child: Text(
                  l10n.onboardingMaxRecordDurationHint(
                    maxSeconds,
                    l10n.settingsRecordingSafety,
                  ),
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: textMuted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
