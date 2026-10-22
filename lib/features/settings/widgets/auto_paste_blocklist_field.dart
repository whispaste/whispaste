/// App list editor for the auto-paste block list (Text & Einfügen).
///
/// The setting stays one comma-separated string. The user never types that
/// string for normal use: they pick apps they dictated into recently, and
/// only advanced users enter an identifier by hand (inside the picker).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/data/history_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/app_profiles/app_profile.dart'
    show normalizeAppIdentifier;
import '../../../services/desktop_paste/focused_target/linux_focused_target.dart';
import '../../../services/paste/auto_paste_blocklist.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_app_row.dart';
import '../../../widgets/wp_button.dart';
import '../../history/widgets/history_helpers.dart'
    show friendlyAppNameFromIdentifier;
import '../settings_widgets.dart';
import 'wp_settings_group.dart';

/// Apps the user dictated into recently, newest first, one per app. Derived
/// from the history target apps, so the picker needs no extra storage.
final recentDictationAppsProvider = Provider<List<RecentTargetApp>>((ref) {
  final entries = ref.watch(historyEntriesProvider).value;
  if (entries == null) return const <RecentTargetApp>[];
  return recentTargetApps([
    for (final entry in entries)
      (targetApp: entry.targetApp, timestamp: entry.timestamp),
  ]);
});

/// Writes a new block-list value through the settings notifier.
void _writeBlocklist(WidgetRef ref, String value) {
  ref
      .read(settingsProvider.notifier)
      .updateSettings((s) => s.copyWith(autoPasteBlocklist: value));
}

/// Example identifiers for the current platform, shown as the manual-entry hint.
String _manualPlaceholder(L10n l10n) => switch (defaultTargetPlatform) {
  TargetPlatform.macOS => l10n.settingsAutoPasteBlocklistPlaceholderMac,
  TargetPlatform.windows => l10n.settingsAutoPasteBlocklistPlaceholderWindows,
  _ => l10n.settingsAutoPasteBlocklistPlaceholderLinux,
};

/// Stable test id fragment for an app: its normalised key.
String _idPart(String identifier) =>
    (normalizeAppIdentifier(identifier) ?? identifier).replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );

/// Identifiers never contain control characters. Line breaks are not in this
/// set: [_LineBreaksToList] turns them into list separators instead.
final TextInputFormatter _noControlCharacters =
    FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x09\x0B-\x1F\x7F]'));

/// A pasted list with line breaks becomes a comma list in the field: one entry
/// per line, trimmed, blanks dropped. Without line breaks the text is left as
/// typed.
class _LineBreaksToList extends TextInputFormatter {
  const _LineBreaksToList();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains(RegExp(r'[\r\n]'))) return newValue;
    final list = autoPasteIdentifiersFromInput(newValue.text).join(', ');
    return TextEditingValue(
      text: list,
      selection: TextSelection.collapsed(offset: list.length),
    );
  }
}

class AutoPasteBlocklistField extends ConsumerWidget {
  const AutoPasteBlocklistField({
    super.key,
    required this.settings,
    this.targetDetectionAvailable,
    this.isMacOS,
  });

  final AppSettings settings;

  /// Whether the native paste host can name the target app. Defaults to the
  /// platform capability; tests pass it explicitly per platform variant.
  final bool? targetDetectionAvailable;

  /// Overrides the macOS branch (bundle-id warning, placeholder). Defaults to
  /// the running platform; tests pass it per variant.
  final bool? isMacOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final raw = settings.behavior.autoPasteBlocklist;
    final linuxStatus = Platform.isLinux
        ? ref.watch(linuxFocusStatusProvider).value
        : null;
    final detection =
        targetDetectionAvailable ??
        autoPasteTargetDetectionAvailable(
          isLinux: Platform.isLinux,
          linuxStatus: linuxStatus,
        );
    final entries = autoPasteBlocklistEntries(raw);

    final addRow = WpSettingsRow(
      rowId: 'text-auto-paste-blocklist',
      title: l10n.settingsAutoPasteBlocklist,
      subtitle: l10n.settingsAutoPasteBlocklistSubtitle,
      trailing: WpButton(
        testId: 'settings-paste-blocklist-add',
        label: l10n.settingsPasteBlocklistAdd,
        variant: WpButtonVariant.secondary,
        icon: LucideIcons.plus,
        onPressed: () => _openPicker(context, ref),
      ),
    );

