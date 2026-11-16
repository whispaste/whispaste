#ifndef RUNNER_DESKTOP_ENTRY_INSTALLER_H_
#define RUNNER_DESKTOP_ENTRY_INSTALLER_H_

#include <string>

// Makes sure `<app_id>.desktop` exists so the xdg-desktop-portal can resolve
// WhisPaste's app ID (see desktop_entry.h for why). Runs on every start; an
// AppImage gets a visible launcher with its icon copied to
// `$XDG_DATA_HOME/icons/hicolor/512x512/apps/<app_id>.png`.
//
// Writes only `$XDG_DATA_HOME/applications/<app_id>.desktop`, and only when
// no package installed one (any `applications/` dir of the system data dirs)
// and the user-level file is missing or one WhisPaste wrote itself. Once a
// package brings its own, an entry WhisPaste wrote is removed with its icon
// copy. Flatpak and Snap get their app ID from the sandbox and are skipped.
//
// Returns false when no entry is in place afterwards (write failed, or the
// executable path cannot be expressed in an Exec key).
bool EnsureDesktopEntry(const char* app_id);

// The desktop ID (without `.desktop`) under which the desktop's settings app
// lists WhisPaste, or "" when it does not: `<app_id>.desktop` must be
// installed and shown in launchers (GNOME Settings skips NoDisplay entries,
// so the self-written one does not count), and the app must run outside
// Flatpak and Snap, whose entries carry other IDs.
std::string SettingsDesktopId(const char* app_id);

#endif  // RUNNER_DESKTOP_ENTRY_INSTALLER_H_
