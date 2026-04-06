import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// A pill-shaped badge indicating whether processing happens locally or in the
/// cloud, derived from the current STT provider setting.
class WpPrivacyBadge extends ConsumerWidget {
  const WpPrivacyBadge({super.key, this.compact = false});

  /// When true, only shows the icon (no text label).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isLocal = settings.sttProvider == 'On Device (Private)';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final color = isLocal
        ? (isDark ? WpColorsDark.success : WpColorsLight.success)
        : (isDark ? WpColorsDark.accent : WpColorsLight.accent);
    final icon = isLocal ? LucideIcons.shieldCheck : LucideIcons.cloud;
    final label = isLocal
        ? l10n.overlayProcessingLocal
        : l10n.overlayProcessingCloud;
    final semanticsLabel = isLocal
        ? 'Processing locally on your device'
        : 'Processing via cloud API';

    return Semantics(
      label: semanticsLabel,
      child: AnimatedSwitcher(
        duration: WpMotion.fast,
        switchInCurve: WpMotion.defaultCurve,
        switchOutCurve: WpMotion.defaultCurve,
        child: Container(
          key: ValueKey(isLocal),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? WpSpacing.xs : WpSpacing.sm,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: WpRadius.borderFull,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: WpIconSize.xs, color: color),
              if (!compact) ...[
                const SizedBox(width: WpSpacing.xxs),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
