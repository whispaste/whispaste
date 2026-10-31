// Runner-owned MethodChannel bridge for system sleep and resume (WP-39, 9.5).
//
// Windows delivers WM_POWERBROADCAST to top-level windows. FlutterWindow
// forwards those messages here; this host turns suspend and resume into
// `willSleep` / `didWake` calls on com.whispaste.power, so Dart can stop a
// running recording before the machine suspends.

#ifndef POWER_EVENT_HOST_H_
#define POWER_EVENT_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class PowerEventHost {
 public:
  explicit PowerEventHost(flutter::FlutterEngine* engine);
  ~PowerEventHost();

  PowerEventHost(const PowerEventHost&) = delete;
  PowerEventHost& operator=(const PowerEventHost&) = delete;

  // Call with the wParam of a WM_POWERBROADCAST message.
  void HandlePowerBroadcast(WPARAM event);

  void Destroy();

 private:
  flutter::FlutterEngine* engine_;
  bool destroyed_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // POWER_EVENT_HOST_H_
