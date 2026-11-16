#include "desktop_entry_installer.h"

#include "desktop_entry.h"

#include <gio/gdesktopappinfo.h>
#include <glib.h>
#include <glib/gstdio.h>

#include <cerrno>
#include <cstring>
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

bool IsAppImage() { return g_getenv("APPIMAGE") != nullptr; }

std::string BundledIconPath() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return "";
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* icon =
      g_build_filename(dir, "data", "flutter_assets", "assets", "icons",
                       "app_icon_512.png", nullptr);
  return g_file_test(icon, G_FILE_TEST_IS_REGULAR) ? icon : "";
}

// The user icon theme file an AppImage's launcher points at.
std::string ThemeIconPath(const char* app_id) {
  g_autofree gchar* name = g_strconcat(app_id, ".png", nullptr);
  g_autofree gchar* path =
      g_build_filename(g_get_user_data_dir(), "icons", "hicolor", "512x512",
                       "apps", name, nullptr);
  return path;
}

// The Icon value. A tarball points at its bundled file. An AppImage's mount
// moves on every launch, so its icon is copied into the user icon theme
// (refreshed when the image brings a different one) and named by app ID; a
// failed copy only costs the icon.
std::string IconValue(const char* app_id) {
  const std::string bundled = BundledIconPath();
  if (!IsAppImage() || bundled.empty()) return bundled;
  const std::string target = ThemeIconPath(app_id);
  gchar* fresh = nullptr;
  gsize fresh_len = 0;
  if (!g_file_get_contents(bundled.c_str(), &fresh, &fresh_len, nullptr)) {
    return "";
  }
  gchar* current = nullptr;
  gsize current_len = 0;
  const bool same =
      g_file_get_contents(target.c_str(), &current, &current_len, nullptr) &&
      current_len == fresh_len && memcmp(current, fresh, fresh_len) == 0;
  g_free(current);
  bool ok = same;
  if (!same) {
    g_autofree gchar* dir = g_path_get_dirname(target.c_str());
    ok = g_mkdir_with_parents(dir, 0755) == 0 &&
         g_file_set_contents(target.c_str(), fresh,
                             static_cast<gssize>(fresh_len), nullptr);
  }
  g_free(fresh);
  return ok ? app_id : "";
}

// The flags are OR-ed as the enum's underlying type, so the constant is typed
// explicitly for g_spawn_async (C++ would pass a plain int).
constexpr GSpawnFlags kQuietSpawn = static_cast<GSpawnFlags>(
    G_SPAWN_SEARCH_PATH | G_SPAWN_STDOUT_TO_DEV_NULL |
    G_SPAWN_STDERR_TO_DEV_NULL);

// Best effort, never waited for: rebuild the user MIME cache so the scheme
// handler is found, and make this entry the whispaste:// default. Desktops
// without these tools read the MimeType key directly.
void RefreshSchemeHandlers(const gchar* dir, const gchar* own_file) {
  const gchar* update[] = {"update-desktop-database", dir, nullptr};
  g_spawn_async(nullptr, const_cast<gchar**>(update), nullptr,
                kQuietSpawn,
                nullptr, nullptr, nullptr, nullptr);
  if (own_file == nullptr) return;
  const gchar* xdg_mime[] = {"xdg-mime", "default", own_file,
                             kUrlSchemeMimeType, nullptr};
  g_spawn_async(nullptr, const_cast<gchar**>(xdg_mime), nullptr,
                kQuietSpawn,
                nullptr, nullptr, nullptr, nullptr);
}

}  // namespace

bool EnsureDesktopEntry(const char* app_id) {
  if (IsSandboxed()) return true;

  const std::string file_name = std::string(app_id) + ".desktop";
  g_autofree gchar* dir =
      g_build_filename(g_get_user_data_dir(), "applications", nullptr);
  g_autofree gchar* path = g_build_filename(dir, file_name.c_str(), nullptr);

  std::optional<std::string> own;
  gchar* contents = nullptr;
  if (g_file_get_contents(path, &contents, nullptr, nullptr)) {
    own = contents;
    g_free(contents);
  }

  const bool packaged = PackagedEntryExists(file_name);
  const auto desired =
      packaged ? std::optional<std::string>(std::string())
               : BuildDesktopEntry(ExecutablePath(), IconValue(app_id),
                                   app_id, IsAppImage());
  if (!desired) {
    g_warning("DesktopEntry: executable path not usable in an Exec key");
    return false;
  }

  switch (DecideDesktopEntry(packaged, own, *desired)) {
    case DesktopEntryAction::kKeep:
      return true;
    case DesktopEntryAction::kRemove:
      if (g_remove(path) != 0) {
        g_warning("DesktopEntry: could not remove %s: %s", path,
                  g_strerror(errno));
        return false;
      }
      g_message("DesktopEntry: removed %s, a package provides it", path);
      // The AppImage's icon copy, if any; the package brings its own.
      g_remove(ThemeIconPath(app_id).c_str());
      RefreshSchemeHandlers(dir, nullptr);
      return true;
    case DesktopEntryAction::kWrite:
      break;
  }

  g_autoptr(GError) error = nullptr;
  if (g_mkdir_with_parents(dir, 0755) != 0 ||
      !g_file_set_contents(path, desired->c_str(), -1, &error)) {
    g_warning("DesktopEntry: could not write %s: %s", path,
              error ? error->message : g_strerror(errno));
    return false;
  }
  g_message("DesktopEntry: wrote %s", path);
  RefreshSchemeHandlers(dir, file_name.c_str());
  return true;
}

std::string SettingsDesktopId(const char* app_id) {
  if (IsSandboxed()) return "";
  const std::string file_name = std::string(app_id) + ".desktop";
  g_autoptr(GDesktopAppInfo) info =
      g_desktop_app_info_new(file_name.c_str());
  if (info == nullptr || !g_app_info_should_show(G_APP_INFO(info))) return "";
  std::string id = g_app_info_get_id(G_APP_INFO(info));
  const std::string suffix = ".desktop";
  if (id.size() > suffix.size() &&
      id.compare(id.size() - suffix.size(), suffix.size(), suffix) == 0) {
    id.resize(id.size() - suffix.size());
  }
  return id;
}
