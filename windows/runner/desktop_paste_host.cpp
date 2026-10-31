#include "desktop_paste_host.h"

#include <flutter/encodable_value.h>

#include "app_identity_host.h"
#include "utils.h"

#include <chrono>
#include <thread>
#include <utility>
#include <wchar.h>

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

// OpenClipboard fails outright while any other process holds the clipboard
// open -- routinely the case for a few ms right after every clipboard
// change, when Windows' clipboard-history service, clipboard managers and
// the paste target read it. A single failed attempt used to send the Dart
// side to its plain, non-history-excluded fallback write, which Win+V then
// records (issue #146). Bounded at ~100 ms on the platform thread.
bool OpenClipboardWithRetry(HWND owner) {
  constexpr int kAttempts = 10;
  for (int attempt = 0; attempt < kAttempts; ++attempt) {
    if (::OpenClipboard(owner)) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return false;
}

ClipboardBackup BackupClipboard(HWND owner) {
  ClipboardBackup backup;
  if (!OpenClipboardWithRetry(owner)) return backup;
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

// Marks the clipboard contents just written as exempt from Windows'
// clipboard-history (Win+V) and cloud-clipboard monitors, per the formats
// documented for opting individual clipboard writes out of history
// (https://learn.microsoft.com/windows/win32/dataxchg/clipboard-history):
// "ExcludeClipboardContentFromMonitorProcessing" hides the write entirely,
// while "CanIncludeInClipboardHistory"/"CanUploadToCloudClipboard" (DWORD 0)
// cover clients that only honor the more specific opt-outs.
// "Clipboard Viewer Ignore" (presence-only) is the older convention that
// third-party clipboard managers check instead -- Ditto 3.25 records every
// write without it (issue #146). Must be called with the clipboard already
// open; does not close it.
void ExcludeFromClipboardHistory() {
  const wchar_t* const kFormatNames[] = {
      L"ExcludeClipboardContentFromMonitorProcessing",
      L"CanIncludeInClipboardHistory",
      L"CanUploadToCloudClipboard",
      L"Clipboard Viewer Ignore",
  };
  for (const wchar_t* name : kFormatNames) {
    UINT format = ::RegisterClipboardFormatW(name);
    if (format == 0) continue;
    HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
    if (handle == nullptr) continue;
    auto* value = static_cast<DWORD*>(::GlobalLock(handle));
    if (value == nullptr) {
      ::GlobalFree(handle);
      continue;
    }
    *value = 0;
    ::GlobalUnlock(handle);
    if (::SetClipboardData(format, handle) == nullptr) {
      ::GlobalFree(handle);
    }
  }
}

// `exclude_from_history` marks the write as exempt from clipboard-history /
// cloud-clipboard capture. Defaults to true: every call site here is
// WhisPaste's own transient plumbing (the temporary transcript write that
// drives Ctrl+V, or restoring the user's prior clipboard contents right
// after), never a fresh copy action the user actually performed -- see
// RestoreClipboard, which also excludes for the same reason (issue #146:
// restoring the user's own value still created a new, redundant Win+V
// entry, since it's WhisPaste re-writing it, not the user re-copying it).
bool WriteClipboardText(HWND owner, const std::wstring& text,
                        bool exclude_from_history = true) {
  if (!OpenClipboardWithRetry(owner)) return false;
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
  if (exclude_from_history) {
    ExcludeFromClipboardHistory();
  }
  ::CloseClipboard();
  return true;
}

void RestoreClipboard(HWND owner, const ClipboardBackup& backup) {
  if (backup.had_text) {
    WriteClipboardText(owner, backup.text, /*exclude_from_history=*/true);
  } else if (OpenClipboardWithRetry(owner)) {
    ::EmptyClipboard();
    ::CloseClipboard();
  }
}

// Formats whose clipboard handle is not global memory (GDI objects, owner
// display, private handles). They cannot be copied byte-wise; CF_BITMAP and
// CF_METAFILEPICT are synthesized again from CF_DIB / CF_ENHMETAFILE.
bool IsHandleFormat(UINT format) {
  switch (format) {
    case CF_BITMAP:
    case CF_METAFILEPICT:
    case CF_PALETTE:
    case CF_OWNERDISPLAY:
    case CF_DSPBITMAP:
    case CF_DSPMETAFILEPICT:
    case CF_DSPENHMETAFILE:
      return true;
    default:
      return (format >= CF_PRIVATEFIRST && format <= CF_PRIVATELAST) ||
             (format >= CF_GDIOBJFIRST && format <= CF_GDIOBJLAST);
  }
}

// Bounds for SnapshotClipboard: a huge image or an owner that renders a
// format slowly (Excel's delayed rendering) must not stall the paste; Dart
// then saves plain text only.
constexpr size_t kSnapshotByteLimit = 64u * 1024u * 1024u;
constexpr auto kSnapshotTimeBudget = std::chrono::milliseconds(1500);

void WaitForModifierRelease(int max_wait_ms) {
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::milliseconds(max_wait_ms);
  const int modifiers[] = {VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN};
  while (std::chrono::steady_clock::now() < deadline) {
    bool held = false;
    for (int vk : modifiers) {
      if ((::GetAsyncKeyState(vk) & 0x8000) != 0) {
        held = true;
        break;
      }
    }
    if (!held) return;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
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
  ResolvePendingRead("superseded");
  DiscardSnapshot();

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

  if (method == "getTargetBundleId") {
    result->Success(TargetBundleId());
    return;
  }

  if (method == "pasteClipboard") {
    const int delay_ms = map ? GetInt(*map, "delayMs", 0) : 0;
    result->Success(PasteClipboard(delay_ms));
    return;
  }

  if (method == "copySelection") {
    const int delay_ms = map ? GetInt(*map, "delayMs", 0) : 0;
    result->Success(CopySelection(delay_ms));
    return;
  }

  if (method == "typeText") {
    const std::string text = map ? GetString(*map, "text") : "";
    const int delay_ms = map ? GetInt(*map, "delayMs", 0) : 0;
    result->Success(TypeText(text, delay_ms));
    return;
  }

  if (method == "writeClipboardText") {
    const std::string text = map ? GetString(*map, "text") : "";
    result->Success(EncodableValue(WriteClipboardTextExcludingHistory(text)));
    return;
  }

  if (method == "writeClipboardTextWithReceipt") {
    const std::string text = map ? GetString(*map, "text") : "";
    result->Success(EncodableValue(WriteClipboardTextWithReceipt(text)));
    return;
  }

  if (method == "waitForClipboardRead") {
    WaitForClipboardRead(std::move(result));
    return;
  }

  if (method == "restoreClipboardTextIfOwner") {
    const std::string text = map ? GetString(*map, "text") : "";
    EncodableMap response;
    response[EncodableValue("status")] =
        EncodableValue(RestoreClipboardTextIfOwner(text));
    result->Success(EncodableValue(std::move(response)));
    return;
  }

  if (method == "snapshotClipboard") {
    result->Success(SnapshotClipboard());
    return;
  }

  if (method == "restoreClipboardSnapshotIfOwner") {
    EncodableMap response;
    response[EncodableValue("status")] =
        EncodableValue(RestoreClipboardSnapshotIfOwner());
    result->Success(EncodableValue(std::move(response)));
    return;
  }

  if (method == "discardClipboardSnapshot") {
    DiscardSnapshot();
    result->Success();
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

  if (method == "inputIdleSnapshot") {
    result->Success(InputIdleSnapshot());
    return;
  }

  // Portal keyboard input is Linux-only (RemoteDesktop/libei). Windows keeps
  // the methods answering "unavailable" so the channel stays uniform.
  if (method == "portalInputAvailable") {
    result->Success(EncodableValue(false));
    return;
  }

  if (method == "portalInputConnect") {
    EncodableMap answer;
    answer[EncodableValue("status")] = EncodableValue("unavailable");
    answer[EncodableValue("restoreToken")] = EncodableValue();
    result->Success(EncodableValue(answer));
    return;
  }

  if (method == "portalInputDisconnect") {
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

  // A target that is still in the foreground (the overlay never takes focus)
  // has nothing to settle; it only waits until the hotkey's modifiers are up,
  // bounded by the same delay, so a held Shift/Alt can't alter the Ctrl+V.
  if (::GetForegroundWindow() == target_window_) {
    WaitForModifierRelease(delay_ms);
  } else if (delay_ms > 0) {
    std::this_thread::sleep_for(std::chrono::milliseconds(delay_ms));
  }

  if (!BringTargetToForeground()) {
    return MakeResultMap(
        "foreground_blocked",
        "SetForegroundWindow refused — UIPI or stale window handle");
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  // From here on, a render request for an armed receipt counts as the
  // target's paste (earlier requests are clipboard monitors).
  receipt_keystroke_posted_ = receipt_active_;
  if (!SendPasteShortcut()) {
    return MakeResultMap("send_input_failed",
                         "SendInput did not inject all 4 key events");
  }
  return MakeResultMap("success", "");
}

// Mirrors PasteClipboard with Ctrl+C: brings the captured target back to the
// foreground and asks it to copy its current selection ("edit selection by
// voice"). Dart snapshots/restores the clipboard around this call and
// detects "no selection" by the clipboard staying unchanged.
EncodableValue DesktopPasteHost::CopySelection(int delay_ms) {
  if (!target_window_ || !::IsWindow(target_window_)) {
    return MakeResultMap("no_target", "no captured target window at copy time");
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
  if (!SendCtrlShortcut('C')) {
    return MakeResultMap("send_input_failed",
                         "SendInput did not inject all 4 key events");
  }
  return MakeResultMap("success", "");
}

// Types `text` into the target window. Windows has no reliable
// layout-independent "post this string directly" primitive: synthetic
// KEYEVENTF_UNICODE bursts corrupt input in Modern Notepad's TSF-backed
// text control — verified on real hardware, stretches of the transcript
// come back as a single repeated/wrong character (even a single
// autocomplete-prone word like "Smiley?" reliably corrupts) even though
// SendInput itself reports full delivery. Other apps (Chromium-based
// inputs, classic Win32 edit controls) were unaffected, but Notepad is far
// too common a dictation target to risk it, and no chunk size/pacing tried
// eliminated the corruption. Routes through the same clipboard+paste
// mechanism as PasteClipboard instead — proven clean in the same
// testing — backing up and restoring the caller's prior clipboard content
// around it so `type` still doesn't clobber it, matching the no-clobber
// behavior of the macOS direct-typing path.
EncodableValue DesktopPasteHost::TypeText(const std::string& text,
                                          int delay_ms) {
  if (!target_window_ || !::IsWindow(target_window_)) {
    return MakeResultMap("no_target", "no captured target window at type time");
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

  const ClipboardBackup backup = BackupClipboard(owner_);
  const std::wstring wide = Utf8ToWide(text);
  if (!WriteClipboardText(owner_, wide)) {
    RestoreClipboard(owner_, backup);
    return MakeResultMap("clipboard_write_failed", "");
  }
  if (!SendPasteShortcut()) {
    RestoreClipboard(owner_, backup);
    return MakeResultMap("send_input_failed",
                         "SendInput did not inject all key events");
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(80));
  RestoreClipboard(owner_, backup);
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

// Issue #146: the default Auto-Paste flow writes the transcript (and later
// restores the user's prior clipboard) from the Dart side via Flutter's
// generic `Clipboard.setData`, which has no history-exclusion formats and
// so bypassed the opt-out added for #98 entirely -- that fix only ever
// covered the TypeText/DiagnosticPaste fallback paths below. This channel
// method gives the Dart paste flow (`DesktopPaster.paste`) a way to route
// both of its writes through the same excluded write those paths already
// use, instead of the plain clipboard write.
bool DesktopPasteHost::WriteClipboardTextExcludingHistory(
    const std::string& text) {
  return WriteClipboardText(owner_, Utf8ToWide(text));
}

// Receipt-based clipboard restore (handy-catchup 06). Puts the transcript
// on the clipboard via delayed rendering: SetClipboardData(CF_UNICODETEXT,
// NULL) only *announces* the text, and Windows sends WM_RENDERFORMAT to this
// owner window the moment a reader actually asks for it -- that request is
// the receipt that the target pasted. Marked history-excluded like every
// other transient write here (issue #146). Returns false when the clipboard
// can't be taken -- Dart then uses its classic write + fixed delay.
bool DesktopPasteHost::WriteClipboardTextWithReceipt(const std::string& text) {
  ResolvePendingRead("superseded");
  receipt_active_ = false;
  if (!OpenClipboardWithRetry(owner_)) return false;
  // EmptyClipboard sends WM_DESTROYCLIPBOARD to the previous owner (maybe
  // us), so the new receipt state is only armed afterwards.
  ::EmptyClipboard();
  ::SetClipboardData(CF_UNICODETEXT, nullptr);
  const bool announced = ::IsClipboardFormatAvailable(CF_UNICODETEXT) != FALSE;
  if (announced) ExcludeFromClipboardHistory();
  ::CloseClipboard();
  if (!announced) return false;

  receipt_text_ = Utf8ToWide(text);
  receipt_active_ = true;
  receipt_keystroke_posted_ = false;
  receipt_read_ = false;
  return true;
}

// Answers "read" once the receipt was rendered after the paste keystroke,
// "lost" once another writer emptied the clipboard; otherwise the result is
// held until then -- Dart bounds the wait with its own timeout.
void DesktopPasteHost::WaitForClipboardRead(
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (receipt_read_) {
    result->Success(MakeResultMap("read", ""));
    return;
  }
  if (!receipt_active_) {
    result->Success(MakeResultMap("lost", ""));
    return;
  }
  ResolvePendingRead("superseded");
  pending_read_ = std::move(result);
}

// Restores `text` only while this window still owns the receipt write --
// never clobbers content another process copied in the meantime.
std::string DesktopPasteHost::RestoreClipboardTextIfOwner(
    const std::string& text) {
  const bool owner = receipt_active_ && ::GetClipboardOwner() == owner_;
  receipt_active_ = false;
  ResolvePendingRead(owner ? "superseded" : "lost");
  if (!owner) return "not_owner";
  return WriteClipboardText(owner_, Utf8ToWide(text)) ? "restored" : "failed";
}

void DesktopPasteHost::DiscardSnapshot() {
  for (SavedFormat& saved : snapshot_) {
    if (saved.metafile != nullptr) ::DeleteEnhMetaFile(saved.metafile);
  }
  snapshot_.clear();
}

// Saves every clipboard format the user had copied (image, files, RTF, HTML,
// ...) for the restore after the paste. The data stays here; Dart gets the
// status, the plain-text form (to mark the restore as its own write) and
// counts for the log.
EncodableValue DesktopPasteHost::SnapshotClipboard() {
  DiscardSnapshot();
  if (!OpenClipboardWithRetry(owner_)) return MakeResultMap("failed", "open");
  const auto started = std::chrono::steady_clock::now();
  std::vector<SavedFormat> saved;
  size_t bytes = 0;
  std::string status = "saved";
  std::wstring text;
  bool has_text = false;
  for (UINT format = ::EnumClipboardFormats(0); format != 0;
       format = ::EnumClipboardFormats(format)) {
    if (std::chrono::steady_clock::now() - started > kSnapshotTimeBudget) {
      status = "failed";
      break;
    }
    if (IsHandleFormat(format)) continue;
    // GetClipboardData makes a delayed-rendering owner render the format.
    HANDLE handle = ::GetClipboardData(format);
    if (handle == nullptr) continue;
    SavedFormat entry;
    entry.format = format;
    if (format == CF_ENHMETAFILE) {
      entry.metafile =
          ::CopyEnhMetaFileW(reinterpret_cast<HENHMETAFILE>(handle), nullptr);
      if (entry.metafile == nullptr) continue;
      saved.push_back(std::move(entry));
      continue;
    }
    const SIZE_T size = ::GlobalSize(handle);
    if (bytes + size > kSnapshotByteLimit) {
      status = "failed";
      break;
    }
    const void* locked = ::GlobalLock(handle);
    if (locked == nullptr) continue;
    const auto* begin = static_cast<const unsigned char*>(locked);
    entry.bytes.assign(begin, begin + size);
    ::GlobalUnlock(handle);
    if (format == CF_UNICODETEXT && size >= sizeof(wchar_t)) {
      const auto* chars = reinterpret_cast<const wchar_t*>(entry.bytes.data());
      text.assign(chars, wcsnlen(chars, size / sizeof(wchar_t)));
      has_text = true;
    }
    bytes += size;
    saved.push_back(std::move(entry));
  }
  ::CloseClipboard();

  if (status != "saved") {
    for (SavedFormat& entry : saved) {
      if (entry.metafile != nullptr) ::DeleteEnhMetaFile(entry.metafile);
    }
    return MakeResultMap(status, "");
  }
  if (saved.empty()) return MakeResultMap("empty", "");
  const auto count = static_cast<int64_t>(saved.size());
  snapshot_ = std::move(saved);
  EncodableMap map;
  map[EncodableValue("status")] = EncodableValue("saved");
  map[EncodableValue("formats")] = EncodableValue(count);
  map[EncodableValue("bytes")] = EncodableValue(static_cast<int64_t>(bytes));
  if (has_text) map[EncodableValue("text")] = EncodableValue(Utf8FromUtf16(text.c_str()));
  return EncodableValue(std::move(map));
}

// Puts the saved snapshot back under the same owner check as
// RestoreClipboardTextIfOwner, history-excluded like every restore here
// (issue #146).
std::string DesktopPasteHost::RestoreClipboardSnapshotIfOwner() {
  if (snapshot_.empty()) return "failed";
  const bool owner = receipt_active_ && ::GetClipboardOwner() == owner_;
  receipt_active_ = false;
  ResolvePendingRead(owner ? "superseded" : "lost");
  if (!owner || !OpenClipboardWithRetry(owner_)) {
    DiscardSnapshot();
    return owner ? "failed" : "not_owner";
  }
  ::EmptyClipboard();
  size_t written = 0;
  for (SavedFormat& entry : snapshot_) {
    if (entry.metafile != nullptr) {
      // The clipboard owns the handle after a successful SetClipboardData.
      if (::SetClipboardData(entry.format, reinterpret_cast<HANDLE>(entry.metafile)) !=
          nullptr) {
        entry.metafile = nullptr;
        ++written;
      }
      continue;
    }
    HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, entry.bytes.size());
    if (handle == nullptr) continue;
    void* dst = ::GlobalLock(handle);
    if (dst == nullptr) {
      ::GlobalFree(handle);
      continue;
    }
    if (!entry.bytes.empty()) {
      std::memcpy(dst, entry.bytes.data(), entry.bytes.size());
    }
    ::GlobalUnlock(handle);
    if (::SetClipboardData(entry.format, handle) == nullptr) {
      ::GlobalFree(handle);
      continue;
    }
    ++written;
  }
  if (written > 0) ExcludeFromClipboardHistory();
  ::CloseClipboard();
  DiscardSnapshot();
  return written > 0 ? "restored" : "failed";
}

// Hands the announced text to the clipboard. Called inside WM_RENDERFORMAT
// (clipboard already opened by the reader -- must not open it again) and
// inside WM_RENDERALLFORMATS (opened by the caller below).
bool DesktopPasteHost::RenderReceiptText() {
  const size_t bytes = (receipt_text_.size() + 1) * sizeof(wchar_t);
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (handle == nullptr) return false;
  auto* dst = static_cast<wchar_t*>(::GlobalLock(handle));
  if (dst == nullptr) {
    ::GlobalFree(handle);
    return false;
  }
  std::memcpy(dst, receipt_text_.c_str(), bytes);
  ::GlobalUnlock(handle);
  if (::SetClipboardData(CF_UNICODETEXT, handle) == nullptr) {
    ::GlobalFree(handle);
    return false;
  }
  return true;
}

void DesktopPasteHost::ResolvePendingRead(const std::string& status) {
  if (!pending_read_) return;
  pending_read_->Success(MakeResultMap(status, ""));
  pending_read_.reset();
}

bool DesktopPasteHost::HandleClipboardOwnerMessage(UINT message,
                                                   WPARAM wparam) {
  switch (message) {
    case WM_RENDERFORMAT:
      if (wparam != CF_UNICODETEXT) return false;
      RenderReceiptText();
      if (receipt_active_ && receipt_keystroke_posted_) {
        receipt_read_ = true;
        ResolvePendingRead("read");
      }
      return true;
    case WM_RENDERALLFORMATS:
      // We are going away while still owning announced-but-unrendered
      // text -- render it so the clipboard keeps the transcript.
      if (::OpenClipboard(owner_)) {
        if (::GetClipboardOwner() == owner_) RenderReceiptText();
        ::CloseClipboard();
      }
      return true;
    case WM_DESTROYCLIPBOARD:
      // Someone (another app, or our own next write) emptied the clipboard.
      receipt_active_ = false;
      ResolvePendingRead("lost");
      return false;
    default:
      return false;
  }
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

// Executable base name of the captured target without ".exe"; null without a
// readable target.
EncodableValue DesktopPasteHost::TargetBundleId() const {
  if (!target_window_ || !::IsWindow(target_window_)) return EncodableValue();
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(target_window_, &process_id);
  if (process_id == 0) return EncodableValue();

  // Elevated targets refuse this access right; they report null, which the
  // block list treats as an unknown target (fail-closed).
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) return EncodableValue();
  wchar_t path[32768];
  DWORD size = static_cast<DWORD>(sizeof(path) / sizeof(path[0]));
  std::string name;
  if (::QueryFullProcessImageNameW(process, 0, path, &size)) {
    std::wstring full(path, size);
    const size_t slash = full.find_last_of(L"\\/");
    std::wstring base =
        slash == std::wstring::npos ? full : full.substr(slash + 1);
    if (base.size() > 4 && _wcsicmp(base.c_str() + base.size() - 4, L".exe") == 0) {
      base.resize(base.size() - 4);
    }
    name = Utf8FromUtf16(base.c_str());
    // Lets the recording rows find the icon even after the app closed.
    RememberTargetExePath(name, full);
  }
  ::CloseHandle(process);
  if (name.empty()) return EncodableValue();
  return EncodableValue(name);
}

// Idle ages in seconds for the undo gate. GetLastInputInfo counts injected
// input too and does not tell keyboard from mouse, so keyIdle and mouseIdle
// share one conservative value: any input since the insert counts as typing.
EncodableValue DesktopPasteHost::InputIdleSnapshot() const {
  LASTINPUTINFO info = {};
  info.cbSize = sizeof(info);
  if (!::GetLastInputInfo(&info)) return EncodableValue();

  const double idle = static_cast<DWORD>(::GetTickCount() - info.dwTime) / 1000.0;
  double synthetic = 1e9;
  if (has_synthetic_key_) {
    synthetic =
        static_cast<DWORD>(::GetTickCount() - last_synthetic_tick_) / 1000.0;
  }
  EncodableMap map;
  map[EncodableValue("keyIdle")] = EncodableValue(idle);
  map[EncodableValue("mouseIdle")] = EncodableValue(idle);
  map[EncodableValue("syntheticIdle")] = EncodableValue(synthetic);
  return EncodableValue(std::move(map));
}

bool DesktopPasteHost::SendPasteShortcut() const {
  return SendCtrlShortcut('V');
}

// Injects Ctrl+<key> as one atomic 4-event SendInput burst — shared by
// paste ('V') and copySelection ('C').
bool DesktopPasteHost::SendCtrlShortcut(WORD key) const {
  INPUT inputs[4] = {};
  last_synthetic_tick_ = ::GetTickCount();
  has_synthetic_key_ = true;

  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;

  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = key;

  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = key;
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;

  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;

  return ::SendInput(4, inputs, sizeof(INPUT)) == 4;
}

