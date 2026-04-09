/// Overlay settings section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Overlay section
// ---------------------------------------------------------------------------

class OverlayButtonSection extends ConsumerWidget {
  const OverlayButtonSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveMode = settings.effectiveOverlayMode;

    return WpSection(
      title: l10n.settingsOverlayFloatingButton,
      subtitle: l10n.settingsOverlayFloatingButtonSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.layers,
            label: l10n.settingsShowOverlay,
            subtitle: l10n.settingsShowOverlaySubtitle,
            trailing: settingsDropdown(
              context: context,
              // Display effective mode so legacy "floating" shows as "in-window"
              value: effectiveMode.value,
              items: const [OverlayMode.inWindow, OverlayMode.off]
                  .map((e) => e.value)
                  .toList(),
              labels: [
                l10n.settingsOverlayModeInWindow,
                l10n.settingsOverlayModeOff,
              ],
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWith(
                        overlayMode: v,
                        showOverlay:
                            OverlayMode.fromValue(v) != OverlayMode.off,
                      ),
                    );
              },
            ),
          ),
          // Hint for in-window mode
          if (effectiveMode == OverlayMode.inWindow)
            Padding(
              padding: const EdgeInsets.only(
                left: WpSpacing.xxl + WpSpacing.md,
                bottom: WpSpacing.sm,
              ),
              child: Text(
                l10n.settingsOverlayInWindowHint,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? WpColorsDark.textMuted
                      : WpColorsLight.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
