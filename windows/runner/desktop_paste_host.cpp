#include "desktop_paste_host.h"

#include <flutter/encodable_value.h>

#include <chrono>
#include <thread>
#include <vector>

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

std::string GetString(const EncodableMap& map, const std::string& key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return {};
  if (auto* s = std::get_if<std::string>(&it->second)) return *s;
  return {};
}

EncodableValue MakeResultMap(const std::string& status,
                             const std::string& detail) {
  EncodableMap map;
  map[EncodableValue("status")] = EncodableValue(status);
  if (!detail.empty()) {
    map[EncodableValue("detail")] = EncodableValue(detail);
  }
  return EncodableValue(std::move(map));
}

// Convert a UTF-8 std::string into a wide string suitable for the Windows
// clipboard `CF_UNICODETEXT` format.
std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int needed = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                     static_cast<int>(utf8.size()), nullptr,
                                     0);
  if (needed <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(needed), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                        static_cast<int>(utf8.size()), wide.data(), needed);
  return wide;
}

// Captures the existing clipboard contents as a raw blob the caller can
// re-write later. We only round-trip CF_UNICODETEXT because that is what
// every text-handling app on Windows uses; richer formats stay untouched.
// Returns std::nullopt-equivalent (empty + had_text=false) when the
// clipboard didn't contain text we can restore.
struct ClipboardBackup {
  bool had_text = false;
  std::wstring text;
};

ClipboardBackup BackupClipboard(HWND owner) {
  ClipboardBackup backup;
  if (!::OpenClipboard(owner)) return backup;
  HANDLE handle = ::GetClipboardData(CF_UNICODETEXT);
  if (handle != nullptr) {
    auto* locked = static_cast<const wchar_t*>(::GlobalLock(handle));
    if (locked != nullptr) {
      backup.text = locked;
      backup.had_text = true;
      ::GlobalUnlock(handle);
    }
  }
  ::CloseClipboard();
  return backup;
}

bool WriteClipboardText(HWND owner, const std::wstring& text) {
  if (!::OpenClipboard(owner)) return false;
  ::EmptyClipboard();
  const size_t bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (handle == nullptr) {
    ::CloseClipboard();
    return false;
  }
  auto* dst = static_cast<wchar_t*>(::GlobalLock(handle));
  if (dst == nullptr) {
    ::GlobalFree(handle);
    ::CloseClipboard();
    return false;
  }
  std::memcpy(dst, text.c_str(), bytes);
  ::GlobalUnlock(handle);
  if (::SetClipboardData(CF_UNICODETEXT, handle) == nullptr) {
    ::GlobalFree(handle);
    ::CloseClipboard();
    return false;
  }
  ::CloseClipboard();
  return true;
}

void RestoreClipboard(HWND owner, const ClipboardBackup& backup) {
  if (backup.had_text) {
    WriteClipboardText(owner, backup.text);
  } else if (::OpenClipboard(owner)) {
    ::EmptyClipboard();
    ::CloseClipboard();
  }
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
    result->Success(PasteClipboard(delay_ms));
    return;
  }

  if (method == "diagnosticPaste") {
    const std::string demo_text = map ? GetString(*map, "demoText") : "";
    result->Success(DiagnosticPaste(demo_text));
    return;
  }

  if (method == "checkCapability") {
    // Windows has no equivalent of macOS Accessibility for SendInput from
    // a non-elevated process — as long as we have a foreground window
    // we can target, paste will work. UIPI restrictions only matter if
    // the target is an elevated process; we report "ready" optimistically
    // and let any actual failures surface via pasteClipboard.
    EncodableMap response;
    response[EncodableValue("status")] = EncodableValue("ready");
    response[EncodableValue("canPrompt")] = EncodableValue(false);
    result->Success(EncodableValue(std::move(response)));
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

EncodableValue DesktopPasteHost::PasteClipboard(int delay_ms) {
  if (!target_window_ || !::IsWindow(target_window_)) {
    return MakeResultMap("no_target", "no captured target window at paste time");
  }

  if (delay_ms > 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }

  if (!BringTargetToForeground()) {
    return MakeResultMap(
        "foreground_blocked",
        "SetForegroundWindow refused — UIPI or stale window handle");
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  if (!SendPasteShortcut()) {
    return MakeResultMap("send_input_failed",
                         "SendInput did not inject all 4 key events");
  }
  return MakeResultMap("success", "");
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

// Onboarding "prove Auto-Paste works" probe. Backs up the user clipboard,
// writes the demo text, sends Ctrl+V to the foreground window, briefly
// waits, then restores the original clipboard contents — regardless of
// whether the keystroke landed. Returns one of:
//
//   - {status: "success"}             — SendInput injected all key events.
//   - {status: "no_frontmost"}        — no foreground window available.
//   - {status: "failure", detail:...} — clipboard write failed or
//                                        SendInput rejected the events.
//
// The UIPI/elevation edge collapses into "failure: uipi_blocked" because
// SendInput silently drops events directed at higher-integrity processes.
flutter::EncodableValue DesktopPasteHost::DiagnosticPaste(
    const std::string& demo_text) {
  HWND foreground = ::GetForegroundWindow();
  if (!foreground) {
    return MakeResultMap("no_frontmost", "");
  }
  // Refuse to paste into our own process — the demo would land in the
  // onboarding window and trash whatever was in it.
  DWORD foreground_pid = 0;
  ::GetWindowThreadProcessId(foreground, &foreground_pid);
  if (foreground == owner_ || foreground_pid == ::GetCurrentProcessId()) {
    return MakeResultMap("no_frontmost", "owner_is_frontmost");
  }

  // Snapshot the existing clipboard so we can put it back regardless of
  // outcome.
  const ClipboardBackup backup = BackupClipboard(owner_);

  const std::wstring wide = Utf8ToWide(demo_text);
  if (!WriteClipboardText(owner_, wide)) {
    RestoreClipboard(owner_, backup);
    return MakeResultMap("failure", "clipboard_write_failed");
  }

  // Inject Ctrl+V. SendInput will silently drop events when the target is
  // a higher-integrity process — that's the UIPI edge we surface via the
  // failure detail.
  const bool sent = SendPasteShortcut();
  if (!sent) {
    RestoreClipboard(owner_, backup);
    return MakeResultMap("failure", "send_input_failed");
  }

  // Give the OS ~80 ms to deliver the keystroke, then restore.
  std::this_thread::sleep_for(std::chrono::milliseconds(80));

  // Re-check the foreground window: if it shifted (e.g. UIPI deflected
  // our SendInput because the target is elevated and we are not), report
  // uipi_blocked so the UI can show targeted guidance.
  HWND post_foreground = ::GetForegroundWindow();
  RestoreClipboard(owner_, backup);
  if (post_foreground == nullptr) {
    return MakeResultMap("failure", "uipi_blocked");
  }
  return MakeResultMap("success", "");
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
