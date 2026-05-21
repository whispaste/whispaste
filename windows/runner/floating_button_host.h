// Runner-owned MethodChannel bridge between Flutter and the native
// floating button window. NOT a Flutter plugin — owned by FlutterWindow
// for explicit lifetime control (Invariant: destroyed BEFORE engine teardown).

#ifndef FLOATING_BUTTON_HOST_H_
#define FLOATING_BUTTON_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "floating_button_window.h"

class FloatingButtonHost {
 public:
  // |engine| must outlive this object. |owner| is the main Flutter HWND.
  FloatingButtonHost(flutter::FlutterEngine* engine, HWND owner);
  ~FloatingButtonHost();

  FloatingButtonHost(const FloatingButtonHost&) = delete;
  FloatingButtonHost& operator=(const FloatingButtonHost&) = delete;

  // Tear down native resources. Safe to call multiple times.
  void Destroy();

  // Re-asserts HWND_TOPMOST on the floating button window. Called from
  // FlutterWindow::MessageHandler on WM_SIZE(minimize) and WM_ACTIVATEAPP.
  void RefreshTopmost();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Fire-and-forget event to Dart (safe if no listener).
  void SendEvent(const std::string& method,
                 const flutter::EncodableValue& args);
  void SendEvent(const std::string& method);

  flutter::FlutterEngine* engine_;  // Not owned
  HWND owner_;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<FloatingButtonWindow> window_;
};

#endif  // FLOATING_BUTTON_HOST_H_
