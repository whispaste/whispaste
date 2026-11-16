// Native right-click menu of the floating button and the floating overlay
// (#393).
//
// Both hosts receive the menu as a tree in the wire format of
// lib/services/app_commands/native_menu_adapter.dart:
//   setContextMenuItems{items:[{id,label,enabled,checked?,shortcut?,
//                               children?} | {type:"separator"}],
//                       appearance:"system"|"light"|"dark"}
// and show it as a Win32 popup menu with submenus, checkmarks, greyed
// entries, right-aligned shortcuts and the app's light or dark appearance.
#ifndef RUNNER_NATIVE_CONTEXT_MENU_H_
#define RUNNER_NATIVE_CONTEXT_MENU_H_

#include <windows.h>

#include <flutter/encodable_value.h>

#include <optional>
#include <string>
#include <vector>

struct NativeMenuEntry {
  bool separator = false;
  std::string id;
  std::wstring label;
  std::wstring shortcut;
  bool enabled = true;
  // -1: plain entry, 0: unchecked checkmark entry, 1: checked.
  int checked = -1;
  std::vector<NativeMenuEntry> children;
};

enum class NativeMenuAppearance { kSystem, kLight, kDark };

struct NativeMenu {
  std::vector<NativeMenuEntry> entries;
  NativeMenuAppearance appearance = NativeMenuAppearance::kSystem;

  bool empty() const { return entries.empty(); }
};

// Parses the setContextMenuItems arguments. Malformed entries are skipped;
// malformed arguments give an empty menu.
NativeMenu ParseNativeMenu(const flutter::EncodableValue* args);

// Shows [menu] at the cursor, owned by [owner], and returns the id of the
// chosen entry, or nothing when the menu was dismissed. Blocks until then.
std::optional<std::string> ShowNativeMenu(HWND owner, const NativeMenu& menu);

#endif  // RUNNER_NATIVE_CONTEXT_MENU_H_
