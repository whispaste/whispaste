// Runner-owned MethodChannel com.whispaste.hang_watchdog (#338).
//
// Dart arms the watchdog once the app is up and then sends `beat` every 2 s;
// the call is handled on the Win32 main thread, so a beat proves that both
// the UI isolate and the message loop still run. A separate watchdog thread
// feeds hang_watchdog::Core (same contract as the macOS and Linux runners).
// On a hang it writes the marker file (diagnosis for the next start), logs a
// short diagnosis via OutputDebugString and, at most once per 10 minutes,
// restarts the app: the new instance gets --hang-restart-wait=<pid> and waits
// in wWinMain until this process is gone (single instance stays intact);
// this process then terminates because its main thread no longer answers.

#ifndef RUNNER_HANG_WATCHDOG_HOST_H_
#define RUNNER_HANG_WATCHDOG_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "hang_watchdog_core.h"

// Called first in wWinMain: when the command line carries
// --hang-restart-wait=<pid>, waits (at most 15 s) for that process to end.
void WaitForHangRestartPredecessor(const wchar_t* command_line);

class HangWatchdogHost {
 public:
  explicit HangWatchdogHost(flutter::FlutterEngine* engine);
  ~HangWatchdogHost();

  HangWatchdogHost(const HangWatchdogHost&) = delete;
  HangWatchdogHost& operator=(const HangWatchdogHost&) = delete;

  void Destroy();

 private:
  void Loop();
  void OnHang(int64_t stalled_ms, const std::wstring& marker_dir);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::mutex mutex_;
  std::condition_variable cv_;
  bool stop_ = false;
  hang_watchdog::Core core_;
  std::wstring marker_dir_;
  std::thread thread_;
};

#endif  // RUNNER_HANG_WATCHDOG_HOST_H_
