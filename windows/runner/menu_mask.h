#ifndef RUNNER_MENU_MASK_H_
#define RUNNER_MENU_MASK_H_

// Decides when the release of a modifier-only hotkey (Win, Alt or Super) must be
// masked, so the desktop does not open its menu (Start on Windows, Activities
// on GNOME). The mask is sent only when the watched key was held and released
// with no other key pressed in between. Autorepeat while held changes nothing.
//
// Pure C++17, free of Win32/X11, so menu_mask_test.cc runs on any host.
// Windows has its own copy in windows/runner/menu_mask.h; keep them identical.
class MenuMaskTracker {
 public:
  void OnWatchedDown() {
    if (held_) return;
    held_ = true;
    alone_ = true;
  }

  // Any other key went down. Only counts while the watched key is held.
  void OnOtherKeyDown() {
    if (held_) alone_ = false;
  }

  // Returns true when the mask must be sent for this release.
  bool OnWatchedUp() {
    const bool send = held_ && alone_;
    held_ = false;
    alone_ = false;
    return send;
  }

  void Reset() {
    held_ = false;
    alone_ = false;
  }

 private:
  bool held_ = false;
  bool alone_ = false;
};

#endif  // RUNNER_MENU_MASK_H_
