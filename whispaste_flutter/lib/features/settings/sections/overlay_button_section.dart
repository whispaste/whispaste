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
                ref.read(settingsProvider.notifier).updateSettings(
                  (s) => s.copyWith(
                    overlayMode: v,
                    showOverlay:
                        OverlayMode.fromValue(v) != OverlayMode.off,
                  ),
                );
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.move,
            label: l10n.settingsShowFloatingButton,
            trailing: settingsToggle(
              value: settings.showFloatingButton,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(showFloatingButton: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.circleDot,
            label: l10n.settingsFloatingButtonOpacity,
            trailing: settingsSlider(
              context: context,
              value: settings.floatingButtonOpacity,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              valueLabel:
                  '${(settings.floatingButtonOpacity * 100).round()}%',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(floatingButtonOpacity: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.maximize2,
            label: l10n.settingsFloatingButtonSize,
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
                  .updateSettings(
                      (s) => s.copyWith(floatingButtonSize: v!)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Floating Button Advanced Options section
// ---------------------------------------------------------------------------

class FloatingButtonAdvancedSection extends ConsumerWidget {
  const FloatingButtonAdvancedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsFloatingButtonAdvanced,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.lock,
            label: l10n.settingsLockPosition,
            subtitle: l10n.settingsLockPositionSubtitle,
            trailing: settingsToggle(
              value: settings.floatingButtonLocked,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(floatingButtonLocked: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.eyeOff,
            label: l10n.settingsAutoHide,
            subtitle: l10n.settingsAutoHideSubtitle,
            trailing: settingsDropdown(
              context: context,
              value: settings.floatingButtonAutoHide,
              items: const ['never', 'after_5s', 'edge'],
              labels: [
                l10n.settingsAutoHideNever,
                l10n.settingsAutoHide5s,
                l10n.settingsAutoHideEdge,
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(floatingButtonAutoHide: v!)),
            ),
          ),
        ],
      ),
    );
  }
}
