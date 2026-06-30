#include "keyboard_monitor_host.h"

#include <flutter/encodable_value.h>

#include <string>
#include <vector>

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

void KeyboardMonitorHost::ArmRelease() {
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
    result->Success(EncodableValue(EnsureRawInputRegistered()));
    return;
  }

  if (method == "armRelease") {
    ArmRelease();
    result->Success();
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
  if (destroyed_ || watched_vk_ == 0) return;

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
  // Only the RELEASE is matched: arming happens via ArmRelease() because
  // RegisterHotKey hides the hotkey key's DOWN from RawInput (#39).
  if (is_break && kb.VKey == watched_vk_) {
    watched_vk_ = 0;
    // Window-proc thread == platform thread, so InvokeMethod is safe here.
    channel_->InvokeMethod("onKeyUp", nullptr);
  }
}
