// Native Win32 floating button window — GDI+ rendered, always-on-top overlay.
// No Flutter dependency. Pure Win32/GDI+.

#ifndef FLOATING_BUTTON_WINDOW_H_
#define FLOATING_BUTTON_WINDOW_H_

#include <windows.h>
#include <gdiplus.h>

#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

// Visual state of the floating button (set from Dart).
enum class FloatingButtonState {
  kIdle = 0,
  kRecording,
  kTranscribing,
  kDone,
  kError,
  kDisabled,
};

// Native Win32 layered popup window rendered with GDI+.
// Owned by FloatingButtonHost (Phase 3.2) which connects it to Flutter.
class FloatingButtonWindow {
 public:
  using ClickCallback = std::function<void()>;
  using ContextMenuCallback = std::function<void(const std::string& id)>;
  using DragEndCallback =
      std::function<void(double logical_x, double logical_y)>;

  FloatingButtonWindow();
  ~FloatingButtonWindow();

  FloatingButtonWindow(const FloatingButtonWindow&) = delete;
  FloatingButtonWindow& operator=(const FloatingButtonWindow&) = delete;

  // Create the native window as an owned popup of |owner|.
  // Position is in logical (DIP) pixels.
  bool Create(HWND owner, double logical_x, double logical_y, int logical_size);
  void Destroy();

  void Show();
  void Hide();
  bool IsVisible() const { return visible_; }
  HWND GetHandle() const { return hwnd_; }

  void SetState(FloatingButtonState state);
  void SetTheme(bool is_dark);
  void SetOpacity(double opacity);
  void SetSize(int logical_size);
  void SetPosition(double logical_x, double logical_y);
  std::pair<double, double> GetPosition() const;

  void SetClickCallback(ClickCallback cb) { click_cb_ = std::move(cb); }
  void SetSecondaryClickCallback(ClickCallback cb) {
    secondary_click_cb_ = std::move(cb);
  }
  void SetContextMenuCallback(ContextMenuCallback cb) {
    context_menu_cb_ = std::move(cb);
  }
  void SetContextMenuItems(
      std::vector<std::pair<std::string, std::wstring>> items) {
    context_menu_items_ = std::move(items);
  }
  void SetDragEndCallback(DragEndCallback cb) {
    drag_end_cb_ = std::move(cb);
  }

  // Re-asserts HWND_TOPMOST z-order. Call after any event that may disrupt
  // the floating window's position in the topmost z-order (e.g., minimize).
  void RefreshTopmost();

 private:
  // ── Win32 window ────────────────────────────────────────────────────
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);
  void BringToTopmost();

  static bool EnsureClassRegistered();
  static bool class_registered_;

  // ── GDI+ lifecycle (ref-counted, once per process) ──────────────────
  static bool AddGdiPlusRef();
  static void ReleaseGdiPlusRef();
  static int gdiplus_ref_count_;
  static ULONG_PTR gdiplus_token_;

  // ── Rendering ───────────────────────────────────────────────────────
  void Render();
  void PaintShadow(Gdiplus::Graphics& g, float cx, float cy, float body_r);
  void PaintBody(Gdiplus::Graphics& g, float cx, float cy, float r);
  void PaintIcon(Gdiplus::Graphics& g, float cx, float cy, float icon_size);
  void PaintPulseRing(Gdiplus::Graphics& g, float cx, float cy, float base_r);

  // Lucide icon drawing (all in 24×24 coordinate space).
  void DrawMicIcon(Gdiplus::Graphics& g, Gdiplus::Pen& pen);
  void DrawSquareIcon(Gdiplus::Graphics& g, Gdiplus::Pen& pen);
  void DrawLoaderIcon(Gdiplus::Graphics& g, Gdiplus::Pen& pen,
                      float rotation_deg);
  void DrawCheckIcon(Gdiplus::Graphics& g, Gdiplus::Pen& pen);
  void DrawAlertIcon(Gdiplus::Graphics& g, Gdiplus::Pen& pen);

  // ── Animation ───────────────────────────────────────────────────────
  static void CALLBACK AnimTimerProc(HWND, UINT, UINT_PTR, DWORD);
  void OnAnimTick();
  void StartAnimTimer();
  void StopAnimTimer();
  bool NeedsAnimation() const;

  // ── DPI ─────────────────────────────────────────────────────────────
  double GetDpiScale() const;
  double GetDpiScaleForOwner() const;
  int ToPhysical(double logical) const;
  double ToLogical(int physical) const;
  int GetOuterPhysical() const;

  // ── Position ────────────────────────────────────────────────────────
  void ApplyWindowPosition();
  void ValidatePosition();

  // ── Thread safety ──────────────────────────────────────────────────
  bool IsOnCreatingThread() const;

  // ── Gradient helpers ────────────────────────────────────────────────
  struct Gradient {
    Gdiplus::Color c0, c1, c2;  // c1 is the mid-stop (used for 3-stop)
    bool three_stop;
  };
  Gradient ColorsFor(FloatingButtonState s) const;
  static Gdiplus::Color LerpColor(const Gdiplus::Color& a,
                                  const Gdiplus::Color& b, float t);

  // ── State ───────────────────────────────────────────────────────────
  HWND hwnd_ = nullptr;
  HWND owner_ = nullptr;
  bool shutting_down_ = false;
  bool visible_ = false;
  bool gdi_plus_acquired_ = false;
  DWORD creating_thread_id_ = 0;

  FloatingButtonState state_ = FloatingButtonState::kIdle;
  FloatingButtonState prev_state_ = FloatingButtonState::kIdle;
  bool is_dark_ = true;
  double opacity_ = 1.0;
  int logical_size_ = 56;
  double logical_x_ = 0.0;
  double logical_y_ = 0.0;

  // Animation
  UINT_PTR anim_timer_ = 0;
  DWORD anim_origin_ = 0;       // GetTickCount at animation start
  DWORD transition_start_ = 0;  // GetTickCount at last state change

  // Drag
  bool dragging_ = false;
  bool drag_moved_ = false;
  POINT drag_cursor_start_ = {};
  POINT drag_window_start_ = {};

  // Callbacks
  ClickCallback click_cb_;
  ClickCallback secondary_click_cb_;
  ContextMenuCallback context_menu_cb_;
  DragEndCallback drag_end_cb_;

  // Context menu items (id, wideLabel).
  std::vector<std::pair<std::string, std::wstring>> context_menu_items_;
};

#endif  // FLOATING_BUTTON_WINDOW_H_
