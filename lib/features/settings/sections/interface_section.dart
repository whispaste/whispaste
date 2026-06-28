/// Interface settings section (theme, language, startup, etc.).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/language_selector.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

class InterfaceSection extends ConsumerWidget {
  const InterfaceSection({super.key});

  static final _log = AppLogger('InterfaceSection');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final channel = ref.watch(deployChannelProvider);

    return WpSection(
      title: l10n.settingsInterface,
      subtitle: l10n.settingsInterfaceSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.palette,
            label: l10n.settingsTheme,
            trailing: settingsDropdown(
              context: context,
              value: switch (settings.themeMode) {
                ThemeMode.dark => 'dark',
                ThemeMode.light => 'light',
                ThemeMode.system => 'system',
              },
              items: const ['dark', 'light', 'system'],
              labels: [
                l10n.settingsThemeDark,
                l10n.settingsThemeLight,
                l10n.settingsThemeSystem,
              ],
              onChanged: (v) {
                final mode = switch (v) {
                  'light' => ThemeMode.light,
                  'system' => ThemeMode.system,
                  _ => ThemeMode.dark,
                };
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(themeMode: mode));
                try {
                  ref.read(telemetryProvider).trackSettingChange('theme');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.globe,
            label: l10n.settingsAppLanguage,
            trailing: SizedBox(
              width: 180,
              child: LanguageSelector(
                currentLocale: settings.locale,
                onChanged: (code) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateSettings((s) => s.copyWith(locale: code));
                  try {
                    ref.read(telemetryProvider).trackSettingChange('language');
                  } catch (e) {
                    _log.debug('telemetry failed: $e');
                  }
                },
              ),
            ),
          ),
          SettingRow(
            icon: LucideIcons.power,
            label: l10n.settingsLaunchAtStartup,
            trailing: settingsDropdown(
              context: context,
              value: !settings.launchAtStartup
                  ? 'never'
                  : settings.startMinimized
                  ? 'minimized'
                  : 'normal',
              items: const ['never', 'normal', 'minimized'],
              labels: [
                l10n.settingsAutostartNever,
                l10n.settingsAutostartNormal,
                l10n.settingsAutostartMinimized,
              ],
              onChanged: (v) {
                final (launch, minimized) = switch (v) {
                  'normal' => (true, false),
                  'minimized' => (true, true),
                  _ => (false, false),
                };
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      // Compatibility write until legacy autostart fields are
                      // removed from AppSettings.copyWith.
                      // ignore: deprecated_member_use
                      (s) => s.copyWith(
                        launchAtStartup: launch,
                        startMinimized: minimized,
                      ),
                    );
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.bell,
            label: l10n.settingsShowNotifications,
            semanticToggledValue: settings.showNotifications,
            trailing: settingsToggle(
              value: settings.showNotifications,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(showNotifications: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.panelBottomClose,
            label: l10n.settingsCloseToTray,
            subtitle: l10n.settingsCloseToTraySubtitle,
            semanticToggledValue: settings.closeToTray,
            trailing: settingsToggle(
              value: settings.closeToTray,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(closeToTray: v)),
            ),
          ),
          if (channel != DeployChannel.store)
            SettingRow(
              icon: LucideIcons.refreshCw,
              label: l10n.settingsCheckUpdates,
              subtitle: l10n.settingsCheckUpdatesSubtitle,
              semanticToggledValue: settings.checkUpdates,
              trailing: settingsToggle(
                value: settings.checkUpdates,
                onChanged: (v) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateSettings((s) => s.copyWith(checkUpdates: v));
                  try {
                    ref
                        .read(telemetryProvider)
                        .trackSettingChange('check_updates');
                  } catch (e) {
                    _log.debug('telemetry failed: $e');
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
