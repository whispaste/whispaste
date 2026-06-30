// Runner-owned RawInput host that supplies global hotkey KEY-UP events on
// Windows (issue #39).
//
// Why this exists: the global hotkey is registered with RegisterHotKey (the
// hotkey_manager plugin), which only ever yields WM_HOTKEY on key-DOWN — there
// is no "hotkey up" message on Windows. That makes hold-to-talk (push-to-talk)
// impossible through the registrar alone.
//
// This host closes the gap WITHOUT taking over the hotkey: it uses RawInput
// (RIDEV_INPUTSINK) to OBSERVE keyboard transitions globally. It never
// intercepts or swallows keys, so the existing RegisterHotKey still suppresses
// the keystroke and provides the key-down; this host only reports the release
// of the watched main key back to Dart as `onKeyUp`.
//
// Channel: com.whispaste.keyboard_monitor
//   Dart → native:  start({keyId, keyLabel, modifiers})  ·  stop()
//   native → Dart:  onKeyUp   (watched main key released)

#ifndef KEYBOARD_MONITOR_HOST_H_
#define KEYBOARD_MONITOR_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class KeyboardMonitorHost {
 public:
  KeyboardMonitorHost(flutter::FlutterEngine* engine, HWND owner);
  ~KeyboardMonitorHost();

  KeyboardMonitorHost(const KeyboardMonitorHost&) = delete;
  KeyboardMonitorHost& operator=(const KeyboardMonitorHost&) = delete;

  // Called by FlutterWindow's message handler for WM_INPUT. Returns true if the
  // message was a keyboard RawInput event this host consumed for observation
  // (the caller should still fall through to DefWindowProc for WM_INPUT).
  void HandleRawInput(HRAWINPUT raw_input);

  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Registers/unregisters this window for RawInput keyboard observation.
  bool EnsureRawInputRegistered();
  void UnregisterRawInput();

  flutter::FlutterEngine* engine_;
  HWND owner_;
  bool destroyed_ = false;
  bool raw_input_registered_ = false;

  // The Win32 virtual-key code of the watched hotkey's MAIN key (0 = not
  // watching). Derived from the Dart payload.
  USHORT watched_vk_ = 0;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // KEYBOARD_MONITOR_HOST_H_
