/// The wording for an auto-paste that macOS secure input skipped (F35-8).
///
/// Kept apart from `paste_result_notice.dart` so the widget layer can use it
/// without pulling in the notice reporter.
library;

import '../../core/l10n/generated/app_localizations.dart';
import '../desktop_paste/desktop_paste_controller_interface.dart';

/// Bundle ids whose menu has a "Secure Keyboard Entry" switch that keeps
/// secure input on, with the tip that names where it is.
const _terminalBundleId = 'com.apple.Terminal';
const _itermBundleId = 'com.googlecode.iterm2';

/// The notice body for a paste that secure input skipped: the app holding the
/// input (or the generic lead when no app is known), the way out, and where
/// the transcript is.
///
/// Terminal and iTerm2 get their own tip, because their menu has the switch
/// that keeps secure input on. Any other holder gets no tip. [shortcut] is the
/// paste key the user presses for the manual paste (Cmd+V on macOS).
String secureInputNoticeBody(
  L10n l10n, {
  required String shortcut,
  SecureInputHolder? holder,
}) {
  final name = holder?.name;
  final lead = name == null
      ? l10n.pasteSecureInputGeneric
      : l10n.pasteSecureInputNamed(name);
  final tip = switch (holder?.bundleId) {
    _terminalBundleId => l10n.pasteSecureInputTerminalTip,
    _itermBundleId => l10n.pasteSecureInputItermTip,
    _ => null,
  };
  return [lead, ?tip, l10n.pasteSecureInputClipboard(shortcut)].join(' ');
}
