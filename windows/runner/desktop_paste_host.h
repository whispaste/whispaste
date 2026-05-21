// Runner-owned MethodChannel bridge between Flutter and native desktop paste.
// NOT a Flutter plugin — owned by FlutterWindow for explicit lifetime control.

#ifndef DESKTOP_PASTE_HOST_H_
#define DESKTOP_PASTE_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class DesktopPasteHost {
 public:
  DesktopPasteHost(flutter::FlutterEngine* engine, HWND owner);
  ~DesktopPasteHost();

  DesktopPasteHost(const DesktopPasteHost&) = delete;
  DesktopPasteHost& operator=(const DesktopPasteHost&) = delete;

  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool CaptureTargetWindow();
  flutter::EncodableValue PasteClipboard(int delay_ms);
  flutter::EncodableValue DiagnosticPaste(const std::string& demo_text);
  bool BringTargetToForeground() const;
  bool SendPasteShortcut() const;

  flutter::FlutterEngine* engine_;
  HWND owner_;
  HWND target_window_ = nullptr;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // DESKTOP_PASTE_HOST_H_
