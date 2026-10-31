// Thin Win32 WS_POPUP shell for the floating overlay (ADR 0002 Phase 2).
//
// All GDI+ drawing, UpdateLayeredWindow, DirectWrite, and animation timer code
// from Phase 1 has been removed. This file only handles:
//   - Shell window creation / destruction
//   - Show / Hide (SW_SHOWNOACTIVATE)
//   - Position + size (DPI-aware, rectangular)
//   - Parenting the Flutter child HWND
//   - WM_DISPLAYCHANGE notification (fires callback for host re-anchor)
//
// See floating_button_window.h for the canonical template that was followed.
//
// TRANSPARENCY_NOTE:
//   DWM sheet-of-glass transparency via DwmExtendFrameIntoClientArea({-1,-1,-1,-1}).
//   The overlay pill is rectangular (346×80 normal, 236×56 compact), NOT
//   circular. The Flutter render engine paints the transparent soft shadow in
//   the 8 px padding area. Click-through in the shadow corners is left to a
//   follow-up: add WM_NCHITTEST hit-testing based on a rounded-rect inset if
//   needed. For now the full client area is HTCLIENT (Flutter handles it).
//
// HIT-TESTING NOTE:
//   WM_NCHITTEST is not overridden — DefWindowProc returns HTCLIENT for the
//   full client area. The Flutter child HWND covers the entire client area, so
//   the OS routes pointer events to the child. If per-pixel shadow-corner
//   click-through is required, add WM_NCHITTEST returning HTTRANSPARENT for
//   the outer 8 logical-px ring.
//
// NO GDI+, NO UpdateLayeredWindow, NO DirectWrite, NO animation timer.

#ifndef FLOATING_OVERLAY_WINDOW_H_
#define FLOATING_OVERLAY_WINDOW_H_

#include <windows.h>
#include <dwmapi.h>

#include <functional>
#include <utility>

// Thin lifecycle-only WS_POPUP shell for the overlay.
// All GDI+ drawing has been removed. The Flutter engine child HWND paints.
class FloatingOverlayWindow {
 public:
  // Fires when the display configuration changes (monitor plug/unplug).
  // The host re-resolves the anchor-based position and calls SetPosition().
  using DisplayChangeCallback = std::function<void()>;

  FloatingOverlayWindow();
  ~FloatingOverlayWindow();

  FloatingOverlayWindow(const FloatingOverlayWindow&) = delete;
  FloatingOverlayWindow& operator=(const FloatingOverlayWindow&) = delete;

  // Create the WS_POPUP shell. Position is in logical (DIP) pixels.
  // |flutter_child| is the HWND returned by
  // render_controller->view()->GetNativeWindow() — it is reparented into
  // the shell and fills the client area.
  bool Create(HWND owner, double logical_x, double logical_y,
              int logical_w, int logical_h, HWND flutter_child);
  void Destroy();

  void Show();
  void Hide();
  bool IsVisible() const { return visible_; }
  HWND GetHandle() const { return hwnd_; }

  // Resize the shell (and its Flutter child). Both dimensions in logical px.
  void SetSize(int logical_w, int logical_h);
  void SetPosition(double logical_x, double logical_y);
  std::pair<double, double> GetPosition() const;

  // Re-asserts HWND_TOPMOST z-order. Call from FlutterWindow::MessageHandler
  // on WM_SIZE(minimize) and WM_ACTIVATEAPP.
  void RefreshTopmost();

  void SetDisplayChangeCallback(DisplayChangeCallback cb) {
    display_change_cb_ = std::move(cb);
  }

 private:
  // ── Win32 window ─────────────────────────────────────────────────────
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);
  void BringToTopmost();

  static bool EnsureClassRegistered();
  static bool class_registered_;

  // ── DPI ──────────────────────────────────────────────────────────────
  double GetDpiScale() const;
  double GetDpiScaleForOwner() const;
  int ToPhysical(double logical) const;
  double ToLogical(int physical) const;

  // ── Position / size helpers ──────────────────────────────────────────
  void ApplyWindowPosition();
  void ApplyChildSize();
  // Clamp the top-left so the window stays within the nearest monitor's work area.
  void ValidatePosition();

  // ── State ────────────────────────────────────────────────────────────
  HWND hwnd_ = nullptr;
  HWND flutter_child_ = nullptr;  // child Flutter view HWND (not owned)
  HWND owner_ = nullptr;          // kept for DPI lookups only
  bool shutting_down_ = false;
  bool visible_ = false;
  DWORD creating_thread_id_ = 0;

  // Logical size in DIPs. Normal 346×80, compact 236×56.
  int logical_w_ = 346;
  int logical_h_ = 80;
  double logical_x_ = 0.0;
  double logical_y_ = 0.0;

  DisplayChangeCallback display_change_cb_;
};

#endif  // FLOATING_OVERLAY_WINDOW_H_
