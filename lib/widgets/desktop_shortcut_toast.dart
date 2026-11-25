/// The notice that tells a GNOME user the hotkey is not system-wide yet.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/navigation/page_state.dart';
import 'wp_notice_bar.dart';

/// GNOME on Wayland without the GlobalShortcuts portal, and WhisPaste's
/// GNOME entry is not set up (XP-6-14): the hotkey reaches only XWayland
/// windows. Names the hotkey and opens the hotkey row, whose block adds the
/// entry with one click. A call site of [showWpNotice], not a component of
/// its own, so it carries no showWp* infix.
void showDesktopShortcutToast({
  required BuildContext context,
  required WidgetRef ref,
}) {
  final l10n = L10n.of(context);
  final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
  showWpNotice(
    context,
    WpNotice(
      id: 'desktop-shortcut',
      kind: WpNoticeKind.warning,
      message: l10n.desktopShortcutToast(
        formatHotkeyKeycap(
          settings.hotkeyModifiers,
          settings.hotkeyKey,
          l10n: l10n,
          displayOverride: settings.hotkey.hotkeyKeyDisplay,
        ),
      ),
      messageFor: (l10n) => l10n.desktopShortcutToast(
        formatHotkeyKeycap(
          settings.hotkeyModifiers,
          settings.hotkeyKey,
          l10n: l10n,
          displayOverride: settings.hotkey.hotkeyKeyDisplay,
        ),
      ),
      actionLabel: l10n.pasteFailureOpenSettings,
      actionLabelFor: (l10n) => l10n.pasteFailureOpenSettings,
      actionTestId: 'notice-desktop-shortcut-open',
      onAction: () {
        ref
            .read(settingsScrollTargetProvider.notifier)
            .set('general-hotkey-combo');
        ref.read(activePageProvider.notifier).setPage('settings');
      },
    ),
  );
}
