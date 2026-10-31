#include "keyboard_monitor_host.h"

#include <flutter/encodable_value.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.keyboard_monitor";

// VK_UNASSIGNED: no application binds it, so a press of it is harmless for
// the shell and the app next to it (PAR-036 menu mask).
constexpr WORD kMenuMaskVk = 0xE8;

// Modifier bits recorded when a hold session is armed (KeyboardMonitorHost::
// armed_mods_). Ctrl and Alt together form AltGr.
constexpr uint8_t kArmedCtrl = 0x1;
constexpr uint8_t kArmedAlt = 0x2;
constexpr uint8_t kArmedShift = 0x4;
constexpr uint8_t kArmedWin = 0x8;

// Raw Input reports Ctrl and Alt with the generic virtual keys (VK_CONTROL,
// VK_MENU) on both sides. The right-hand key carries the RI_KEY_E0 flag, so
// the side is read from that flag. Shift may arrive as VK_SHIFT; its side is
// in the scan code (0x36 right, 0x2A left). Win arrives side-specific.
USHORT SideSpecificVk(const RAWKEYBOARD& kb) {
  const bool e0 = (kb.Flags & RI_KEY_E0) != 0;
  if (kb.VKey == VK_CONTROL) return e0 ? VK_RCONTROL : VK_LCONTROL;
  if (kb.VKey == VK_MENU) return e0 ? VK_RMENU : VK_LMENU;
  if (kb.VKey == VK_SHIFT) return kb.MakeCode == 0x36 ? VK_RSHIFT : VK_LSHIFT;
  return kb.VKey;
}

// A lone tap of Win opens the start menu, a lone tap of Alt focuses the menu
// bar of the window in front. Watching one of them needs the release mask.
bool NeedsMenuMask(USHORT vk) {
  return vk == VK_LWIN || vk == VK_RWIN || vk == VK_LMENU || vk == VK_RMENU;
}

// True for virtual-keys that are modifiers/locks — these never become the
// watched "main key" of a hotkey.
bool IsModifierVk(USHORT vk) {
  switch (vk) {
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT:
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL:
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU:
    case VK_LWIN:
    case VK_RWIN:
    case VK_CAPITAL:
    case VK_NUMLOCK:
    case VK_SCROLL:
      return true;
    default:
      return false;
  }
}

// Longest press that is still reported with its length. A longer gap is not a
// tap, so it is passed on as unknown.
constexpr DWORD kMaxPressMs = 60000;

// Argument of the native `onKeyUp`: {pressMs} when the press start is known and
// the length is plausible, otherwise nullptr (Dart reads that as unknown).
std::unique_ptr<EncodableValue> PressArgs(bool down_known, DWORD elapsed_ms) {
  if (!down_known || elapsed_ms > kMaxPressMs) return nullptr;
  EncodableMap map;
  map[EncodableValue("pressMs")] = EncodableValue(static_cast<int>(elapsed_ms));
  return std::make_unique<EncodableValue>(std::move(map));
}

}  // namespace

KeyboardMonitorHost* KeyboardMonitorHost::menu_mask_owner_ = nullptr;
KeyboardMonitorHost* KeyboardMonitorHost::repeat_mask_owner_ = nullptr;

KeyboardMonitorHost::KeyboardMonitorHost(flutter::FlutterEngine* engine,
                                         HWND owner)
    : engine_(engine), owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

KeyboardMonitorHost::~KeyboardMonitorHost() { Destroy(); }

void KeyboardMonitorHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;
  watched_vk_ = 0;
  hotkey_vk_ = 0;
  armed_down_known_ = false;
  UninstallMenuMaskHook();
  UninstallRepeatMaskHook();
  UnregisterRawInput();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void KeyboardMonitorHost::SendMenuMask() {
  // Press and release the unassigned key so the shell sees Win used as part
  // of a combination instead of a lone tap. Called from the low-level hook,
  // before the Win release is passed on. The hook ignores injected events,
  // so this key never feeds back into the tracker.
  INPUT inputs[2] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = kMenuMaskVk;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = kMenuMaskVk;
  inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
  ::SendInput(2, inputs, sizeof(INPUT));
}

void KeyboardMonitorHost::UpdateMenuMaskHook() {
  const bool wanted = !destroyed_ && NeedsMenuMask(watched_mod_vk_);
  if (wanted == (menu_mask_hook_ != nullptr)) return;
  if (!wanted) {
    UninstallMenuMaskHook();
    return;
  }
  menu_mask_owner_ = this;
  menu_mask_hook_ = ::SetWindowsHookExW(
      WH_KEYBOARD_LL, &KeyboardMonitorHost::MenuMaskHookProc,
      ::GetModuleHandleW(nullptr), 0);
  if (!menu_mask_hook_) {
    // Without the hook the release is simply not masked; hold-to-talk works.
    menu_mask_owner_ = nullptr;
  }
}

