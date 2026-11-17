// Decision logic of the side panel's edge trigger (#1782), shared contract of
// all three runners. Keep windows/runner/side_panel_edge_core.h byte-identical
// to this file; SidePanelEdgeCore in macos/Runner/SidePanelWindow.swift mirrors
// the same rules (checked by test/scripts/side_panel_edge_core_test.sh).
//
// Why it exists: the edge trigger used to be an invisible, always-on-top
// window strip at the screen edge. It ate every mouse event there, also in
// games that scroll their camera when the pointer touches the edge, and on
// Windows and macOS it was created at startup even with the panel switched
// off. Windows and macOS now watch the pointer position instead (nothing at
// the edge takes input); Linux keeps a strip, because a Wayland session gives
// no global pointer position, and hides it while a fullscreen window is
// focused. Rules:
// * The zone is the first [width] px along the docked edge of a monitor's
//   work area, top to bottom.
// * A fullscreen app in front (game, presentation, video) switches the trigger
//   off: the caller passes that as "not in the zone".
// * Raw enter/exit fire at once (they keep an open panel alive); the open
//   signal fires once per visit after [dwell] ms in the zone, and only while
//   no mouse button is held (dragging a window to the edge must not open it).
//
// Pure logic on millisecond timestamps, no clocks, no windowing API, so it can
// be tested with simulated time.

#ifndef RUNNER_SIDE_PANEL_EDGE_CORE_H_
#define RUNNER_SIDE_PANEL_EDGE_CORE_H_

#include <cstdint>

namespace side_panel_edge {

constexpr int kZoneWidth = 6;         // logical px, DPI-scaled by the caller
constexpr int64_t kDwellMs = 60;      // pointer must rest this long to open
constexpr int64_t kPollMs = 40;       // pointer sampling interval

struct Rect {
  int left = 0;
  int top = 0;
  int right = 0;  // exclusive
  int bottom = 0;  // exclusive
};

// Whether (x, y) lies in the [width]-px strip along the docked edge of
// [work_area]. [dock_right] picks the right edge instead of the left.
inline bool InZone(int x, int y, const Rect& work_area, int width,
                   bool dock_right) {
  if (width <= 0) return false;
  if (y < work_area.top || y >= work_area.bottom) return false;
  if (x < work_area.left || x >= work_area.right) return false;
  return dock_right ? x >= work_area.right - width
                    : x < work_area.left + width;
}

// Whether a window with [window] bounds fills the whole [monitor] (not just
// its work area): a fullscreen or borderless-fullscreen app. A maximised
// window stops at the taskbar/menu bar and does not count.
inline bool CoversMonitor(const Rect& window, const Rect& monitor) {
  if (monitor.right <= monitor.left || monitor.bottom <= monitor.top) {
    return false;
  }
  return window.left <= monitor.left && window.top <= monitor.top &&
         window.right >= monitor.right && window.bottom >= monitor.bottom;
}

struct Events {
  bool raw_enter = false;
  bool raw_exit = false;
  bool open = false;
};

class Tracker {
 public:
  explicit Tracker(int64_t dwell_ms = kDwellMs) : dwell_ms_(dwell_ms) {}

  // One pointer sample. [in_zone] already folds in "no fullscreen app in
  // front"; [buttons_down] is whether any mouse button is held.
  Events Update(bool in_zone, bool buttons_down, int64_t now_ms) {
    Events e;
    if (!in_zone) {
      if (inside_) {
        inside_ = false;
        e.raw_exit = true;
      }
      return e;
    }
    if (!inside_) {
      inside_ = true;
      opened_ = false;
      entered_ms_ = now_ms;
      e.raw_enter = true;
    }
    if (buttons_down) {
      // A held button restarts the dwell: only a resting pointer opens.
      entered_ms_ = now_ms;
      return e;
    }
    if (!opened_ && now_ms - entered_ms_ >= dwell_ms_) {
      opened_ = true;
      e.open = true;
    }
    return e;
  }

  // Forget the current visit (trigger switched off). No events.
  void Reset() {
    inside_ = false;
    opened_ = false;
    entered_ms_ = 0;
  }

  bool inside() const { return inside_; }

 private:
  int64_t dwell_ms_;
  bool inside_ = false;
  bool opened_ = false;
  int64_t entered_ms_ = 0;
};

}  // namespace side_panel_edge

#endif  // RUNNER_SIDE_PANEL_EDGE_CORE_H_
