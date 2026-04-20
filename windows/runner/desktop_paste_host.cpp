#include "desktop_paste_host.h"

#include <flutter/encodable_value.h>

#include <chrono>
#include <thread>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.desktop_paste";

int GetInt(const EncodableMap& map, const std::string& key, int fallback = 0) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (auto* l = std::get_if<int64_t>(&it->second))
    return static_cast<int>(*l);
  return fallback;
}

}  // namespace

DesktopPasteHost::DesktopPasteHost(flutter::FlutterEngine* engine, HWND owner)
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

DesktopPasteHost::~DesktopPasteHost() { Destroy(); }

void DesktopPasteHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;
  target_window_ = nullptr;

  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

void DesktopPasteHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "DesktopPasteHost is destroyed");
    return;
  }

  const auto& method = call.method_name();
  const auto* args = call.arguments();
  const EncodableMap* map =
      args ? std::get_if<EncodableMap>(args) : nullptr;

  if (method == "captureTarget") {
    result->Success(EncodableValue(CaptureTargetWindow()));
    return;
  }

  if (method == "pasteClipboard") {
    const int delay_ms = map ? GetInt(*map, "delayMs", 0) : 0;
    result->Success(EncodableValue(PasteClipboard(delay_ms)));
    return;
  }

  if (method == "destroy") {
    Destroy();
    result->Success();
    return;
  }

  result->NotImplemented();
}

bool DesktopPasteHost::CaptureTargetWindow() {
  HWND foreground = ::GetForegroundWindow();
  if (!foreground) {
    target_window_ = nullptr;
    return false;
  }

  DWORD process_id = 0;
  ::GetWindowThreadProcessId(foreground, &process_id);
  if (foreground == owner_ || process_id == ::GetCurrentProcessId()) {
    target_window_ = nullptr;
    return false;
  }

  target_window_ = foreground;
  return true;
}

bool DesktopPasteHost::PasteClipboard(int delay_ms) {
  if (!target_window_ || !::IsWindow(target_window_)) {
    return false;
  }

  if (delay_ms > 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }

  if (!BringTargetToForeground()) {
    return false;
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  return SendPasteShortcut();
}

bool DesktopPasteHost::BringTargetToForeground() const {
  if (!target_window_ || !::IsWindow(target_window_)) {
    return false;
  }

  if (::IsIconic(target_window_)) {
    ::ShowWindow(target_window_, SW_RESTORE);
  }

  HWND foreground = ::GetForegroundWindow();
  const DWORD foreground_thread =
      foreground ? ::GetWindowThreadProcessId(foreground, nullptr) : 0;
  const DWORD target_thread =
      ::GetWindowThreadProcessId(target_window_, nullptr);

  bool attached = false;
  if (foreground_thread != 0 && target_thread != 0 &&
      foreground_thread != target_thread) {
    attached =
        ::AttachThreadInput(foreground_thread, target_thread, TRUE) != FALSE;
  }

  const bool activated = ::SetForegroundWindow(target_window_) != FALSE;
  ::BringWindowToTop(target_window_);
  ::SetActiveWindow(target_window_);

  if (attached) {
    ::AttachThreadInput(foreground_thread, target_thread, FALSE);
  }

  return activated || ::GetForegroundWindow() == target_window_;
}

bool DesktopPasteHost::SendPasteShortcut() const {
  INPUT inputs[4] = {};

  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;

  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';

  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;

  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

  return ::SendInput(4, inputs, sizeof(INPUT)) == 4;
}
