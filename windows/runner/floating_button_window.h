// Thin Win32 WS_POPUP shell for the floating button (ADR 0002 Phase 2).
//
// This file is the remnant of the old GDI+ window after Phase 2 surgery:
// ALL drawing code (GDI+, UpdateLayeredWindow, animation timer) has been
// removed. The class is now lifecycle-only: create/show/hide/move/resize the
// shell window and host the Flutter child HWND inside it.
//
// Choice (Option B): keep the file as a thin shell class instead of deleting
// it and folding everything into the host. Rationale: the host already had
// a `window_` pointer and the show/hide/setPosition/getPosition split is a
// clean seam. The GDI+ statics, gdiplus_helper, and all Paint* methods are
// gone.
//
// Transparency approach (DWM):
// - Window styles: WS_POPUP, WS_EX_TOPMOST | WS_EX_TOOLWINDOW |
//   WS_EX_NOACTIVATE. NO WS_EX_LAYERED — Flutter drives its own surface and
//   UpdateLayeredWindow does NOT apply to windows hosting a Flutter ANGLE/D3D
//   child.
// - DWM transparent frame: DwmExtendFrameIntoClientArea with -1 margins
//   (sheet-of-glass) so DWM composites the Flutter surface over a transparent
//   background. The Flutter Dart side already paints no background in the
//   button render entrypoint.
// - Risk: on some GPU/driver combinations the DWM approach may produce a
//   black background instead of transparency. If that occurs on-device, the
//   alternative is to use the flutter_acrylic plugin's
//   Window.setEffect(effect: WindowEffect.transparent) API from the Dart
//   render entrypoint — see TRANSPARENCY_NOTE in .cpp.

#ifndef FLOATING_BUTTON_WINDOW_H_
#define FLOATING_BUTTON_WINDOW_H_

#include <windows.h>
#include <dwmapi.h>

#include <functional>
#include <string>
#include <utility>
#include <vector>

// Thin lifecycle-only WS_POPUP shell.
// All GDI+ drawing has been removed; the Flutter engine child HWND paints.
class FloatingButtonWindow {
 public:
  using DragEndCallback =
      std::function<void(double logical_x, double logical_y)>;

  FloatingButtonWindow();
  ~FloatingButtonWindow();

  FloatingButtonWindow(const FloatingButtonWindow&) = delete;
  FloatingButtonWindow& operator=(const FloatingButtonWindow&) = delete;

  // Create the WS_POPUP shell. Position is in logical (DIP) pixels.
  // |flutter_child| is the HWND returned by
  // render_controller->view()->GetNativeWindow() — it is reparented into
  // the shell and fills the client area.
  bool Create(HWND owner, double logical_x, double logical_y,
              int total_logical_size, HWND flutter_child);
  void Destroy();

  void Show();
  void Hide();
  bool IsVisible() const { return visible_; }
  HWND GetHandle() const { return hwnd_; }

  // Resize the shell (and its Flutter child) to |total_logical_size| × same.
  // total_logical_size = disc_diameter + 2 * shadowPadding (i.e. size + 16).
  void SetTotalSize(int total_logical_size);

  void SetPosition(double logical_x, double logical_y);
  std::pair<double, double> GetPosition() const;

  // Re-asserts HWND_TOPMOST z-order. Call from FlutterWindow::MessageHandler
  // on WM_SIZE(minimize) and WM_ACTIVATEAPP.
  void RefreshTopmost();

  // Context menu items forwarded from Dart (for native TrackPopupMenu).
  void SetContextMenuItems(
      std::vector<std::pair<std::string, std::wstring>> items) {
    context_menu_items_ = std::move(items);
  }

  void SetDragEndCallback(DragEndCallback cb) {
    drag_end_cb_ = std::move(cb);
  }

 private:
  // ── Win32 window ────────────────────────────────────────────────────
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);
  void BringToTopmost();

  static bool EnsureClassRegistered();
  static bool class_registered_;

  // ── DPI ─────────────────────────────────────────────────────────────
  double GetDpiScale() const;
  double GetDpiScaleForOwner() const;
  int ToPhysical(double logical) const;
  double ToLogical(int physical) const;

  void ApplyWindowPosition();
  void ValidatePosition();
  void ApplyChildSize();

  // ── State ────────────────────────────────────────────────────────────
  HWND hwnd_ = nullptr;
  HWND flutter_child_ = nullptr;  // child Flutter view HWND (not owned)
  HWND owner_ = nullptr;          // kept for DPI lookups only
  bool shutting_down_ = false;
  bool visible_ = false;
  DWORD creating_thread_id_ = 0;

  int total_logical_size_ = 72;  // disc + 2*shadowPadding
  double logical_x_ = 0.0;
  double logical_y_ = 0.0;

  // Context menu items (id, wideLabel) — used by host for TrackPopupMenu.
  std::vector<std::pair<std::string, std::wstring>> context_menu_items_;

  // Called by the host after the OS drag loop ends.
  DragEndCallback drag_end_cb_;
};

#endif  // FLOATING_BUTTON_WINDOW_H_
