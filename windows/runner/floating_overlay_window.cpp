// Thin Win32 WS_POPUP shell for the floating overlay (ADR 0002 Phase 2).
//
// Migration from GDI+/DirectWrite drawing (Phase 1) to hosting a second Flutter
// engine (Phase 2). All drawing code has been removed — this file is now a
// structural mirror of floating_button_window.cpp (the canonical template).
//
// Key differences from the button shell:
//   - Rectangular window (logical_w_ × logical_h_) instead of square.
//   - No disc-radius hit-testing; full client area is HTCLIENT.
//   - WM_DISPLAYCHANGE fires display_change_cb_ so the host can re-anchor.
//   - SetSize(w, h) replaces SetTotalSize(n).
//
// TRANSPARENCY_NOTE (identical to floating_button_window.cpp):
//   WS_EX_LAYERED is intentionally absent — incompatible with a Flutter D3D
//   child surface. DWM transparency is achieved via DwmExtendFrameIntoClientArea
//   with MARGINS {-1,-1,-1,-1} (sheet-of-glass).
//
//   If testing on-device shows an opaque black background:
//     Option A — call Window.setEffect(effect: WindowEffect.transparent) from
//       the Dart render entrypoint using the flutter_acrylic plugin.
//     Option B — set WCA_ACCENT_POLICY via SetWindowCompositionAttribute.
//   Document whichever workaround is needed here after on-device validation.
//
// NO GDI+, NO UpdateLayeredWindow, NO DirectWrite, NO animation timer.

#include "floating_overlay_window.h"

#include <windowsx.h>  // GET_X_LPARAM, GET_Y_LPARAM (kept for future use)
#include <algorithm>
#include <cmath>

#pragma comment(lib, "dwmapi.lib")

namespace {

constexpr const wchar_t kClassName[] = L"WHISPASTE_FLOATING_OVL_V2";

}  // namespace

// ── Static members ────────────────────────────────────────────────────
bool FloatingOverlayWindow::class_registered_ = false;

// ══════════════════════════════════════════════════════════════════════
// Window class registration
// ══════════════════════════════════════════════════════════════════════

bool FloatingOverlayWindow::EnsureClassRegistered() {
  if (class_registered_) return true;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  // No background brush — DWM / Flutter paints everything.
  wc.hbrBackground = nullptr;
  if (!RegisterClassExW(&wc)) return false;
  class_registered_ = true;
  return true;
}

// ══════════════════════════════════════════════════════════════════════
// Constructor / Destructor
// ══════════════════════════════════════════════════════════════════════

FloatingOverlayWindow::FloatingOverlayWindow() = default;
FloatingOverlayWindow::~FloatingOverlayWindow() { Destroy(); }

// ══════════════════════════════════════════════════════════════════════
// Create / Destroy
// ══════════════════════════════════════════════════════════════════════

bool FloatingOverlayWindow::Create(HWND owner, double lx, double ly,
                                   int logical_w, int logical_h,
                                   HWND flutter_child) {
  if (hwnd_) return true;

  if (!EnsureClassRegistered()) {
    OutputDebugStringW(L"[FloatingOverlay] RegisterClassEx failed\n");
    return false;
  }

  owner_ = owner;
  flutter_child_ = flutter_child;
  logical_w_ = std::max(logical_w, 32);
  logical_h_ = std::max(logical_h, 32);
  logical_x_ = lx;
  logical_y_ = ly;

  double dpi = GetDpiScaleForOwner();
  int phys_w = static_cast<int>(std::round(logical_w_ * dpi));
  int phys_h = static_cast<int>(std::round(logical_h_ * dpi));
  int px = static_cast<int>(std::round(lx * dpi));
  int py = static_cast<int>(std::round(ly * dpi));

  // WS_EX_LAYERED is intentionally absent — incompatible with a Flutter D3D
  // child surface. See TRANSPARENCY_NOTE in the file header.
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kClassName, L"", WS_POPUP,
      px, py, phys_w, phys_h,
      nullptr,  // no Win32 owner — avoids auto-minimize on main-window minimize
      nullptr, GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    OutputDebugStringW(L"[FloatingOverlay] CreateWindowEx failed\n");
    return false;
  }

  // ── DWM sheet-of-glass transparency ──────────────────────────────────
  // Extends the DWM frame across the entire client area (-1 = all edges).
  // This composites the Flutter surface over a transparent background.
  // See TRANSPARENCY_NOTE above if this produces a black background on device.
  MARGINS m = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd_, &m);

  // ── Parent the Flutter view into the shell ────────────────────────────
  if (flutter_child_) {
    // Remove the Flutter child's own title bar / borders; keep WS_CHILD.
    LONG style = GetWindowLong(flutter_child_, GWL_STYLE);
    style = (style & ~(WS_OVERLAPPEDWINDOW | WS_CAPTION | WS_BORDER)) |
            WS_CHILD;
    SetWindowLong(flutter_child_, GWL_STYLE, style);
    SetParent(flutter_child_, hwnd_);
    // Flutter child fills the entire client area.
    SetWindowPos(flutter_child_, nullptr, 0, 0, phys_w, phys_h,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  }

  creating_thread_id_ = GetCurrentThreadId();
  OutputDebugStringW(
      L"[FloatingOverlay] Shell window created (v2, Flutter child)\n");
  return true;
}