void KeyboardMonitorHost::UninstallMenuMaskHook() {
  if (menu_mask_hook_ != nullptr) {
    ::UnhookWindowsHookEx(menu_mask_hook_);
    menu_mask_hook_ = nullptr;
  }
  if (menu_mask_owner_ == this) menu_mask_owner_ = nullptr;
  menu_mask_.Reset();
}

LRESULT CALLBACK KeyboardMonitorHost::MenuMaskHookProc(int code, WPARAM wparam,
                                                       LPARAM lparam) {
  KeyboardMonitorHost* self = menu_mask_owner_;
  if (self != nullptr && code == HC_ACTION) {
    self->OnMenuMaskHookKey(
        wparam, *reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam));
  }
  // Always pass the event on, after any mask has been queued above, so the
  // mask lands before the Win release reaches the shell.
  return ::CallNextHookEx(self != nullptr ? self->menu_mask_hook_ : nullptr,
                          code, wparam, lparam);
}

void KeyboardMonitorHost::OnMenuMaskHookKey(WPARAM wparam,
                                            const KBDLLHOOKSTRUCT& key) {
  // Injected events (our own mask and any automation) never count.
  if ((key.flags & LLKHF_INJECTED) != 0) return;
  const bool is_down = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
  const bool is_up = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
  if (key.vkCode == watched_mod_vk_) {
    if (is_down) {
      menu_mask_.OnWatchedDown();
    } else if (is_up && menu_mask_.OnWatchedUp()) {
      SendMenuMask();
    }
    return;
  }
  if (is_down) menu_mask_.OnOtherKeyDown();
}

void KeyboardMonitorHost::HandleHotkeyDown(LPARAM lparam) {
  if (destroyed_) return;
  // WM_HOTKEY: HIWORD(lparam) is the virtual key, GetMessageTime() the time
  // the key went down.
  hotkey_vk_ = static_cast<USHORT>(HIWORD(lparam));
  hotkey_down_ms_ = static_cast<DWORD>(::GetMessageTime());
}

void KeyboardMonitorHost::UpdateRepeatMaskHook() {
  // Needed only while a modifier-armed session swallows repeats. watched_vk_
  // alone is not enough: a session that ended by the gap rule keeps it.
  const bool wanted = !destroyed_ && watched_vk_ != 0 && armed_mods_ != 0;
  if (wanted == (repeat_mask_hook_ != nullptr)) return;
  if (!wanted) {
    UninstallRepeatMaskHook();
    return;
  }
  repeat_mask_owner_ = this;
  repeat_mask_hook_ = ::SetWindowsHookExW(
      WH_KEYBOARD_LL, &KeyboardMonitorHost::RepeatMaskHookProc,
      ::GetModuleHandleW(nullptr), 0);
  if (!repeat_mask_hook_) {
    // Without the hook the repeats reach the app as before; the session still
    // ends on the RawInput release.
    repeat_mask_owner_ = nullptr;
  }
}

void KeyboardMonitorHost::UninstallRepeatMaskHook() {
  if (repeat_mask_hook_ != nullptr) {
    ::UnhookWindowsHookEx(repeat_mask_hook_);
    repeat_mask_hook_ = nullptr;
  }
  if (repeat_mask_owner_ == this) repeat_mask_owner_ = nullptr;
}

LRESULT CALLBACK KeyboardMonitorHost::RepeatMaskHookProc(int code,
                                                         WPARAM wparam,
                                                         LPARAM lparam) {
  KeyboardMonitorHost* self = repeat_mask_owner_;
  // Taken before SwallowsRepeat, which may remove this hook.
  const HHOOK next = self != nullptr ? self->repeat_mask_hook_ : nullptr;
  if (self != nullptr && code == HC_ACTION &&
      self->SwallowsRepeat(wparam,
                           *reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam))) {
    return 1;
  }
  return ::CallNextHookEx(next, code, wparam, lparam);
}

uint8_t KeyboardMonitorHost::HeldModifierMask() {
  uint8_t mask = 0;
  auto down = [](int vk) { return (::GetAsyncKeyState(vk) & 0x8000) != 0; };
  if (down(VK_CONTROL) || down(VK_LCONTROL) || down(VK_RCONTROL)) {
    mask |= kArmedCtrl;
  }
  if (down(VK_MENU) || down(VK_LMENU) || down(VK_RMENU)) mask |= kArmedAlt;
  if (down(VK_SHIFT) || down(VK_LSHIFT) || down(VK_RSHIFT)) {
    mask |= kArmedShift;
  }
  if (down(VK_LWIN) || down(VK_RWIN)) mask |= kArmedWin;
  return mask;
}

