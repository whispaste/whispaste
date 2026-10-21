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
// can never be bound.

#include <optional>
#include <string>

// Last line of every entry WhisPaste wrote. An entry without it belongs to a
// package or to the user and is never touched.
inline constexpr char kDesktopEntryMarker[] = "X-WhisPaste-Generated=true";

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

// The full entry. [icon_path] may be empty (no Icon key). NoDisplay keeps it
// out of the app grid: it only gives the portal an app ID, the launchers come
// from the packages.
inline std::optional<std::string> BuildDesktopEntry(
    const std::string& exec_path, const std::string& icon_path) {
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
      "Exec=" + *exec + "\n";
  if (!icon_path.empty()) {
    std::string icon;
    for (const char c : icon_path) {
      if (c == '\\') icon += '\\';
      icon += c;
    }
    out += "Icon=" + icon + "\n";
  }
  out +=
      "Terminal=false\n"
      "NoDisplay=true\n"
      "StartupWMClass=de.whispaste.app\n";
  out += kDesktopEntryMarker;
  out += '\n';
  return out;
}

enum class DesktopEntryAction { kKeep, kWrite };

// [packaged_elsewhere]: an entry of the same name exists in a system data dir
// (.deb, distro package). [own_entry]: the content of the user-level entry,
// if there is one.
inline DesktopEntryAction DecideDesktopEntry(
    bool packaged_elsewhere, const std::optional<std::string>& own_entry,
    const std::string& desired) {
  if (packaged_elsewhere) return DesktopEntryAction::kKeep;
  if (!own_entry) return DesktopEntryAction::kWrite;
  if (own_entry->find(kDesktopEntryMarker) == std::string::npos) {
    return DesktopEntryAction::kKeep;
  }
  return *own_entry == desired ? DesktopEntryAction::kKeep
                               : DesktopEntryAction::kWrite;
}

#endif  // RUNNER_DESKTOP_ENTRY_H_
