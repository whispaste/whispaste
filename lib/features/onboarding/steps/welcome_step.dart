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

/// Onboarding Step 1 — clean welcome with language & theme selection.
///
/// Single centered column: wordmark, headline, subtitle, two segmented
/// selectors (language + theme), and a CTA. Nothing else.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final borderColor =
        isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final surfaceVariant = (isDark
            ? WpColorsDark.surfaceVariant
            : WpColorsLight.surfaceVariant)
        .withValues(alpha: 0.55);

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const WpBrandWordmark(height: 40),
        const SizedBox(height: WpSpacing.xl),

        // Headline
        Text(
          l10n.onboardingWelcome,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            height: 1.12,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),

        // Subtitle
        Text(
          l10n.onboardingWelcomeHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: textSecondary, height: 1.5),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Language toggle — flag thumb slides between EN/DE
        _LanguageToggle(
          locale: settings.locale,
          onChanged: selectLocale,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          surfaceColor: surfaceVariant,
          borderColor: borderColor,
        ),
        const SizedBox(height: WpSpacing.lg),

        // Theme selector
        _SegmentedSelector(
          items: [
            _SegmentItem(
              icon: const Icon(LucideIcons.sun),
              label: l10n.onboardingThemeLight,
              isActive: settings.themeMode == ThemeMode.light,
              onTap: () => selectThemeMode(ThemeMode.light),
            ),
            _SegmentItem(
              icon: const Icon(LucideIcons.moon),
              label: l10n.onboardingThemeDark,
              isActive: settings.themeMode == ThemeMode.dark,
              onTap: () => selectThemeMode(ThemeMode.dark),
            ),
            _SegmentItem(
              icon: const Icon(LucideIcons.monitor),
              label: l10n.onboardingThemeSystem,
              isActive: settings.themeMode == ThemeMode.system,
              onTap: () => selectThemeMode(ThemeMode.system),
            ),
          ],
          activeGradient: accentGradient,
          borderColor: borderColor,
          surfaceColor: surfaceVariant,
          textSecondary: textSecondary,
          height: 48,
        ),
        const SizedBox(height: WpSpacing.xxl),

        // CTA
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

// =============================================================================
// Segmented selector — animated pill indicator shared by language & theme.
// =============================================================================

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

// =============================================================================
// Language toggle — circular flag thumb that slides between EN and DE.
// Inspired by flag-thumb toggle references: a pill track with a sliding
// circular flag indicator and flanking language labels.
// =============================================================================

class _LanguageToggle extends StatefulWidget {
  const _LanguageToggle({
    required this.locale,
    required this.onChanged,
    required this.textPrimary,
    required this.textSecondary,
    required this.surfaceColor,
    required this.borderColor,
  });

  final String locale;
  final ValueChanged<String> onChanged;
  final Color textPrimary;
  final Color textSecondary;
  final Color surfaceColor;
  final Color borderColor;

  @override
  State<_LanguageToggle> createState() => _LanguageToggleState();
}

class _LanguageToggleState extends State<_LanguageToggle> {
  bool _trackHovered = false;

  static const double _trackW = 104;
  static const double _trackH = 50;
  static const double _thumb = 40;
  static const double _pad = 5;

  @override
  Widget build(BuildContext context) {
    final isEn = widget.locale == 'en';

    return Semantics(
      label: 'Language',
      value: isEn ? 'English' : 'Deutsch',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // English label
          _LangLabel(
            text: 'English',
            isActive: isEn,
            textPrimary: widget.textPrimary,
            textSecondary: widget.textSecondary,
            onTap: () => widget.onChanged('en'),
          ),
          const SizedBox(width: WpSpacing.md),

          // Toggle track with sliding flag thumb
          MouseRegion(
            onEnter: (_) => setState(() => _trackHovered = true),
            onExit: (_) => setState(() => _trackHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => widget.onChanged(isEn ? 'de' : 'en'),
              child: AnimatedContainer(
                duration: WpMotion.fast,
                width: _trackW,
                height: _trackH,
                decoration: BoxDecoration(
                  color: _trackHovered
                      ? widget.surfaceColor.withValues(alpha: 0.75)
                      : widget.surfaceColor,
                  borderRadius: WpRadius.borderFull,
                  border: Border.all(color: widget.borderColor),
                  boxShadow: WpShadows.glassInner,
                ),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: WpMotion.smooth,
                      curve: Curves.easeOutCubic,
                      left: isEn ? _pad : (_trackW - _thumb - _pad),
                      top: _pad,
                      child: Container(
                        width: _thumb,
                        height: _thumb,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: WpShadows.card,
                        ),
                        child: ClipOval(
                          child: ExcludeSemantics(
                            child: AnimatedSwitcher(
                              duration: WpMotion.fast,
                              child: SvgPicture.asset(
                                isEn
                                    ? 'assets/flags/us.svg'
                                    : 'assets/flags/de.svg',
                                key: ValueKey(widget.locale),
                                width: _thumb,
                                height: _thumb,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.md),

          // Deutsch label
          _LangLabel(
            text: 'Deutsch',
            isActive: !isEn,
            textPrimary: widget.textPrimary,
            textSecondary: widget.textSecondary,
            onTap: () => widget.onChanged('de'),
          ),
        ],
      ),
    );
  }
}

class _LangLabel extends StatefulWidget {
  const _LangLabel({
    required this.text,
    required this.isActive,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  final String text;
  final bool isActive;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  @override
  State<_LangLabel> createState() => _LangLabelState();
}

class _LangLabelState extends State<_LangLabel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: WpMotion.fast,
          style: TextStyle(
            fontSize: 15,
            fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w500,
            color: widget.isActive
                ? widget.textPrimary
                : (_hovered
                    ? widget.textPrimary.withValues(alpha: 0.7)
                    : widget.textSecondary),
          ),
          child: Text(widget.text),
        ),
      ),
    );
  }
}