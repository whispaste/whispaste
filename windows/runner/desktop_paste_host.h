// Runner-owned MethodChannel bridge between Flutter and native desktop paste.
// NOT a Flutter plugin — owned by FlutterWindow for explicit lifetime control.

#ifndef DESKTOP_PASTE_HOST_H_
#define DESKTOP_PASTE_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

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
  bool RenderReceiptText();
  void ResolvePendingRead(const std::string& status);
  bool BringTargetToForeground() const;
  bool SendPasteShortcut() const;
  bool SendCtrlShortcut(WORD key) const;

  flutter::FlutterEngine* engine_;
  HWND owner_;
  HWND target_window_ = nullptr;
  bool destroyed_ = false;

  // Receipt write state (see WriteClipboardTextWithReceipt). All of it is
  // touched on the window's UI thread only (method channel + WndProc).
  std::wstring receipt_text_;
  bool receipt_active_ = false;
  bool receipt_keystroke_posted_ = false;
  bool receipt_read_ = false;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_read_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // DESKTOP_PASTE_HOST_H_
