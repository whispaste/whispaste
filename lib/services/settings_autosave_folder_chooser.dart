/// The one place the Autosicherung feature is allowed to open a dialog
/// (Ticket 26).
///
/// Deliberately a separate file from `settings_autosave_service.dart`, which
/// performs the background runs. H1 of the ticket is that a run must never
/// pop a native panel over a user who did not ask for one, and the strongest
/// form of that promise is that the code doing the runs has no dialog to
/// reach for: the `file_selector` import lives here, this class is only ever
/// constructed by the settings section, and [choose] is only ever called from
/// a press. `test/services/settings_autosave_no_dialog_guard_test.dart` holds
/// the line by scanning both files' source.
///
/// The directory picked here already exists — that is what a directory
/// chooser returns — so unlike the export *file* case in
/// `SettingsPortabilityController`, its security-scoped bookmark can be
/// created right away, while the panel's grant is still live in this
/// process. That matters more here than there: the manual export can always
/// re-ask, and this cannot.
library;

import 'package:file_selector/file_selector.dart' show getDirectoryPath;

import 'secure_bookmark_service.dart';

/// Opens the native directory chooser. Returns the chosen path, or `null` if
/// the user cancels.
typedef AutosaveFolderPickFn =
    Future<String?> Function({String? initialDirectory});

/// A confirmed rotation folder and the bookmark that keeps it reachable
/// after a restart (empty outside the macOS sandbox).
class SettingsAutosaveLocation {
  const SettingsAutosaveLocation({
    required this.folder,
    required this.bookmark,
  });

  final String folder;
  final String bookmark;
}

class SettingsAutosaveFolderChooser {
  const SettingsAutosaveFolderChooser({
    this.pickFolder = _defaultPickFolder,
    this.bookmarks = const SecureBookmarkService(),
  });

  final AutosaveFolderPickFn pickFolder;
  final SecureBookmarkService bookmarks;

  /// Asks for a folder and pairs it with a fresh bookmark. Returns `null` on
  /// cancel — the caller must treat that as "nothing changed", including
  /// leaving the switch off.
  Future<SettingsAutosaveLocation?> choose({String? initialDirectory}) async {
    final picked = await pickFolder(initialDirectory: initialDirectory);
    if (picked == null || picked.isEmpty) return null;
    final bookmark = bookmarks.isSupported
        ? await bookmarks.create(picked)
        : null;
    return SettingsAutosaveLocation(folder: picked, bookmark: bookmark ?? '');
  }
}

Future<String?> _defaultPickFolder({String? initialDirectory}) =>
    getDirectoryPath(initialDirectory: initialDirectory);
