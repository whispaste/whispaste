/// The one-time hint after a dictation that was only copied (maintainer
/// 2026-10-31, point 3).
///
/// Clipboard-only is the factory setting, so a user who skipped the Auto-Paste
/// step may never learn that WhisPaste can put the text into the field itself.
/// The first copied dictation after the onboarding therefore posts one quiet
/// OS notice ("The text is on the clipboard … click here to set it up") that
/// opens the Auto-Paste setting. Once per installation, no sound, no tray
/// entry, no dock bounce; the "Paste notices" switch silences it. The status
/// bar's "Auto-Paste off" chip is the in-app counterpart (shown only while the
/// window is open); closing it also ends this hint.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/settings_labels.dart';
import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../system_attention_service.dart';
import '../tray_service.dart';
import 'paste_policy.dart';
import 'paste_result_notice.dart' show appNoticeL10n;

final _log = AppLogger('PasteSetupHint');

/// Set once the hint was posted (additive key, never reset).
const String kPasteSetupHintShownKey = 'paste_setup_hint_shown';

class PasteSetupHint {
  PasteSetupHint(this._ref, {Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Ref _ref;
  final Future<SharedPreferences> Function() _prefs;

  /// Claimed in the same synchronous step as the check, so two dictations
  /// finishing close together cannot both post the hint.
  bool _claimed = false;

  /// Called after a dictation was copied without a paste. Returns true when
  /// the hint was posted.
  Future<bool> afterClipboardOnly(AppSettings settings) async {
    if (_claimed) return false;
    _claimed = true;
    try {
      final prefs = await _prefs();
      final shown = prefs.getBool(kPasteSetupHintShownKey) ?? false;
      final due = shouldOfferPasteSetupHint(
        action: settings.afterTranscriptionAction,
        onboardingCompleted: settings.onboarding.onboardingCompleted,
        alreadyShown: shown,
        offHintDismissed: settings.onboarding.autoPasteOffHintDismissed,
      );
      if (!due || !_ref.mounted) {
        // Shown before: stay claimed, so later dictations skip the lookup.
        _claimed = shown;
        return false;
      }
      final l10n = appNoticeL10n(settings.locale);
      final shortcut = pasteShortcutLabel(
        l10n: l10n,
        isMacOS: defaultTargetPlatform == TargetPlatform.macOS,
      );
      final tray = _ref.read(trayServiceProvider.notifier);
      final shownNow = await _ref
          .read(systemAttentionServiceProvider)
          .requestAttention(
            kind: AttentionKind.pasteSetupHint,
            title: l10n.pasteSetupHintTitle,
            body: l10n.pasteSetupHintBody(shortcut),
            onClick: () => tray.openActionNeeded(kTrayPasteActionNeededKey),
          );
      // Only a notice the user could see counts as shown; otherwise a later
      // copied dictation offers it again (core review L-15, F15-6).
      if (!shownNow) {
        _claimed = false;
        return false;
      }
      await prefs.setBool(kPasteSetupHintShownKey, true);
      _log.info('Paste setup hint posted');
      return true;
    } on Object catch (e) {
      _claimed = false;
      _log.warning('Paste setup hint failed (non-fatal): $e');
      return false;
    }
  }
}

final pasteSetupHintProvider = Provider<PasteSetupHint>(PasteSetupHint.new);
