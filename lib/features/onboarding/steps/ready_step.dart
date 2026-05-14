import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/wp_accent_button.dart';

/// Onboarding Step 4 — Ready screen with hotkey summary and quick-start guide.
class ReadyStep extends ConsumerWidget {
  const ReadyStep({super.key, required this.onComplete, required this.onBack});

  final VoidCallback onComplete;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;

    final hotkeyKey = settings.hotkeyKey;
    final hotkeyDisplay = settings.hotkey.hotkeyKeyDisplay;
    final hotkeyModifiers = settings.hotkeyModifiers;
    final modifierLabels = hotkeyModifierLabels(hotkeyModifiers, l10n: l10n);
    final keyCapLabel = hotkeyDisplay.trim().isNotEmpty
        ? (hotkeyDisplay.length == 1
              ? hotkeyDisplay.toUpperCase()
              : hotkeyDisplay)
        : hotkeyKey;
    final formattedHotkey = formatHotkeyShortcut(
      hotkeyModifiers,
      hotkeyKey,
      l10n: l10n,
      displayOverride: hotkeyDisplay,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Text(
          l10n.onboardingReadyTitle,
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
          l10n.onboardingReadySubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Hotkey display
        Text(
          l10n.onboardingReadyCurrentHotkey,
          style: TextStyle(fontSize: 12, color: textMuted),
        ),
        const SizedBox(height: WpSpacing.sm),
        Semantics(
          label: '${l10n.onboardingReadyCurrentHotkey}: $formattedHotkey',
          child: _HotkeyKeyCaps(
            modifiers: modifierLabels,
            keyLabel: keyCapLabel,
            isDark: isDark,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              final result = await HotkeyRecorderDialog.show(
                context,
                initialKey: hotkeyKey,
                initialDisplayKey: hotkeyDisplay,
                initialModifiers: hotkeyModifiers,
              );
              if (result != null && context.mounted) {
                await ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWith(
                        hotkeyKey: result.key,
                        hotkeyKeyDisplay: result.displayKey,
                        hotkeyModifiers: result.modifiers,
                      ),
                    );
              }
            },
            borderRadius: WpRadius.borderSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xs,
              ),
              child: Text(
                l10n.onboardingReadyChangeHotkey,
                style: TextStyle(
                  fontSize: 13,
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.xl),

        // Quick start instructions
        _InstructionRow(
          number: '1.',
          text: l10n.onboardingReadyStep1,
          icon: LucideIcons.keyboard,
          accent: accent,
          textColor: textPrimary,
        ),
        const SizedBox(height: WpSpacing.md),
        _InstructionRow(
          number: '2.',
          text: l10n.onboardingReadyStep2,
          icon: LucideIcons.micOff,
          accent: accent,
          textColor: textPrimary,
        ),
        const SizedBox(height: WpSpacing.md),
        _InstructionRow(
          number: '3.',
          text: l10n.onboardingReadyStep3,
          icon: LucideIcons.clipboard,
          accent: accent,
          textColor: textPrimary,
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Navigation row
        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textMuted, fontSize: 14),
              ),
            ),
            const Spacer(),
            Expanded(
              flex: 2,
              child: WpAccentButton(
                label: l10n.onboardingStartDictating,
                gradient: accentGradient,
                onPressed: onComplete,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hotkey key caps row — modifier pills + "+" separators + primary key
// ---------------------------------------------------------------------------

class _HotkeyKeyCaps extends StatelessWidget {
  const _HotkeyKeyCaps({
    required this.modifiers,
    required this.keyLabel,
    required this.isDark,
  });

  final List<String> modifiers;
  final String keyLabel;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surfaceVariant = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

    final caps = <Widget>[];
    for (var i = 0; i < modifiers.length; i++) {
      if (i > 0) {
        caps.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
            child: Text(
              '+',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
          ),
        );
      }
      caps.add(
        _KeyCapPill(
          label: modifiers[i],
          bgColor: surfaceVariant,
          borderColor: borderColor,
          textColor: textPrimary,
        ),
      );
    }

    if (keyLabel.isNotEmpty) {
      if (caps.isNotEmpty) {
        caps.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
            child: Text(
              '+',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
          ),
        );
      }
      caps.add(
        _KeyCapPill(
          label: keyLabel,
          bgColor: surfaceVariant,
          borderColor: borderColor,
          textColor: textPrimary,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WpSpacing.xxs,
      runSpacing: WpSpacing.xs,
      children: caps,
    );
  }
}

class _KeyCapPill extends StatelessWidget {
  const _KeyCapPill({
    required this.label,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
  });

  final String label;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: 0.3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Instruction row — numbered step with icon
// ---------------------------------------------------------------------------

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({
    required this.number,
    required this.text,
    required this.icon,
    required this.accent,
    required this.textColor,
  });

  final String number;
  final String text;
  final IconData icon;
  final Color accent;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      label: '$number $text',
      child: Row(
        children: [
          Icon(icon, size: WpIconSize.md, color: accent),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              '$number $text',
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
