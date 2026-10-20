/// The toast that tells a GNOME user the hotkey is not system-wide yet.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/navigation/page_state.dart';
import 'toast.dart';

/// GNOME on Wayland without the GlobalShortcuts portal, and WhisPaste's
/// GNOME entry is not set up (XP-6-14): the hotkey reaches only XWayland
/// windows. Names the hotkey and opens the hotkey row, whose block adds the
/// entry with one click. A call site of [WpToast], not a component of its
/// own, so it carries no showWp* infix.
void showDesktopShortcutToast({
  required BuildContext context,
  required WidgetRef ref,
}) {
  final l10n = L10n.of(context);
  final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
  WpToast.show(
    context,
    message: l10n.desktopShortcutToast(
      formatHotkeyKeycap(
        settings.hotkeyModifiers,
        settings.hotkeyKey,
        l10n: l10n,
        displayOverride: settings.hotkey.hotkeyKeyDisplay,
      ),
    ),
    type: WpToastType.warning,
    messageTestId: 'toast-desktop-shortcut',
    duration: const Duration(seconds: 10),
    action: WpToastAction(
      label: l10n.pasteFailureOpenSettings,
      testId: 'toast-desktop-shortcut-open',
      onPressed: () {
        ref
            .read(settingsScrollTargetProvider.notifier)
            .set('general-hotkey-combo');
        ref.read(activePageProvider.notifier).setPage('settings');
      },
    ),
  );
}
