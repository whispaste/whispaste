/// Interface settings section (theme, language, startup, etc.).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

class InterfaceSection extends ConsumerWidget {
  const InterfaceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

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
                ref.read(settingsProvider.notifier).updateSettings(
                  (s) => s.copyWith(themeMode: mode),
                );
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.globe,
            label: l10n.settingsLanguage,
            trailing: settingsDropdown(
              context: context,
              value: settings.locale == 'de' ? 'de' : 'en',
              items: const ['en', 'de'],
              labels: [
                l10n.settingsLanguageEnglish,
                l10n.settingsLanguageGerman,
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).updateSettings(
                    (s) => s.copyWith(locale: v),
                  );
                }
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.power,
            label: l10n.settingsLaunchAtStartup,
            trailing: settingsToggle(
              value: settings.launchAtStartup,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(launchAtStartup: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.bell,
            label: l10n.settingsShowNotifications,
            trailing: settingsToggle(
              value: settings.showNotifications,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(showNotifications: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.panelBottomClose,
            label: l10n.settingsCloseToTray,
            subtitle: l10n.settingsCloseToTraySubtitle,
            trailing: settingsToggle(
              value: settings.closeToTray,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(closeToTray: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.refreshCw,
            label: l10n.settingsCheckUpdates,
            subtitle: l10n.settingsCheckUpdatesSubtitle,
            trailing: settingsToggle(
              value: settings.checkUpdates,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(checkUpdates: v)),
            ),
          ),
        ],
      ),
    );
  }
}
