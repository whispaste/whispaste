// Reports the system setting "Animation effects" (Settings > Accessibility >
// Visual effects) to every Flutter engine of the app (#1756).
//
// The Windows embedder does not set AccessibilityFeatures.disableAnimations,
// so MediaQuery.disableAnimations stayed false although the user turned
// animations off. Each engine (main window, floating overlay, floating
// button, tray panel, side panel, snippet picker) owns one
// SystemMotionChannel on com.whispaste.system_motion: Dart reads the value
// with `reduceMotion` and gets `reduceMotionChanged` when it flips at runtime.
// Mirrors macos/Runner/SystemMotionHost.swift; the Dart side is
// lib/core/accessibility/system_motion.dart.
//
// Lifetime: the owner resets its SystemMotionChannel BEFORE the engine's
// FlutterViewController, next to its render channel, so the broadcast list
// never holds a dead messenger.

#ifndef RUNNER_SYSTEM_MOTION_CHANNEL_H_
#define RUNNER_SYSTEM_MOTION_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

class SystemMotionChannel {
 public:
  explicit SystemMotionChannel(flutter::BinaryMessenger* messenger);
  ~SystemMotionChannel();

  SystemMotionChannel(const SystemMotionChannel&) = delete;
  SystemMotionChannel& operator=(const SystemMotionChannel&) = delete;

  // True when the user turned animation effects off.
  static bool ReduceMotion();

  // Call on WM_SETTINGCHANGE of a top-level window: re-reads the setting and
  // pushes it to every live engine when it changed.
  static void OnSettingChange();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_SYSTEM_MOTION_CHANNEL_H_