bool KeyboardMonitorHost::SwallowsRepeat(WPARAM wparam,
                                         const KBDLLHOOKSTRUCT& key) {
  if (watched_vk_ == 0 || key.vkCode != watched_vk_) return false;
  // Key-ups pass and do not touch watched_vk_: the RawInput break reports the
  // release, and this hook sees the key-up first.
  if (wparam != WM_KEYDOWN && wparam != WM_SYSKEYDOWN) return false;
  const bool was_seen = main_down_seen_;
  const DWORD gap = key.time - last_main_down_ms_;
  main_down_seen_ = true;
  last_main_down_ms_ = key.time;
  // Only once a modifier of the hotkey was released: while the combination is
  // intact, the key-down belongs to RegisterHotKey and must reach it.
  if (armed_mods_ == 0 || (armed_mods_ & HeldModifierMask()) == armed_mods_) {
    return false;
  }
  // Auto-repeat follows the press after one delay and then every interval. A
  // longer gap means a new press whose key-up was lost: end the session and
  // let this key-down through.
  if (was_seen && gap > repeat_gap_limit_ms_) {
    EndRepeatSession();
    return false;
  }
  // Keep the menu mask's view identical to a passed-through key-down.
  if ((key.flags & LLKHF_INJECTED) == 0) menu_mask_.OnOtherKeyDown();
  return true;
}

void KeyboardMonitorHost::EndRepeatSession() {
  // Stops swallowing only. watched_vk_ stays, so the RawInput release still
  // reports onKeyUp for this hold; Dart ignores it when nothing records.
  armed_mods_ = 0;
  UpdateRepeatMaskHook();
}

DWORD KeyboardMonitorHost::RepeatGapLimitMs() {
  DWORD delay_setting = 1;  // 0..3: 250, 500, 750 or 1000 ms before a repeat
  DWORD speed_setting = 31;  // 0..31: 2.5 to 30 repeats per second
  ::SystemParametersInfoW(SPI_GETKEYBOARDDELAY, 0, &delay_setting, 0);
  ::SystemParametersInfoW(SPI_GETKEYBOARDSPEED, 0, &speed_setting, 0);
  const double delay_ms = 250.0 * (delay_setting + 1);
  const double repeats_per_s = 2.5 + 27.5 * speed_setting / 31.0;
  const double interval_ms = 1000.0 / repeats_per_s;
  // The first repeat comes one delay after the press, later ones one interval
  // apart. Four intervals of slack absorb scheduling jitter.
  return static_cast<DWORD>(delay_ms + 4.0 * interval_ms);
}

bool KeyboardMonitorHost::ArmRelease(uint8_t hotkey_mods) {
  // The hotkey just fired, so its main key is physically down now. Find the
  // first non-modifier key GetAsyncKeyState reports as down and watch for its
  // release. GetAsyncKeyState reflects true key state even though RegisterHotKey
  // suppressed the key's DOWN from the RawInput stream.
  watched_vk_ = 0;
  for (int vk = 0x08; vk <= 0xFE; ++vk) {
    if (IsModifierVk(static_cast<USHORT>(vk))) continue;
    if ((::GetAsyncKeyState(vk) & 0x8000) != 0) {
      watched_vk_ = static_cast<USHORT>(vk);
      break;
    }
  }
  // The hotkey's own modifiers, not the ones held right now: a modifier that
  // was already released before this call must still count as broken.
  armed_mods_ = watched_vk_ != 0 ? hotkey_mods : 0;
  main_down_seen_ = false;
  repeat_gap_limit_ms_ = RepeatGapLimitMs();
  UpdateRepeatMaskHook();
  // The press start is known only when the armed key is the hotkey key that
  // WM_HOTKEY timed.
  armed_down_known_ = watched_vk_ != 0 && watched_vk_ == hotkey_vk_;
  armed_down_ms_ = hotkey_down_ms_;
  return watched_vk_ != 0;
}

