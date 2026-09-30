import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../../history/data/history_lock.dart';
import '../../history/widgets/history_pin_dialogs.dart';
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

    final history = settings.history;
    final hasPin = history.historyPin.isNotEmpty;
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
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.clock,
            label: l10n.settingsHistoryRetentionPreset,
            trailing: settingsDropdown(
              context: context,
              value: currentPreset.name,
              items: presetItems.map((p) => p.name).toList(),
              labels: presetItems.map(labelFor).toList(),
              onChanged: (v) {
                if (v == null || v == HistoryRetentionPreset.custom.name) {
                  return;
                }
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
          SettingRow(
            icon: LucideIcons.eyeOff,
            label: l10n.settingsHistoryHideOnOpen,
            subtitle: l10n.settingsHistoryHideOnOpenSubtitle,
            semanticToggledValue: history.historyHideOnOpen,
            trailing: settingsToggle(
              value: history.historyHideOnOpen,
              onChanged: (v) => _setHideOnOpen(context, ref, v),
            ),
          ),
          if (history.historyHideOnOpen || hasPin) ...[
            SettingRow(
              icon: LucideIcons.lock,
              label: l10n.settingsHistoryPin,
              subtitle: l10n.settingsHistoryPinSubtitle,
              trailing: hasPin
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WpButton(
                          label: l10n.settingsHistoryPinChange,
                          variant: WpButtonVariant.secondary,
                          onPressed: () => _changePin(context, ref),
                        ),
                        const SizedBox(width: WpSpacing.sm),
                        WpButton(
                          label: l10n.settingsHistoryPinRemove,
                          variant: WpButtonVariant.secondary,
                          tone: WpButtonTone.danger,
                          onPressed: () => _removePin(context, ref),
                        ),
                      ],
                    )
                  : WpButton(
                      label: l10n.historyPinSetTitle,
                      variant: WpButtonVariant.secondary,
                      onPressed: () => _setPin(context, ref),
                    ),
            ),
            SettingRow(
              icon: LucideIcons.timer,
              label: l10n.settingsHistoryAutoLock,
              subtitle: l10n.settingsHistoryAutoLockSubtitle,
              trailing: settingsDropdown(
                context: context,
                value: '${history.historyAutoLockMinutes}',
                items: [for (final m in _autoLockChoices(history)) '$m'],
                labels: [
                  for (final m in _autoLockChoices(history))
                    m == 0
                        ? l10n.settingsHistoryAutoLockNever
                        : l10n.settingsHistoryAutoLockMinutes(m),
                ],
                onChanged: (v) {
                  final minutes = int.tryParse(v ?? '');
                  if (minutes == null) return;
                  _updateHistory(
                    ref,
                    (h) => h.copyWith(historyAutoLockMinutes: minutes),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _kAutoLockMinutes = [0, 1, 5, 15, 30, 60];

  /// The offered auto-lock choices, plus a stored value outside them (e.g.
  /// from an imported file) so the dropdown always has its current value.
  static List<int> _autoLockChoices(HistorySettings history) => [
    ..._kAutoLockMinutes,
    if (!_kAutoLockMinutes.contains(history.historyAutoLockMinutes))
      history.historyAutoLockMinutes,
  ];

  static Future<void> _updateHistory(
    WidgetRef ref,
    HistorySettings Function(HistorySettings) f,
  ) => ref
      .read(settingsProvider.notifier)
      .updateSettings((s) => s.copyWithSections(history: f(s.history)));

  /// Switching the gate off while a PIN is set needs that PIN and drops it —
  /// a PIN without its gate would protect nothing on the History page.
  static Future<void> _setHideOnOpen(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final hasPin =
        ref.read(settingsProvider).value?.history.historyPin.isNotEmpty ??
        false;
    if (!value && hasPin) {
      if (!await showHistoryPinUnlockDialog(context)) return;
      await ref.read(historyRevealedProvider.notifier).removePin();
    }
    await _updateHistory(ref, (h) => h.copyWith(historyHideOnOpen: value));
  }

  static Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final pin = await showHistoryPinSetDialog(context);
    if (pin == null) return;
    await ref.read(historyRevealedProvider.notifier).setPin(pin);
  }

  static Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    if (!await showHistoryPinUnlockDialog(context)) return;
    if (!context.mounted) return;
    await _setPin(context, ref);
  }

  static Future<void> _removePin(BuildContext context, WidgetRef ref) async {
    if (!await showHistoryPinUnlockDialog(context)) return;
    await ref.read(historyRevealedProvider.notifier).removePin();
  }
}
