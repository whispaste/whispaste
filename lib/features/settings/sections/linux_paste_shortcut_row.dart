/// Linux only (V1 Wayland): the "always Ctrl+Shift+V" switch with a status
/// line that says whether WhisPaste can tell terminals apart on this
/// desktop. Sits under the paste capability indicator, since it changes how
/// Auto-Paste presses the shortcut.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/desktop_paste/focused_target/linux_focused_target.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';
import 'linux_input_setup.dart';

/// Whether the row belongs on this host. A provider rather than a
/// `Platform.isLinux` check at the call site, so settings tests that render
/// as macOS can still place and reach the row.
final linuxPasteShortcutRowShownProvider = Provider<bool>(
  (ref) => Platform.isLinux,
);

class LinuxPasteShortcutRow extends ConsumerWidget {
  const LinuxPasteShortcutRow({super.key, required this.settings, this.status});

  final AppSettings settings;

  /// Overrides the probed session status (tests).
  final LinuxFocusStatus? status;

  static String statusText(L10n l10n, LinuxFocusStatus status) =>
      switch (status) {
        LinuxFocusStatus.available => l10n.settingsLinuxTargetStatusAvailable,
        LinuxFocusStatus.gnomeExtensionMissing =>
          l10n.settingsLinuxTargetStatusGnome,
        LinuxFocusStatus.unsupported =>
          l10n.settingsLinuxTargetStatusUnsupported,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final value = settings.behavior.linuxAlwaysShiftPaste;
    final current = status ?? ref.watch(linuxFocusStatusProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WpSettingsRow(
          rowId: 'text-linux-always-shift-paste',
          title: l10n.settingsLinuxAlwaysShiftPaste,
          subtitle: l10n.settingsLinuxAlwaysShiftPasteSubtitle,
          semanticToggledValue: value,
          trailing: Semantics(
            identifier: 'text-linux-always-shift-paste-toggle',
            child: settingsToggle(
              key: const Key('text-linux-always-shift-paste-toggle'),
              value: value,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      behavior: s.behavior.copyWith(linuxAlwaysShiftPaste: v),
                    ),
                  ),
            ),
          ),
        ),
        if (current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSettingRowInset,
              0,
              kSettingRowInset,
              WpSpacing.xs,
            ),
            child: Semantics(
              identifier: 'text-linux-target-status',
              child: Text(
                statusText(l10n, current),
                key: const Key('text-linux-target-status'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            kSettingRowInset,
            0,
            kSettingRowInset,
            WpSpacing.sm,
          ),
          child: LinuxInputSetup(idPrefix: 'text'),
        ),
      ],
    );
  }
}
