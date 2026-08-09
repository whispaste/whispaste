/// Prominent "permission granted — restart to apply" banner (macOS).
///
/// Surfaces the confirmed platform quirk where a running process never sees
/// a freshly granted Accessibility permission (`AXIsProcessTrusted()` /
/// `CGPreflightPostEventAccess()` stay stale until relaunch — macOS itself
/// offers a "Quit & Relaunch" flow for this permission type). Shown whenever
/// [PasteCapabilityNotifier.needsRestart] fires: in the settings capability
/// indicator and in the onboarding Auto-Paste step.
///
/// Deliberately styled in the accent palette, NOT the error/warning palette:
/// the user already did everything right — this is the last step of a
/// succeeding flow, not a failure. The accent framing also keeps it visually
/// distinct from the red/amber "not yet allowed" first-contact state.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/platform/macos_lifecycle_channel.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';

class WpPasteCapabilityRestartBanner extends StatelessWidget {
  const WpPasteCapabilityRestartBanner({super.key, this.onRestart});

  /// Tap handler for the restart button. Defaults to
  /// [MacOSLifecycleChannel.restart]; injectable for widget tests.
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final fill = isDark
        ? WpColorsDark.accentButtonFill
        : WpColorsLight.accentButtonFill;
    final border = isDark
        ? WpColorsDark.accentBorder20
        : WpColorsLight.accentBorder20;
    final badgeFill = isDark
        ? WpColorsDark.accentChipFill
        : WpColorsLight.accentChipFill;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: badgeFill,
                  borderRadius: WpRadius.borderSm,
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.rotateCw,
                    size: WpIconSize.sm,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.pasteCapabilityRestartTitle,
                      style: TextStyle(
                        fontSize: WpTypography.subheading,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: WpSpacing.xxs),
                    Text(
                      l10n.pasteCapabilityRestartBody,
                      style: TextStyle(
                        fontSize: WpTypography.small,
                        color: textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.sm),
          WpButton(
            label: l10n.pasteCapabilityRestartButton,
            variant: WpButtonVariant.primary,
            icon: LucideIcons.rotateCw,
            onPressed: onRestart ?? MacOSLifecycleChannel.restart,
          ),
        ],
      ),
    );
  }
}
