/// What the user is told when a paste did not land (UIA-SHL-04).
///
/// Every paste path reports its outcome here: the dictation pipeline, the
/// clipboard side panel and the snippet picker. The same outcome therefore
/// gets the same wording, the same in-app toast, the same OS notice and the
/// same tray entry, whichever path ran it.
///
/// [pasteResultNotice] is the pure decision table. [PasteResultReporter] reads
/// the live state (permissions, Linux uinput, language) and fires the result.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/settings_labels.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../desktop_paste/linux_uinput_access.dart';
import '../desktop_paste/linux_uinput_consent_notice.dart';
import '../permissions/tcc_entry_reset_confirm.dart';
import '../sound_feedback_service.dart';
import '../system_attention_service.dart';
import '../tray_service.dart';
import 'paste_capability_notifier.dart';
import 'paste_failure_notifier.dart';
import 'paster.dart';

final _log = AppLogger('PasteNotice');

/// A click target a notice can carry. The reporter resolves it to a closure.
enum PasteNoticeAction {
  /// The macOS/Windows permission recovery (restart, entry reset or Settings).
  permissionRecovery,

  /// Opens the Auto-Paste settings through the tray action-needed entry.
  openAutoPasteSettings,
}

/// One notice for a paste that did not land: the OS attention entry and,
/// optionally, the persistent tray entry.
class PasteResultNotice {
  const PasteResultNotice({
    required this.kind,
    required this.title,
    required this.body,
    this.trayLabel,
    this.trayMenuItemKey = kTrayPasteActionNeededKey,
    this.action,
  });

  final AttentionKind kind;
  final String title;
  final String body;

  /// Tray entry text, or null when the notice has no persistent tray entry.
  final String? trayLabel;

  /// Tray menu key that runs the recovery for this notice.
  final String trayMenuItemKey;

  /// What clicking the notice does, or null when it has no click target.
  final PasteNoticeAction? action;
}

/// The OS notice for [outcome], or null when no OS notice is due.
///
/// Silent outcomes: a landed paste; a blocked app (the user's own block-list
/// rule); an unconfirmed paste on a platform without a read receipt
/// ([PasteOutcome.unconfirmedNoBridge], no warning by design). A target change
/// ([PasteOutcome.targetChanged]) is an in-app toast only, so it is null here.
///
/// [uinputDeviceMissing] (Linux), [restartNeeded] and [resetEntryFirst]
/// (macOS/Windows) pick the wording of a permission notice. [linuxConsentNotice]
/// is the one-time notice after a .deb upgrade took the access away.
PasteResultNotice? pasteResultNotice({
  required PasteOutcome outcome,
  required L10n l10n,
  required TargetPlatform platform,
  bool uinputDeviceMissing = false,
  bool restartNeeded = false,
  bool resetEntryFirst = false,
  bool linuxConsentNotice = false,
}) {
  final isMacOS = platform == TargetPlatform.macOS;
  final shortcut = pasteShortcutLabel(l10n: l10n, isMacOS: isMacOS);
  switch (outcome) {
    case PasteOutcome.success ||
        PasteOutcome.blocked ||
        PasteOutcome.unconfirmedNoBridge ||
        PasteOutcome.targetChanged:
      return null;
    case PasteOutcome.noTarget:
      return PasteResultNotice(
        kind: AttentionKind.pasteBlockedNoTarget,
        title: l10n.pasteNotificationNoTargetTitle,
        body: l10n.pasteNotificationNoTargetBody,
        trayLabel: l10n.pasteNotificationNoTargetTray,
      );
    case PasteOutcome.permissionMissing when platform == TargetPlatform.linux:
      return PasteResultNotice(
        kind: AttentionKind.pasteBlockedPermission,
        title: l10n.pasteNotificationPermissionBlockedTitle,
        body: linuxConsentNotice
            ? l10n.linuxUinputConsentNotice(shortcut)
            : uinputDeviceMissing
            ? l10n.pasteNotificationLinuxNoDeviceBody(shortcut)
            : l10n.pasteNotificationLinuxUinputBody(shortcut),
        trayLabel: uinputDeviceMissing
            ? l10n.pasteNotificationLinuxNoDeviceTray
            : l10n.pasteNotificationLinuxUinputTray,
        action: PasteNoticeAction.openAutoPasteSettings,
      );
    case PasteOutcome.permissionMissing:
      // macOS, and Windows reads the same way (no permission dialog there).
      // The paste left the transcript on the clipboard, so the body says so.
      final hint = l10n.pasteNotificationClipboardHint;
      return PasteResultNotice(
        kind: AttentionKind.pasteBlockedPermission,
        title: restartNeeded
            ? l10n.pasteNotificationRestartNeededTitle
            : l10n.pasteNotificationPermissionBlockedTitle,
        body:
            '${restartNeeded
                ? l10n.pasteNotificationRestartNeededBody
                : resetEntryFirst
                ? l10n.pasteNotificationPermissionResetEntryBody
                : l10n.pasteNotificationPermissionOpenSettingsBody} $hint',
        trayLabel: restartNeeded
            ? l10n.pasteNotificationRestartNeededTray
            : l10n.pasteNotificationPermissionBlockedTray,
        trayMenuItemKey: kTrayPastePermissionActionNeededKey,
        action: PasteNoticeAction.permissionRecovery,
      );
    case PasteOutcome.elevationBlocked:
      return PasteResultNotice(
        kind: AttentionKind.pasteBlockedElevation,
        title: l10n.pasteNotificationElevationBlockedTitle,
        body: l10n.pasteNotificationElevationBlockedBody,
        trayLabel: l10n.pasteNotificationElevationBlockedTray,
      );
    case PasteOutcome.unconfirmed:
      // Shortcut sent, no proof of arrival. The text is still on the clipboard.
      return PasteResultNotice(
        kind: AttentionKind.pasteFailedUnknown,
        title: l10n.pasteNotificationFailedTitle,
        body: l10n.pasteFailureUnconfirmed(shortcut),
      );
    case PasteOutcome.failed || PasteOutcome.platformUnavailable:
      return PasteResultNotice(
        kind: AttentionKind.pasteFailedUnknown,
        title: l10n.pasteNotificationFailedTitle,
        body: l10n.pasteNotificationFailedBody(shortcut),
        trayLabel: l10n.pasteNotificationFailedTray,
      );
  }
}

