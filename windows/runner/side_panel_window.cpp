#include "side_panel_window.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr const wchar_t kSensorClassName[] = L"WHISPASTE_SIDE_PANEL_SENSOR_V1";
constexpr const wchar_t kContentClassName[] = L"WHISPASTE_SIDE_PANEL_CONTENT_V1";

}  // namespace

// ══════════════════════════════════════════════════════════════════════
// SidePanelSensorWindow
// ══════════════════════════════════════════════════════════════════════

bool SidePanelSensorWindow::class_registered_ = false;

bool SidePanelSensorWindow::EnsureClassRegistered() {
  if (class_registered_) return true;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kSensorClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = nullptr;
  if (!RegisterClassExW(&wc)) return false;
  class_registered_ = true;
  return true;
}

SidePanelSensorWindow::SidePanelSensorWindow() = default;
SidePanelSensorWindow::~SidePanelSensorWindow() { Destroy(); }

bool SidePanelSensorWindow::Create(int px, int py, int pwidth, int pheight,
                                   int dwell_ms) {
  if (hwnd_) return true;
  if (!EnsureClassRegistered()) {
    OutputDebugStringW(L"[SidePanel] Sensor RegisterClassEx failed\n");
    return false;
  }

  dwell_ms_ = dwell_ms;

  // WS_EX_NOACTIVATE -- this strip must never take focus, only report
  // hover (see the header's file comment: canBecomeKey is false, matches
  // SidePanelSensorPanel on macOS).
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kSensorClassName,
      L"", WS_POPUP, px, py, pwidth, pheight, nullptr, nullptr,
      GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    OutputDebugStringW(L"[SidePanel] Sensor CreateWindowEx failed\n");
    return false;
  }

  // Fully transparent -- this strip is a hit-test target only, never
  // painted (mirrors SidePanelSensorPanel's isOpaque=false/clear
  // background, just via layered-window alpha instead of an NSView).
  // Alpha=1, not 0: a layered window at exactly alpha=0 is treated by the
  // desktop compositor as click-through and stops receiving mouse input
  // entirely, even without WS_EX_TRANSPARENT (confirmed via on-device
  // repro on SilviosPC -- the window was created successfully at the
  // right DPI-scaled rect but never received WM_MOUSEMOVE/WM_MOUSEHOVER).
  // 1/255 alpha is visually indistinguishable from fully invisible.
  SetWindowLong(hwnd_, GWL_EXSTYLE,
               GetWindowLong(hwnd_, GWL_EXSTYLE) | WS_EX_LAYERED);
  SetLayeredWindowAttributes(hwnd_, 0, 1, LWA_ALPHA);

  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
              SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

  OutputDebugStringW(L"[SidePanel] Sensor window created\n");
  return true;
}

void SidePanelSensorWindow::Destroy() {
  if (shutting_down_) return;
  shutting_down_ = true;
  on_hover_entered = nullptr;
  on_raw_enter = nullptr;
  on_raw_exit = nullptr;
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  tracking_ = false;
  shutting_down_ = false;
}

void SidePanelSensorWindow::UpdateRect(int px, int py, int pwidth,
                                       int pheight) {
  if (!hwnd_) return;
  SetWindowPos(hwnd_, nullptr, px, py, pwidth, pheight,
              SWP_NOZORDER | SWP_NOACTIVATE);
}

void SidePanelSensorWindow::ArmTracking(bool leave_only) {
  if (tracking_) return;
  TRACKMOUSEEVENT tme = {};
  tme.cbSize = sizeof(tme);
  tme.dwFlags = leave_only ? TME_LEAVE : (TME_HOVER | TME_LEAVE);
  tme.hwndTrack = hwnd_;
  tme.dwHoverTime = static_cast<DWORD>(dwell_ms_);
  if (TrackMouseEvent(&tme)) {
    tracking_ = true;
  }
}

