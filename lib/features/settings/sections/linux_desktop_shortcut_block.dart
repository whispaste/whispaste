/// Linux only (V1 Wayland): under the hotkey, where the desktop cannot bind
/// system-wide shortcuts for apps (no GlobalShortcuts portal). On GNOME a
/// button adds the hotkey to the GNOME keyboard shortcuts; elsewhere the
/// block shows the command to bind by hand.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/linux_desktop_shortcut.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

final _log = AppLogger('LinuxDesktopShortcutBlock');

/// The command [DesktopShortcutFallback.manual] shows. A provider so tests
/// do not depend on the test runner's own executable.
final manualToggleCommandProvider = Provider<String>(
  (ref) =>
      manualToggleCommand(Platform.environment, Platform.resolvedExecutable),
);

class LinuxDesktopShortcutBlock extends ConsumerStatefulWidget {
  const LinuxDesktopShortcutBlock({super.key, required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<LinuxDesktopShortcutBlock> createState() =>
      _LinuxDesktopShortcutBlockState();
}

class _LinuxDesktopShortcutBlockState
    extends ConsumerState<LinuxDesktopShortcutBlock> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _change({required bool add}) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final shortcut = ref.read(gnomeToggleShortcutProvider);
      if (add) {
        await shortcut.install(desktopShortcutAccelerator(widget.settings));
      } else {
        await shortcut.remove();
      }
    } on Object catch (e) {
      _log.warning('GNOME shortcut not changed', e);
      if (mounted) setState(() => _failed = true);
    } finally {
      ref.invalidate(gnomeToggleShortcutInstalledProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String command, L10n l10n) async {
    try {
      await Clipboard.setData(ClipboardData(text: command));
      if (!mounted) return;
      WpToast.show(
        context,
        message: l10n.manualCodeCopied,
        type: WpToastType.success,
      );
    } on Object catch (e) {
      _log.debug('copy failed', e);
      if (!mounted) return;
      WpToast.show(
        context,
        message: l10n.manualCodeCopyFailed,
        type: WpToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final fallback =
        ref.watch(desktopShortcutFallbackProvider).value ??
        DesktopShortcutFallback.notNeeded;
    final installed =
        ref.watch(gnomeToggleShortcutInstalledProvider).value ?? false;
    final settings = widget.settings;
    final keys = formatHotkeyKeycap(
      settings.hotkeyModifiers,
      settings.hotkeyKey,
      l10n: l10n,
      displayOverride: settings.hotkey.hotkeyKeyDisplay,
    );

    final Widget child;
    if (installed) {
      // Also after a desktop upgrade brought the portal: the entry is ours
      // to take out again.
      child = _block(
        context,
        text: l10n.settingsDesktopShortcutInstalled(keys),
        button: WpButton(
          label: l10n.settingsDesktopShortcutRemove,
          variant: WpButtonVariant.secondary,
          testId: 'general-desktop-shortcut-remove',
          isLoading: _busy,
          onPressed: _busy ? null : () => _change(add: false),
        ),
      );
    } else if (fallback == DesktopShortcutFallback.gnome) {
      child = _block(
        context,
        text: l10n.settingsDesktopShortcutGnome(keys),
        button: WpButton(
          label: l10n.settingsDesktopShortcutAdd,
          variant: WpButtonVariant.secondary,
          testId: 'general-desktop-shortcut-add',
          isLoading: _busy,
          onPressed:
              _busy ||
                  gnomeAccelerator(
                        settings.hotkeyModifiers,
                        settings.hotkeyKey,
                      ) ==
                      null
              ? null
              : () => _change(add: true),
        ),
      );
    } else if (fallback == DesktopShortcutFallback.manual) {
      final command = ref.watch(manualToggleCommandProvider);
      child = _block(
        context,
        text: l10n.settingsDesktopShortcutManual,
        command: command,
        button: WpButton(
          label: l10n.manualCodeCopy,
          variant: WpButtonVariant.ghost,
          testId: 'general-desktop-shortcut-copy',
          onPressed: () => _copy(command, l10n),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      identifier: 'general-desktop-shortcut',
      child: Padding(
        key: const ValueKey('general-desktop-shortcut'),
        padding: const EdgeInsetsDirectional.fromSTEB(
          kSettingRowTextInset,
          0,
          kSettingRowInset,
          WpSpacing.sm,
        ),
        child: child,
      ),
    );
  }

  Widget _block(
    BuildContext context, {
    required String text,
    String? command,
    required Widget button,
  }) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          key: const ValueKey('general-desktop-shortcut-text'),
          style: theme.bodySmall?.copyWith(color: WpColors.textSecondary),
        ),
        if (command != null) ...[
          const SizedBox(height: WpSpacing.xs),
          Semantics(
            identifier: 'general-desktop-shortcut-command',
            child: SelectableText(
              command,
              key: const ValueKey('general-desktop-shortcut-command'),
              textDirection: TextDirection.ltr,
              style: theme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
        if (_failed) ...[
          const SizedBox(height: WpSpacing.xs),
          Text(
            L10n.of(context).settingsDesktopShortcutFailed,
            key: const ValueKey('general-desktop-shortcut-failed'),
            style: theme.bodySmall?.copyWith(color: WpColors.error),
          ),
        ],
        const SizedBox(height: WpSpacing.xs),
        button,
      ],
    );
  }
}
