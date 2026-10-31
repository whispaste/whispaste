// Thin Win32 WS_POPUP shell for the floating button (ADR 0002 Phase 2).
//
// All GDI+ drawing, UpdateLayeredWindow, and animation timer code from Phase 1
// has been removed. This file only handles:
//   - Shell window creation / destruction
//   - Show / Hide (SW_SHOWNOACTIVATE)
//   - Position + size (DPI-aware)
//   - Parenting the Flutter child HWND
//   - WM_NCHITTEST → HTTRANSPARENT outside the disc so clicks fall through
//
// TRANSPARENCY_NOTE:
//   We apply DWM sheet-of-glass transparency via DwmExtendFrameIntoClientArea
//   with MARGINS {-1,-1,-1,-1}. This tells DWM to composite the window's
//   content (Flutter's D3D surface) over a transparent background instead of
//   opaque black.
//
//   If testing on-device shows an opaque black or white background:
//     Option A — call Window.setEffect(effect: WindowEffect.transparent) from
//       the Dart render entrypoint using the flutter_acrylic plugin (already
//       bundled as flutter_acrylic_plugin.dll).
//     Option B — set the DWM composition policy and/or enable WCA_ACCENT_POLICY
//       via SetWindowCompositionAttribute (undocumented but widely used).
//   Document whichever workaround is needed here after on-device validation.
//
// HIT-TESTING NOTE:
//   WM_NCHITTEST returns HTTRANSPARENT for pixels outside the disc radius so
//   mouse events pass through to windows behind. The Flutter child HWND
//   receives all events within the disc because the Flutter embedder forwards
//   input from the parent shell. This may require on-device tuning if Flutter
//   consumes events differently at the child-HWND boundary.

#include "floating_button_window.h"

#include <windowsx.h>  // GET_X_LPARAM, GET_Y_LPARAM
#include <algorithm>
#include <cmath>

#pragma comment(lib, "dwmapi.lib")

namespace {

constexpr const wchar_t kClassName[] = L"WHISPASTE_FLOATING_BTN_V2";

}  // namespace

// ── Static members ────────────────────────────────────────────────────
bool FloatingButtonWindow::class_registered_ = false;

// ══════════════════════════════════════════════════════════════════════
// Window class registration
// ══════════════════════════════════════════════════════════════════════

bool FloatingButtonWindow::EnsureClassRegistered() {
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

FloatingButtonWindow::FloatingButtonWindow() = default;
FloatingButtonWindow::~FloatingButtonWindow() { Destroy(); }

// ══════════════════════════════════════════════════════════════════════
// Create / Destroy
// ══════════════════════════════════════════════════════════════════════

bool FloatingButtonWindow::Create(HWND owner, double lx, double ly,
                                  int total_logical_size, HWND flutter_child) {
  if (hwnd_) return true;

  if (!EnsureClassRegistered()) {
    OutputDebugStringW(L"[FloatingButton] RegisterClassEx failed\n");
    return false;
  }

  owner_ = owner;
  flutter_child_ = flutter_child;
  total_logical_size_ = std::max(total_logical_size, 32);
  logical_x_ = lx;
  logical_y_ = ly;

  double dpi = GetDpiScaleForOwner();
  int phys = static_cast<int>(std::round(total_logical_size_ * dpi));
  int px = static_cast<int>(std::round(lx * dpi));
  int py = static_cast<int>(std::round(ly * dpi));

  // WS_EX_LAYERED is intentionally absent — it is incompatible with a Flutter
  // D3D child surface. DWM transparency is achieved via
  // DwmExtendFrameIntoClientArea (see below).
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kClassName, L"", WS_POPUP,
      px, py, phys, phys,
      nullptr,  // no Win32 owner — see Phase 1 note: avoids auto-minimize
      nullptr, GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    OutputDebugStringW(L"[FloatingButton] CreateWindowEx failed\n");
    return false;
  }

  // ── DWM sheet-of-glass transparency ───────────────────────────────
  // Extends the DWM frame across the entire client area (-1 = all edges).
  // This composites the Flutter surface over a transparent background.
  // See TRANSPARENCY_NOTE above if this produces a black background on device.
  MARGINS m = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd_, &m);

  // ── Parent the Flutter view into the shell ─────────────────────────
  if (flutter_child_) {
    // Remove the Flutter child's own title bar / borders; keep WS_CHILD.
    LONG style = GetWindowLong(flutter_child_, GWL_STYLE);
    style = (style & ~(WS_OVERLAPPEDWINDOW | WS_CAPTION | WS_BORDER)) |
            WS_CHILD;
    SetWindowLong(flutter_child_, GWL_STYLE, style);
    SetParent(flutter_child_, hwnd_);
    // Flutter child fills the entire client area.
    SetWindowPos(flutter_child_, nullptr, 0, 0, phys, phys,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  }

  creating_thread_id_ = GetCurrentThreadId();
  OutputDebugStringW(L"[FloatingButton] Shell window created (v2, Flutter child)\n");
  return true;
}

