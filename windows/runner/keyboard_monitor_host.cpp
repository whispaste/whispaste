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

// Reads a string entry from an EncodableMap, or "" if absent.
std::string ReadString(const EncodableMap* map, const char* key) {
  if (!map) return "";
  auto it = map->find(EncodableValue(key));
  if (it == map->end()) return "";
  if (auto* s = std::get_if<std::string>(&it->second)) return *s;
  return "";
}

// Derives the Win32 virtual-key code of the watched MAIN key from the Dart
// payload. Returns 0 if it cannot be mapped (the monitor then matches nothing).
//
// v1 handles the common case (A–Z / 0–9, whose VK equals the ASCII uppercase)
// and falls back to the active keyboard layout for other single characters via
// VkKeyScan. Layout-dependent OEM keys and F-keys still need scan-code matching
// — to be finalised on the Windows box where real RawInput can be observed
// (see issue #39); a letter hotkey exercises the full plumbing meanwhile.
USHORT DeriveWatchedVk(const std::string& key_label) {
  if (key_label.size() == 1) {
    char c = key_label[0];
    if (c >= 'a' && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
    if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
      return static_cast<USHORT>(c);
    }
    const SHORT scan = ::VkKeyScanW(static_cast<wchar_t>(
        static_cast<unsigned char>(key_label[0])));
    if (scan != -1) {
      return static_cast<USHORT>(scan & 0xFF);
    }
  }
  return 0;
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
    const std::string key_label = ReadString(map, "keyLabel");
    watched_vk_ = DeriveWatchedVk(key_label);
    const bool ok = EnsureRawInputRegistered();
    // Success even if the VK could not be derived: registration still works and
    // a later re-start with a mappable key will begin matching.
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
  // RI_KEY_BREAK marks a key-UP (release).
  const bool is_break = (kb.Flags & RI_KEY_BREAK) != 0;
  if (kb.VKey == watched_vk_ && is_break) {
    // Window-proc thread == platform thread, so InvokeMethod is safe here.
    channel_->InvokeMethod("onKeyUp", nullptr);
  }
}
