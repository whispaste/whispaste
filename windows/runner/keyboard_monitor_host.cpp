#include "keyboard_monitor_host.h"

#include <flutter/encodable_value.h>

#include <string>
#include <vector>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.keyboard_monitor";

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

bool KeyDown(int vk) { return (::GetAsyncKeyState(vk) & 0x8000) != 0; }

}  // namespace

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
  UnregisterRawInput();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

bool KeyboardMonitorHost::RequiredModifiersDown() const {
  if (req_ctrl_ && !KeyDown(VK_CONTROL)) return false;
  if (req_alt_ && !KeyDown(VK_MENU)) return false;
  if (req_shift_ && !KeyDown(VK_SHIFT)) return false;
  if (req_meta_ && !(KeyDown(VK_LWIN) || KeyDown(VK_RWIN))) return false;
  return true;
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
    const auto* args = call.arguments();
    const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
    req_ctrl_ = req_alt_ = req_shift_ = req_meta_ = false;
    watched_vk_ = 0;
    if (map) {
      auto it = map->find(EncodableValue("modifiers"));
      if (it != map->end()) {
        if (const auto* mods = std::get_if<EncodableList>(&it->second)) {
          for (const auto& m : *mods) {
            if (const auto* name = std::get_if<std::string>(&m)) {
              if (*name == "control") req_ctrl_ = true;
              else if (*name == "alt") req_alt_ = true;
              else if (*name == "shift") req_shift_ = true;
              else if (*name == "meta") req_meta_ = true;
            }
          }
        }
      }
    }
    const bool ok = EnsureRawInputRegistered();
    result->Success(EncodableValue(ok));
    return;
  }

  if (method == "stop") {
    watched_vk_ = 0;
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
  if (destroyed_) return;

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
  const USHORT vk = kb.VKey;
  // 0xFF is an escaped/fake key (e.g. part of an extended sequence); ignore.
  if (vk == 0 || vk == 0xFF || IsModifierVk(vk)) return;

  const bool is_break = (kb.Flags & RI_KEY_BREAK) != 0;

  if (!is_break) {
    // A non-modifier key went down. If the hotkey's modifiers are all held,
    // this is (the latest candidate for) the hotkey's main key — arm its
    // release. Layout-independent: we never map a key name to a VK.
    if (RequiredModifiersDown()) {
      watched_vk_ = vk;
    }
  } else if (watched_vk_ != 0 && vk == watched_vk_) {
    // The armed main key was released → report the hotkey key-up.
    watched_vk_ = 0;
    // Window-proc thread == platform thread, so InvokeMethod is safe here.
    channel_->InvokeMethod("onKeyUp", nullptr);
  }
}