void FloatingButtonWindow::Destroy() {
  if (shutting_down_) return;
  shutting_down_ = true;

  drag_end_cb_ = nullptr;

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

void FloatingButtonWindow::Show() {
  if (!hwnd_ || shutting_down_) return;
  ValidatePosition();
  ApplyWindowPosition();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  BringToTopmost();
  visible_ = true;
}

void FloatingButtonWindow::Hide() {
  if (!hwnd_ || shutting_down_) return;
  ShowWindow(hwnd_, SW_HIDE);
  visible_ = false;
}

void FloatingButtonWindow::BringToTopmost() {
  if (!hwnd_) return;
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void FloatingButtonWindow::RefreshTopmost() {
  if (!hwnd_ || shutting_down_) return;
  BringToTopmost();
}

// ══════════════════════════════════════════════════════════════════════
// Public setters
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonWindow::SetTotalSize(int total_logical_size) {
  total_logical_size_ = std::max(total_logical_size, 32);
  if (hwnd_) {
    int phys = static_cast<int>(std::round(total_logical_size_ * GetDpiScale()));
    SetWindowPos(hwnd_, nullptr, 0, 0, phys, phys,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    ApplyChildSize();
  }
}

void FloatingButtonWindow::SetPosition(double lx, double ly) {
  logical_x_ = lx;
  logical_y_ = ly;
  if (hwnd_) ApplyWindowPosition();
}

std::pair<double, double> FloatingButtonWindow::GetPosition() const {
  return {logical_x_, logical_y_};
}

// ══════════════════════════════════════════════════════════════════════
// WndProc
// ══════════════════════════════════════════════════════════════════════

LRESULT CALLBACK FloatingButtonWindow::WndProc(HWND hwnd, UINT msg,
                                               WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return TRUE;
  }
  auto* self = reinterpret_cast<FloatingButtonWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) return self->HandleMessage(msg, wp, lp);
  return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT FloatingButtonWindow::HandleMessage(UINT msg, WPARAM wp, LPARAM lp) {
  if (shutting_down_) return DefWindowProcW(hwnd_, msg, wp, lp);

  switch (msg) {
    // ── Focus prevention ──────────────────────────────────────────────
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;

    // ── Transparent corners (click-through outside disc) ──────────────
    // The disc sits centred in the total_logical_size window with
    // shadowPadding (8 logical px) on every side.  Clicks landing in
    // the corner padding fall through to whatever is behind.
    //
    // HIT-TESTING NOTE: because Flutter's child HWND covers the full
    // client area, the OS routes pointer events to the child before the
    // shell's WM_NCHITTEST. WM_NCHITTEST therefore only handles the case
    // where the pointer is over the transparent shell frame (non-client
    // area or before child routing).  Empirically this is sufficient for
    // the corner-passthrough behaviour on Windows 10/11, but flag for
    // on-device verification.
    case WM_NCHITTEST: {
      POINT pt = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
      ScreenToClient(hwnd_, &pt);
      double dpi = GetDpiScale();
      int phys = static_cast<int>(std::round(total_logical_size_ * dpi));
      float cx = phys / 2.0f;
      float cy = phys / 2.0f;
      // Disc radius = (total - 2*shadowPadding) / 2 = (total - 16) / 2.
      float disc_logical = static_cast<float>((total_logical_size_ - 16) / 2.0);
      float r = static_cast<float>(disc_logical * dpi);
      float dx = static_cast<float>(pt.x) - cx;
      float dy = static_cast<float>(pt.y) - cy;
      if (dx * dx + dy * dy <= r * r) return HTCLIENT;
      return HTTRANSPARENT;
    }

    // ── Re-assert topmost if z-order was changed externally ──────────
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
    case WM_DISPLAYCHANGE:
      if (visible_) {
        ValidatePosition();
        ApplyWindowPosition();
      }
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

double FloatingButtonWindow::GetDpiScale() const {
  if (!hwnd_) return GetDpiScaleForOwner();
  UINT dpi = GetDpiForWindow(hwnd_);
  return dpi / 96.0;
}

double FloatingButtonWindow::GetDpiScaleForOwner() const {
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

int FloatingButtonWindow::ToPhysical(double logical) const {
  return static_cast<int>(std::round(logical * GetDpiScale()));
}

double FloatingButtonWindow::ToLogical(int physical) const {
  double dpi = GetDpiScale();
  return (dpi > 0) ? physical / dpi : static_cast<double>(physical);
}

// ══════════════════════════════════════════════════════════════════════
// Position / size helpers
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonWindow::ApplyWindowPosition() {
  if (!hwnd_) return;
  int phys = static_cast<int>(std::round(total_logical_size_ * GetDpiScale()));
  int px = ToPhysical(logical_x_);
  int py = ToPhysical(logical_y_);
  SetWindowPos(hwnd_, nullptr, px, py, phys, phys,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FloatingButtonWindow::ApplyChildSize() {
  if (!hwnd_ || !flutter_child_) return;
  int phys = static_cast<int>(std::round(total_logical_size_ * GetDpiScale()));
  SetWindowPos(flutter_child_, nullptr, 0, 0, phys, phys,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FloatingButtonWindow::ValidatePosition() {
  // Clamp to nearest monitor's work area so the button stays on-screen.
  POINT pt = {ToPhysical(logical_x_), ToPhysical(logical_y_)};
  HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(mon, &mi)) return;

  const RECT& wa = mi.rcWork;
  int half = static_cast<int>(std::round(total_logical_size_ * GetDpiScale())) / 2;
  int cx = std::clamp(pt.x, wa.left + half, wa.right - half);
  int cy = std::clamp(pt.y, wa.top + half, wa.bottom - half);

  if (cx != pt.x || cy != pt.y) {
    logical_x_ = ToLogical(cx);
    logical_y_ = ToLogical(cy);
  }
}
