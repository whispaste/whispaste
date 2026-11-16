#ifndef RUNNER_URL_SCHEME_REGISTRATION_H_
#define RUNNER_URL_SCHEME_REGISTRATION_H_

// Registers the `whispaste://` URL scheme for the current user, so a web page
// (the newsletter confirmation) can hand the user back to the app. Windows
// starts `whispaste.exe "<url>"`; the single-instance channel passes the link
// to the running instance (lib/services/app_link.dart).
//
// The MSIX package declares the scheme in its manifest (msix_config
// protocol_activation) and is skipped here. The installer, winget and Scoop
// builds register on every start, which also follows a moved executable;
// the uninstaller removes the key. Writes only when something differs.
void EnsureUrlSchemeRegistered();

#endif  // RUNNER_URL_SCHEME_REGISTRATION_H_
