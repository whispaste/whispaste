import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart';
import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio_service.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../services/app_identity/app_identity_service.dart';
import '../../history/data/history_lock.dart';
import '../../history/widgets/history_pin_dialogs.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

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

/// Whether any recording exists, in Recordings, archive or trash. Asked when
/// "Aufnahmen speichern" is switched off, so the offer to delete appears only
/// when there is something to delete.
final historyHasEntriesProvider = FutureProvider.autoDispose<bool>((ref) async {
  final db = ref.read(historyDatabaseProvider);
  final counts = await Future.wait([
    db.countActive(),
    db.countArchived(),
    db.countTrash(),
  ]);
  return counts.any((count) => count > 0);
});

/// Deletes every recording (active, archived and trashed) and the audio files
/// they own. Notes stay. A seam so the tests do not need a database.
final historyDeleteAllEntriesProvider = Provider<Future<void> Function()>((
  ref,
) {
  return () async {
    final db = ref.read(historyDatabaseProvider);
    final files = await db.deleteAllHistory();
    final audio = ref.read(audioServiceProvider.notifier);
    for (final path in files) {
      await audio.cleanupFile(path);
    }
    // The icon cache tells which apps were dictated into; it goes too.
    await ref.read(appIdentityServiceProvider).clear();
    ref.invalidate(appIdentityProvider);
    ref.invalidate(historyHasEntriesProvider);
  };
});

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

    return WpSettingsGroup(
      heading: l10n.settingsHistory,
      children: [
        WpSettingsRow(
          rowId: 'privacy-history-save',
          title: l10n.settingsHistorySave,
          subtitle: l10n.settingsHistorySaveSubtitle,
          semanticToggledValue: history.saveHistory,
          trailing: settingsToggle(
            value: history.saveHistory,
            testId: 'privacy-history-save-toggle',
            onChanged: (v) => _setSaveHistory(context, ref, v),
          ),
        ),
        if (!history.saveHistory)
          WpSettingsRow(
            rowId: 'privacy-history-delete-existing',
            title: l10n.settingsHistoryDeleteExisting,
            subtitle: l10n.settingsHistoryDeleteExistingSubtitle,
            trailing: WpButton(
              label: l10n.settingsHistoryDeleteExistingAction,
              variant: WpButtonVariant.secondary,
              tone: WpButtonTone.danger,
              onPressed: () => _confirmDeleteExisting(context, ref),
            ),
          ),
        WpSettingsRow(
          rowId: 'privacy-history-retention',
          title: l10n.settingsHistoryRetentionPreset,
          subtitle: l10n.settingsHistoryRetentionSubtitle,
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
        WpSettingsRow(
          rowId: 'privacy-history-hide-on-open',
          title: l10n.settingsHistoryHideOnOpen,
          subtitle: l10n.settingsHistoryHideOnOpenSubtitle,
          semanticToggledValue: history.historyHideOnOpen,
          trailing: settingsToggle(
            value: history.historyHideOnOpen,
            onChanged: (v) => _setHideOnOpen(context, ref, v),
          ),
        ),
        if (history.historyHideOnOpen || hasPin) ...[
          WpSettingsRow(
            rowId: 'privacy-history-pin',
            title: l10n.settingsHistoryPin,
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
          WpSettingsRow(
            rowId: 'privacy-history-auto-lock',
            title: l10n.settingsHistoryAutoLock,
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
    );
  }

  /// Switching saving off keeps the recordings that exist. When there are any,
  /// the user is asked whether to delete them now; nothing is deleted silently.
  static Future<void> _setSaveHistory(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    await _updateHistory(ref, (h) => h.copyWith(saveHistory: value));
    if (value) return;
    final hasEntries = await ref.read(historyHasEntriesProvider.future);
    if (!hasEntries || !context.mounted) return;
    final l10n = L10n.of(context);
    final delete = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsHistorySaveDeleteTitle,
      message: l10n.settingsHistorySaveDeleteMessage,
      confirmLabel: l10n.settingsHistoryDeleteConfirm,
      cancelLabel: l10n.settingsHistorySaveDeleteKeep,
      destructive: true,
    );
    if (delete && context.mounted) await _deleteAll(ref);
  }

  static Future<void> _confirmDeleteExisting(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsHistoryDeleteExisting,
      message: l10n.settingsHistoryDeleteMessage,
      confirmLabel: l10n.settingsHistoryDeleteConfirm,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (confirmed && context.mounted) await _deleteAll(ref);
  }

  static Future<void> _deleteAll(WidgetRef ref) =>
      ref.read(historyDeleteAllEntriesProvider)();

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