std::string KeyboardMonitorHost::ResolveLayoutLabel(int vk) {
  if (vk <= 0) return "";
  const HKL hkl = ::GetKeyboardLayout(0);
  const UINT sc = ::MapVirtualKeyExW(static_cast<UINT>(vk), MAPVK_VK_TO_VSC, hkl);
  BYTE keystate[256] = {0};  // no modifiers held → the bare key char
  wchar_t buf[8] = {0};
  const int n =
      ::ToUnicodeEx(static_cast<UINT>(vk), sc, keystate, buf, 8, 0, hkl);
  if (n < 0) {
    // Dead key (e.g. ^ ` ´): the accent is in buf[0], but the call armed the
    // layout's dead-key state — call again to flush it so live typing is not
    // affected.
    wchar_t flush[8] = {0};
    ::ToUnicodeEx(static_cast<UINT>(vk), sc, keystate, flush, 8, 0, hkl);
  }
  if (buf[0] == 0) return "";

  char utf8[8] = {0};
  const int len = ::WideCharToMultiByte(CP_UTF8, 0, buf, 1, utf8,
                                        sizeof(utf8), nullptr, nullptr);
  if (len <= 0) return "";
  return std::string(utf8, len);
}

int KeyboardMonitorHost::ResolveLiveVirtualKey(int scan_code) {
  if (scan_code <= 0) return 0;
  const HKL hkl = ::GetKeyboardLayout(0);
  return static_cast<int>(::MapVirtualKeyExW(
      static_cast<UINT>(scan_code), MAPVK_VSC_TO_VK_EX, hkl));
}

void KeyboardMonitorHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "KeyboardMonitorHost is destroyed");
    return;
  }

  const auto& method = call.method_name();

  if (method == "start") {
    watched_vk_ = 0;
    watched_mod_vk_ = 0;
    UpdateMenuMaskHook();
    UpdateRepeatMaskHook();
    result->Success(EncodableValue(EnsureRawInputRegistered()));
    return;
  }

  if (method == "watchModifier") {
    const auto* args = call.arguments();
    const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
    std::string key;
    if (map) {
      auto it = map->find(EncodableValue("key"));
      if (it != map->end()) {
        if (const auto* v = std::get_if<std::string>(&it->second)) key = *v;
      }
    }
    // Same names as the macOS and Linux hosts; Fn has no Windows key.
    USHORT vk = 0;
    if (key == "leftShift") vk = VK_LSHIFT;
    else if (key == "rightShift") vk = VK_RSHIFT;
    else if (key == "leftControl") vk = VK_LCONTROL;
    else if (key == "rightControl") vk = VK_RCONTROL;
    else if (key == "leftAlt") vk = VK_LMENU;
    else if (key == "rightAlt") vk = VK_RMENU;
    else if (key == "leftMeta") vk = VK_LWIN;
    else if (key == "rightMeta") vk = VK_RWIN;
    if (vk == 0) {
      result->Error("INVALID_ARGS", "Unknown modifier key name");
      return;
    }
    watched_mod_vk_ = vk;
    UpdateMenuMaskHook();
    const bool registered = EnsureRawInputRegistered();
    if (!registered) {
      // Not observed, so the key is no longer the trigger: the Win key must
      // open the start menu again instead of staying masked (PAR-055).
      watched_mod_vk_ = 0;
      UpdateMenuMaskHook();
    }
    result->Success(EncodableValue(registered));
    return;
  }

  if (method == "armRelease") {
    // The hotkey definition's modifier bits (kArmed*), sent by Dart. Only the
    // bits this host knows are kept; a missing argument arms no modifiers.
    uint8_t mods = 0;
    const auto* args = call.arguments();
    const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
    if (map) {
      auto it = map->find(EncodableValue("modifiers"));
      if (it != map->end()) {
        if (const auto* v = std::get_if<int>(&it->second)) {
          mods = static_cast<uint8_t>(*v & (kArmedCtrl | kArmedAlt |
                                            kArmedShift | kArmedWin));
        }
      }
    }
    // Reply with whether the main key is still held, so Dart can end a press
    // whose release already happened (on-screen keyboard click).
    result->Success(EncodableValue(ArmRelease(mods)));
    return;
  }

  if (method == "resolveLayoutLabel") {
    const auto* args = call.arguments();
    const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
    int vk = 0;
    if (map) {
      auto it = map->find(EncodableValue("vk"));
      if (it != map->end()) {
        if (const auto* v = std::get_if<int>(&it->second)) vk = *v;
      }
    }
    result->Success(EncodableValue(ResolveLayoutLabel(vk)));
    return;
  }

  if (method == "resolveLiveVirtualKey") {
    const auto* args = call.arguments();
    const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
    int scan_code = 0;
    if (map) {
      auto it = map->find(EncodableValue("scanCode"));
      if (it != map->end()) {
        if (const auto* v = std::get_if<int>(&it->second)) scan_code = *v;
      }
    }
    result->Success(EncodableValue(ResolveLiveVirtualKey(scan_code)));
    return;
  }

  if (method == "stop") {
    watched_vk_ = 0;
    watched_mod_vk_ = 0;
    hotkey_vk_ = 0;
    armed_down_known_ = false;
    UpdateMenuMaskHook();
    UpdateRepeatMaskHook();
    UnregisterRawInput();
    result->Success();
    return;
  }

  result->NotImplemented();
}

