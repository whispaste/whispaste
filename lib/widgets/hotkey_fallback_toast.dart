/// The toast that tells the user the safe default replaced their hotkey.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/l10n/ltr_isolate.dart';
import '../core/navigation/page_state.dart';
import '../services/hotkey_service.dart';
import '../services/system_attention_service.dart';
import '../services/window_activation.dart';
import 'toast.dart';

/// Another app holds the configured hotkey, so [safeDefaultHotKey] starts
/// dictation instead (XP-5-09). Names both combinations and offers the way to
/// the hotkey row in settings. A call site of [WpToast], not a component of
/// its own, so it carries no showWp* infix.
void showHotkeyFallbackToast({
  required BuildContext context,
  required WidgetRef ref,
}) {
  final l10n = L10n.of(context);
  WpToast.show(
    context,
    message: _fallbackMessage(ref, l10n),
    type: WpToastType.warning,
    messageTestId: 'toast-hotkey-fallback',
    duration: const Duration(seconds: 10),
    action: WpToastAction(
      label: l10n.settingsChangeHotkey,
      testId: 'toast-hotkey-fallback-change',
      onPressed: () {
        ref
            .read(settingsScrollTargetProvider.notifier)
            .set('general-hotkey-combo');
        ref.read(activePageProvider.notifier).setPage('settings');
      },
    ),
  );
}

/// The same message as an OS notification, but only while the main window is
/// hidden or minimised: the app starts minimised to the tray by default, and
/// a toast in a hidden window reaches nobody. Clicking it brings the window
/// forward, where the toast and the warning in settings wait.
void notifyHotkeyFallbackIfHidden({
  required WidgetRef ref,
  required L10n l10n,
}) {
  final body = _fallbackMessage(ref, l10n);
  final isHidden = ref.read(mainWindowHiddenProvider);
  final activate = ref.read(windowActivatorProvider);
  final attention = ref.read(systemAttentionServiceProvider);
  unawaited(() async {
    if (!await isHidden()) return;
    await attention.requestAttention(
      kind: AttentionKind.hotkeyFallback,
      title: l10n.notificationHotkeyFallbackTitle,
      body: body,
      onClick: () => unawaited(activate()),
    );
  }());
}

String _fallbackMessage(WidgetRef ref, L10n l10n) => hotkeyFallbackMessage(
  ref.read(settingsProvider).value ?? AppSettings.defaults,
  l10n,
);

/// The "fallback hotkey is active" sentence, shared by the toast, the
/// notification and the notice in Settings › Keyboard shortcuts.
///
/// Each combination is an LTR isolate, so in Hebrew the Latin key names keep
/// their order and do not wrap apart (UIA-VIS-08).
String hotkeyFallbackMessage(AppSettings settings, L10n l10n) {
  final active = activeGlobalHotkey(settings, fallback: true);
  return l10n.hotkeyFallbackActive(
    ltrIsolate(
      formatHotkeyKeycap(
        settings.hotkeyModifiers,
        settings.hotkeyKey,
        l10n: l10n,
        displayOverride: settings.hotkey.hotkeyKeyDisplay,
      ),
    ),
    ltrIsolate(formatHotkeyKeycap(active.modifiers, active.key, l10n: l10n)),
  );
}

/// Whether a status change is a new registration conflict of a secondary
/// hotkey (UIA-SHL-05). A conflict that is already shown does not repeat.
bool isNewHotkeyConflict(
  HotkeyRegistrationStatus? previous,
  HotkeyRegistrationStatus next,
) =>
    next == HotkeyRegistrationStatus.conflict &&
    previous != HotkeyRegistrationStatus.conflict;

/// A secondary hotkey (quick note, snippet picker) is held by another app and
/// stays unregistered, so pressing it does nothing (UIA-SHL-05). The toast
/// names the action and offers the way to its settings row via [onChange].
/// Wp naming: call site of WpToast, not a component (see wp_prefix_consistency_test).
void showHotkeyConflictToast({
  required BuildContext context,
  required L10n l10n,
  required String actionName,
  required VoidCallback onChange,
}) {
  WpToast.show(
    context,
    message: l10n.hotkeyConflictActive(actionName),
    type: WpToastType.warning,
    messageTestId: 'toast-hotkey-conflict',
    duration: const Duration(seconds: 10),
    action: WpToastAction(
      label: l10n.settingsChangeHotkey,
      testId: 'toast-hotkey-conflict-change',
      onPressed: onChange,
    ),
  );
}