/// The app's own persisted language (Settings → Language), falling back to
/// English. Not the raw OS locale, so notices match the rest of the app.
L10n appNoticeL10n(String? localeCode) {
  if (localeCode != null) {
    try {
      return lookupL10n(Locale(localeCode));
    } catch (e) {
      _log.debug('Unsupported locale "$localeCode", falling back to en: $e');
    }
  }
  return lookupL10n(const Locale('en'));
}

/// Reports one paste outcome to the user, for every paste path.
///
/// Holds no state of its own: it reads the live services when a result
/// arrives. Obtain it with [pasteResultReporterProvider], which lives as long
/// as the app, so a panel or picker that closes during a paste still reports.
class PasteResultReporter {
  PasteResultReporter(this._ref);

  final Ref _ref;

  /// Reports [outcome]. Returns true when an OS notice and the error sound
  /// fired, so the caller can tell that the user was already alerted.
  Future<bool> report(PasteOutcome outcome) async {
    // The app container is gone (shutdown, or a test tearing down): no live
    // service is left to report to, and reading [_ref] would throw.
    if (!_ref.mounted) return false;
    if (outcome == PasteOutcome.success) {
      _clearNotice();
      return false;
    }
    unawaited(_recheckCapability());
    // Silent outcomes never reach the in-app toast either.
    if (outcome == PasteOutcome.blocked ||
        outcome == PasteOutcome.unconfirmedNoBridge) {
      return false;
    }
    _ref.read(pasteFailureNotifierProvider.notifier).report(outcome);

    final l10n = _resolveL10n();
    final platform = defaultTargetPlatform;
    final notice = outcome == PasteOutcome.permissionMissing
        ? await _permissionNotice(l10n, platform)
        : pasteResultNotice(outcome: outcome, l10n: l10n, platform: platform);
    if (notice == null || !_ref.mounted) return false;
    _fire(notice, l10n);
    return true;
  }

