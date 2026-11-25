#ifndef RUNNER_AUTOSTART_HOST_H_
#define RUNNER_AUTOSTART_HOST_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Packaged Windows autostart via the manifest StartupTask.
class AutostartHost {
 public:
  // |window| receives async replies on the Flutter platform thread.
  AutostartHost(flutter::BinaryMessenger* messenger, HWND window);
  ~AutostartHost();

  AutostartHost(const AutostartHost&) = delete;
  AutostartHost& operator=(const AutostartHost&) = delete;

  // Runs a closure posted by this channel. Returns true when |message| was
  // such a closure (the caller then stops processing it).
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND window_;
};

#endif  // RUNNER_AUTOSTART_HOST_H_