bool KeyboardMonitorHost::EnsureRawInputRegistered() {
  if (raw_input_registered_) return true;
  if (!owner_ || !::IsWindow(owner_)) return false;

  RAWINPUTDEVICE rid = {};
  rid.usUsagePage = 0x01;  // Generic Desktop Controls
  rid.usUsage = 0x06;      // Keyboard
  // RIDEV_INPUTSINK: receive WM_INPUT even when the window is not foreground —
  // required for a global push-to-talk release. No RIDEV_NOLEGACY, so we do NOT
  // suppress normal key delivery (observe-only).
  rid.dwFlags = RIDEV_INPUTSINK;
  rid.hwndTarget = owner_;

  raw_input_registered_ =
      ::RegisterRawInputDevices(&rid, 1, sizeof(RAWINPUTDEVICE)) != FALSE;
  return raw_input_registered_;
}

void KeyboardMonitorHost::UnregisterRawInput() {
  if (!raw_input_registered_) return;
  RAWINPUTDEVICE rid = {};
  rid.usUsagePage = 0x01;
  rid.usUsage = 0x06;
  rid.dwFlags = RIDEV_REMOVE;
  rid.hwndTarget = nullptr;  // must be null for RIDEV_REMOVE
  ::RegisterRawInputDevices(&rid, 1, sizeof(RAWINPUTDEVICE));
  raw_input_registered_ = false;
}

void KeyboardMonitorHost::HandleRawInput(HRAWINPUT raw_input) {
  if (destroyed_ || (watched_vk_ == 0 && watched_mod_vk_ == 0)) return;

  UINT size = 0;
  if (::GetRawInputData(raw_input, RID_INPUT, nullptr, &size,
                        sizeof(RAWINPUTHEADER)) != 0) {
    return;
  }
  if (size == 0) return;

  std::vector<BYTE> buffer(size);
  if (::GetRawInputData(raw_input, RID_INPUT, buffer.data(), &size,
                        sizeof(RAWINPUTHEADER)) != size) {
    return;
  }

  const RAWINPUT* ri = reinterpret_cast<const RAWINPUT*>(buffer.data());
  if (ri->header.dwType != RIM_TYPEKEYBOARD) return;

  const RAWKEYBOARD& kb = ri->data.keyboard;
  const bool is_break = (kb.Flags & RI_KEY_BREAK) != 0;

  // The menu mask (PAR-036) is not decided here: the low-level hook sends it
  // before the shell sees the Win release. This path stays observe-only.
  if (watched_mod_vk_ != 0) {
    const USHORT vk = SideSpecificVk(kb);
    // AltGr arrives as a synthetic left Ctrl plus right Alt; that Ctrl is
    // part of the watched right Alt, not a chord.
    const bool altgr_ctrl =
        watched_mod_vk_ == VK_RMENU && vk == VK_LCONTROL;
    if (vk == watched_mod_vk_) {
      channel_->InvokeMethod(is_break ? "onModifierUp" : "onModifierDown",
                             nullptr);
    } else if (!is_break && kb.VKey != kMenuMaskVk && !altgr_ctrl &&
               kb.VKey != VK_CAPITAL && kb.VKey != VK_NUMLOCK &&
               kb.VKey != VK_SCROLL) {
      // Any other key, another modifier too (Shift + Ctrl …), makes the
      // press a chord and no gesture.
      channel_->InvokeMethod("onOtherKey", nullptr);
    }
  }

  // Only the RELEASE is matched: arming happens via ArmRelease() because
  // RegisterHotKey hides the hotkey key's DOWN from RawInput (#39).
  if (watched_vk_ != 0 && is_break && kb.VKey == watched_vk_) {
    // Press length from message times, so a busy UI thread does not stretch it.
    const DWORD up_ms = static_cast<DWORD>(::GetMessageTime());
    auto args = PressArgs(armed_down_known_, up_ms - armed_down_ms_);
    armed_down_known_ = false;
    watched_vk_ = 0;
    UpdateRepeatMaskHook();
    // Window-proc thread == platform thread, so InvokeMethod is safe here.
    channel_->InvokeMethod("onKeyUp", std::move(args));
  }
}
