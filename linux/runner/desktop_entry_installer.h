#ifndef RUNNER_DESKTOP_ENTRY_INSTALLER_H_
#define RUNNER_DESKTOP_ENTRY_INSTALLER_H_

// Makes sure `<app_id>.desktop` exists so the xdg-desktop-portal can resolve
// WhisPaste's app ID (see desktop_entry.h for why).
//
// Writes only `$XDG_DATA_HOME/applications/<app_id>.desktop`, and only when
// no package installed one (any `applications/` dir of the system data dirs)
// and the user-level file is missing or one WhisPaste wrote itself. Flatpak
// and Snap get their app ID from the sandbox and are skipped.
//
// Returns false when no entry is in place afterwards (write failed, or the
// executable path cannot be expressed in an Exec key).
bool EnsureDesktopEntry(const char* app_id);

#endif  // RUNNER_DESKTOP_ENTRY_INSTALLER_H_
