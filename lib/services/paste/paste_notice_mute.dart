/// Which paste notices the user may switch off (#1852), and whether one is.
///
/// Read by [PasteResultReporter] (card, OS notice, sound) and by
/// [PasteFailureNotifier] (paths that raise the card directly), so a muted
/// notice stays away on every path.
library;

import '../../core/config/mutable_notice.dart';
import '../../core/config/settings_sections.dart' show InterfaceSettings;
import 'paster.dart';

/// The notice the user may switch off for [outcome] (#1852), or null when the
/// outcome's notice always shows. Only an unconfirmed paste qualifies: a
/// receipt that went missing proves nothing, the transcript is in the history,
/// and a clipboard tool reading first can cause it on every dictation (#1847).
/// [PasteOutcome.unconfirmedReceiptRefused] is information, never a warning,
/// so it stays as it is.
MutableNotice? mutableNoticeForPaste(PasteOutcome outcome) => switch (outcome) {
  PasteOutcome.unconfirmed ||
  PasteOutcome.unconfirmedRestored => MutableNotice.pasteUnconfirmed,
  _ => null,
};

/// Whether the user switched off the notice for [outcome] in [settings].
bool pasteNoticeMuted(PasteOutcome outcome, InterfaceSettings? settings) {
  final notice = mutableNoticeForPaste(outcome);
  return notice != null && (settings?.isNoticeMuted(notice) ?? false);
}
