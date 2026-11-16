/// The notice that tells the user the safe default replaced their hotkey.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_labels.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/l10n/ltr_isolate.dart';
import '../core/navigation/page_state.dart';
import '../services/hotkey_disturbance.dart';
import '../services/hotkey_service.dart';
import '../services/system_attention_service.dart';
import '../services/window_activation.dart';
import 'wp_notice_bar.dart';

/// The configured hotkey is held by another app or uses an unknown key, so
/// [safeDefaultHotKey] starts dictation instead (XP-5-09). Names both
/// combinations and offers the way to the hotkey row in settings. A call site
/// of [showWpNotice], not a component of its own, so it carries no showWp*
/// infix.
void showHotkeyFallbackToast({
  required BuildContext context,
  required WidgetRef ref,
}) {
  final l10n = L10n.of(context);
  showWpNotice(
    context,
    WpNotice(
      id: 'hotkey-fallback',
      kind: WpNoticeKind.warning,
      message: _fallbackMessage(ref, l10n),
      actionLabel: l10n.settingsChangeHotkey,
      actionTestId: 'notice-hotkey-fallback-change',
      onAction: () {
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
/// a notice in a hidden window reaches nobody. Clicking it brings the window
/// forward, where the notice and the warning in settings wait.
void notifyHotkeyFallbackIfHidden({
  required WidgetRef ref,
  required L10n l10n,
}) {
  final body = _fallbackMessage(ref, l10n);
  final unknownKey =
      ref.read(hotkeyRegistrationStatusProvider) ==
      HotkeyRegistrationStatus.unknownKey;
  final isHidden = ref.read(mainWindowHiddenProvider);
  final activate = ref.read(windowActivatorProvider);
  final attention = ref.read(systemAttentionServiceProvider);
  unawaited(() async {
    if (!await isHidden()) return;
    await attention.requestAttention(
      kind: AttentionKind.hotkeyFallback,
      title: unknownKey
          ? l10n.notificationHotkeyUnknownKeyTitle
          : l10n.notificationHotkeyFallbackTitle,
      body: body,
      onClick: () => unawaited(activate()),
    );
  }());
}

String _fallbackMessage(WidgetRef ref, L10n l10n) => hotkeyFallbackMessage(
  ref.read(settingsProvider).value ?? AppSettings.defaults,
  l10n,
  status: ref.read(hotkeyRegistrationStatusProvider),
);

/// The "fallback hotkey is active" sentence, shared by the toast, the
/// notification and the notice in Settings › Keyboard shortcuts. [status]
/// picks the cause it names: an unknown key, or else another app.
///
/// Each combination is an LTR isolate, so in Hebrew the Latin key names keep
/// their order and do not wrap apart (UIA-VIS-08).
String hotkeyFallbackMessage(
  AppSettings settings,
  L10n l10n, {
  HotkeyRegistrationStatus status = HotkeyRegistrationStatus.conflict,
}) {
  final active = activeGlobalHotkey(settings, fallback: true);
  final message = status == HotkeyRegistrationStatus.unknownKey
      ? l10n.hotkeyFallbackUnknownKey
      : l10n.hotkeyFallbackActive;
  return message(
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

/// Whether a status change is a new registration failure of a secondary
/// hotkey (UIA-SHL-05). A failure that is already shown does not repeat.
bool isNewHotkeyConflict(
  HotkeyRegistrationStatus? previous,
  HotkeyRegistrationStatus next,
) => next.needsNewKey && previous != next;

/// A secondary hotkey (quick note, snippet picker) is held by another app or
/// uses an unknown key ([status]) and stays unregistered, so pressing it does
/// nothing (UIA-SHL-05). The notice names the action and offers the way to its
/// settings row via [onChange].
/// Wp naming: call site of showWpNotice, not a component (see wp_prefix_consistency_test).
void showHotkeyConflictToast({
  required BuildContext context,
  required L10n l10n,
  required String actionName,
  required HotkeyRegistrationStatus status,
  required VoidCallback onChange,
}) {
  showWpNotice(
    context,
    WpNotice(
      id: 'hotkey-conflict',
      kind: WpNoticeKind.warning,
      message: status == HotkeyRegistrationStatus.unknownKey
          ? l10n.hotkeyUnknownKeyActive(actionName)
          : l10n.hotkeyConflictActive(actionName),
      actionLabel: l10n.settingsChangeHotkey,
      actionTestId: 'notice-hotkey-conflict-change',
      onAction: onChange,
    ),
  );
}

/// macOS (#831): secure input or another app's slow keyboard tap disturbs the
/// hotkey. Same text as the system notification, shown in the app as well so
/// it also reaches users who switched system notifications off. Call site of
/// [showWpNotice].
///
/// The action "What to do?" runs [onHelp], which opens the handbook section on
/// its own (#1607). [onAcknowledged] runs once when the notice leaves, closed
/// or followed: for a slow tap that is the user's acknowledgement, and the
/// notice does not come back for that app.
/// Wp naming: call site of showWpNotice, not a component (see wp_prefix_consistency_test).
void showHotkeyDisturbanceToast({
  required BuildContext context,
  required L10n l10n,
  required HotkeyDisturbanceNotice notice,
  VoidCallback? onHelp,
  VoidCallback? onAcknowledged,
}) {
  final text = hotkeyDisturbanceText(l10n, notice);
  final slowTap = notice.cause == HotkeyDisturbanceCause.slowKeyboardTap;
  showWpNotice(
    context,
    WpNotice(
      id: 'hotkey-disturbance',
      kind: WpNoticeKind.warning,
      message: '${text.title}. ${text.body}',
      nextStep: slowTap ? l10n.hotkeyDisturbanceDismissNote : null,
      actionLabel: onHelp == null ? null : l10n.hotkeyDisturbanceHelpAction,
      actionTestId: 'notice-hotkey-disturbance-help',
      onAction: onHelp,
      onDismissed: onAcknowledged,
    ),
  );
}
