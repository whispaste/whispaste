#include "native_context_menu.h"

#include <utility>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

// First command id; the entry index follows it.
constexpr UINT kFirstCommand = 1000;

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  // 0 means the UTF-8 is invalid; show nothing rather than garbage.
  if (len <= 0) return std::wstring();
  std::wstring wide(len - 1, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), len);
  return wide;
}

// A single "&" marks the access key in a Win32 menu label; device names and
// recording previews must show it literally.
std::wstring EscapeAmpersands(const std::wstring& text) {
  std::wstring out;
  out.reserve(text.size());
  for (wchar_t c : text) {
    if (c == L'&') out.push_back(L'&');
    out.push_back(c);
  }
  return out;
}

const EncodableValue* Field(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string StringField(const EncodableMap& map, const char* key) {
  const EncodableValue* v = Field(map, key);
  const auto* s = v ? std::get_if<std::string>(v) : nullptr;
  return s ? *s : std::string();
}

std::vector<NativeMenuEntry> ParseEntries(const EncodableList& list) {
  std::vector<NativeMenuEntry> entries;
  for (const auto& value : list) {
    const auto* map = std::get_if<EncodableMap>(&value);
    if (!map) continue;
    NativeMenuEntry entry;
    if (StringField(*map, "type") == "separator") {
      entry.separator = true;
      entries.push_back(std::move(entry));
      continue;
    }
    entry.id = StringField(*map, "id");
    entry.label = Utf8ToWide(StringField(*map, "label"));
    if (entry.id.empty() || entry.label.empty()) continue;
    entry.shortcut = Utf8ToWide(StringField(*map, "shortcut"));
    if (const EncodableValue* v = Field(*map, "enabled")) {
      if (const auto* b = std::get_if<bool>(v)) entry.enabled = *b;
    }
    if (const EncodableValue* v = Field(*map, "checked")) {
      if (const auto* b = std::get_if<bool>(v)) entry.checked = *b ? 1 : 0;
    }
    if (const EncodableValue* v = Field(*map, "children")) {
      if (const auto* children = std::get_if<EncodableList>(v)) {
        entry.children = ParseEntries(*children);
      }
    }
    entries.push_back(std::move(entry));
  }
  return entries;
}

// Fills [menu] with [entries]; every action gets the next command id and its
// menu id is recorded in [ids] at that index.
void AppendEntries(HMENU menu, const std::vector<NativeMenuEntry>& entries,
                   std::vector<std::string>& ids) {
  for (const auto& entry : entries) {
    if (entry.separator) {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    std::wstring text = EscapeAmpersands(entry.label);
    if (!entry.shortcut.empty()) {
      // A tab right-aligns the rest of the label as the shortcut column.
      text += L"\t" + EscapeAmpersands(entry.shortcut);
    }
    UINT flags = MF_STRING | (entry.enabled ? MF_ENABLED : MF_GRAYED);
    if (!entry.children.empty()) {
      HMENU submenu = CreatePopupMenu();
      AppendEntries(submenu, entry.children, ids);
      // The parent menu owns the submenu and destroys it with itself.
      AppendMenuW(menu, flags | MF_POPUP, reinterpret_cast<UINT_PTR>(submenu),
                  text.c_str());
      continue;
    }
    if (entry.checked == 1) flags |= MF_CHECKED;
    UINT command = kFirstCommand + static_cast<UINT>(ids.size());
    ids.push_back(entry.id);
    AppendMenuW(menu, flags, command, text.c_str());
  }
}

// Undocumented but stable uxtheme exports (Windows 10 1903+, used by the
// shell and by Explorer's own menus): ordinal 133 AllowDarkModeForWindow,
// 135 SetPreferredAppMode, 136 FlushMenuThemes.
enum class PreferredAppMode { kDefault = 0, kAllowDark, kForceDark, kForceLight };
using AllowDarkModeForWindowFn = BOOL(WINAPI*)(HWND, BOOL);
using SetPreferredAppModeFn = PreferredAppMode(WINAPI*)(PreferredAppMode);
using FlushMenuThemesFn = void(WINAPI*)();

bool SupportsPreferredAppMode() {
  using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  if (!ntdll) return false;
  auto get_version = reinterpret_cast<RtlGetVersionFn>(
      GetProcAddress(ntdll, "RtlGetVersion"));
  if (!get_version) return false;
  OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  if (get_version(&info) != 0) return false;
  // Before 1903 (build 18362) ordinal 135 had another signature.
  return info.dwMajorVersion > 10 ||
         (info.dwMajorVersion == 10 && info.dwBuildNumber >= 18362);
}

// Popup menus take the process-wide app mode, so it is set before every
// popup. Without the exports the menu keeps the system's light look.
void ApplyMenuAppearance(HWND owner, NativeMenuAppearance appearance) {
  static const bool supported = SupportsPreferredAppMode();
  if (!supported) return;
  static HMODULE uxtheme =
      LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!uxtheme) return;
  static auto allow_for_window = reinterpret_cast<AllowDarkModeForWindowFn>(
      GetProcAddress(uxtheme, MAKEINTRESOURCEA(133)));
  static auto set_mode = reinterpret_cast<SetPreferredAppModeFn>(
      GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
  static auto flush = reinterpret_cast<FlushMenuThemesFn>(
      GetProcAddress(uxtheme, MAKEINTRESOURCEA(136)));
  if (!set_mode || !flush) return;
  PreferredAppMode mode = PreferredAppMode::kAllowDark;
  if (appearance == NativeMenuAppearance::kDark) {
    mode = PreferredAppMode::kForceDark;
  } else if (appearance == NativeMenuAppearance::kLight) {
    mode = PreferredAppMode::kForceLight;
  }
  if (allow_for_window && owner) allow_for_window(owner, TRUE);
  set_mode(mode);
  flush();
}

}  // namespace

NativeMenu ParseNativeMenu(const EncodableValue* args) {
  NativeMenu menu;
  const auto* map = args ? std::get_if<EncodableMap>(args) : nullptr;
  if (!map) return menu;
  if (const EncodableValue* items = Field(*map, "items")) {
    if (const auto* list = std::get_if<EncodableList>(items)) {
      menu.entries = ParseEntries(*list);
    }
  }
  const std::string appearance = StringField(*map, "appearance");
  if (appearance == "dark") {
    menu.appearance = NativeMenuAppearance::kDark;
  } else if (appearance == "light") {
    menu.appearance = NativeMenuAppearance::kLight;
  }
  return menu;
}

std::optional<std::string> ShowNativeMenu(HWND owner, const NativeMenu& menu) {
  if (menu.empty()) return std::nullopt;
  ApplyMenuAppearance(owner, menu.appearance);

  HMENU popup = CreatePopupMenu();
  std::vector<std::string> ids;
  AppendEntries(popup, menu.entries, ids);

  POINT pt;
  GetCursorPos(&pt);
  // TPM_RETURNCMD returns the chosen command instead of posting WM_COMMAND,
  // TPM_RIGHTBUTTON lets the right button pick an entry as well. The owner is
  // the non-activating button/overlay window, so the target app keeps focus.
  int cmd = TrackPopupMenu(
      popup, TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN | TPM_RIGHTBUTTON,
      pt.x, pt.y, 0, owner, nullptr);
  DestroyMenu(popup);

  if (cmd < static_cast<int>(kFirstCommand)) return std::nullopt;
  size_t index = static_cast<size_t>(cmd) - kFirstCommand;
  if (index >= ids.size()) return std::nullopt;
  return ids[index];
}
