import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/brand_wordmark.dart';
import '../../../widgets/wp_accent_button.dart';

/// Onboarding Step 1 — premium welcome scene with language & theme selection.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final cardColor = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    void selectLocale(String locale) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(locale: locale));
    }

    void selectThemeMode(ThemeMode mode) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(themeMode: mode));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final spacing = isWide ? WpSpacing.xl : WpSpacing.lg;
        final hero = _WelcomeHero(
          isDark: isDark,
          isWide: isWide,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          l10n: l10n,
        );
        final panel = _WelcomeControlPanel(
          isDark: isDark,
          isWide: isWide,
          accent: accent,
          accentGradient: accentGradient,
          borderColor: borderColor,
          cardColor: cardColor,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          settings: settings,
          l10n: l10n,
          onLocaleSelected: selectLocale,
          onThemeSelected: selectThemeMode,
          onNext: onNext,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: isWide ? Alignment.centerLeft : Alignment.center,
              child: const WpBrandWordmark(height: 56),
            ),
            const SizedBox(height: WpSpacing.xl),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: hero),
                  SizedBox(width: spacing),
                  Expanded(flex: 5, child: panel),
                ],
              )
            else
              Column(
                children: [
                  hero,
                  SizedBox(height: spacing),
                  panel,
                ],
              ),
          ],
        );
      },
    );
  }
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({
    required this.isDark,
    required this.isWide,
    required this.textPrimary,
    required this.textSecondary,
    required this.l10n,
  });

  final bool isDark;
  final bool isWide;
  final Color textPrimary;
  final Color textSecondary;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final accentSubtle = isDark
        ? WpColorsDark.accentSubtle
        : WpColorsLight.accentSubtle;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? WpColorsDark.warmSurfaceGradient
            : WpColorsLight.warmSurfaceGradient,
        borderRadius: WpRadius.borderXl,
        border: Border.all(color: borderColor),
        boxShadow: WpShadows.card,
      ),
      padding: const EdgeInsets.all(WpSpacing.xxl),
      child: Column(
        crossAxisAlignment: isWide
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: accentSubtle,
              borderRadius: WpRadius.borderFull,
            ),
            child: Text(
              l10n.onboardingWelcomeEyebrow,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          Text(
            l10n.onboardingWelcome,
            textAlign: isWide ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: isWide ? 34 : 28,
              height: 1.08,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(
            l10n.onboardingWelcomeHint,
            textAlign: isWide ? TextAlign.left : TextAlign.center,
            style: TextStyle(fontSize: 15, color: textSecondary, height: 1.55),
          ),
          const SizedBox(height: WpSpacing.lg),
          Wrap(
            alignment: isWide ? WrapAlignment.start : WrapAlignment.center,
            spacing: WpSpacing.sm,
            runSpacing: WpSpacing.sm,
            children: [
              _FeaturePill(
                isDark: isDark,
                label: l10n.onboardingWelcomeFeaturePrivate,
              ),
              _FeaturePill(
                isDark: isDark,
                label: l10n.onboardingWelcomeFeaturePaste,
              ),
              _FeaturePill(
                isDark: isDark,
                label: l10n.onboardingWelcomeFeatureFast,
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xl),
          _PreviewStage(isDark: isDark, l10n: l10n),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.isDark, required this.label});

  final bool isDark;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final bg = isDark
        ? WpColorsDark.surfaceVariant.withValues(alpha: 0.8)
        : WpColorsLight.surface.withValues(alpha: 0.95);
    final dot = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: WpRadius.borderFull,
        border: Border.all(
          color: (isDark
              ? WpColorsDark.borderSubtle
              : WpColorsLight.borderSubtle),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: dot,
              borderRadius: WpRadius.borderFull,
            ),
          ),
          const SizedBox(width: WpSpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStage extends StatelessWidget {
  const _PreviewStage({required this.isDark, required this.l10n});

  final bool isDark;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? WpColorsDark.surface : WpColorsLight.surface;
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surface.withValues(alpha: isDark ? 0.78 : 0.96),
        borderRadius: WpRadius.borderXl,
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(WpSpacing.lg),
      child: Column(
        children: [
          _PreviewCard(
            isDark: isDark,
            label: l10n.onboardingPreviewSourceLabel,
            text: l10n.onboardingPreviewSourceText,
            icon: LucideIcons.mic,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
            child: Row(
              children: [
                Expanded(child: Divider(color: borderColor, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
                  child: Icon(
                    LucideIcons.arrowDown,
                    size: WpIconSize.sm,
                    color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                  ),
                ),
                Expanded(child: Divider(color: borderColor, height: 1)),
              ],
            ),
          ),
          _PreviewCard(
            isDark: isDark,
            label: l10n.onboardingPreviewResultLabel,
            text: l10n.onboardingPreviewResultText,
            icon: LucideIcons.check,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.isDark,
    required this.label,
    required this.text,
    required this.icon,
    this.emphasized = false,
  });

  final bool isDark;
  final String label;
  final String text;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final borderColor = emphasized
        ? (isDark ? WpColorsDark.accent : WpColorsLight.accent).withValues(
            alpha: 0.28,
          )
        : (isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle);
    final bg = emphasized
        ? (isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle)
        : (isDark
              ? WpColorsDark.surfaceElevated
              : WpColorsLight.surfaceElevated);
    final primary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final secondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: emphasized
                  ? accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: WpRadius.borderMd,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: WpIconSize.sm,
              color: emphasized ? accent : secondary,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: emphasized ? accent : secondary,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxs),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                    color: primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeControlPanel extends StatelessWidget {
  const _WelcomeControlPanel({
    required this.isDark,
    required this.isWide,
    required this.accent,
    required this.accentGradient,
    required this.borderColor,
    required this.cardColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.settings,
    required this.l10n,
    required this.onLocaleSelected,
    required this.onThemeSelected,
    required this.onNext,
  });

  final bool isDark;
  final bool isWide;
  final Color accent;
  final LinearGradient accentGradient;
  final Color borderColor;
  final Color cardColor;
  final Color textPrimary;
  final Color textSecondary;
  final AppSettings settings;
  final L10n l10n;
  final ValueChanged<String> onLocaleSelected;
  final ValueChanged<ThemeMode> onThemeSelected;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: WpRadius.borderXl,
        border: Border.all(color: borderColor),
        boxShadow: WpShadows.card,
      ),
      padding: const EdgeInsets.all(WpSpacing.xl),
      child: Column(
        crossAxisAlignment: isWide
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Text(
            l10n.onboardingPersonalizeTitle,
            textAlign: isWide ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            l10n.onboardingPersonalizeHint,
            textAlign: isWide ? TextAlign.left : TextAlign.center,
            style: TextStyle(fontSize: 14, color: textSecondary, height: 1.5),
          ),
          const SizedBox(height: WpSpacing.xl),
          _PreferenceSection(
            title: l10n.onboardingLanguageTitle,
            subtitle: l10n.onboardingLanguageSubtitle,
            alignCenter: !isWide,
            child: _SegmentedSelector(
              items: [
                _SegmentItem(
                  icon: ExcludeSemantics(
                    child: ClipOval(
                      child: SvgPicture.asset(
                        'assets/flags/us.svg',
                        width: 22,
                        height: 22,
                      ),
                    ),
                  ),
                  label: 'English',
                  isActive: settings.locale == 'en',
                  onTap: () => onLocaleSelected('en'),
                ),
                _SegmentItem(
                  icon: ExcludeSemantics(
                    child: ClipOval(
                      child: SvgPicture.asset(
                        'assets/flags/de.svg',
                        width: 22,
                        height: 22,
                      ),
                    ),
                  ),
                  label: 'Deutsch',
                  isActive: settings.locale == 'de',
                  onTap: () => onLocaleSelected('de'),
                ),
              ],
              activeGradient: accentGradient,
              borderColor: borderColor,
              surfaceColor:
                  (isDark
                          ? WpColorsDark.surfaceVariant
                          : WpColorsLight.surfaceVariant)
                      .withValues(alpha: 0.55),
              textSecondary: textSecondary,
              height: 58,
            ),
          ),
          const SizedBox(height: WpSpacing.xl),
          _PreferenceSection(
            title: l10n.onboardingThemeTitle,
            subtitle: l10n.onboardingThemeSubtitle,
            alignCenter: !isWide,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ThemePreviewCard(
                        isDark: isDark,
                        icon: LucideIcons.sun,
                        label: l10n.onboardingThemeLight,
                        isActive: settings.themeMode == ThemeMode.light,
                        previewBackground: WpColorsLight.surface,
                        previewHeader: WpColorsLight.background,
                        previewAccent: WpColorsLight.accent,
                        onTap: () => onThemeSelected(ThemeMode.light),
                      ),
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    Expanded(
                      child: _ThemePreviewCard(
                        isDark: isDark,
                        icon: LucideIcons.moon,
                        label: l10n.onboardingThemeDark,
                        isActive: settings.themeMode == ThemeMode.dark,
                        previewBackground: WpColorsDark.surface,
                        previewHeader: WpColorsDark.background,
                        previewAccent: WpColorsDark.accent,
                        onTap: () => onThemeSelected(ThemeMode.dark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WpSpacing.sm),
                _SystemThemeChip(
                  isDark: isDark,
                  label: l10n.onboardingThemeSystemHint,
                  isActive: settings.themeMode == ThemeMode.system,
                  onTap: () => onThemeSelected(ThemeMode.system),
                ),
              ],
            ),
          ),
          const SizedBox(height: WpSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: WpAccentButton(
              label: l10n.onboardingGetStarted,
              gradient: accentGradient,
              onPressed: onNext,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: Text(
              l10n.onboardingPersonalizeLater,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.alignCenter,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool alignCenter;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return Column(
      crossAxisAlignment: alignCenter
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: alignCenter ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        child,
        const SizedBox(height: WpSpacing.xs),
        Text(
          subtitle,
          textAlign: alignCenter ? TextAlign.center : TextAlign.left,
          style: TextStyle(fontSize: 12, color: textSecondary, height: 1.45),
        ),
      ],
    );
  }
}

class _ThemePreviewCard extends StatefulWidget {
  const _ThemePreviewCard({
    required this.isDark,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.previewBackground,
    required this.previewHeader,
    required this.previewAccent,
    required this.onTap,
  });

  final bool isDark;
  final IconData icon;
  final String label;
  final bool isActive;
  final Color previewBackground;
  final Color previewHeader;
  final Color previewAccent;
  final VoidCallback onTap;

  @override
  State<_ThemePreviewCard> createState() => _ThemePreviewCardState();
}

class _ThemePreviewCardState extends State<_ThemePreviewCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final borderColor = widget.isActive
        ? accent.withValues(alpha: 0.28)
        : (widget.isDark
              ? WpColorsDark.borderSubtle
              : WpColorsLight.borderSubtle);
    final bg = widget.isActive
        ? (widget.isDark
              ? WpColorsDark.accentSubtle
              : WpColorsLight.accentSubtle)
        : (widget.isDark
                  ? WpColorsDark.surfaceVariant
                  : WpColorsLight.surfaceVariant)
              .withValues(alpha: _hovered ? 0.9 : 0.62);

    return Semantics(
      button: true,
      selected: widget.isActive,
      label: widget.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: WpRadius.borderLg,
          focusColor: accent.withValues(alpha: 0.18),
          onHover: (hovering) => setState(() => _hovered = hovering),
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            constraints: const BoxConstraints(minHeight: 110),
            padding: const EdgeInsets.all(WpSpacing.sm),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: WpRadius.borderLg,
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.previewBackground,
                    borderRadius: WpRadius.borderMd,
                    border: Border.all(
                      color: borderColor.withValues(alpha: 0.7),
                    ),
                  ),
                  padding: const EdgeInsets.all(WpSpacing.xs),
                  child: Column(
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.previewHeader,
                          borderRadius: WpRadius.borderSm,
                        ),
                      ),
                      const SizedBox(height: WpSpacing.xs),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: widget.previewAccent,
                              borderRadius: WpRadius.borderSm,
                            ),
                          ),
                          const SizedBox(width: WpSpacing.xs),
                          Expanded(
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: widget.previewHeader.withValues(
                                  alpha: 0.65,
                                ),
                                borderRadius: WpRadius.borderSm,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: WpSpacing.sm),
                Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: WpIconSize.sm,
                      color: widget.isActive ? accent : textSecondary,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: widget.isActive ? textPrimary : textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemThemeChip extends StatefulWidget {
  const _SystemThemeChip({
    required this.isDark,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final bool isDark;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_SystemThemeChip> createState() => _SystemThemeChipState();
}

class _SystemThemeChipState extends State<_SystemThemeChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final bg = widget.isActive
        ? (widget.isDark
              ? WpColorsDark.accentSubtle
              : WpColorsLight.accentSubtle)
        : (widget.isDark
                  ? WpColorsDark.surfaceVariant
                  : WpColorsLight.surfaceVariant)
              .withValues(alpha: _hovered ? 0.9 : 0.62);
    final borderColor = widget.isActive
        ? accent.withValues(alpha: 0.28)
        : (widget.isDark
              ? WpColorsDark.borderSubtle
              : WpColorsLight.borderSubtle);

    return Semantics(
      button: true,
      selected: widget.isActive,
      label: widget.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: WpRadius.borderFull,
          focusColor: accent.withValues(alpha: 0.18),
          onHover: (hovering) => setState(() => _hovered = hovering),
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: WpRadius.borderFull,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.monitor,
                  size: WpIconSize.sm,
                  color: widget.isActive ? accent : textSecondary,
                ),
                const SizedBox(width: WpSpacing.xs),
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.isActive ? textPrimary : textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentItem {
  const _SegmentItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
}

class _SegmentedSelector extends StatelessWidget {
  const _SegmentedSelector({
    required this.items,
    required this.activeGradient,
    required this.borderColor,
    required this.surfaceColor,
    required this.textSecondary,
    this.height = 48,
  });

  final List<_SegmentItem> items;
  final LinearGradient activeGradient;
  final Color borderColor;
  final Color surfaceColor;
  final Color textSecondary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final activeIndex = items.indexWhere((item) => item.isActive);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final itemWidth = totalWidth / items.length;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: WpRadius.borderFull,
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: WpMotion.normal,
                curve: Curves.easeOutCubic,
                left: activeIndex >= 0 ? activeIndex * itemWidth + 4 : 4,
                top: 4,
                bottom: 4,
                width: itemWidth - 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: activeGradient,
                    borderRadius: WpRadius.borderFull,
                    boxShadow: WpShadows.subtle,
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: _SegmentButton(
                        item: item,
                        textSecondary: textSecondary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({required this.item, required this.textSecondary});

  final _SegmentItem item;
  final Color textSecondary;

  @override
  State<_SegmentButton> createState() => _SegmentButtonState();
}

class _SegmentButtonState extends State<_SegmentButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.item.isActive;

    return Semantics(
      button: true,
      selected: isActive,
      label: widget.item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.item.onTap,
          borderRadius: WpRadius.borderFull,
          focusColor: widget.textSecondary.withValues(alpha: 0.15),
          onHover: (hovering) => setState(() => _hovered = hovering),
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            color: !isActive && _hovered
                ? widget.textSecondary.withValues(alpha: 0.08)
                : Colors.transparent,
            alignment: Alignment.center,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          color: isActive ? Colors.white : widget.textSecondary,
                          size: 18,
                        ),
                        child: DefaultTextStyle(
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : widget.textSecondary,
                          ),
                          child: widget.item.icon,
                        ),
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      AnimatedDefaultTextStyle(
                        duration: WpMotion.fast,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isActive ? Colors.white : widget.textSecondary,
                        ),
                        child: Text(widget.item.label),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
