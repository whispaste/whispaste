import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/brand_wordmark.dart';
import '../../../widgets/language_selector.dart';

/// Welcome content of onboarding page 1 — wordmark, three demo beats and the
/// language selection.
///
/// The language choice acts immediately on the whole UI and pre-seeds the
/// recognition language (and thus the engine recommendation on page 3) —
/// existing behaviour, unchanged. The theme choice deliberately does NOT
/// live here anymore: it moved to page 3, because the pre-rendered demo
/// loops cannot follow a live theme switch (see the extracted
/// `WpSegmentedSelector` in `lib/widgets/wp_segmented_selector.dart`, which
/// page 3 reuses for it). Content only — navigation (Back/Next) is owned by
/// the onboarding shell, so this widget renders no CTA of its own.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

    void selectLocale(String locale) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(locale: locale));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const WpBrandWordmark(height: 40),
        const SizedBox(height: WpSpacing.md),

        // Headline — the brand claim. The old subtitle was dropped on
        // purpose: its message is exactly what the three beat captions below
        // say, and page 1 must fit 1100×720 without scrolling.
        Text(
          l10n.onboardingWelcome,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.headline,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.md),

        // Three demo beats, side by side. Captions are rendered by Flutter
        // (l10n, incl. RTL) — never baked into the artwork.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DemoBeat(
                icon: LucideIcons.audioLines,
                title: l10n.onboardingBeat1Title,
                caption: l10n.onboardingBeat1Caption,
              ),
            ),
            const SizedBox(width: WpSpacing.md),
            Expanded(
              child: _DemoBeat(
                icon: LucideIcons.cpu,
                title: l10n.onboardingBeat2Title,
                caption: l10n.onboardingBeat2Caption,
              ),
            ),
            const SizedBox(width: WpSpacing.md),
            Expanded(
              child: _DemoBeat(
                icon: LucideIcons.appWindow,
                title: l10n.onboardingBeat3Title,
                caption: l10n.onboardingBeat3Caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: WpSpacing.lg),

        // Language selector — items derived from L10n.supportedLocales so
        // adding a new language is an ARB-only change.  Rendered as a
        // compact dropdown without flag icons (see widget docs).
        LanguageSelector(
          currentLocale: settings.locale,
          onChanged: selectLocale,
        ),
      ],
    );
  }
}

// =============================================================================
// Demo beat — placeholder card until the pre-rendered loops land.
// =============================================================================

/// One demo beat: media area on top, Flutter-rendered title + caption below.
///
/// The media area is currently a placeholder (icon on a soft surface). The
/// asset-production ticket swaps ONLY the [_BeatMediaPlaceholder] for a
/// pre-rendered animated loop (`Image.asset`, animated WebP/GIF in a
/// light/dark variant) — the card structure, the l10n captions and the
/// reduced-motion seam below stay as they are:
/// `MediaQuery.of(context).disableAnimations` (already consulted through
/// [WpMotion.durationFor] for the fade-in) is the switch that must then show
/// a still frame instead of the loop.
class _DemoBeat extends StatelessWidget {
  const _DemoBeat({
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    // Gentle fade-in instead of a hard pop. With "Reduce Motion" active,
    // WpMotion.durationFor collapses the duration to zero — the beat appears
    // instantly, exactly like the future loop will fall back to a still.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WpMotion.durationFor(context, WpMotion.smooth),
      curve: WpMotion.smooth_,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Column(
        children: [
          _BeatMediaPlaceholder(icon: icon),
          const SizedBox(height: WpSpacing.xs),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WpTypography.subheading,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder media surface — replaced 1:1 by the pre-rendered loop asset.
class _BeatMediaPlaceholder extends StatelessWidget {
  const _BeatMediaPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return AspectRatio(
      aspectRatio: 21 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: border),
        ),
        child: Center(
          child: Icon(
            icon,
            size: WpIconSize.xl,
            color: accent.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
