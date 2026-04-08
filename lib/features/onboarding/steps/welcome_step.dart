import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
        const WpBrandLogo(size: 80, withBackground: true),
        const SizedBox(height: WpSpacing.md),
        const WpBrandWordmark(height: 36),
        const SizedBox(height: WpSpacing.lg),

        Text(
          l10n.onboardingWelcome,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),

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
        _SegmentedSelector(
          items: [
            _SegmentItem(
              icon: const Text('EN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              label: 'English',
              isActive: settings.locale == 'en',
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(locale: 'en')),
            ),
            _SegmentItem(
              icon: const Text('DE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              label: 'Deutsch',
              isActive: settings.locale == 'de',
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(locale: 'de')),
            ),
          ],
          accent: accent,
          surfaceVariant: surfaceVariant,
          textSecondary: textSecondary,
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingLanguageSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.lg),

        // Theme selector
        Text(
          l10n.onboardingThemeTitle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        _SegmentedSelector(
          items: [
            _SegmentItem(
              icon: const Icon(LucideIcons.sun, size: 16),
              label: l10n.onboardingThemeLight,
              isActive: settings.themeMode == ThemeMode.light,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(themeMode: ThemeMode.light)),
            ),
            _SegmentItem(
              icon: const Icon(LucideIcons.moon, size: 16),
              label: l10n.onboardingThemeDark,
              isActive: settings.themeMode == ThemeMode.dark,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(themeMode: ThemeMode.dark)),
            ),
            _SegmentItem(
              icon: const Icon(LucideIcons.monitor, size: 16),
              label: l10n.onboardingThemeSystem,
              isActive: settings.themeMode == ThemeMode.system,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(themeMode: ThemeMode.system)),
            ),
          ],
          accent: accent,
          surfaceVariant: surfaceVariant,
          textSecondary: textSecondary,
        ),
        const SizedBox(height: WpSpacing.xxl),

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
// Segment item data
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Segmented selector — a row of rounded segments with icon + label
// ---------------------------------------------------------------------------

class _SegmentedSelector extends StatelessWidget {
  const _SegmentedSelector({
    required this.items,
    required this.accent,
    required this.surfaceVariant,
    required this.textSecondary,
  });

  final List<_SegmentItem> items;
  final Color accent;
  final Color surfaceVariant;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle;

    return Container(
      decoration: BoxDecoration(
        borderRadius: WpRadius.borderFull,
        border: Border.all(color: borderColor),
        color: surfaceVariant.withValues(alpha: 0.5),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            _SegmentButton(
              item: items[i],
              accent: accent,
              textSecondary: textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentButton extends StatefulWidget {
  const _SegmentButton({
    required this.item,
    required this.accent,
    required this.textSecondary,
  });

  final _SegmentItem item;
  final Color accent;
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.item.onTap,
          child: AnimatedContainer(
            duration: WpMotion.fast,
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? widget.accent
                  : _hovered
                      ? widget.textSecondary.withValues(alpha: 0.08)
                      : Colors.transparent,
              borderRadius: WpRadius.borderFull,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: isActive ? Colors.white : widget.textSecondary,
                    size: 16,
                  ),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: isActive ? Colors.white : widget.textSecondary,
                    ),
                    child: widget.item.icon,
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : widget.textSecondary,
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
