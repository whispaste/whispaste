// Runner-owned MethodChannel bridge between Flutter and the native
// floating overlay window. NOT a Flutter plugin — owned by FlutterWindow
// for explicit lifetime control (destroyed BEFORE engine teardown).

#ifndef FLOATING_OVERLAY_HOST_H_
#define FLOATING_OVERLAY_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "floating_overlay_window.h"

class FloatingOverlayHost {
 public:
  FloatingOverlayHost(flutter::FlutterEngine* engine, HWND owner);
  ~FloatingOverlayHost();

  FloatingOverlayHost(const FloatingOverlayHost&) = delete;
  FloatingOverlayHost& operator=(const FloatingOverlayHost&) = delete;

  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SendEvent(const std::string& method,
                 const flutter::EncodableValue& args);
  void SendEvent(const std::string& method);

  flutter::FlutterEngine* engine_;
  HWND owner_;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<FloatingOverlayWindow> window_;
};

#endif  // FLOATING_OVERLAY_HOST_H_
