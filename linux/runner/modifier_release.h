#ifndef RUNNER_MODIFIER_RELEASE_H_
#define RUNNER_MODIFIER_RELEASE_H_

// Waits until the user has let go of Shift, Ctrl, Alt and Super before the
// synthetic Ctrl+V/Ctrl+C. X11, Mutter and KWin merge the key state of all
// keyboards, so a hotkey Alt still held would turn Ctrl+Shift+V into
// Ctrl+Shift+Alt+V. A virtual device cannot release another device's keys,
// so waiting is the only fix (the Windows bridge does the same).
//
// Pure C++17, free of X11/GLib/evdev, so modifier_release_test.cc runs on
// any host; the real readers live in desktop_paste_host.cc.

#include <chrono>
#include <functional>
#include <optional>

enum class ModifierWait {
  kNoneHeld,   // nothing was held, or it was released in time
  kTimedOut,   // still held after max_wait; the shortcut goes out anyway
  kUnknown,    // no reader can see the key state (e.g. Wayland, no evdev)
};

// [any_held] answers true/false, or nullopt when the state is unknown.
// [sleep] waits one poll step; replaceable in tests.
inline ModifierWait WaitForModifierRelease(
    const std::function<std::optional<bool>()>& any_held,
    std::chrono::milliseconds max_wait,
    const std::function<void(std::chrono::milliseconds)>& sleep,
    std::chrono::milliseconds step = std::chrono::milliseconds(10)) {
  std::chrono::milliseconds waited(0);
  while (true) {
    const std::optional<bool> held = any_held();
    if (!held.has_value()) return ModifierWait::kUnknown;
    if (!*held) return ModifierWait::kNoneHeld;
    if (waited >= max_wait) return ModifierWait::kTimedOut;
    sleep(step);
    waited += step;
  }
}

#endif  // RUNNER_MODIFIER_RELEASE_H_