  /// Reads the live permission state and asks [pasteResultNotice] for the
  /// wording. A failed paste is when a revoked permission shows up, so the
  /// capability notifier is re-probed by [report] first.
  Future<PasteResultNotice?> _permissionNotice(
    L10n l10n,
    TargetPlatform platform,
  ) async {
    final capability = _ref.read(pasteCapabilityNotifierProvider);
    final capNotifier = _ref.read(pasteCapabilityNotifierProvider.notifier);
    final uinputDeviceMissing =
        capability.capability?.status == PasteCapabilityStatus.unsupported;
    // Two causes look alike from the outcome alone. A stale grant needs a
    // restart; an entry that may be stale is reset before the request.
    final restartNeeded = capNotifier.needsRestart;
    final resetEntryFirst =
        !restartNeeded && capNotifier.staleEntryResetCandidate;
    // A .deb upgrade can take the install-time uinput access away; the first
    // blocked paste says so, once. Not on a machine without any uinput device.
    final consent =
        platform == TargetPlatform.linux &&
        !uinputDeviceMissing &&
        await _takeLinuxConsentNotice();
    _log.info(
      'Paste permission notice: '
      '${restartNeeded
          ? 'restart'
          : resetEntryFirst
          ? 'reset-entry-then-grant'
          : 'open-settings'}',
    );
    return pasteResultNotice(
      outcome: PasteOutcome.permissionMissing,
      l10n: l10n,
      platform: platform,
      uinputDeviceMissing: uinputDeviceMissing,
      restartNeeded: restartNeeded,
      resetEntryFirst: resetEntryFirst,
      linuxConsentNotice: consent,
    );
  }

  void _fire(PasteResultNotice notice, L10n l10n) {
    // Short, quiet error tone: audible when the user is not looking at the
    // screen. Respects the sound volume and errorSound setting.
    try {
      unawaited(_ref.read(soundFeedbackProvider.notifier).playError());
    } on Exception catch (e) {
      _log.warning('Error sound failed: $e');
    }
    // Dock bounce, native notification and tray badge reach the user with the
    // main window hidden, the usual case for WhisPaste.
    unawaited(
      _ref
          .read(systemAttentionServiceProvider)
          .requestAttention(
            kind: notice.kind,
            title: notice.title,
            body: notice.body,
            onClick: _onClick(notice.action, l10n),
          ),
    );
    final label = notice.trayLabel;
    if (label != null) {
      try {
        _ref
            .read(trayServiceProvider.notifier)
            .setActionNeeded(
              label: label,
              tooltip: 'WhisPaste — $label',
              menuItemKey: notice.trayMenuItemKey,
            );
      } on Exception catch (e) {
        _log.warning('Tray action-needed update failed', e);
      }
    }
  }

  /// The click closure for [action]. The permission arm re-resolves its state
  /// when clicked, because a notification can sit unread for a long time.
  void Function()? _onClick(PasteNoticeAction? action, L10n l10n) {
    switch (action) {
      case null:
        return null;
      case PasteNoticeAction.permissionRecovery:
        final capNotifier = _ref.read(pasteCapabilityNotifierProvider.notifier);
        return () => capNotifier.runMissingPermissionRecovery(
          confirmReset: () => confirmTccEntryReset(l10n: l10n),
        );
      case PasteNoticeAction.openAutoPasteSettings:
        final tray = _ref.read(trayServiceProvider.notifier);
        return () => tray.openActionNeeded(kTrayPasteActionNeededKey);
    }
  }

  void _clearNotice() {
    unawaited(_ref.read(systemAttentionServiceProvider).clearAttention());
    try {
      _ref.read(trayServiceProvider.notifier).clearActionNeeded();
    } on Exception catch (e) {
      _log.debug('clearActionNeeded failed', e);
    }
  }

  Future<void> _recheckCapability() async {
    try {
      await _ref
          .read(pasteCapabilityNotifierProvider.notifier)
          .recheckAfterPasteFailure();
    } on Object catch (e) {
      _log.debug('Capability recheck after paste failure failed: $e');
    }
  }

  L10n _resolveL10n() =>
      appNoticeL10n(_ref.read(settingsProvider).value?.locale);

  Future<bool> _takeLinuxConsentNotice() async {
    final settings = _ref.read(settingsProvider).value ?? AppSettings.defaults;
    try {
      return await takeLinuxUinputConsentNotice(
        prefs: await SharedPreferences.getInstance(),
        canManage: _ref.read(linuxUinputAccessProvider).canManage,
        // This paste ran, so Auto-Paste is on, and it was just refused.
        autoPasteOn: true,
        onboardingDone: settings.onboarding.onboardingCompleted,
        pasteBlocked: () async => true,
      );
    } on Object catch (e) {
      _log.warning('Consent notice check failed: $e');
      return false;
    }
  }
}

/// The app-wide reporter. Every paste path reads it once and calls
/// [PasteResultReporter.report] with the outcome.
final pasteResultReporterProvider = Provider<PasteResultReporter>(
  PasteResultReporter.new,
);
