#ifndef RUNNER_DESKTOP_ENTRY_H_
#define RUNNER_DESKTOP_ENTRY_H_

// The desktop entry WhisPaste writes for itself when nothing installed one
// (tarball, AppImage without desktop integration). Pure and free of GLib so
// desktop_entry_test.cc can run on any host; desktop_entry_installer.cc does
// the file system part.
//
// Why it exists: the xdg-desktop-portal only gives an unsandboxed app an app
// ID (org.freedesktop.host.portal.Registry.Register) if a matching
// `<app-id>.desktop` is installed, and GlobalShortcuts.CreateSession refuses
// apps without one ("An app id is required"). Without it the Wayland hotkey
// can never be bound. It also registers the whispaste:// scheme, so the
// newsletter confirmation page can hand the user back to the app.

#include <optional>
#include <string>

// Last line of every entry WhisPaste wrote. An entry without it belongs to a
// package or to the user and is never touched.
inline constexpr char kDesktopEntryMarker[] = "X-WhisPaste-Generated=true";

// The app's URL scheme as a MIME type (kAppUrlScheme in lib/services/app_link.dart).
inline constexpr char kUrlSchemeMimeType[] = "x-scheme-handler/whispaste";

// The audio types file transcription reads (audioImportExtensions in
// lib/services/audio/import/audio_file_decoder.dart: WAV, MP3, FLAC, M4A,
// AAC, Ogg, Opus), with the aliases file managers report. Listing them puts
// WhisPaste under "Open With" (#1684); it never becomes the default app,
// since that needs an entry in mimeapps.list, which nothing here writes.
// Guard: test/parity/open_with_parity_test.dart.
inline constexpr char kOpenWithAudioMimeTypes[] =
    "audio/x-wav;audio/wav;audio/vnd.wave;audio/mpeg;audio/flac;audio/x-flac;audio/mp4;audio/x-m4a;audio/aac;audio/x-aac;audio/ogg;audio/x-vorbis+ogg;audio/x-opus+ogg;audio/opus;";

// One argument of the Exec key (Desktop Entry Spec, "The Exec key"): always
// quoted, with `"`, `` ` ``, `$` and `\` escaped inside the quotes, then the
// string-value escape (`\` → `\\`) on top, and `%` doubled so it is never a
// field code. Only absolute paths without control characters are accepted.
inline std::optional<std::string> DesktopExecArg(const std::string& path) {
  if (path.empty() || path[0] != '/') return std::nullopt;
  std::string out = "\"";
  for (const char c : path) {
    const auto u = static_cast<unsigned char>(c);
    if (u < 0x20 || u == 0x7f) return std::nullopt;
    switch (c) {
      case '"':
      case '`':
      case '$':
        out += "\\\\";
        out += c;
        break;
      case '\\':
        out += "\\\\\\\\";
        break;
      case '%':
        out += "%%";
        break;
      default:
        out += c;
    }
  }
  out += '"';
  return out;
}

// The full entry. [icon] may be empty (no Icon key): a file path or an icon
// theme name. [visible]: the AppImage integrates itself as a launcher (it has
// no other one, and the system settings only open an app's page, Wayland
// shortcuts included, for an entry that is shown); a tarball's entry stays
// NoDisplay. Once a package installs its own entry this one is removed
// (DecideDesktopEntry), so the menu never lists two. Either way the entry
// registers the whispaste:// scheme for the newsletter return and the audio
// types for "Open With" (MimeType, %U: links and files, several at once).
// [app_id] is the running build's application ID (a local build's ends in
// .dev); StartupWMClass follows it, since the runner sets it as prgname.
inline std::optional<std::string> BuildDesktopEntry(
    const std::string& exec_path, const std::string& icon_path,
    const std::string& app_id = "de.whispaste.app", bool visible = false) {
  const auto exec = DesktopExecArg(exec_path);
  if (!exec) return std::nullopt;
  for (const char c : icon_path) {
    const auto u = static_cast<unsigned char>(c);
    if (u < 0x20 || u == 0x7f) return std::nullopt;
  }
  std::string out =
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=WhisPaste\n"
      "Exec=" + *exec + " %U\n";
  if (!icon_path.empty()) {
    std::string icon;
    for (const char c : icon_path) {
      if (c == '\\') icon += '\\';
      icon += c;
    }
    out += "Icon=" + icon + "\n";
  }
  out +=
      "Terminal=false\n";
  out += visible ? "Categories=Utility;Accessibility;\n" : "NoDisplay=true\n";
  out += "MimeType=" + std::string(kUrlSchemeMimeType) + ";" +
         kOpenWithAudioMimeTypes + "\n";
  out += "StartupWMClass=" + app_id + "\n";
  out += kDesktopEntryMarker;
  out += '\n';
  return out;
}

enum class DesktopEntryAction { kKeep, kWrite, kRemove };

// [packaged_elsewhere]: an entry of the same name exists in a system data dir
// (.deb, distro package). [own_entry]: the content of the user-level entry,
// if there is one.
inline DesktopEntryAction DecideDesktopEntry(
    bool packaged_elsewhere, const std::optional<std::string>& own_entry,
    const std::string& desired) {
  if (packaged_elsewhere) {
    // A user-level entry shadows the package's (a hidden one hides it, a
    // visible one starts the old AppImage, scheme handler included); an own
    // one is left over from an AppImage or tarball and has to go.
    return own_entry &&
                   own_entry->find(kDesktopEntryMarker) != std::string::npos
               ? DesktopEntryAction::kRemove
               : DesktopEntryAction::kKeep;
  }
  if (!own_entry) return DesktopEntryAction::kWrite;
  if (own_entry->find(kDesktopEntryMarker) == std::string::npos) {
    return DesktopEntryAction::kKeep;
  }
  return *own_entry == desired ? DesktopEntryAction::kKeep
                               : DesktopEntryAction::kWrite;
}

#endif  // RUNNER_DESKTOP_ENTRY_H_
