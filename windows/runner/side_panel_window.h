// Native shell windows for the clipboard quick-paste side panel (issue 04/09
// Windows port). Structural precedent: snippet_picker_window.{h,cpp} (a
// second-Flutter-engine shell that DOES take keyboard focus, unlike the
// floating button/overlay). Behavioral precedent: macos/Runner/
// SidePanelWindow.swift + SidePanelHost.swift.
//
// One window class. The edge trigger is no window any more (#1782): an
// always-on-top strip at the screen edge ate every mouse event there, also in
// games that scroll their camera at the edge, and stayed after the panel was
// switched off. SidePanelHost now samples the pointer position
// (side_panel_edge_core.h) and nothing at the edge takes input.
//
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

  // Fired when this shell's own WM_ACTIVATE reports WA_INACTIVE while shown
  // -- some other top-level window (outside this process) just took
  // activation away, e.g. the user clicked another app's window or
  // Alt-Tabbed without the pointer ever leaving this shell's client area.
  // TME_LEAVE-based on_content_exit above only fires on real pointer motion,
  // so a focus switch that leaves the cursor resting over the panel was
  // never observed by anything, and the panel stayed open until the pointer
  // eventually moved -- mirrors SnippetPickerWindow::on_focus_lost /
  // SidePanelHost.swift's windowDidResignKey, both added for exactly this
  // gap. No activation-settle suppression needed here (see side_panel_host
  // .h's file comment): unlike SnippetPickerHost, nothing on this path calls
  // SetForegroundWindow on another window, so there is no self-inflicted
  // WA_INACTIVE to filter out.
  std::function<void()> on_deactivate;

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
