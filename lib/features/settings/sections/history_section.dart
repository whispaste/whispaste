import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Retention preset — maps the two raw fields to a named UX preset.
// ---------------------------------------------------------------------------

enum HistoryRetentionPreset { minimal, standard, unlimited, custom }

/// Derives the current retention preset from the stored field values.
///
/// Preset mappings (maxEntries, autoTrashDays):
/// - minimal:   100, 30
/// - standard: 1000, 90
/// - unlimited:   0,  0 (unlimited entries, never auto-trash)
/// - custom:   anything else
HistoryRetentionPreset resolveRetentionPreset(
  int maxEntries,
  int autoTrashDays,
) {
  if (maxEntries == 100 && autoTrashDays == 30) {
    return HistoryRetentionPreset.minimal;
  }
  if (maxEntries == 1000 && autoTrashDays == 90) {
    return HistoryRetentionPreset.standard;
  }
  if (maxEntries == 0 && autoTrashDays == 0) {
    return HistoryRetentionPreset.unlimited;
  }
  return HistoryRetentionPreset.custom;
}

/// Returns the (maxEntries, autoTrashDays) pair for a named preset.
/// Returns null for [HistoryRetentionPreset.custom] — no-op.
(int, int)? presetValues(HistoryRetentionPreset preset) => switch (preset) {
  HistoryRetentionPreset.minimal => (100, 30),
  HistoryRetentionPreset.standard => (1000, 90),
  HistoryRetentionPreset.unlimited => (0, 0),
  HistoryRetentionPreset.custom => null,
};

// ---------------------------------------------------------------------------

class HistorySection extends ConsumerWidget {
  const HistorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final l10n = L10n.of(context);

    final maxEntries = settings.history.historyMaxEntries;
    final autoTrashDays = settings.history.historyAutoTrashDays;
    final currentPreset = resolveRetentionPreset(maxEntries, autoTrashDays);

    String labelFor(HistoryRetentionPreset p) => switch (p) {
      HistoryRetentionPreset.minimal => l10n.settingsHistoryPresetMinimal,
      HistoryRetentionPreset.standard => l10n.settingsHistoryPresetStandard,
      HistoryRetentionPreset.unlimited => l10n.settingsHistoryPresetUnlimited,
      HistoryRetentionPreset.custom => l10n.settingsHistoryPresetCustom,
    };

    // 'custom' is only included when the stored combo matches no named preset,
    // so it is always the current selection in that case and users can never
    // navigate TO it — they can only navigate AWAY by picking a real preset.
    final presetItems = [
      HistoryRetentionPreset.minimal,
      HistoryRetentionPreset.standard,
      HistoryRetentionPreset.unlimited,
      if (currentPreset == HistoryRetentionPreset.custom)
        HistoryRetentionPreset.custom,
    ];

    return WpSection(
      title: l10n.settingsHistory,
      subtitle: l10n.settingsHistorySubtitle,
      padding: EdgeInsets.zero,
      child: SettingRow(
        icon: LucideIcons.clock,
        label: l10n.settingsHistoryRetentionPreset,
        trailing: settingsDropdown(
          context: context,
          value: currentPreset.name,
          items: presetItems.map((p) => p.name).toList(),
          labels: presetItems.map(labelFor).toList(),
          onChanged: (v) {
            if (v == null || v == HistoryRetentionPreset.custom.name) return;
            final preset = HistoryRetentionPreset.values.firstWhere(
              (p) => p.name == v,
            );
            final vals = presetValues(preset);
            if (vals == null) return;
            final (maxE, trashD) = vals;
            ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    history: s.history.copyWith(
                      historyMaxEntries: maxE,
                      historyAutoTrashDays: trashD,
                    ),
                  ),
                );
          },
        ),
      ),
    );
  }
}
