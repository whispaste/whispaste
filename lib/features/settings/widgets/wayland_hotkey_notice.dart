/// Inline notice for a main hotkey that the Linux Wayland desktop has not
/// bound (XP-2-06): says why it does not work in other apps, offers to ask
/// the desktop again, and walks through the custom-shortcut fallback. Shown
/// under the hotkey in Settings and onboarding.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/keyboard_up_monitor.dart';
import '../../../services/linux_desktop_shortcut.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

/// The reason the notice shows, or null when it should not show: the hotkey
/// works, or (no portal) the desktop shortcut block still carries the fix and
/// no longer needs this notice.
final waylandHotkeyNoticeReasonProvider = Provider<WaylandHotkeyBinding?>((
  ref,
) {
  final status = ref.watch(hotkeyRegistrationStatusProvider);
  if (status != HotkeyRegistrationStatus.waylandUnbound) return null;
  final binding = ref.watch(waylandHotkeyBindingProvider);
  if (binding == WaylandHotkeyBinding.unavailable &&
      !ref.watch(desktopShortcutPendingProvider)) {
    return null;
  }
  return binding;
});

/// Why the hotkey is unbound, in the user's words.
String waylandHotkeyIssueText(L10n l10n, WaylandHotkeyBinding binding) =>
    switch (binding) {
      WaylandHotkeyBinding.noAppId => l10n.waylandHotkeyNoAppId,
      WaylandHotkeyBinding.unavailable => l10n.waylandHotkeyUnavailable,
      _ => l10n.waylandHotkeyDeclined,
    };

/// [idPrefix] names the screen in every testID (`settings`, `onboarding`).
class WaylandHotkeyNotice extends ConsumerStatefulWidget {
  const WaylandHotkeyNotice({super.key, required this.idPrefix});

  final String idPrefix;

  @override
  ConsumerState<WaylandHotkeyNotice> createState() =>
      _WaylandHotkeyNoticeState();
}

class _WaylandHotkeyNoticeState extends ConsumerState<WaylandHotkeyNotice> {
  bool _copied = false;

  ValueKey<String> _id(String element) =>
      ValueKey('${widget.idPrefix}-wayland-hotkey-$element');

  /// The compositor owns the hotkey: name the shortcut it set (when the
  /// portal delivered one), otherwise say where the shortcut is set.
  Widget _boundNote(BuildContext context) {
    final l10n = L10n.of(context);
    final trigger = ref.watch(waylandBoundTriggerProvider);
    final text = trigger == null
        ? l10n.waylandHotkeyBoundNoTrigger
        : l10n.waylandHotkeyBoundTrigger(trigger);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        kSettingRowTextInset,
        0,
        kSettingRowInset,
        WpSpacing.sm,
      ),
      child: Text(
        text,
        key: _id('bound'),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: WpColors.textMuted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(settingsProvider).value?.hotkeyEnabled ?? true;
    final binding = ref.watch(waylandHotkeyNoticeReasonProvider);
    if (!enabled) return const SizedBox.shrink();
    if (binding == null) {
      final bound =
          ref.watch(waylandHotkeyBindingProvider) == WaylandHotkeyBinding.bound;
      return bound ? _boundNote(context) : const SizedBox.shrink();
    }

    final l10n = L10n.of(context);
    final desktop = ref.watch(keyboardShortcutSettingsDesktopProvider);
    final command = ref.watch(manualToggleCommandProvider);
    // Without a portal the desktop shortcut block below offers the command
    // and the GNOME entry itself; this notice only names the reason and,
    // where possible, the settings to look at.
    final noPortal = binding == WaylandHotkeyBinding.unavailable;
    final issue = waylandHotkeyIssueText(l10n, binding);

    return Column(
      key: _id('notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HotkeyNotice(
          noticeKey: _id('issue'),
          icon: LucideIcons.triangleAlert,
          color: WpColors.warning,
          text: noPortal ? issue : '$issue ${l10n.waylandHotkeyFallback}',
        ),
        if (!noPortal || desktop != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              kSettingRowTextInset,
              0,
              kSettingRowInset,
              WpSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!noPortal) ...[
                  // A shell command reads left to right in every UI language.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: WpSpacing.xs,
                        vertical: WpSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: WpColors.surfaceMutedFill,
                        borderRadius: BorderRadius.circular(WpRadius.sm),
                      ),
                      child: SelectableText(
                        command,
                        key: _id('command'),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: WpTypography.caption,
                          color: WpColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xs),
                ],
                Wrap(
                  spacing: WpSpacing.xs,
                  runSpacing: WpSpacing.xs,
                  children: [
                    if (!noPortal)
                      WpButton(
                        label: l10n.waylandHotkeyReconnect,
                        icon: LucideIcons.refreshCw,
                        variant: WpButtonVariant.secondary,
                        size: WpButtonSize.dense,
                        testId: _id('reconnect').value,
                        onPressed: () => unawaited(
                          ref
                              .read(hotkeyServiceProvider.notifier)
                              .reconnectWaylandHotkey(),
                        ),
                      ),
                    if (!noPortal)
                      WpButton(
                        label: _copied
                            ? l10n.waylandHotkeyCommandCopied
                            : l10n.waylandHotkeyCopyCommand,
                        icon: _copied ? LucideIcons.check : LucideIcons.copy,
                        variant: WpButtonVariant.secondary,
                        tone: WpButtonTone.neutral,
                        size: WpButtonSize.dense,
                        testId: _id('copy-command').value,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: command));
                          if (mounted) setState(() => _copied = true);
                        },
                      ),
                    if (desktop != null)
                      WpButton(
                        label: l10n.waylandHotkeyOpenKeyboardSettings,
                        icon: LucideIcons.keyboard,
                        variant: WpButtonVariant.secondary,
                        tone: WpButtonTone.neutral,
                        size: WpButtonSize.dense,
                        testId: _id('open-keyboard-settings').value,
                        onPressed: () => unawaited(
                          ref.read(keyboardShortcutSettingsOpenerProvider)(
                            desktop,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
