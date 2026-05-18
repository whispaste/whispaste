import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_native_name.dart';
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
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final surfaceVariant =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
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

        // Language selector — items derived from L10n.supportedLocales so
        // adding a new language is an ARB-only change.
        _LanguageSelector(
          currentLocale: settings.locale,
          onChanged: selectLocale,
          activeGradient: accentGradient,
          borderColor: borderColor,
          surfaceColor: surfaceVariant,
          textSecondary: textSecondary,
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
    required this.label,
    required this.isActive,
    required this.onTap,
    this.icon,
  });

  /// Optional decorative icon rendered left of the label.  Null = text-only
  /// (used for locales that don't bundle a flag SVG).
  final Widget? icon;
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
                      if (widget.item.icon != null) ...[
                        IconTheme(
                          data: IconThemeData(
                            color: isActive
                                ? Colors.white
                                : widget.textSecondary,
                            size: 18,
                          ),
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : widget.textSecondary,
                            ),
                            child: widget.item.icon!,
                          ),
                        ),
                        const SizedBox(width: WpSpacing.xs),
                      ],
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
// Language selector — derived from L10n.supportedLocales.
// Each supported locale becomes one segment in the same `_SegmentedSelector`
// used for theme selection below.  Flags (assets/flags/<code>.svg) are
// decorative: rendered only when the asset is bundled; missing assets fall
// back to text-only labels without crashing.
// =============================================================================

class _LanguageSelector extends StatefulWidget {
  const _LanguageSelector({
    required this.currentLocale,
    required this.onChanged,
    required this.activeGradient,
    required this.borderColor,
    required this.surfaceColor,
    required this.textSecondary,
  });

  final String currentLocale;
  final ValueChanged<String> onChanged;
  final LinearGradient activeGradient;
  final Color borderColor;
  final Color surfaceColor;
  final Color textSecondary;

  @override
  State<_LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<_LanguageSelector> {
  /// Asset paths confirmed present in the bundle.  Populated asynchronously
  /// via [AssetManifest]; until it resolves, labels render text-only.
  Set<String> _bundledFlagPaths = const <String>{};

  @override
  void initState() {
    super.initState();
    _loadBundledFlags();
  }

  Future<void> _loadBundledFlags() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final available = manifest.listAssets().toSet();
      if (!mounted) return;
      setState(() {
        _bundledFlagPaths = <String>{
          for (final locale in L10n.supportedLocales)
            if (available.contains(localeFlagAssetPath(locale)))
              localeFlagAssetPath(locale),
        };
      });
    } catch (_) {
      // Manifest unavailable (e.g. some test bundles) → stay text-only.
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SegmentedSelector(
      items: [
        for (final locale in L10n.supportedLocales)
          _SegmentItem(
            label: localeNativeName(locale),
            icon: _flagIconFor(locale),
            isActive: locale.languageCode == widget.currentLocale,
            onTap: () => widget.onChanged(locale.languageCode),
          ),
      ],
      activeGradient: widget.activeGradient,
      borderColor: widget.borderColor,
      surfaceColor: widget.surfaceColor,
      textSecondary: widget.textSecondary,
      height: 48,
    );
  }

  Widget? _flagIconFor(Locale locale) {
    final path = localeFlagAssetPath(locale);
    if (!_bundledFlagPaths.contains(path)) return null;
    return ClipOval(
      child: SvgPicture.asset(path, width: 18, height: 18, fit: BoxFit.cover),
    );
  }
}
