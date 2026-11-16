/// Asks the user before WhisPaste clears a stale macOS Accessibility entry.
///
/// `tccutil reset` removes the entry and makes the next paste prompt again, so
/// it must never happen without the user saying yes. The dialog is the native
/// `NSAlert` from [MacOSLifecycleChannel], so it also appears when the reset is
/// offered from a notification or the tray, where no widget context exists.
library;

import 'dart:async';
import 'dart:ui' show Locale;

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/platform/macos_lifecycle_channel.dart';

/// Shows the confirmation for a stale-entry reset. Resolves `true` only when
/// the user explicitly confirms. Declining, closing the dialog, or a failed
/// dispatch (non-macOS, channel error) all resolve `false`, so no reset runs.
Future<bool> confirmTccEntryReset({required L10n l10n}) async {
  final choice = Completer<bool>();
  final bool dispatched;
  try {
    dispatched = await MacOSLifecycleChannel.showPermissionGrantAlert(
      id: 'autopaste_entry_reset',
      title: l10n.autoPasteResetConfirmTitle,
      body: l10n.autoPasteResetConfirmBody,
      confirmLabel: l10n.autoPasteResetConfirmButton,
      cancelLabel: l10n.permissionAlertLaterButton,
      onDismiss: (confirmed) {
        if (!choice.isCompleted) choice.complete(confirmed);
      },
    );
  } on Exception {
    // No native alert channel: treat as declined, never as confirmed.
    return false;
  }
  if (!dispatched) return false;
  return choice.future;
}

/// Strings for the saved app language, falling back to English. For callers
/// without a [BuildContext] (tray and notification actions).
L10n l10nForLocaleCode(String? localeCode) {
  try {
    return lookupL10n(Locale(localeCode ?? 'en'));
  } catch (_) {
    return lookupL10n(const Locale('en'));
  }
}
