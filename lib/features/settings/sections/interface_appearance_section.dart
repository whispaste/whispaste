/// Appearance settings card (WP-23b, spec 07-settings-ia §3 "Darstellung"):
/// the mode picker, dock utilisation and the clipboard side panel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../settings_widgets.dart';
import '../widgets/wp_appearance_picker.dart';
import '../widgets/wp_settings_group.dart';

class InterfaceAppearanceSection extends ConsumerWidget {
  const InterfaceAppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final iface = settings.interface_;

    return WpSettingsGroup(
      heading: l10n.settingsAppearance,
      children: [
        SettingsRowFrame(
          rowId: 'appearance-mode',
          child: KeyedSubtree(
            key: const ValueKey('settings-appearance'),
            child: WpAppearancePicker(
              mode: iface.appearance,
              platformBrightness: MediaQuery.platformBrightnessOf(context),
              onChanged: (mode) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      interface_: s.interface_.copyWith(appearance: mode),
                    ),
                  ),
            ),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-backend-utilization',
          title: l10n.settingsShowBackendUtilization,
          subtitle: l10n.settingsShowBackendUtilizationSubtitle,
          semanticToggledValue: iface.showBackendUtilization,
          trailing: settingsToggle(
            value: iface.showBackendUtilization,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    interface_: s.interface_.copyWith(
                      showBackendUtilization: v,
                    ),
                  ),
                ),
          ),
        ),
        WpSettingsRow(
          rowId: 'appearance-side-panel',
          title: l10n.settingsSidePanelEnabled,
          subtitle: l10n.settingsSidePanelEnabledSubtitle,
          semanticToggledValue: iface.sidePanelEnabled,
          trailing: settingsToggle(
            value: iface.sidePanelEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    interface_: s.interface_.copyWith(sidePanelEnabled: v),
                  ),
                ),
          ),
        ),
        if (iface.sidePanelEnabled)
          WpSettingsRow(
            rowId: 'appearance-side-panel-edge',
            title: l10n.settingsSidePanelEdge,
            subtitle: l10n.settingsSidePanelEdgeSubtitle,
            trailing: settingsDropdown(
              context: context,
              value: iface.sidePanelEdge.value,
              items: const ['left', 'right'],
              labels: [
                l10n.settingsSidePanelEdgeLeft,
                l10n.settingsSidePanelEdgeRight,
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      interface_: s.interface_.copyWith(
                        sidePanelEdge: SidePanelEdge.fromValue(v),
                      ),
                    ),
                  ),
            ),
          ),
      ],
    );
  }
}
