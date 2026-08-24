// Native shell windows for the clipboard quick-paste side panel (issue 04/09
// Windows port). Structural precedent: snippet_picker_window.{h,cpp} (a
// second-Flutter-engine shell that DOES take keyboard focus, unlike the
// floating button/overlay). Behavioral precedent: macos/Runner/
// SidePanelWindow.swift + SidePanelHost.swift.
//
// Two window classes, mirroring the macOS pair:
//   * SidePanelSensorWindow  -- one per monitor, hugs the LEFT edge (see
//     SidePanelWindow.swift's file comment for why left, and why a few
//     points wide rather than 1px). Non-activating (WS_EX_NOACTIVATE), never
//     takes focus. Reports a raw enter/exit immediately and a dwelled
//     "hover entered" after SidePanelHost::kDwellDelayMs -- both via the
//     standard Win32 TrackMouseEvent(TME_HOVER | TME_LEAVE) idiom rather
//     than an app-level timer: WM_MOUSEHOVER's dwell is a system-owned
//     timer that (unlike a naive SetTimer) is not at risk of the
//     .eventTrackingRunLoopMode starvation macOS's Timer.scheduledTimer hit
//     (see SidePanelWindow.swift's mouseEntered doc comment) -- Win32's
//     single message queue has no equivalent mode split, so there is
//     nothing here to port that fix for.
//   * SidePanelContentWindow -- the actual panel: a focusable WS_POPUP shell
//     hosting the render engine's Flutter child, slid in/out along X with a
//     self-driven WM_TIMER animation (Win32 has no NSAnimationContext
//     equivalent). Tracks its own hover (TME_LEAVE only, no dwell needed --
//     the panel is already open) to drive the native close-grace fallback,
//     mirroring SidePanelContentHoverTracker in SidePanelHost.swift.
//
// Unlike SnippetPickerWindow, this shell needs no previousFrontApp save/
// restore and no activation-settle suppression window: see side_panel_host
// .h's file comment for why the Windows paste-target invariant doesn't need
// either, the same asymmetry SnippetPickerHost already documents.

#ifndef SIDE_PANEL_WINDOW_H_
#define SIDE_PANEL_WINDOW_H_

#include <windows.h>

#include <dwmapi.h>

#include <functional>
#include <optional>

// ═══════════════════════════════════════════════════════════════════════
// SidePanelSensorWindow -- one per NSScreen/HMONITOR equivalent
// ═══════════════════════════════════════════════════════════════════════
class SidePanelSensorWindow {
 public:
  SidePanelSensorWindow();
  ~SidePanelSensorWindow();

  SidePanelSensorWindow(const SidePanelSensorWindow&) = delete;
  SidePanelSensorWindow& operator=(const SidePanelSensorWindow&) = delete;

  // |px|/|py|/|pwidth|/|pheight| are the strip's rect in PHYSICAL pixels,
  // already DPI-resolved by the caller (SidePanelHost::RebuildSensors owns
  // that math, same split as SnippetPickerHost::ComputePanelRect).
  bool Create(int px, int py, int pwidth, int pheight, int dwell_ms);
  void Destroy();

  void UpdateRect(int px, int py, int pwidth, int pheight);

  // Fired after the dwell elapses (WM_MOUSEHOVER).
  std::function<void()> on_hover_entered;
  // Fired immediately on the raw WM_MOUSEMOVE that starts tracking, and on
  // WM_MOUSELEAVE respectively -- see the file comment on why these exist
  // alongside the dwelled signal (keeps an already-open panel alive while
  // the pointer sits on the strip instead of the panel proper).
  std::function<void()> on_raw_enter;
  std::function<void()> on_raw_exit;

 private:
  static bool EnsureClassRegistered();
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);

  // |leave_only| arms TME_LEAVE without TME_HOVER -- used to re-arm after a
  // hover has already fired once, so the strip doesn't keep re-signalling
  // on_hover_entered while the pointer sits still on it.
  void ArmTracking(bool leave_only = false);

  static bool class_registered_;

  HWND hwnd_ = nullptr;
  int dwell_ms_ = 60;
  bool tracking_ = false;
  bool shutting_down_ = false;
};

// ═══════════════════════════════════════════════════════════════════════
// SidePanelContentWindow -- the actual panel shell
// ═══════════════════════════════════════════════════════════════════════
class SidePanelContentWindow {
 public:
  SidePanelContentWindow();
  ~SidePanelContentWindow();

  SidePanelContentWindow(const SidePanelContentWindow&) = delete;
  SidePanelContentWindow& operator=(const SidePanelContentWindow&) = delete;

  // Created off-screen and hidden; |flutter_child| is the render engine's
  // view HWND (reparented in, fills the client area). All rects are
  // PHYSICAL pixels, pre-resolved by the caller (SidePanelHost).
  bool Create(int px, int py, int pwidth, int pheight, HWND flutter_child);
  void Destroy();

  // Places the window at (staging_x, y, width, height) instantly, shows it
  // non-activated, then animates x from staging_x to shown_x over
  // |duration_ms| and claims keyboard focus for the Flutter child --
  // mirrors SidePanelHost.slideIn's orderFront-then-animate-then-makeKey
  // ordering (the focus claim happens at the START, not after the
  // animation settles, same as macOS).
  void SlideIn(int staging_x, int shown_x, int y, int width, int height,
              int duration_ms);

  // Animates x from the current position back to staging_x over
  // |duration_ms|, hiding the window (ShowWindow(SW_HIDE)) once it lands.
  void SlideOut(int staging_x, int duration_ms);

  // Instant reposition/resize while NOT shown -- mirrors
  // SidePanelHost.positionPanel's "not currently shown -- safe to relocate"
  // branch (e.g. the user hovered a different monitor's edge this time).
  void SetRect(int px, int py, int pwidth, int pheight);

  bool visible() const { return visible_; }
  HWND hwnd() const { return hwnd_; }

  // Native close-grace fallback, mirrors SidePanelContentHoverTracker.
  std::function<void()> on_content_enter;
  std::function<void()> on_content_exit;

  // Forwarded to the render engine's FlutterViewController::
  // HandleTopLevelWindowProc before this window's own handling -- same
  // reasoning as SnippetPickerWindow::forward_to_flutter.
  std::function<std::optional<LRESULT>(HWND, UINT, WPARAM, LPARAM)>
      forward_to_flutter;

 private:
  static bool EnsureClassRegistered();
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);

  void ApplyChildSize(int pwidth, int pheight);
  void ArmContentTracking();
  void ClaimKeyboardFocus();

  void StartAnimation(int from_x, int to_x, int duration_ms, bool hide_on_done);
  void StepAnimation();

  static bool class_registered_;

  static constexpr UINT_PTR kAnimTimerId = 1;
  static constexpr UINT kAnimIntervalMs = 16;  // ~60fps

  HWND hwnd_ = nullptr;
  HWND flutter_child_ = nullptr;

  bool visible_ = false;
  bool shutting_down_ = false;
  bool content_tracking_ = false;

  // ── Animation state ─────────────────────────────────────────────────
  bool animating_ = false;
  bool anim_hide_on_done_ = false;
  int anim_from_x_ = 0;
  int anim_to_x_ = 0;
  int anim_y_ = 0;
  int anim_w_ = 0;
  int anim_h_ = 0;
  ULONGLONG anim_start_tick_ = 0;
  int anim_duration_ms_ = 220;
};

#endif  // SIDE_PANEL_WINDOW_H_
