// Runner-owned MethodChannel bridge between Flutter and native desktop paste.
// NOT a Flutter plugin — owned by FlutterWindow for explicit lifetime control.

#ifndef DESKTOP_PASTE_HOST_H_
#define DESKTOP_PASTE_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include "undo_input_watcher.h"

#include <memory>
#include <string>
#include <vector>

class DesktopPasteHost {
 public:
  DesktopPasteHost(flutter::FlutterEngine* engine, HWND owner);
  ~DesktopPasteHost();

  DesktopPasteHost(const DesktopPasteHost&) = delete;
  DesktopPasteHost& operator=(const DesktopPasteHost&) = delete;

  void Destroy();

  // Clipboard-owner messages for the receipt write (delayed rendering):
  // WM_RENDERFORMAT, WM_RENDERALLFORMATS, WM_DESTROYCLIPBOARD. Returns true
  // when the message was handled and must not be passed on.
  bool HandleClipboardOwnerMessage(UINT message, WPARAM wparam);
  // Replies of worker threads (the activation wait of activateTarget),
  // posted to the owner window. Returns true when the message was handled.
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool CaptureTargetWindow();
  flutter::EncodableValue PasteClipboard(int delay_ms);
  flutter::EncodableValue CopySelection(int delay_ms);
  flutter::EncodableValue TypeText(const std::string& text, int delay_ms);
  flutter::EncodableValue DiagnosticPaste(const std::string& demo_text);
  bool WriteClipboardTextExcludingHistory(const std::string& text);
  bool WriteClipboardTextWithReceipt(const std::string& text);
  void WaitForClipboardRead(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  std::string RestoreClipboardTextIfOwner(const std::string& text);
  flutter::EncodableValue SnapshotClipboard();
  std::string RestoreClipboardSnapshotIfOwner();
  bool RenderReceiptText();
  void ResolvePendingRead(const std::string& status);
  bool BringTargetToForeground() const;
  bool SendPasteShortcut() const;
  bool SendCtrlShortcut(WORD key) const;
  bool SendEnterKey() const;
  // Idle ages for the undo gate (DEV-185, GS-056, DEV-232); null when unknown.
  flutter::EncodableValue InputIdleSnapshot() const;
  // Executable base name of the captured target without ".exe" (the identifier
  // the block list and app profiles compare); null without a readable target.
  flutter::EncodableValue TargetBundleId() const;
  // Platform contract of the keystroke undo (#428, #580): what this host can
  // answer, the focused window, and bringing the paste target back.
  flutter::EncodableValue UndoPlatformSupport() const;
  flutter::EncodableValue ForegroundWindow() const;
  void ActivateTarget(
      const std::string& id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // Ctrl+Z after a last check; "sent" or why not (undo_policy.h).
  const char* SendUndoShortcut() const;
  // Key/click watcher for the undo gate: started without waiting when a
  // recording captures its target (and again, as a no-op or restart, right
  // before an insert's keys), armed by a successful insert, and ended
  // kUndoWatchMs after the last capture or insert by a timer; not running the
  // rest of the time.
  void WakeUndoWatch();
  void StartUndoWatch(ULONGLONG paste_tick);
  void StopUndoWatch();
  void RestartUndoWatchTimer();
  static VOID CALLBACK OnUndoWatchExpired(HWND, UINT, UINT_PTR, DWORD);

  flutter::FlutterEngine* engine_;
  HWND owner_;
  HWND target_window_ = nullptr;
  bool destroyed_ = false;

  // Receipt write state (see WriteClipboardTextWithReceipt). All of it is
  // touched on the window's UI thread only (method channel + WndProc).
  std::wstring receipt_text_;
  bool receipt_active_ = false;
  // Tick of our own last synthetic key burst (GetTickCount), for the undo gate.
  // Mutable: SendCtrlShortcut is const and records the burst it sends.
  mutable DWORD last_synthetic_tick_ = 0;
  mutable bool has_synthetic_key_ = false;
  UndoInputWatcher undo_watcher_;
  UINT_PTR undo_watch_timer_ = 0;
  bool receipt_keystroke_posted_ = false;
  bool receipt_read_ = false;
  // Log-only facts about reads of the armed receipt (#1147).
  int receipt_pre_reads_ = 0;
  ULONGLONG receipt_keystroke_tick_ = 0;
  long long receipt_first_read_after_ms_ = -1;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_read_;

  // Full clipboard backup taken before a dictation's paste (P1.1): every
  // memory-backed format, plus an enhanced metafile copy. Empty when none.
  struct SavedFormat {
    UINT format = 0;
    std::vector<unsigned char> bytes;
    HENHMETAFILE metafile = nullptr;  // CF_ENHMETAFILE only, owned here.
  };
  std::vector<SavedFormat> snapshot_;
  void DiscardSnapshot();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // DESKTOP_PASTE_HOST_H_
