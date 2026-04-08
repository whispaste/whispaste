/// Overlay & Floating Button settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Overlay & Floating Button section
// ---------------------------------------------------------------------------

class OverlayButtonSection extends ConsumerWidget {
  const OverlayButtonSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

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
              value: settings.overlayMode,
              items: OverlayMode.values.map((e) => e.value).toList(),
              labels: [
                l10n.settingsOverlayModeInWindow,
                l10n.settingsOverlayModeFloating,
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
          // Overlay start position (only relevant for floating mode)
          if (settings.overlayModeType == OverlayMode.floating)
            SettingRow(
              icon: LucideIcons.mapPin,
              label: l10n.settingsOverlayStartPosition,
              subtitle: l10n.settingsOverlayStartPositionSubtitle,
              trailing: settingsDropdown(
                context: context,
                value: settings.overlayStartPosition,
                items: OverlayStartPosition.values.map((e) => e.value).toList(),
                labels: [
                  l10n.settingsOverlayStartTopCenter,
                  l10n.settingsOverlayStartBottomCenter,
                  l10n.settingsOverlayStartLastPosition,
                ],
                onChanged: (v) {
                  if (v == null) return;
                  ref
                      .read(settingsProvider.notifier)
                      .updateSettings(
                        (s) => s.copyWith(overlayStartPosition: v),
                      );
                },
              ),
            ),
          SettingRow(
            icon: LucideIcons.move,
            label: l10n.settingsShowFloatingButton,
            subtitle: l10n.settingsShowFloatingButtonSubtitle,
            trailing: settingsToggle(
              value: settings.showFloatingButton,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(showFloatingButton: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.circleDot,
            label: l10n.settingsFloatingButtonOpacity,
            subtitle: l10n.settingsFloatingButtonOpacitySubtitle,
            trailing: settingsSlider(
              context: context,
              value: settings.floatingButtonOpacity,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              valueLabel: '${(settings.floatingButtonOpacity * 100).round()}%',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(floatingButtonOpacity: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.maximize2,
            label: l10n.settingsFloatingButtonSize,
            subtitle: l10n.settingsFloatingButtonSizeSubtitle,
            trailing: settingsDropdown(
              context: context,
              value: settings.floatingButtonSize,
              items: const ['Small', 'Normal', 'Large'],
              labels: [
                l10n.settingsSizeSmall,
                l10n.settingsSizeNormal,
                l10n.settingsSizeLarge,
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(floatingButtonSize: v!)),
            ),
          ),
        ],
      ),
    );
  }
}
