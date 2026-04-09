/// Overlay settings section.
library;

import 'dart:io';

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

          // ── Native floating button (desktop only) ────────────────────
          if (Platform.isWindows) ...[
            const Divider(height: 1),
            SettingRow(
              icon: LucideIcons.circle,
              label: l10n.settingsShowFloatingButton,
              subtitle: l10n.settingsShowFloatingButtonSubtitle,
              trailing: settingsToggle(
                value: settings.showFloatingButton,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWith(showFloatingButton: v),
                    ),
              ),
            ),
            if (settings.showFloatingButton) ...[
              SettingRow(
                icon: LucideIcons.maximize2,
                label: l10n.settingsFloatingButtonSize,
                subtitle: l10n.settingsFloatingButtonSizeSubtitle,
                trailing: settingsDropdown(
                  context: context,
                  value: settings.floatingButtonSizeType.value,
                  items: FloatingButtonSize.values
                      .map((e) => e.value)
                      .toList(),
                  labels: [
                    l10n.settingsSizeSmall,
                    l10n.settingsSizeNormal,
                    l10n.settingsSizeLarge,
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWith(floatingButtonSize: v),
                        );
                  },
                ),
              ),
              SettingRow(
                icon: LucideIcons.sun,
                label: l10n.settingsFloatingButtonOpacity,
                subtitle: l10n.settingsFloatingButtonOpacitySubtitle,
                trailing: settingsSlider(
                  context: context,
                  value: settings.floatingButtonOpacity,
                  min: 0.3,
                  max: 1.0,
                  divisions: 7,
                  valueLabel:
                      '${(settings.floatingButtonOpacity * 100).round()}%',
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateSettings(
                        (s) => s.copyWith(floatingButtonOpacity: v),
                      ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
