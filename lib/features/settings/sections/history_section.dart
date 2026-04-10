import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

class HistorySection extends ConsumerWidget {
  const HistorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final l10n = L10n.of(context);

    const maxEntriesOptions = ['0', '100', '500', '1000', '5000'];
    const autoTrashOptions = ['0', '7', '14', '30', '90'];

    String maxEntriesLabel(String v) {
      if (v == '0') return l10n.settingsHistoryMaxEntriesUnlimited;
      return v;
    }

    String autoTrashLabel(String v) {
      if (v == '0') return l10n.settingsHistoryAutoTrashNever;
      final count = int.parse(v);
      return l10n.settingsHistoryAutoTrashDaysLabel(count);
    }

    return WpSection(
      title: l10n.settingsHistory,
      subtitle: l10n.settingsHistorySubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
          icon: LucideIcons.listOrdered,
          label: l10n.settingsHistoryMaxEntries,
          trailing: settingsDropdown(
            context: context,
            value: settings.historyMaxEntries.toString(),
            items: maxEntriesOptions,
            labels: maxEntriesOptions.map(maxEntriesLabel).toList(),
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).updateSettings(
                      (s) => s.copyWith(historyMaxEntries: int.parse(v!)),
                    ),
          ),
        ),
        SettingRow(
          icon: LucideIcons.trash2,
          label: l10n.settingsHistoryAutoTrashDays,
          trailing: settingsDropdown(
            context: context,
            value: settings.historyAutoTrashDays.toString(),
            items: autoTrashOptions,
            labels: autoTrashOptions.map(autoTrashLabel).toList(),
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).updateSettings(
                      (s) => s.copyWith(historyAutoTrashDays: int.parse(v!)),
                    ),
          ),
        ),
        ],
      ),
    );
  }
}