    final listed = entries.isEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(
              kSettingRowInset,
              0,
              kSettingRowInset,
              WpSpacing.sm,
            ),
            child: Semantics(
              identifier: 'settings-paste-blocklist-empty',
              child: Text(
                l10n.settingsPasteBlocklistEmpty,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: WpColors.textSecondary),
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSettingRowInset,
                  ),
                  child: WpAppRow(
                    testId: 'settings-paste-blocklist-row-${_idPart(entry)}',
                    identifier: entry,
                    name: friendlyAppNameFromIdentifier(entry),
                    trailing: IconButton(
                      key: ValueKey(
                        'settings-paste-blocklist-remove-${_idPart(entry)}',
                      ),
                      tooltip: l10n.settingsPasteBlocklistRemoveTooltip(
                        friendlyAppNameFromIdentifier(entry),
                      ),
                      icon: const Icon(LucideIcons.x, size: WpIconSize.sm),
                      onPressed: () => _writeBlocklist(
                        ref,
                        autoPasteBlocklistWithout(raw, entry),
                      ),
                    ),
                  ),
                ),
            ],
          );

    // Shown wherever the target cannot be named (AUF-1): a set list then only
    // copies. Hidden on its own once the detector reports the capability.
    final notices = [
      if (!detection)
        (
          id: 'text-auto-paste-blocklist-no-detection-hint',
          text: linuxStatus == LinuxFocusStatus.gnomeExtensionMissing
              ? l10n.settingsAutoPasteBlocklistNoDetectionHintGnome
              : l10n.settingsAutoPasteBlocklistNoDetectionHint,
        ),
      // Bundle ids are a macOS notion; Windows and Linux entries are plain names.
      if ((isMacOS ?? defaultTargetPlatform == TargetPlatform.macOS) &&
          detection &&
          autoPasteShortPrefixEntries(raw).isNotEmpty)
        (
          id: 'text-auto-paste-blocklist-short-prefix-warning',
          text: l10n.settingsAutoPasteBlocklistShortPrefixWarning,
        ),
    ];

    // Maintainer 4a+c: a blocked paste copies to the clipboard by default; this
    // switch turns that off (text then only goes to the history). Object-bound,
    // so it sits inline in this section.
    final copy = settings.behavior.copyBlockedToClipboard;
    final copyRow = WpSettingsRow(
      rowId: 'text-auto-paste-blocklist-copy',
      title: l10n.settingsAutoPasteBlocklistCopyToggle,
      subtitle: l10n.settingsAutoPasteBlocklistCopyToggleSubtitle,
      semanticToggledValue: copy,
      trailing: Semantics(
        identifier: 'text-auto-paste-blocklist-copy-toggle',
        child: settingsToggle(
          key: const Key('text-auto-paste-blocklist-copy-toggle'),
          value: copy,
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  behavior: s.behavior.copyWith(copyBlockedToClipboard: v),
                ),
              ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        addRow,
        listed,
        for (final notice in notices)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSettingRowInset,
              0,
              kSettingRowInset,
              WpSpacing.xs,
            ),
            child: Semantics(
              identifier: notice.id,
              child: Text(
                notice.text,
                key: Key(notice.id),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        copyRow,
      ],
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return showWpDialog<void>(
      context: context,
      title: l10n.settingsPasteBlocklistPickerTitle,
      content: _AutoPasteAppPicker(
        onPicked: (identifiers) {
          final current = ref.read(settingsProvider).value?.behavior;
          _writeBlocklist(
            ref,
            autoPasteBlocklistWithAll(
              current?.autoPasteBlocklist ?? '',
              identifiers,
            ),
          );
        },
      ),
      actions: [
        WpButton(
          testId: 'settings-paste-blocklist-picker-cancel',
          label: l10n.actionCancel,
          variant: WpButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Picker body: recently dictated apps first, then a manual identifier field
/// for advanced users. Picking an app writes it and closes the dialog.
class _AutoPasteAppPicker extends ConsumerStatefulWidget {
  const _AutoPasteAppPicker({required this.onPicked});

  /// Receives one identifier per entry; the manual field may give several.
  final void Function(List<String> identifiers) onPicked;

  @override
  ConsumerState<_AutoPasteAppPicker> createState() =>
      _AutoPasteAppPickerState();
}

class _AutoPasteAppPickerState extends ConsumerState<_AutoPasteAppPicker> {
  final _manual = TextEditingController();

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _pick(String identifier) {
    if (identifier.trim().isEmpty) return;
    widget.onPicked([identifier]);
    Navigator.of(context).pop();
  }

  void _addManual() {
    final identifiers = autoPasteIdentifiersFromInput(_manual.text);
    if (identifiers.isEmpty) return;
    widget.onPicked(identifiers);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final raw =
        ref.watch(settingsProvider).value?.behavior.autoPasteBlocklist ?? '';
    final recent = [
      for (final app in ref.watch(recentDictationAppsProvider))
        if (!autoPasteBlocklistContains(raw, app.identifier)) app,
    ];
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: WpColors.textSecondary,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.settingsPasteBlocklistRecentHeading, style: muted),
            const SizedBox(height: WpSpacing.xs),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: WpSpacing.sm),
                child: Text(
                  l10n.settingsPasteBlocklistPickerEmpty,
                  key: const ValueKey('settings-paste-blocklist-picker-empty'),
                  style: muted,
                ),
              )
            else
              for (final app in recent)
                Semantics(
                  label: friendlyAppNameFromIdentifier(app.identifier),
                  button: true,
                  child: WpAppRow(
                    testId:
                        'settings-paste-blocklist-picker-app-${_idPart(app.identifier)}',
                    identifier: app.identifier,
                    name: friendlyAppNameFromIdentifier(app.identifier),
                    onTap: () => _pick(app.identifier),
                  ),
                ),
            const Divider(height: WpSpacing.lg),
            Text(l10n.settingsPasteBlocklistManualHeading, style: muted),
            const SizedBox(height: WpSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    key: const ValueKey(
                      'settings-paste-blocklist-manual-field',
                    ),
                    identifier: 'settings-paste-blocklist-manual-field',
                    child: settingsTextField(
                      context: context,
                      controller: _manual,
                      hintText: _manualPlaceholder(l10n),
                      semanticLabel: l10n.settingsPasteBlocklistManualHeading,
                      onChanged: (_) => setState(() {}),
                      // More than one line on purpose: a single-line field
                      // turns line breaks into spaces before the formatter
                      // below sees them. The field still shows one line.
                      maxLines: 2,
                      // One identifier per entry: a pasted line break separates
                      // entries, tabs and other control characters are dropped.
                      inputFormatters: [
                        _noControlCharacters,
                        const _LineBreaksToList(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
                WpButton(
                  testId: 'settings-paste-blocklist-manual-add',
                  label: l10n.settingsPasteBlocklistManualAdd,
                  variant: WpButtonVariant.secondary,
                  onPressed: autoPasteIdentifiersFromInput(_manual.text).isEmpty
                      ? null
                      : _addManual,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