void FloatingOverlayWindow::Destroy() {
  if (shutting_down_) return;
  shutting_down_ = true;

  display_change_cb_ = nullptr;

  // Un-parent the Flutter child before destroying the shell so the Flutter
  // embedder can destroy it cleanly via its own controller teardown.
  if (flutter_child_ && IsWindow(flutter_child_)) {
    SetParent(flutter_child_, nullptr);
    flutter_child_ = nullptr;
  }

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  visible_ = false;
  owner_ = nullptr;
  shutting_down_ = false;
}

// ══════════════════════════════════════════════════════════════════════
// Show / Hide
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::Show() {
  if (!hwnd_ || shutting_down_) return;
  ValidatePosition();
  ApplyWindowPosition();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  BringToTopmost();
  visible_ = true;
}

void FloatingOverlayWindow::Hide() {
  if (!hwnd_ || shutting_down_) return;
  ShowWindow(hwnd_, SW_HIDE);
  visible_ = false;
}

void FloatingOverlayWindow::BringToTopmost() {
  if (!hwnd_) return;
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void FloatingOverlayWindow::RefreshTopmost() {
  if (!hwnd_ || shutting_down_) return;
  BringToTopmost();
}

// ══════════════════════════════════════════════════════════════════════
// Public setters
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::SetSize(int logical_w, int logical_h) {
  logical_w_ = std::max(logical_w, 32);
  logical_h_ = std::max(logical_h, 32);
  if (hwnd_) {
    int phys_w = static_cast<int>(std::round(logical_w_ * GetDpiScale()));
    int phys_h = static_cast<int>(std::round(logical_h_ * GetDpiScale()));
    SetWindowPos(hwnd_, nullptr, 0, 0, phys_w, phys_h,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    ApplyChildSize();
  }
}

void FloatingOverlayWindow::SetPosition(double lx, double ly) {
  logical_x_ = lx;
  logical_y_ = ly;
  if (hwnd_) ApplyWindowPosition();
}

std::pair<double, double> FloatingOverlayWindow::GetPosition() const {
  return {logical_x_, logical_y_};
}

// ══════════════════════════════════════════════════════════════════════
// WndProc
// ══════════════════════════════════════════════════════════════════════

LRESULT CALLBACK FloatingOverlayWindow::WndProc(HWND hwnd, UINT msg,
                                                WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return TRUE;
  }
  auto* self = reinterpret_cast<FloatingOverlayWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) return self->HandleMessage(msg, wp, lp);
  return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT FloatingOverlayWindow::HandleMessage(UINT msg, WPARAM wp, LPARAM lp) {
  if (shutting_down_) return DefWindowProcW(hwnd_, msg, wp, lp);

  switch (msg) {
    // ── Focus prevention ───────────────────────────────────────────────
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;

    // ── Re-assert topmost if z-order was changed externally ────────────
    case WM_WINDOWPOSCHANGED: {
      auto* wp_pos = reinterpret_cast<WINDOWPOS*>(lp);
      if (visible_ && !(wp_pos->flags & SWP_NOZORDER)) {
        if (!(GetWindowLong(hwnd_, GWL_EXSTYLE) & WS_EX_TOPMOST))
          BringToTopmost();
      }
      return DefWindowProcW(hwnd_, msg, wp, lp);
    }

    // ── DPI change ────────────────────────────────────────────────────
    case WM_DPICHANGED:
      ApplyWindowPosition();
      ApplyChildSize();
      return 0;

    // ── Display change (monitor plug/unplug) ──────────────────────────
    // The host re-resolves the anchor-based position and calls SetPosition().
    case WM_DISPLAYCHANGE:
      if (display_change_cb_) display_change_cb_();
      return 0;

    // ── No WM_PAINT needed — Flutter child paints everything ──────────
    case WM_PAINT: {
      PAINTSTRUCT ps;
      BeginPaint(hwnd_, &ps);
      EndPaint(hwnd_, &ps);
      return 0;
    }

    case WM_DESTROY:
      return 0;

    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
      hwnd_ = nullptr;
      owner_ = nullptr;
      visible_ = false;
      flutter_child_ = nullptr;
      return 0;
  }

  return DefWindowProcW(hwnd_, msg, wp, lp);
}

// ══════════════════════════════════════════════════════════════════════
// DPI helpers
// ══════════════════════════════════════════════════════════════════════

double FloatingOverlayWindow::GetDpiScale() const {
  if (!hwnd_) return GetDpiScaleForOwner();
  UINT dpi = GetDpiForWindow(hwnd_);
  return dpi / 96.0;
}

double FloatingOverlayWindow::GetDpiScaleForOwner() const {
  if (owner_) {
    UINT dpi = GetDpiForWindow(owner_);
    if (dpi > 0) return dpi / 96.0;
  }
  HDC dc = GetDC(nullptr);
  if (dc) {
    int dpi = GetDeviceCaps(dc, LOGPIXELSX);
    ReleaseDC(nullptr, dc);
    if (dpi > 0) return dpi / 96.0;
  }
  return 1.0;
}

int FloatingOverlayWindow::ToPhysical(double logical) const {
  return static_cast<int>(std::round(logical * GetDpiScale()));
}

double FloatingOverlayWindow::ToLogical(int physical) const {
  double dpi = GetDpiScale();
  return (dpi > 0) ? physical / dpi : static_cast<double>(physical);
}

// ══════════════════════════════════════════════════════════════════════
// Position / size helpers
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::ApplyWindowPosition() {
  if (!hwnd_) return;
  int phys_w = static_cast<int>(std::round(logical_w_ * GetDpiScale()));
  int phys_h = static_cast<int>(std::round(logical_h_ * GetDpiScale()));
  int px = ToPhysical(logical_x_);
  int py = ToPhysical(logical_y_);
  SetWindowPos(hwnd_, nullptr, px, py, phys_w, phys_h,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FloatingOverlayWindow::ApplyChildSize() {
  if (!hwnd_ || !flutter_child_) return;
  int phys_w = static_cast<int>(std::round(logical_w_ * GetDpiScale()));
  int phys_h = static_cast<int>(std::round(logical_h_ * GetDpiScale()));
  SetWindowPos(flutter_child_, nullptr, 0, 0, phys_w, phys_h,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FloatingOverlayWindow::ValidatePosition() {
  // Clamp top-left so the overlay remains within the nearest monitor's work
  // area. Used on Show() and after WM_DISPLAYCHANGE (via host re-anchor).
  POINT pt = {ToPhysical(logical_x_), ToPhysical(logical_y_)};
  HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(mon, &mi)) return;

  const RECT& wa = mi.rcWork;
  int phys_w = static_cast<int>(std::round(logical_w_ * GetDpiScale()));
  int phys_h = static_cast<int>(std::round(logical_h_ * GetDpiScale()));

  // Clamp so the entire pill fits within the work area.
  int cx = std::clamp(pt.x, wa.left,
                      std::max(wa.left, wa.right - phys_w));
  int cy = std::clamp(pt.y, wa.top,
                      std::max(wa.top, wa.bottom - phys_h));

  if (cx != pt.x || cy != pt.y) {
    logical_x_ = ToLogical(cx);
    logical_y_ = ToLogical(cy);
  }
}