LRESULT CALLBACK SidePanelSensorWindow::WndProc(HWND hwnd, UINT msg,
                                                WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return TRUE;
  }
  auto* self = reinterpret_cast<SidePanelSensorWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) return self->HandleMessage(msg, wp, lp);
  return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT SidePanelSensorWindow::HandleMessage(UINT msg, WPARAM wp, LPARAM lp) {
  if (shutting_down_) return DefWindowProcW(hwnd_, msg, wp, lp);

  switch (msg) {
    // Never take focus on click -- mirrors canBecomeKey == false.
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;

    // ── Raw enter (first WM_MOUSEMOVE after leaving) ──────────────────
    // Win32 has no separate "raw enter" message; TrackMouseEvent's own
    // arm-on-first-move is the raw-enter signal (mirrors
    // SidePanelSensorView.mouseEntered firing onRawEnter immediately,
    // dwell separately below via WM_MOUSEHOVER).
    case WM_MOUSEMOVE:
      if (!tracking_) {
        ArmTracking();
        if (on_raw_enter) on_raw_enter();
      }
      return 0;

    // ── Dwelled hover (system-owned timer, see the header's file
    // comment for why this needs no .common-runloop-mode-style fix) ────
    case WM_MOUSEHOVER:
      tracking_ = false;  // TrackMouseEvent auto-clears; re-arm below.
      if (on_hover_entered) on_hover_entered();
      // Re-arm for TME_LEAVE only -- a HOVER already fired, the strip is
      // only a few px wide so the pointer likely leaves immediately onto
      // the content panel; onRawExit still needs to fire when it does.
      // leave_only=true so a stationary pointer doesn't keep re-firing
      // WM_MOUSEHOVER (and therefore on_hover_entered) forever.
      ArmTracking(/*leave_only=*/true);
      return 0;

    case WM_MOUSELEAVE:
      tracking_ = false;
      if (on_raw_exit) on_raw_exit();
      return 0;

    case WM_DISPLAYCHANGE:
      return 0;

    case WM_DESTROY:
      return 0;

    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
      hwnd_ = nullptr;
      tracking_ = false;
      return 0;
  }

  return DefWindowProcW(hwnd_, msg, wp, lp);
}

// ══════════════════════════════════════════════════════════════════════
// SidePanelContentWindow
// ══════════════════════════════════════════════════════════════════════

bool SidePanelContentWindow::class_registered_ = false;

bool SidePanelContentWindow::EnsureClassRegistered() {
  if (class_registered_) return true;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kContentClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = nullptr;
  if (!RegisterClassExW(&wc)) return false;
  class_registered_ = true;
  return true;
}

SidePanelContentWindow::SidePanelContentWindow() = default;
SidePanelContentWindow::~SidePanelContentWindow() { Destroy(); }

bool SidePanelContentWindow::Create(int px, int py, int pwidth, int pheight,
                                    HWND flutter_child) {
  if (hwnd_) return true;
  if (!EnsureClassRegistered()) {
    OutputDebugStringW(L"[SidePanel] Content RegisterClassEx failed\n");
    return false;
  }

  flutter_child_ = flutter_child;

  // WS_EX_TOPMOST + WS_EX_TOOLWINDOW, deliberately WITHOUT WS_EX_NOACTIVATE
  // -- same rationale as SnippetPickerWindow (this shell DOES take
  // keyboard focus). Created off-screen and hidden (see the header doc);
  // caller passes the staging rect.
  hwnd_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kContentClassName,
                          L"", WS_POPUP, px, py, pwidth, pheight, nullptr,
                          nullptr, GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    OutputDebugStringW(L"[SidePanel] Content CreateWindowEx failed\n");
    return false;
  }

  MARGINS m = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd_, &m);

  ApplyChildSize(pwidth, pheight);

  OutputDebugStringW(L"[SidePanel] Content window created\n");
  return true;
}

void SidePanelContentWindow::Destroy() {
  if (shutting_down_) return;
  shutting_down_ = true;

  on_content_enter = nullptr;
  on_content_exit = nullptr;
  forward_to_flutter = nullptr;

  if (animating_) {
    KillTimer(hwnd_, kAnimTimerId);
    animating_ = false;
  }

  if (flutter_child_ && IsWindow(flutter_child_)) {
    SetParent(flutter_child_, nullptr);
    flutter_child_ = nullptr;
  }

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  visible_ = false;
  content_tracking_ = false;
  shutting_down_ = false;
}

void SidePanelContentWindow::SetRect(int px, int py, int pwidth,
                                     int pheight) {
  if (!hwnd_ || visible_) return;
  SetWindowPos(hwnd_, nullptr, px, py, pwidth, pheight,
              SWP_NOZORDER | SWP_NOACTIVATE);
  ApplyChildSize(pwidth, pheight);
}

