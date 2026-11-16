#include "app_identity_host.h"

#include <gtk/gtk.h>

#include <cstring>
#include <string>
#include <vector>

namespace {

constexpr char kChannelName[] = "com.whispaste.app_identity";
constexpr char kGroup[] = "Desktop Entry";

std::string Lower(std::string s) {
  for (char& c : s) c = g_ascii_tolower(c);
  return s;
}

// Every `applications` folder a desktop entry can live in, user first.
std::vector<std::string> ApplicationDirs() {
  std::vector<std::string> dirs;
  auto add = [&](const std::string& base) {
    g_autofree gchar* dir =
        g_build_filename(base.c_str(), "applications", nullptr);
    dirs.emplace_back(dir);
  };
  add(g_get_user_data_dir());
  g_autofree gchar* user_flatpak = g_build_filename(
      g_get_user_data_dir(), "flatpak", "exports", "share", nullptr);
  add(user_flatpak);
  for (const gchar* const* dir = g_get_system_data_dirs(); *dir; ++dir) {
    add(*dir);
  }
  add("/var/lib/flatpak/exports/share");
  dirs.emplace_back("/var/lib/snapd/desktop/applications");
  return dirs;
}

GKeyFile* LoadEntry(const std::string& path) {
  GKeyFile* file = g_key_file_new();
  if (!g_key_file_load_from_file(file, path.c_str(), G_KEY_FILE_NONE,
                                 nullptr) ||
      !g_key_file_has_group(file, kGroup)) {
    g_key_file_free(file);
    return nullptr;
  }
  return file;
}

// Base name of the Exec key's program, e.g. "firefox" for
// `Exec=/usr/bin/firefox %u`.
std::string ExecName(GKeyFile* file) {
  g_autofree gchar* exec = g_key_file_get_string(file, kGroup, "Exec", nullptr);
  if (exec == nullptr) return "";
  gint argc = 0;
  gchar** argv = nullptr;
  if (!g_shell_parse_argv(exec, &argc, &argv, nullptr) || argc == 0) {
    return "";
  }
  // `env VAR=x prog` and `flatpak run` keep the program further in.
  gint i = 0;
  if (strcmp(argv[0], "env") == 0 || g_str_has_suffix(argv[0], "/env")) {
    i = 1;
    while (i < argc && strchr(argv[i], '=') != nullptr) ++i;
  }
  std::string name;
  if (i < argc) {
    g_autofree gchar* base = g_path_get_basename(argv[i]);
    name = base;
  }
  g_strfreev(argv);
  return Lower(name);
}

// The desktop entry of [id]: by file name first (Wayland app_id), then by
// StartupWMClass or Exec program (X11 WM_CLASS res_name).
GKeyFile* FindEntry(const std::string& id) {
  const std::string lower = Lower(id);
  const auto dirs = ApplicationDirs();
  for (const auto& dir : dirs) {
    for (const std::string& name : {id, lower}) {
      g_autofree gchar* path =
          g_build_filename(dir.c_str(), (name + ".desktop").c_str(), nullptr);
      if (GKeyFile* file = LoadEntry(path)) return file;
    }
  }
  // gnome-terminal reports its server process as WM_CLASS name.
  std::string program = lower;
  const std::string server = "-server";
  if (program.size() > server.size() &&
      program.compare(program.size() - server.size(), server.size(),
                      server) == 0) {
    program.resize(program.size() - server.size());
  }
  for (const auto& dir : dirs) {
    GDir* handle = g_dir_open(dir.c_str(), 0, nullptr);
    if (handle == nullptr) continue;
    while (const gchar* entry = g_dir_read_name(handle)) {
      if (!g_str_has_suffix(entry, ".desktop")) continue;
      g_autofree gchar* path = g_build_filename(dir.c_str(), entry, nullptr);
      GKeyFile* file = LoadEntry(path);
      if (file == nullptr) continue;
      g_autofree gchar* wm_class =
          g_key_file_get_string(file, kGroup, "StartupWMClass", nullptr);
      if ((wm_class != nullptr && Lower(wm_class) == lower) ||
          ExecName(file) == program) {
        g_dir_close(handle);
        return file;
      }
      g_key_file_free(file);
    }
    g_dir_close(handle);
  }
  return nullptr;
}

// The entry's icon at [size] pixels as PNG bytes, or null.
FlValue* IconPng(GKeyFile* file, int size) {
  g_autofree gchar* icon = g_key_file_get_string(file, kGroup, "Icon", nullptr);
  if (icon == nullptr || *icon == '\0') return nullptr;
  g_autoptr(GdkPixbuf) pixbuf = nullptr;
  if (g_path_is_absolute(icon)) {
    pixbuf = gdk_pixbuf_new_from_file_at_size(icon, size, size, nullptr);
  } else {
    pixbuf = gtk_icon_theme_load_icon(gtk_icon_theme_get_default(), icon, size,
                                      GTK_ICON_LOOKUP_FORCE_SIZE, nullptr);
  }
  if (pixbuf == nullptr) return nullptr;
  gchar* buffer = nullptr;
  gsize length = 0;
  if (!gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &length, "png", nullptr,
                                 nullptr)) {
    return nullptr;
  }
  FlValue* value =
      fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(buffer), length);
  g_free(buffer);
  return value;
}

FlValue* ResolveApp(const std::string& id, int size) {
  FlValue* result = fl_value_new_map();
  if (id.empty()) return result;
  GKeyFile* file = FindEntry(id);
  if (file == nullptr) return result;
  g_autofree gchar* name =
      g_key_file_get_locale_string(file, kGroup, "Name", nullptr, nullptr);
  if (name != nullptr && *name != '\0') {
    fl_value_set_string_take(result, "name", fl_value_new_string(name));
  }
  if (FlValue* png = IconPng(file, size)) {
    fl_value_set_string_take(result, "icon", png);
  }
  g_key_file_free(file);
  return result;
}

}  // namespace

AppIdentityHost::AppIdentityHost(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                            nullptr);
}

AppIdentityHost::~AppIdentityHost() {
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
  }
  g_clear_object(&channel_);
}

void AppIdentityHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                   FlMethodCall* method_call,
                                   gpointer /*user_data*/) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "resolveApp") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    std::string id;
    int size = 64;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* id_value = fl_value_lookup_string(args, "id");
      if (id_value != nullptr &&
          fl_value_get_type(id_value) == FL_VALUE_TYPE_STRING) {
        id = fl_value_get_string(id_value);
      }
      FlValue* size_value = fl_value_lookup_string(args, "size");
      if (size_value != nullptr &&
          fl_value_get_type(size_value) == FL_VALUE_TYPE_INT) {
        size = static_cast<int>(fl_value_get_int(size_value));
      }
    }
    if (size < 16 || size > 256) size = 64;
    g_autoptr(FlValue) result = ResolveApp(id, size);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}
