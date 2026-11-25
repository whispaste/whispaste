/// Notices the user may switch off with "Don't show again" (#1852).
///
/// Only uncertain notices qualify: the app cannot prove that something went
/// wrong, and nothing is lost when the notice stays away. A real failure
/// (missing permission, nothing pasted, elevated target, secure input,
/// password field) is never listed here, so it always reaches the user.
///
/// A muted notice shows no overlay card or banner, no OS notification and
/// plays no error sound. Its log line and the history entry stay. Settings ›
/// General lists every muted notice with "Show again".
///
/// Adding a notice here is a product decision: it needs the same reasoning
/// as [pasteUnconfirmed] in the commit and in `internal-notes`.
library;

enum MutableNotice {
  /// "Auto-paste not confirmed" (`PasteOutcome.unconfirmed` and
  /// `unconfirmedRestored`): the shortcut went out but no read receipt came
  /// back. Usually the text landed anyway (a clipboard tool read it first,
  /// #1847); the transcript is always in the history.
  pasteUnconfirmed('paste-unconfirmed');

  const MutableNotice(this.id);

  /// Stable id, stored in `InterfaceSettings.mutedNotices`. Never rename.
  final String id;

  /// The notice for a stored [id], or null for an id this build does not know
  /// (written by a newer version, or a notice that was retired).
  static MutableNotice? fromId(String id) {
    for (final notice in values) {
      if (notice.id == id) return notice;
    }
    return null;
  }
}
