// Runner-owned RawInput host that supplies global hotkey KEY-UP events on
// Windows (issue #39).
//
// Why this exists: the global hotkey is registered with RegisterHotKey (the
// hotkey_manager plugin), which only ever yields WM_HOTKEY on key-DOWN — there
// is no "hotkey up" message on Windows. That makes hold-to-talk (push-to-talk)
// impossible through the registrar alone.
//
// How it works WITHOUT taking over the hotkey: RawInput (RIDEV_INPUTSINK)
// observes keyboard transitions globally (never intercepting / swallowing
// keys, so RegisterHotKey still suppresses the keystroke and provides the
// key-down). Crucially, RegisterHotKey ALSO suppresses the hotkey key's DOWN
// from the RawInput stream — only its release is observable — so the main key
// cannot be learned by watching for a make. Instead Dart calls ArmRelease()
// the moment the hotkey fires; the host snapshots the non-modifier key that is
// physically down (GetAsyncKeyState) and reports `onKeyUp` when it is released.
//
// Channel: com.whispaste.keyboard_monitor
//   Dart → native:  start()  ·  armRelease()  ·  stop()
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

  // Called by FlutterWindow's message handler for WM_INPUT.
  void HandleRawInput(HRAWINPUT raw_input);

  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Registers/unregisters this window for RawInput keyboard observation.
  bool EnsureRawInputRegistered();
  void UnregisterRawInput();

  // Snapshots the currently-held non-modifier key as the one whose release
  // ends the hold (see header comment).
  void ArmRelease();

  flutter::FlutterEngine* engine_;
  HWND owner_;
  bool destroyed_ = false;
  bool raw_input_registered_ = false;

  // Virtual-key of the armed main key (0 = not armed). Set by ArmRelease(); its
  // release (break) fires `onKeyUp`.
  USHORT watched_vk_ = 0;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // KEYBOARD_MONITOR_HOST_H_