void SidePanelContentWindow::ApplyChildSize(int pwidth, int pheight) {
  if (!flutter_child_) return;
  LONG style = GetWindowLong(flutter_child_, GWL_STYLE);
  style = (style & ~(WS_OVERLAPPEDWINDOW | WS_CAPTION | WS_BORDER)) |
          WS_CHILD;
  SetWindowLong(flutter_child_, GWL_STYLE, style);
  SetParent(flutter_child_, hwnd_);
  SetWindowPos(flutter_child_, nullptr, 0, 0, pwidth, pheight,
              SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void SidePanelContentWindow::ArmContentTracking() {
  if (content_tracking_) return;
  TRACKMOUSEEVENT tme = {};
  tme.cbSize = sizeof(tme);
  tme.dwFlags = TME_LEAVE;
  tme.hwndTrack = hwnd_;
  if (TrackMouseEvent(&tme)) {
    content_tracking_ = true;
  }
}

void SidePanelContentWindow::ClaimKeyboardFocus() {
  // Same AttachThreadInput fallback as SnippetPickerWindow::Show -- a
  // plain SetForegroundWindow can be silently refused by Windows'
  // foreground-lock when this process has no recent input.
  HWND foreground = ::GetForegroundWindow();
  const DWORD foreground_thread =
      foreground ? ::GetWindowThreadProcessId(foreground, nullptr) : 0;
  const DWORD this_thread = ::GetWindowThreadProcessId(hwnd_, nullptr);

  bool attached = false;
  if (foreground_thread != 0 && this_thread != 0 &&
      foreground_thread != this_thread) {
    attached =
        ::AttachThreadInput(foreground_thread, this_thread, TRUE) != FALSE;
  }

  ::SetForegroundWindow(hwnd_);
  ::BringWindowToTop(hwnd_);
  ::SetActiveWindow(hwnd_);

  if (attached) {
    ::AttachThreadInput(foreground_thread, this_thread, FALSE);
  }

  if (flutter_child_) {
    ::SetFocus(flutter_child_);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Slide animation
// ══════════════════════════════════════════════════════════════════════

void SidePanelContentWindow::SlideIn(int staging_x, int shown_x, int y,
                                     int width, int height,
                                     int duration_ms) {
  if (!hwnd_ || shutting_down_) return;

  anim_y_ = y;
  anim_w_ = width;
  anim_h_ = height;

  // Place instantly at the staging position, then show non-activated --
  // mirrors SidePanelHost.slideIn's setFrame(shown:false)/orderFront
  // sequence, keeping the "claim focus at the START, not after the
  // animation settles" ordering the header's doc comment calls out.
  SetWindowPos(hwnd_, HWND_TOPMOST, staging_x, y, width, height,
              SWP_NOACTIVATE);
  ApplyChildSize(width, height);
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  visible_ = true;

  ArmContentTracking();
  ClaimKeyboardFocus();

  StartAnimation(staging_x, shown_x, duration_ms, /*hide_on_done=*/false);
}

void SidePanelContentWindow::SlideOut(int staging_x, int duration_ms) {
  if (!hwnd_ || shutting_down_ || !visible_) return;
  RECT rect = {};
  GetWindowRect(hwnd_, &rect);
  StartAnimation(rect.left, staging_x, duration_ms, /*hide_on_done=*/true);
}

void SidePanelContentWindow::StartAnimation(int from_x, int to_x,
                                            int duration_ms,
                                            bool hide_on_done) {
  if (animating_) {
    KillTimer(hwnd_, kAnimTimerId);
  }
  anim_from_x_ = from_x;
  anim_to_x_ = to_x;
  anim_duration_ms_ = std::max(duration_ms, 1);
  anim_hide_on_done_ = hide_on_done;
  anim_start_tick_ = GetTickCount64();
  animating_ = true;
  SetTimer(hwnd_, kAnimTimerId, kAnimIntervalMs, nullptr);
  // Paint the first frame immediately rather than waiting kAnimIntervalMs.
  StepAnimation();
}

void SidePanelContentWindow::StepAnimation() {
  if (!hwnd_ || !animating_) return;

  const ULONGLONG elapsed = GetTickCount64() - anim_start_tick_;
  double t = anim_duration_ms_ > 0
                ? static_cast<double>(elapsed) / anim_duration_ms_
                : 1.0;
  t = std::clamp(t, 0.0, 1.0);
  // Ease-out (matches CAMediaTimingFunction(name: .easeOut) closely enough
  // for a 220ms slide -- no CAMediaTimingFunction equivalent in Win32).
  const double eased = 1.0 - std::pow(1.0 - t, 3.0);

  const int x = anim_from_x_ +
               static_cast<int>(std::round((anim_to_x_ - anim_from_x_) * eased));
  SetWindowPos(hwnd_, nullptr, x, anim_y_, anim_w_, anim_h_,
              SWP_NOZORDER | SWP_NOACTIVATE);

  // Unlike AppKit's tracking-area reconciliation (which resynthesizes
  // mouseEntered whenever a window's visibility/frame changes under an
  // already-stationary cursor -- see SidePanelSensorView's doc comment),
  // Win32 only ever generates WM_MOUSEMOVE on genuine pointer movement. A
  // user who flicks the pointer to the edge sensor and then holds it still
  // would otherwise never get a WM_MOUSEMOVE once this window slides under
  // the cursor, so TME_LEAVE would never be armed on this window. Arm it
  // proactively as soon as the cursor is within the animated rect (the
  // actual close-grace decision is made at fire time in
  // SidePanelHost::NativeCloseTimerProc, which re-checks cursor-vs-rect
  // directly -- this only needs to make sure a later genuine exit is still
  // observed).
  if (!anim_hide_on_done_) {
    POINT cursor;
    if (GetCursorPos(&cursor)) {
      RECT rect = {x, anim_y_, x + anim_w_, anim_y_ + anim_h_};
      if (PtInRect(&rect, cursor)) {
        ArmContentTracking();
      }
    }
  }

  if (t >= 1.0) {
    KillTimer(hwnd_, kAnimTimerId);
    animating_ = false;
    if (anim_hide_on_done_) {
      ShowWindow(hwnd_, SW_HIDE);
      visible_ = false;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
// WndProc
// ══════════════════════════════════════════════════════════════════════

LRESULT CALLBACK SidePanelContentWindow::WndProc(HWND hwnd, UINT msg,
                                                 WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCT*>(lp);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
    return TRUE;
  }
  auto* self = reinterpret_cast<SidePanelContentWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self) return self->HandleMessage(msg, wp, lp);
  return DefWindowProcW(hwnd, msg, wp, lp);
}

LRESULT SidePanelContentWindow::HandleMessage(UINT msg, WPARAM wp,
                                              LPARAM lp) {
  if (shutting_down_) return DefWindowProcW(hwnd_, msg, wp, lp);

  if (forward_to_flutter) {
    if (auto result = forward_to_flutter(hwnd_, msg, wp, lp)) {
      return *result;
    }
  }

  switch (msg) {
    case WM_MOUSEMOVE:
      ArmContentTracking();
      if (on_content_enter) on_content_enter();
      return 0;

    case WM_MOUSELEAVE:
      content_tracking_ = false;
      if (on_content_exit) on_content_exit();
      return 0;

    // Click-outside / focus-switch detection -- see on_deactivate's doc
    // comment in side_panel_window.h. Only meaningful while shown: this
    // shell also receives WM_ACTIVATE/WA_INACTIVE as part of its own
    // ShowWindow(SW_HIDE) in SlideOut, which on_deactivate's caller
    // (SidePanelHost::HandleContentDeactivate, routed through the same
    // idempotent hoverLeft relay as every other close trigger) tolerates.
    case WM_ACTIVATE:
      if (LOWORD(wp) == WA_INACTIVE && visible_ && on_deactivate) {
        on_deactivate();
      }
      return DefWindowProcW(hwnd_, msg, wp, lp);

    case WM_TIMER:
      if (wp == kAnimTimerId) {
        StepAnimation();
        return 0;
      }
      return DefWindowProcW(hwnd_, msg, wp, lp);

    case WM_DISPLAYCHANGE:
      return 0;

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
      visible_ = false;
      content_tracking_ = false;
      flutter_child_ = nullptr;
      return 0;
  }

  return DefWindowProcW(hwnd_, msg, wp, lp);
}
