#include "desktop_entry_installer.h"

#include "desktop_entry.h"

#include <glib.h>

#include <cerrno>
#include <string>

namespace {

bool IsSandboxed() {
  return g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS) ||
         g_getenv("SNAP") != nullptr;
}

bool PackagedEntryExists(const std::string& file_name) {
  for (const gchar* const* dir = g_get_system_data_dirs(); *dir != nullptr;
       ++dir) {
    g_autofree gchar* path =
        g_build_filename(*dir, "applications", file_name.c_str(), nullptr);
    if (g_file_test(path, G_FILE_TEST_EXISTS)) return true;
  }
  return false;
}

// The AppImage runtime mounts the image at a new path on every launch;
// $APPIMAGE is the stable file the user starts.
std::string ExecutablePath() {
  const gchar* appimage = g_getenv("APPIMAGE");
  if (appimage != nullptr && g_path_is_absolute(appimage)) return appimage;
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  return exe != nullptr ? exe : "";
}

// The bundled app icon, unless it sits in a per-launch AppImage mount.
std::string IconPath() {
  if (g_getenv("APPIMAGE") != nullptr) return "";
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return "";
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* icon =
      g_build_filename(dir, "data", "flutter_assets", "assets", "icons",
                       "app_icon_512.png", nullptr);
  return g_file_test(icon, G_FILE_TEST_IS_REGULAR) ? icon : "";
}

}  // namespace

bool EnsureDesktopEntry(const char* app_id) {
  if (IsSandboxed()) return true;

  const std::string file_name = std::string(app_id) + ".desktop";
  if (PackagedEntryExists(file_name)) return true;

  const auto desired = BuildDesktopEntry(ExecutablePath(), IconPath(), app_id);
  if (!desired) {
    g_warning("DesktopEntry: executable path not usable in an Exec key");
    return false;
  }

  g_autofree gchar* dir =
      g_build_filename(g_get_user_data_dir(), "applications", nullptr);
  g_autofree gchar* path = g_build_filename(dir, file_name.c_str(), nullptr);

  std::optional<std::string> own;
  gchar* contents = nullptr;
  if (g_file_get_contents(path, &contents, nullptr, nullptr)) {
    own = contents;
    g_free(contents);
  }

  if (DecideDesktopEntry(false, own, *desired) == DesktopEntryAction::kKeep) {
    return true;
  }

  g_autoptr(GError) error = nullptr;
  if (g_mkdir_with_parents(dir, 0755) != 0 ||
      !g_file_set_contents(path, desired->c_str(), -1, &error)) {
    g_warning("DesktopEntry: could not write %s: %s", path,
              error ? error->message : g_strerror(errno));
    return false;
  }
  g_message("DesktopEntry: wrote %s", path);
  return true;
}
