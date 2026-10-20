/// Navigation state providers — shared between [app.dart] and any widget or
/// service that needs to read or drive the active page / settings scroll target.
///
/// Extracted from [app.dart] to break a circular import: previously every file
/// that needed [activePageProvider] or [settingsScrollTargetProvider] imported
/// [app.dart], while [app.dart] itself imports those same files.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'help_target.dart';

// ---------------------------------------------------------------------------
// Active page provider
// ---------------------------------------------------------------------------

/// Tracks which top-level page is currently shown in the app shell.
class ActivePageNotifier extends Notifier<String> {
  @override
  String build() => kDefaultStartPage;

  void setPage(String id) {
    _landOnRetiredTarget(id);
    state = canonicalPageId(id);
  }

  /// Start-up only: shows the page restored from the last session. Callers
  /// pass the result of [resolveStartPage], so an invalid id never gets here.
  void restore(String pageId) {
    _landOnRetiredTarget(pageId);
    state = canonicalPageId(pageId);
  }

  /// A retired id that pointed at a section also sets that section's target,
  /// so the old bookmark still lands on the same content (WP-78).
  void _landOnRetiredTarget(String id) {
    switch (id) {
      case 'support':
        ref
            .read(helpTargetProvider.notifier)
            .set(const HelpTarget(tab: HelpTab.support));
      case 'about':
        ref.read(settingsScrollTargetProvider.notifier).set('about');
    }
  }
}

/// Page ids that were retired, mapped to the page that now shows them. A
/// stored or deep-linked id on the left keeps working (WP-78):
/// - `about` opened the About page, which is now the "Über WhisPaste" area of
///   Settings (the scroll target `about` is set on the way);
/// - `support` opened the support page, which is now the Support tab of the
///   Help hub (the Help target is set on the way).
const kRetiredPageIds = <String, String>{
  'about': 'settings',
  'support': 'help',
};

/// The current id for [id]: the id itself, or its replacement when it was
/// retired. Every place that stores or switches to a page goes through this.
String canonicalPageId(String id) => kRetiredPageIds[id] ?? id;

/// Page shown when nothing valid was restored.
const kDefaultStartPage = 'history';

/// Key of the last-visited page inside the `app_settings` key-value table.
///
/// Deliberately not an [AppSettings] field: the portable settings bundle
/// lists its keys explicitly, and a navigation memory does not belong in an
/// export or an import.
const kLastPageSettingKey = 'last_page';

/// Top-level pages that may be restored on start: the nav areas, Settings
/// and Help. `smartMode` only opens a Settings section, and feedback and
/// support are sub-pages reached from Help, so they are not restorable.
const kRestorablePageIds = <String>{
  'snippets',
  'notes',
  'history',
  'replacements',
  'analytics',
  'settings',
  'help',
};

/// The page to show at start for a stored [stored] id.
///
/// Falls back to [kDefaultStartPage] for a missing, unknown or removed id, and
/// for every first run that has not completed onboarding.
String resolveStartPage(String? stored, {required bool onboardingCompleted}) {
  if (!onboardingCompleted || stored == null) return kDefaultStartPage;
  final pageId = canonicalPageId(stored);
  return kRestorablePageIds.contains(pageId) ? pageId : kDefaultStartPage;
}

/// The id to remember when the user lands on [pageId], or null when it must
/// not be remembered. While an onboarding surface is on top ([surfaceActive])
/// nothing is stored, so a review opened from Settings never becomes the
/// restored page.
String? persistablePage(String pageId, {required bool surfaceActive}) {
  final current = canonicalPageId(pageId);
  if (surfaceActive || !kRestorablePageIds.contains(current)) return null;
  return current;
}

final activePageProvider = NotifierProvider<ActivePageNotifier, String>(
  ActivePageNotifier.new,
);

// ---------------------------------------------------------------------------
// Settings scroll-target provider
// ---------------------------------------------------------------------------

/// Optional settings section to scroll to after navigating to Settings.
/// Set before calling [activePageProvider.notifier.setPage]('settings') —
/// SettingsPage consumes & clears it on mount.
class SettingsScrollTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? target) => state = target;
}

final settingsScrollTargetProvider =
    NotifierProvider<SettingsScrollTargetNotifier, String?>(
      SettingsScrollTargetNotifier.new,
    );

// ---------------------------------------------------------------------------
// Settings highlight-target provider
// ---------------------------------------------------------------------------

/// Optional settings section key to briefly highlight after a scroll-jump.
///
/// The settings search field sets this alongside [settingsScrollTargetProvider]
/// when the user selects a suggestion. [SettingsPage] listens and renders a
/// temporary border around the target section, then clears the provider.
class SettingsHighlightTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? target) => state = target;
}

final settingsHighlightTargetProvider =
    NotifierProvider<SettingsHighlightTargetNotifier, String?>(
      SettingsHighlightTargetNotifier.new,
    );

// ---------------------------------------------------------------------------
// Notes editor-target provider
// ---------------------------------------------------------------------------

/// Optional note id the Notizen area should open in its editor after
/// navigating there — the notes-side twin of [settingsScrollTargetProvider]
/// (a note id instead of a section key).
///
/// Set before calling [activePageProvider.notifier].setPage('notes');
/// `NotesPage` consumes it on mount and via `ref.listen`, and **clears it
/// synchronously as it reads it**. Clearing matters twice over: a later
/// manual visit to the Notizen area must not jump to the note again, and
/// re-setting the same id (two quick-note runs against the same note) would
/// otherwise be a silent no-op — a `Notifier` skips notification when the new
/// state equals the old one.
class NotesEditorTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? noteId) => state = noteId;
}

final notesEditorTargetProvider =
    NotifierProvider<NotesEditorTargetNotifier, String?>(
      NotesEditorTargetNotifier.new,
    );
