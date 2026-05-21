// Native Win32 floating overlay — GDI+ + DirectWrite rendered layered window.
// Shows recording/transcription status. Dart owns ALL state; C++ is a dumb renderer.
// Pattern: single UpdateSnapshot(viewModel) call carries the entire view state.

#include "floating_overlay_window.h"
#include "gdiplus_helper.h"

#include <dwmapi.h>
#include <windowsx.h>
#include <algorithm>
#include <cmath>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "dwrite.lib")

using namespace Gdiplus;

namespace {

// ── Window class ──────────────────────────────────────────────────────
constexpr const wchar_t kClassName[] = L"WHISPASTE_FLOATING_OVERLAY";

// ── Layout constants (logical pixels) ─────────────────────────────────
constexpr float kNormalWidth = 380.0f;
constexpr float kCompactWidth = 280.0f;
constexpr float kCompactHeight = 40.0f;
constexpr float kCornerRadius = 14.0f;       // WpRadius.lg
constexpr float kCompactRadius = 20.0f;      // pill shape
constexpr float kAccentBarHeight = 4.0f;
constexpr float kPaddingH = 16.0f;           // horizontal
constexpr float kPaddingTop = 14.0f;
constexpr float kPaddingBottom = 12.0f;
constexpr float kHeaderHeight = 20.0f;       // dot + label + timer line
constexpr float kGapAfterHeader = 10.0f;
constexpr float kWaveformHeight = 24.0f;     // match RecordingPill
constexpr float kBarWidth = 2.5f;            // match in-app pill
constexpr float kBarGap = 1.5f;              // match in-app pill
constexpr float kBarRadius = 2.0f;           // match RecordingPill
constexpr float kShimmerHeight = 4.0f;
constexpr float kProgressHeight = 4.0f;
constexpr float kGapAfterViz = 8.0f;
constexpr float kHintHeight = 14.0f;
constexpr float kErrorMsgHeight = 16.0f;
constexpr float kButtonHeight = 24.0f;
constexpr float kButtonGap = 8.0f;
constexpr float kDotSize = 8.0f;
constexpr float kCloseSize = 36.0f;          // match _PillIconButton 36x36
constexpr float kBadgeHeight = 18.0f;

// ── Pill mode layout (normal, horizontal) ─────────────────────────────
constexpr float kPillHeight = 64.0f;         // 12+36+12+4 = 64 (match RecordingPill)
constexpr float kPillPadH = 16.0f;           // WpSpacing.md
constexpr float kPillGap = 14.0f;            // WpSpacing.sm + extra breathing room
constexpr float kWfStopGap = 22.0f;          // extra margin between waveform and stop button
constexpr float kProgressBarH = 4.0f;
constexpr float kStopBtnSize = 36.0f;        // circle 36x36 (match _PillStopButton)
constexpr float kStopIconSize = 14.0f;       // white square inside stop button
constexpr float kSpinnerSize = 16.0f;        // transcribing spinner diameter
constexpr float kDotTextGap = 8.0f;          // WpSpacing.xs
constexpr float kTimerWfGap = 18.0f;         // WpSpacing.md + extra breathing room

// ── Shadow (WpShadows.elevated) ───────────────────────────────────────
// NOTE: 12 overlapping GDI+ layers compound via alpha compositing.
// peak_alpha ≈ 0x08 yields ~17% composite at body edge (matching Flutter).
constexpr float kShadowBlur1 = 20.0f;
constexpr float kShadowOffsetY1 = 6.0f;
constexpr BYTE  kShadowAlpha1Dark = 0x06;    // ~2.4% per layer → ~12% composite
constexpr BYTE  kShadowAlpha1Light = 0x04;   // ~1.6% per layer → ~8% composite
constexpr float kShadowBlur2 = 3.0f;
constexpr float kShadowOffsetY2 = 1.0f;
constexpr BYTE  kShadowAlpha2Dark = 0x03;    // ~1.2% per layer → ~6% composite
constexpr BYTE  kShadowAlpha2Light = 0x02;   // ~0.8% per layer → ~4% composite
constexpr float kShadowPad = 28.0f;          // extra space for wider shadow blur

// ── Animation durations (ms) ──────────────────────────────────────────
constexpr DWORD kShowMs = 200;
constexpr DWORD kHideMs = 150;
constexpr DWORD kDotPulseMs = 900;           // matching RecordingPill
constexpr DWORD kShimmerMs = 1200;
constexpr DWORD kSpinnerMs = 750;              // transcribing spinner rotation
constexpr DWORD kCelebrationMs = 200;
constexpr DWORD kTransitionMs = 200;
constexpr UINT  kTimerIntervalMs = 33;       // ~30 fps
constexpr UINT_PTR kTimerId = 0xF001;

// ── Easing — delegate to GdiPlusHelper ────────────────────────────────
float EaseOut(float t) { return GdiPlusHelper::EaseOut(t); }
float EaseInOut(float t) { return GdiPlusHelper::EaseInOut(t); }
float PingPong(float t) { return GdiPlusHelper::PingPong(t); }
float AnimProgress(DWORD now, DWORD origin, DWORD period_ms) {
  return GdiPlusHelper::AnimProgress(now, origin, period_ms);
}
Color LerpColor(const Color& a, const Color& b, float t) {
  return GdiPlusHelper::LerpColor(a, b, t);
}

// ── Accent gradient colors per state ──────────────────────────────────
struct GradientPair { Color c0, c1; };

GradientPair AccentColorsFor(OverlayVisualState s) {
  switch (s) {
    case OverlayVisualState::kRecording:
      return {Color(255, 0xEF, 0x44, 0x44), Color(255, 0xDC, 0x26, 0x26)};
    case OverlayVisualState::kTranscribing:
      return {Color(255, 0xF5, 0x9E, 0x0B), Color(255, 0xD9, 0x77, 0x06)};
    case OverlayVisualState::kProcessing:
      return {Color(255, 0xF5, 0x9E, 0x0B), Color(255, 0xD9, 0x77, 0x06)};
    case OverlayVisualState::kDone:
      return {Color(255, 0x22, 0xC5, 0x5E), Color(255, 0x16, 0xA3, 0x4A)};
    case OverlayVisualState::kError:
      return {Color(255, 0xEF, 0x44, 0x44), Color(255, 0xB9, 0x1C, 0x1C)};
  }
  return {Color(255, 0xF5, 0x9E, 0x0B), Color(255, 0xD9, 0x77, 0x06)};
}

}  // namespace

// ── Static ────────────────────────────────────────────────────────────
bool FloatingOverlayWindow::class_registered_ = false;

// ═══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ═══════════════════════════════════════════════════════════════════════

FloatingOverlayWindow::FloatingOverlayWindow() = default;

FloatingOverlayWindow::~FloatingOverlayWindow() { Destroy(); }

// ═══════════════════════════════════════════════════════════════════════
// Window class registration
// ═══════════════════════════════════════════════════════════════════════

bool FloatingOverlayWindow::EnsureClassRegistered() {
  if (class_registered_) return true;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kClassName;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  if (!RegisterClassExW(&wc)) return false;
  class_registered_ = true;
  return true;
}

// ═══════════════════════════════════════════════════════════════════════
// Create / Destroy
// ═══════════════════════════════════════════════════════════════════════

bool FloatingOverlayWindow::Create(HWND owner) {
  if (hwnd_) return true;

  if (!GdiPlusHelper::AddRef()) return false;

  if (!EnsureClassRegistered()) {
    GdiPlusHelper::Release();
    OutputDebugStringW(L"[FloatingOverlay] RegisterClassEx failed\n");
    return false;
  }

  if (!InitDirectWrite()) {
    GdiPlusHelper::Release();
    OutputDebugStringW(L"[FloatingOverlay] DirectWrite init failed\n");
    return false;
  }

  owner_ = owner;

  // Start off-screen, invisible. SetPosition will place it correctly.
  // Pass nullptr as the owner so this window is not an "owned window" in
  // Win32 terms. Owned windows are automatically minimized/hidden when the
  // owner minimizes — we want the overlay to stay visible and on top
  // regardless of the main window's state. owner_ is kept for DPI lookups.
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
      kClassName, L"", WS_POPUP, -9999, -9999, 1, 1, nullptr, nullptr,
      GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    OutputDebugStringW(L"[FloatingOverlay] CreateWindowEx failed\n");
    GdiPlusHelper::Release();
    return false;
  }

  creating_thread_id_ = GetCurrentThreadId();
  anim_origin_ = GetTickCount();
  return true;
}

void FloatingOverlayWindow::Destroy() {
  if (shutting_down_) return;
  shutting_down_ = true;

  StopAnimTimer();

  if (hwnd_ && GetCapture() == hwnd_) ReleaseCapture();

  drag_end_cb_ = nullptr;
  close_cb_ = nullptr;
  body_click_cb_ = nullptr;
  retry_cb_ = nullptr;
  context_menu_cb_ = nullptr;

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  visible_ = false;
  owner_ = nullptr;

  // Release DirectWrite resources
  if (text_format_label_) { text_format_label_->Release(); text_format_label_ = nullptr; }
  if (text_format_timer_) { text_format_timer_->Release(); text_format_timer_ = nullptr; }
  if (text_format_hint_) { text_format_hint_->Release(); text_format_hint_ = nullptr; }
  if (text_format_badge_) { text_format_badge_->Release(); text_format_badge_ = nullptr; }
  if (text_format_button_) { text_format_button_->Release(); text_format_button_ = nullptr; }
  if (text_format_compact_) { text_format_compact_->Release(); text_format_compact_ = nullptr; }
  if (dwrite_factory_) { dwrite_factory_->Release(); dwrite_factory_ = nullptr; }

  backbuffer_.reset();
  GdiPlusHelper::Release();

  shutting_down_ = false;
}

// ═══════════════════════════════════════════════════════════════════════
// DirectWrite initialization
// ═══════════════════════════════════════════════════════════════════════

bool FloatingOverlayWindow::InitDirectWrite() {
  HRESULT hr = DWriteCreateFactory(
      DWRITE_FACTORY_TYPE_SHARED,
      __uuidof(IDWriteFactory),
      reinterpret_cast<IUnknown**>(&dwrite_factory_));
  if (FAILED(hr)) return false;

  auto makeFormat = [&](float size, DWRITE_FONT_WEIGHT weight,
                        IDWriteTextFormat** out) -> bool {
    hr = dwrite_factory_->CreateTextFormat(
        L"Segoe UI", nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
        DWRITE_FONT_STRETCH_NORMAL, size, L"", out);
    return SUCCEEDED(hr);
  };

  if (!makeFormat(15.0f, DWRITE_FONT_WEIGHT_BOLD, &text_format_label_)) return false;
  if (!makeFormat(14.0f, DWRITE_FONT_WEIGHT_REGULAR, &text_format_timer_)) return false;
  if (!makeFormat(12.0f, DWRITE_FONT_WEIGHT_REGULAR, &text_format_hint_)) return false;
  if (!makeFormat(10.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &text_format_badge_)) return false;
  if (!makeFormat(11.0f, DWRITE_FONT_WEIGHT_MEDIUM, &text_format_button_)) return false;
  if (!makeFormat(13.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &text_format_compact_)) return false;

  // Alignment
  text_format_timer_->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_TRAILING);
  text_format_compact_->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);

  return true;
}

// ═══════════════════════════════════════════════════════════════════════
// WndProc
// ═══════════════════════════════════════════════════════════════════════

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
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;

    case WM_NCHITTEST: {
      POINT pt = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
      ScreenToClient(hwnd_, &pt);
      if (!IsInsideRoundedRect(pt.x, pt.y)) return HTTRANSPARENT;
      return HTCLIENT;
    }

    case WM_LBUTTONDOWN: {
      POINT client = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
      HitZone zone = HitTest(client.x, client.y);
      if (zone == HitZone::kClose) {
        if (!shutting_down_ && close_cb_) close_cb_();
        return 0;
      }
      if (zone == HitZone::kRetry) {
        if (!shutting_down_ && retry_cb_) retry_cb_();
        return 0;
      }
      if (zone == HitZone::kDismiss) {
        if (!shutting_down_ && close_cb_) close_cb_();
        return 0;
      }
      if (zone == HitZone::kStop) {
        if (!shutting_down_ && close_cb_) close_cb_();
        return 0;
      }
      // Start drag from header or body
      SetCapture(hwnd_);
      GetCursorPos(&drag_cursor_start_);
      RECT rc;
      GetWindowRect(hwnd_, &rc);
      drag_window_start_ = {rc.left, rc.top};
      dragging_ = true;
      drag_moved_ = false;
      return 0;
    }

    case WM_MOUSEMOVE: {
      // Track mouse for close button hover
      if (!tracking_mouse_) {
        TRACKMOUSEEVENT tme = {};
        tme.cbSize = sizeof(tme);
        tme.dwFlags = TME_LEAVE;
        tme.hwndTrack = hwnd_;
        TrackMouseEvent(&tme);
        tracking_mouse_ = true;
      }

      if (dragging_) {
        POINT cur;
        GetCursorPos(&cur);
        int dx = cur.x - drag_cursor_start_.x;
        int dy = cur.y - drag_cursor_start_.y;
        if (!drag_moved_ && abs(dx) < GetSystemMetrics(SM_CXDRAG) &&
            abs(dy) < GetSystemMetrics(SM_CYDRAG))
          return 0;
        drag_moved_ = true;
        SetWindowPos(hwnd_, nullptr, drag_window_start_.x + dx,
                     drag_window_start_.y + dy, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        return 0;
      }

      // Update hover states
      POINT client = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
      HitZone zone = HitTest(client.x, client.y);
      bool was_close = close_hover_;
      bool was_stop = stop_hover_;
      close_hover_ = (zone == HitZone::kClose);
      stop_hover_ = (zone == HitZone::kStop);
      if (close_hover_ != was_close || stop_hover_ != was_stop) {
        if (visible_) Render();
      }
      return 0;
    }

    case WM_LBUTTONUP: {
      if (!dragging_) break;
      ReleaseCapture();
      dragging_ = false;
      if (drag_moved_) {
        RECT rc;
        GetWindowRect(hwnd_, &rc);
        double dpi = GetDpiScale();
        double lx = rc.left / dpi;
        double ly = rc.top / dpi;
        anchor_x_ = lx;
        anchor_y_ = ly;
        anchor_mode_ = OverlayAnchorMode::kTopLeft;
        if (!shutting_down_ && drag_end_cb_)
          drag_end_cb_(lx, ly, "custom");
      } else {
        if (!shutting_down_ && body_click_cb_) body_click_cb_();
      }
      return 0;
    }

    case WM_RBUTTONUP: {
      if (snap_.compact && !context_menu_items_.empty()) {
        POINT pt;
        GetCursorPos(&pt);
        ShowContextMenu(pt.x, pt.y);
      }
      return 0;
    }

    case WM_MOUSELEAVE:
      tracking_mouse_ = false;
      if (close_hover_ || stop_hover_) {
        close_hover_ = false;
        stop_hover_ = false;
        if (visible_) Render();
      }
      return 0;

    case WM_CAPTURECHANGED:
    case WM_CANCELMODE:
      dragging_ = false;
      return 0;

    case WM_DPICHANGED:
      backbuffer_.reset();
      if (visible_) {
        RecalcPosition();
        Render();
      }
      return 0;

    case WM_DISPLAYCHANGE:
      if (visible_) {
        ValidateOnScreen();
        RecalcPosition();
        Render();
      }
      return 0;

    case WM_TIMER:
      if (wp == kTimerId) OnAnimTick();
      return 0;

    // ── Re-assert topmost if z-order was changed externally ──────────
    case WM_WINDOWPOSCHANGED: {
      auto* wp_pos = reinterpret_cast<WINDOWPOS*>(lp);
      if (visible_ && !(wp_pos->flags & SWP_NOZORDER)) {
        // Only re-assert if we actually lost TOPMOST (prevents re-entry loop)
        if (!(GetWindowLong(hwnd_, GWL_EXSTYLE) & WS_EX_TOPMOST))
          BringToTopmost();
      }
      return DefWindowProcW(hwnd_, msg, wp, lp);
    }

    case WM_PAINT: {
      PAINTSTRUCT ps;
      BeginPaint(hwnd_, &ps);
      EndPaint(hwnd_, &ps);
      return 0;
    }

    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
      StopAnimTimer();
      if (GetCapture() == hwnd_) ReleaseCapture();
      hwnd_ = nullptr;
      owner_ = nullptr;
      visible_ = false;
      dragging_ = false;
      return 0;
  }

  return DefWindowProcW(hwnd_, msg, wp, lp);
}

// ═══════════════════════════════════════════════════════════════════════
// Public API
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::UpdateSnapshot(const OverlaySnapshot& snapshot) {
  if (!hwnd_ || shutting_down_) return;

  bool was_visible = snap_.visible;
  bool state_changed = (snap_.state != snapshot.state);
  prev_snap_ = snap_;
  snap_ = snapshot;

  if (snapshot.visible && !was_visible) {
    // Resize + position before showing
    int w = ToPhysical(CalculateWidth() + kShadowPad * 2);
    int h = ToPhysical(CalculateHeight() + kShadowPad * 2);
    SetWindowPos(hwnd_, nullptr, 0, 0, w, h,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    RecalcPosition();
    StartShowAnimation();
    ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
    BringToTopmost();
    visible_ = true;
    if (NeedsAnimation()) StartAnimTimer();
    Render();
  } else if (!snapshot.visible && was_visible) {
    StartHideAnimation();
  } else if (snapshot.visible) {
    // Already visible — update in place
    if (state_changed) {
      transition_start_ = GetTickCount();
      anim_origin_ = transition_start_;
      // Reset spinner when leaving transcribing
      if (prev_snap_.state == OverlayVisualState::kTranscribing)
        spinner_origin_ = 0;
      // Start done celebration
      if (snapshot.state == OverlayVisualState::kDone) {
        celebration_start_ = GetTickCount();
        celebration_progress_ = 0.0f;
      }
    }

    // Resize if height/width changed (mode switch, state change)
    int new_w = ToPhysical(CalculateWidth() + kShadowPad * 2);
    int new_h = ToPhysical(CalculateHeight() + kShadowPad * 2);
    RECT rc;
    GetWindowRect(hwnd_, &rc);
    int cur_w = rc.right - rc.left;
    int cur_h = rc.bottom - rc.top;
    if (new_w != cur_w || new_h != cur_h) {
      backbuffer_.reset();
      SetWindowPos(hwnd_, nullptr, 0, 0, new_w, new_h,
                   SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
      RecalcPosition();
    }

    if (NeedsAnimation())
      StartAnimTimer();
    else
      StopAnimTimer();
    Render();
  }
}

void FloatingOverlayWindow::SetWaveformBars(const std::vector<double>& bars) {
  if (!hwnd_ || shutting_down_) return;
  // Copy verbatim; render branch clamps each value to [0, 1].
  waveform_bars_ = bars;
  if (visible_) {
    InvalidateRect(hwnd_, nullptr, FALSE);
  }
}

void FloatingOverlayWindow::SetPosition(double logical_x, double logical_y,
                                         OverlayAnchorMode anchor) {
  anchor_x_ = logical_x;
  anchor_y_ = logical_y;
  anchor_mode_ = anchor;
  if (hwnd_ && visible_) {
    RecalcPosition();
    Render();
  }
}

void FloatingOverlayWindow::SetContextMenuItems(
    std::vector<OverlayContextMenuItem> items) {
  context_menu_items_ = std::move(items);
}

void FloatingOverlayWindow::SetOpacity(double opacity) {
  opacity_ = std::clamp(opacity, 0.0, 1.0);
  if (hwnd_ && visible_) {
    Render();
  }
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

// ═══════════════════════════════════════════════════════════════════════
// DPI helpers
// ═══════════════════════════════════════════════════════════════════════

double FloatingOverlayWindow::GetDpiScale() const {
  if (hwnd_) {
    UINT dpi = GetDpiForWindow(hwnd_);
    if (dpi > 0) return dpi / 96.0;
  }
  if (owner_) {
    UINT dpi = GetDpiForWindow(owner_);
    if (dpi > 0) return dpi / 96.0;
  }
  return 1.0;
}

int FloatingOverlayWindow::ToPhysical(double logical) const {
  return static_cast<int>(std::round(logical * GetDpiScale()));
}

double FloatingOverlayWindow::ToLogical(int physical) const {
  double dpi = GetDpiScale();
  return dpi > 0.0 ? physical / dpi : physical;
}

// ═══════════════════════════════════════════════════════════════════════
// Size calculation
// ═══════════════════════════════════════════════════════════════════════

int FloatingOverlayWindow::CalculateWidth() const {
  return static_cast<int>(snap_.compact ? kCompactWidth : kNormalWidth);
}

int FloatingOverlayWindow::CalculateHeight() const {
  if (snap_.compact) return static_cast<int>(kCompactHeight);
  return static_cast<int>(kPillHeight);
}

// ═══════════════════════════════════════════════════════════════════════
// Positioning
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::RecalcPosition() {
  if (!hwnd_) return;
  double dpi = GetDpiScale();
  int w = ToPhysical(CalculateWidth() + kShadowPad * 2);
  int h = ToPhysical(CalculateHeight() + kShadowPad * 2);

  // Get work area (taskbar-aware)
  RECT work;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);

  int px = 0, py = 0;
  int work_w = work.right - work.left;

  switch (anchor_mode_) {
    case OverlayAnchorMode::kTopCenter:
      px = work.left + (work_w - w) / 2;
      py = work.top + ToPhysical(16.0);  // 16px margin from top
      break;
    case OverlayAnchorMode::kBottomCenter:
      px = work.left + (work_w - w) / 2;
      py = work.bottom - h - ToPhysical(16.0);  // 16px margin from bottom
      break;
    case OverlayAnchorMode::kTopLeft:
      px = static_cast<int>(std::round(anchor_x_ * dpi));
      py = static_cast<int>(std::round(anchor_y_ * dpi));
      break;
  }

  SetWindowPos(hwnd_, nullptr, px, py, w, h,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FloatingOverlayWindow::ValidateOnScreen() {
  if (!hwnd_) return;
  RECT rc;
  GetWindowRect(hwnd_, &rc);

  RECT work;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);

  int w = rc.right - rc.left;
  int h = rc.bottom - rc.top;
  int x = rc.left;
  int y = rc.top;

  if (x + w > work.right) x = work.right - w;
  if (y + h > work.bottom) y = work.bottom - h;
  if (x < work.left) x = work.left;
  if (y < work.top) y = work.top;

  if (x != rc.left || y != rc.top) {
    SetWindowPos(hwnd_, nullptr, x, y, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Hit-testing
// ═══════════════════════════════════════════════════════════════════════

bool FloatingOverlayWindow::IsInsideRoundedRect(int x, int y) const {
  double dpi = GetDpiScale();
  float pad = static_cast<float>(kShadowPad * dpi);
  float w = static_cast<float>(CalculateWidth() * dpi);
  float h = static_cast<float>(CalculateHeight() * dpi);
  float r = static_cast<float>((snap_.compact ? kCompactRadius : kPillHeight / 2.0f) * dpi);

  float lx = x - pad;
  float ly = y - pad;

  if (lx < 0 || ly < 0 || lx > w || ly > h) return false;

  // Check corners
  if (lx < r && ly < r) {
    float dx = lx - r, dy = ly - r;
    return dx * dx + dy * dy <= r * r;
  }
  if (lx > w - r && ly < r) {
    float dx = lx - (w - r), dy = ly - r;
    return dx * dx + dy * dy <= r * r;
  }
  if (lx < r && ly > h - r) {
    float dx = lx - r, dy = ly - (h - r);
    return dx * dx + dy * dy <= r * r;
  }
  if (lx > w - r && ly > h - r) {
    float dx = lx - (w - r), dy = ly - (h - r);
    return dx * dx + dy * dy <= r * r;
  }

  return true;
}

FloatingOverlayWindow::HitZone FloatingOverlayWindow::HitTest(int px,
                                                                int py) const {
  double dpi = GetDpiScale();
  float pad = static_cast<float>(kShadowPad * dpi);
  float lx = (px - pad) / static_cast<float>(dpi);
  float ly = (py - pad) / static_cast<float>(dpi);

  if (snap_.compact) {
    // Compact mode: close button at left (matching normal)
    float cx = 10.0f;
    float cy = (kCompactHeight - 3.0f - 28.0f) / 2.0f;
    if (lx >= cx && lx <= cx + 28.0f &&
        ly >= cy && ly <= cy + 28.0f) {
      return HitZone::kClose;
    }
    // Stop button at right
    if (snap_.state == OverlayVisualState::kRecording) {
      float sx = kCompactWidth - 10.0f - 28.0f;
      float sy = (kCompactHeight - 3.0f - 28.0f) / 2.0f;
      if (lx >= sx && lx <= sx + 28.0f &&
          ly >= sy && ly <= sy + 28.0f) {
        return HitZone::kStop;
      }
    }
    return HitZone::kBody;
  }

  // Normal (pill) mode
  float content_h = kPillHeight - kProgressBarH;
  float cy = content_h / 2.0f;

  // Close button: left side (36x36 circle)
  float close_x = kPillPadH;
  float close_y = cy - kCloseSize / 2.0f;
  if (lx >= close_x && lx <= close_x + kCloseSize &&
      ly >= close_y && ly <= close_y + kCloseSize) {
    return HitZone::kClose;
  }

  // Stop button: right side (36x36 circle, recording only)
  if (snap_.state == OverlayVisualState::kRecording) {
    float stop_x = kNormalWidth - kPillPadH - kStopBtnSize;
    float stop_y = cy - kStopBtnSize / 2.0f;
    if (lx >= stop_x && lx <= stop_x + kStopBtnSize &&
        ly >= stop_y && ly <= stop_y + kStopBtnSize) {
      return HitZone::kStop;
    }
  }

  return HitZone::kBody;
}

// ═══════════════════════════════════════════════════════════════════════
// Color helpers
// ═══════════════════════════════════════════════════════════════════════

FloatingOverlayWindow::ThemeColors FloatingOverlayWindow::GetThemeColors() const {
  ThemeColors c;
  if (snap_.is_dark) {
    c.background = Color(0xFF, 0x14, 0x19, 0x26);       // 100% alpha — SourceConstantAlpha drives all transparency
    c.border = Color(0x14, 0xFF, 0xFF, 0xFF);            // 8% white
    c.text_primary = Color(255, 0xF0, 0xF4, 0xFA);      // WpColorsDark.textPrimary
    c.text_muted = Color(255, 0x8A, 0x99, 0xB2);        // WpColorsDark.textMuted
    c.shadow1 = Color(kShadowAlpha1Dark, 0, 0, 0);
    c.shadow2 = Color(kShadowAlpha2Dark, 0, 0, 0);
    c.close_hover_bg = Color(0x1A, 0xFF, 0xFF, 0xFF);    // 10% white
    c.close_icon = Color(255, 0x8A, 0x99, 0xB2);         // same as textMuted
    c.waveform_active = Color(0xD9, 0x38, 0xD9, 0xF0);   // 85% accent (match waveform_bars.dart)
    c.waveform_muted = Color(0x80, 0x8A, 0x99, 0xB2);    // 50% textMuted (match waveform_bars.dart)
    c.badge_local_bg = Color(0x26, 0x36, 0xD9, 0x8B);    // 15% of success
    c.badge_local_text = Color(255, 0x36, 0xD9, 0x8B);   // WpColorsDark.success
    c.badge_cloud_bg = Color(0x26, 0x38, 0xD9, 0xF0);    // 15%
    c.badge_cloud_text = Color(255, 0x38, 0xD9, 0xF0);
    c.accent = Color(255, 0x38, 0xD9, 0xF0);             // WpColorsDark.accent
    c.success_color = Color(255, 0x36, 0xD9, 0x8B);      // WpColorsDark.success
    c.error_color = Color(255, 0xFF, 0x7B, 0x7B);        // WpColorsDark.error
    c.retry_bg = Color(0x1A, 0xFF, 0xFF, 0xFF);          // 10% white
    c.retry_text = Color(255, 0xF0, 0xF4, 0xFA);         // textPrimary
    c.dismiss_text = Color(255, 0x8A, 0x99, 0xB2);       // textMuted
    c.shimmer_alpha_lo = 0.15f;
    c.shimmer_alpha_hi = 0.60f;
  } else {
    c.background = Color(0xFF, 0xF0, 0xF3, 0xF7);       // 100% alpha — SourceConstantAlpha drives all transparency
    c.border = Color(0x14, 0x0F, 0x17, 0x2A);            // 8% dark
    c.text_primary = Color(255, 0x10, 0x18, 0x28);
    c.text_muted = Color(255, 0x5B, 0x69, 0x7E);
    c.shadow1 = Color(kShadowAlpha1Light, 0, 0, 0);
    c.shadow2 = Color(kShadowAlpha2Light, 0, 0, 0);
    c.close_hover_bg = Color(0x14, 0x00, 0x00, 0x00);    // 8% black
    c.close_icon = Color(255, 0x5B, 0x69, 0x7E);
    c.waveform_active = Color(0xD9, 0x08, 0x87, 0xA8);   // 85% accent (match waveform_bars.dart)
    c.waveform_muted = Color(0x80, 0x5B, 0x69, 0x7E);    // 50% textMuted (match waveform_bars.dart)
    c.badge_local_bg = Color(0x26, 0x05, 0x87, 0x5C);    // 15% of WpColorsLight.success
    c.badge_local_text = Color(255, 0x05, 0x87, 0x5C);   // WpColorsLight.success
    c.badge_cloud_bg = Color(0x26, 0x08, 0x87, 0xA8);    // 15% of WpColorsLight.accent
    c.badge_cloud_text = Color(255, 0x08, 0x87, 0xA8);   // WpColorsLight.accent
    c.accent = Color(255, 0x08, 0x87, 0xA8);             // WpColorsLight.accent
    c.success_color = Color(255, 0x05, 0x87, 0x5C);      // WpColorsLight.success
    c.error_color = Color(255, 0xCC, 0x1C, 0x1C);        // WpColorsLight.error
    c.retry_bg = Color(0x1F, 0xEF, 0x44, 0x44);          // 12% red
    c.retry_text = Color(255, 0xDC, 0x26, 0x26);
    c.dismiss_text = Color(255, 0x5B, 0x69, 0x7E);
    c.shimmer_alpha_lo = 0.12f;
    c.shimmer_alpha_hi = 0.50f;
  }
  return c;
}

FloatingOverlayWindow::AccentGradient FloatingOverlayWindow::GetAccentColors() const {
  // Interpolate accent colors over kTransitionMs when state changes
  if (transition_start_ != 0 && prev_snap_.state != snap_.state) {
    DWORD now = GetTickCount();
    float progress = std::clamp(
        static_cast<float>(now - transition_start_) / kTransitionMs, 0.0f, 1.0f);
    if (progress < 1.0f) {
      auto prev = AccentColorsFor(prev_snap_.state);
      auto curr = AccentColorsFor(snap_.state);
      return {LerpColor(prev.c0, curr.c0, progress),
              LerpColor(prev.c1, curr.c1, progress)};
    }
  }
  auto g = AccentColorsFor(snap_.state);
  return {g.c0, g.c1};
}

// ═══════════════════════════════════════════════════════════════════════
// Animation management
// ═══════════════════════════════════════════════════════════════════════

bool FloatingOverlayWindow::NeedsAnimation() const {
  if (is_showing_ || is_hiding_) return true;
  if (celebration_progress_ >= 0.0f) return true;
  switch (snap_.state) {
    case OverlayVisualState::kRecording:     return true;   // dot pulse + waveform
    case OverlayVisualState::kTranscribing:  return true;   // shimmer
    case OverlayVisualState::kProcessing:    return true;   // shimmer
    default: break;
  }
  // Check transition in progress
  if (transition_start_ != 0) {
    DWORD now = GetTickCount();
    if (now - transition_start_ < kTransitionMs) return true;
  }
  return false;
}

void FloatingOverlayWindow::StartAnimTimer() {
  if (anim_timer_ || !hwnd_) return;
  anim_timer_ = SetTimer(hwnd_, kTimerId, kTimerIntervalMs, nullptr);
}

void FloatingOverlayWindow::StopAnimTimer() {
  if (anim_timer_ && hwnd_) {
    KillTimer(hwnd_, kTimerId);
  }
  anim_timer_ = 0;
}

void FloatingOverlayWindow::OnAnimTick() {
  if (shutting_down_ || !hwnd_) return;
  if (!visible_ && !is_showing_) return;  // skip work when hidden

  // Waveform bars are pushed by Dart via SetWaveformBars — no smoothing
  // happens here. This tick exists for show/hide, the recording-dot pulse,
  // the transcribing spinner, and the done celebration.

  // Show/hide transition
  OnShowHideAnimTick();

  // Done celebration
  if (celebration_progress_ >= 0.0f) {
    float elapsed = static_cast<float>(GetTickCount() - celebration_start_);
    celebration_progress_ = std::clamp(elapsed / kCelebrationMs, 0.0f, 1.0f);
    if (celebration_progress_ >= 1.0f) celebration_progress_ = -1.0f;
  }

  Render();

  if (!NeedsAnimation()) StopAnimTimer();
}

void FloatingOverlayWindow::StartShowAnimation() {
  is_showing_ = true;
  is_hiding_ = false;
  show_hide_progress_ = 0.0f;
  show_hide_start_ = GetTickCount();
  StartAnimTimer();
}

void FloatingOverlayWindow::StartHideAnimation() {
  is_hiding_ = true;
  is_showing_ = false;
  show_hide_progress_ = 1.0f;
  show_hide_start_ = GetTickCount();
  StartAnimTimer();
}

void FloatingOverlayWindow::OnShowHideAnimTick() {
  DWORD now = GetTickCount();
  if (is_showing_) {
    float t = static_cast<float>(now - show_hide_start_) / kShowMs;
    show_hide_progress_ = std::clamp(EaseOut(t), 0.0f, 1.0f);
    if (t >= 1.0f) {
      show_hide_progress_ = 1.0f;
      is_showing_ = false;
    }
  } else if (is_hiding_) {
    float t = static_cast<float>(now - show_hide_start_) / kHideMs;
    show_hide_progress_ = std::clamp(1.0f - EaseOut(t), 0.0f, 1.0f);
    if (t >= 1.0f) {
      show_hide_progress_ = 0.0f;
      is_hiding_ = false;
      ShowWindow(hwnd_, SW_HIDE);
      visible_ = false;
      StopAnimTimer();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Render pipeline
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::Render() {
  if (!hwnd_ || shutting_down_) return;

  double dpi = GetDpiScale();
  float content_w = static_cast<float>(CalculateWidth());
  float content_h = static_cast<float>(CalculateHeight());
  float total_w = content_w + kShadowPad * 2;
  float total_h = content_h + kShadowPad * 2;
  int phys_w = ToPhysical(total_w);
  int phys_h = ToPhysical(total_h);

  // ── Create 32-bit ARGB DIB section ──────────────────────────────────
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = phys_w;
  bmi.bmiHeader.biHeight = -phys_h;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(nullptr, &bmi, DIB_RGB_COLORS, &bits,
                                 nullptr, 0);
  if (!dib) return;

  Bitmap bmp(phys_w, phys_h, phys_w * 4, PixelFormat32bppPARGB,
             static_cast<BYTE*>(bits));
  Graphics g(&bmp);
  g.SetSmoothingMode(SmoothingModeHighQuality);
  g.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
  g.Clear(Color(0, 0, 0, 0));

  // Scale to DPI
  g.ScaleTransform(static_cast<float>(dpi), static_cast<float>(dpi));
  // Offset by shadow padding
  g.TranslateTransform(kShadowPad, kShadowPad);

  // Celebration scale
  if (celebration_progress_ >= 0.0f) {
    float t = PingPong(celebration_progress_);
    float scale_factor = 1.0f + 0.05f * EaseInOut(t);
    float cx = content_w / 2.0f;
    float cy = content_h / 2.0f;
    g.TranslateTransform(cx, cy);
    g.ScaleTransform(scale_factor, scale_factor);
    g.TranslateTransform(-cx, -cy);
  }

  // Render the appropriate mode
  if (snap_.compact)
    RenderCompact(g, content_w, content_h);
  else
    RenderNormal(g, content_w, content_h);

  g.Flush(FlushIntentionSync);

  // ── UpdateLayeredWindow ────────────────────────────────────────────
  HDC screen = GetDC(nullptr);
  if (!screen) { DeleteObject(dib); return; }
  HDC mem = CreateCompatibleDC(screen);
  if (!mem) { ReleaseDC(nullptr, screen); DeleteObject(dib); return; }
  HBITMAP old_bmp = static_cast<HBITMAP>(SelectObject(mem, dib));

  RECT rc;
  GetWindowRect(hwnd_, &rc);
  POINT dst = {rc.left, rc.top};
  SIZE sz = {phys_w, phys_h};
  POINT src = {0, 0};
  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = static_cast<BYTE>(
      std::clamp(show_hide_progress_ * static_cast<float>(opacity_), 0.0f,
                 1.0f) *
      255);
  blend.AlphaFormat = AC_SRC_ALPHA;

  UpdateLayeredWindow(hwnd_, screen, &dst, &sz, mem, &src, 0, &blend,
                      ULW_ALPHA);

  SelectObject(mem, old_bmp);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  DeleteObject(dib);
}

// ── Normal mode rendering (horizontal pill) ───────────────────────────

void FloatingOverlayWindow::RenderNormal(Graphics& g, float w, float h) {
  ThemeColors tc = GetThemeColors();
  float pill_r = h / 2.0f;
  float content_h = h - kProgressBarH;
  float cy = content_h / 2.0f;

  // 1. Shadow
  PaintShadow(g, w, h, pill_r);

  // 2. Background pill
  GraphicsPath bgPath;
  GdiPlusHelper::MakeRoundedRect(&bgPath, 0, 0, w, h, pill_r);
  SolidBrush bgBrush(tc.background);
  g.FillPath(&bgBrush, &bgPath);

  // 3. Border
  Pen borderPen(tc.border, 1.0f);
  g.DrawPath(&borderPen, &bgPath);

  // 4. Bottom progress bar (clipped to pill)
  PaintBottomProgressBar(g, w, h, pill_r);

  // 5. Horizontal content layout
  float x = kPillPadH;
  bool active = (snap_.state == OverlayVisualState::kRecording ||
                 snap_.state == OverlayVisualState::kTranscribing ||
                 snap_.state == OverlayVisualState::kProcessing);

  // 5a. Close/cancel button (left, 36x36 circle)
  PaintCloseButton(g, x, cy - kCloseSize / 2.0f, kCloseSize);
  x += kCloseSize + kPillGap;

  // 5b. Privacy badge (during active states)
  if (active && !snap_.privacy_mode.empty()) {
    float badge_w = PaintPrivacyBadge(g, x, cy - kBadgeHeight / 2.0f);
    x += badge_w + kPillGap;
  }

  // 5c. Right boundary (reserve space for stop button during recording)
  float right_edge = w - kPillPadH;
  if (snap_.state == OverlayVisualState::kRecording)
    right_edge -= kStopBtnSize + kWfStopGap;

  // 5d. Phase-specific center content
  switch (snap_.state) {
    case OverlayVisualState::kRecording: {
      // Phase dot
      PaintPhaseDot(g, x, cy - kDotSize / 2.0f, kDotSize);
      x += kDotSize + kDotTextGap;
      // Timer (15px BOLD, tabular figures)
      PaintText(g, snap_.elapsed, x, cy - 7.5f, 55.0f, 15.0f,
               DWRITE_FONT_WEIGHT_BOLD, tc.text_primary, true);
      x += 55.0f + kTimerWfGap;
      // Waveform (24px height) — clip to allocated area to prevent overflow into stop button
      float wf_w = right_edge - x;
      if (wf_w > 20.0f) {
        GraphicsState gs = g.Save();
        g.SetClip(RectF(x, cy - kWaveformHeight / 2.0f, wf_w, kWaveformHeight));
        PaintWaveform(g, x, cy - kWaveformHeight / 2.0f, wf_w, kWaveformHeight);
        g.Restore(gs);
      }
      break;
    }
    case OverlayVisualState::kTranscribing:
    case OverlayVisualState::kProcessing: {
      // Spinning arc (16x16) — accent color (cyan), not gradient amber
      if (spinner_origin_ == 0) spinner_origin_ = GetTickCount();
      float angle = static_cast<float>(
          ((GetTickCount() - spinner_origin_) % kSpinnerMs) * 360.0 / kSpinnerMs);
      float spin_y = cy - kSpinnerSize / 2.0f;
      Pen spinPen(tc.accent, 2.0f);
      spinPen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawArc(&spinPen, x, spin_y, kSpinnerSize, kSpinnerSize,
                angle, 270.0f);
      x += kSpinnerSize + kDotTextGap;
      // Label ("Transcribing..." / "Processing...") — accent color
      PaintText(g, snap_.label, x, cy - 6.5f, 110.0f, 13.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, tc.accent);
      x += 100.0f + 6.0f;
      // Elapsed time
      PaintText(g, snap_.elapsed, x, cy - 6.0f, 45.0f, 12.0f,
               DWRITE_FONT_WEIGHT_REGULAR, tc.text_muted, true);
      break;
    }
    case OverlayVisualState::kDone: {
      // Lucide circleCheck icon (16px) — success color
      float is = 16.0f;
      float sc = is / 24.0f;
      float ix = x, iy = cy - is / 2.0f;
      Pen cp(tc.success_color, 1.5f);
      cp.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawEllipse(&cp, ix + 2 * sc, iy + 2 * sc, 20 * sc, 20 * sc);
      g.DrawLine(&cp, ix + 9 * sc, iy + 12 * sc,
                 ix + 11 * sc, iy + 14 * sc);
      g.DrawLine(&cp, ix + 11 * sc, iy + 14 * sc,
                 ix + 15 * sc, iy + 10 * sc);
      x += is + kDotTextGap;
      PaintText(g, snap_.done_message, x, cy - 6.5f, right_edge - x, 13.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, tc.success_color);
      break;
    }
    case OverlayVisualState::kError: {
      // Lucide circleAlert icon (16px) — error color
      float is = 16.0f;
      float sc = is / 24.0f;
      float ix = x, iy = cy - is / 2.0f;
      Pen ep(tc.error_color, 1.5f);
      ep.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawEllipse(&ep, ix + 2 * sc, iy + 2 * sc, 20 * sc, 20 * sc);
      g.DrawLine(&ep, ix + 12 * sc, iy + 8 * sc,
                 ix + 12 * sc, iy + 12 * sc);
      SolidBrush db(tc.error_color);
      g.FillEllipse(&db, ix + 11.25f * sc, iy + 15.25f * sc,
                    1.5f * sc, 1.5f * sc);
      x += is + kDotTextGap;
      PaintText(g, snap_.error_message, x, cy - 6.5f, right_edge - x, 13.0f,
               DWRITE_FONT_WEIGHT_MEDIUM, tc.error_color);
      break;
    }
  }

  // 5e. Stop button (right side, recording only — 36x36 circle)
  if (snap_.state == OverlayVisualState::kRecording) {
    PaintStopButton(g, w - kPillPadH - kStopBtnSize, cy - kStopBtnSize / 2.0f);
  }
}

// ── Compact mode rendering ────────────────────────────────────────────

void FloatingOverlayWindow::RenderCompact(Graphics& g, float w, float h) {
  ThemeColors tc = GetThemeColors();
  float r = kCompactRadius;

  PaintShadow(g, w, h, r);

  // Background (pill shape, same colors/opacity as normal)
  GraphicsPath bgPath;
  GdiPlusHelper::MakeRoundedRect(&bgPath, 0, 0, w, h, r);
  SolidBrush bgBrush(tc.background);
  g.FillPath(&bgBrush, &bgPath);
  Pen borderPen(tc.border, 1.0f);
  g.DrawPath(&borderPen, &bgPath);

  // Bottom progress bar (3px, clipped to pill shape)
  constexpr float kCompactBarH = 3.0f;
  constexpr float kCompactBtnSize = 28.0f;
  constexpr float kCompactStopIcon = 10.0f;
  {
    GraphicsState saved = g.Save();
    GraphicsPath clipPath;
    GdiPlusHelper::MakeRoundedRect(&clipPath, 0, 0, w, h, r);
    Region clipRegion(&clipPath);
    Region barRect(RectF(0, h - kCompactBarH, w, kCompactBarH));
    clipRegion.Intersect(&barRect);
    g.SetClip(&clipRegion);

    switch (snap_.state) {
      case OverlayVisualState::kRecording: {
        if (snap_.progress > 0.0f) {
          float fill_w = w * (std::min)(snap_.progress, 1.0f);
          // Match Flutter _timerColor(): textPrimary → amber @75% → red @90%
          Color fill_color = tc.text_primary;
          if (snap_.progress >= 0.90f) {
            fill_color = Color(255, 0xFF, 0x52, 0x52);
          } else if (snap_.progress >= 0.75f) {
            fill_color = Color(255, 0xFF, 0xC1, 0x07);
          }
          SolidBrush fillBrush(fill_color);
          g.FillRectangle(&fillBrush, 0.0f, h - kCompactBarH, fill_w, kCompactBarH);
        } else {
          Color subtle(0x4D, tc.accent.GetR(), tc.accent.GetG(), tc.accent.GetB());
          SolidBrush subtleBrush(subtle);
          g.FillRectangle(&subtleBrush, 0.0f, h - kCompactBarH, w, kCompactBarH);
        }
        break;
      }
      case OverlayVisualState::kTranscribing:
      case OverlayVisualState::kProcessing: {
        // Shimmer uses theme accent color (cyan)
        DWORD now = GetTickCount();
        float t = AnimProgress(now, anim_origin_, kShimmerMs);
        float sweep = -0.3f + t * 1.6f;
        Color base(static_cast<BYTE>(tc.shimmer_alpha_lo * 255),
                   tc.accent.GetR(), tc.accent.GetG(), tc.accent.GetB());
        SolidBrush baseBrush(base);
        g.FillRectangle(&baseBrush, 0.0f, h - kCompactBarH, w, kCompactBarH);
        float glow_w = w * 0.3f;
        float glow_x = sweep * w - glow_w / 2.0f;
        Color glow_hi(static_cast<BYTE>(tc.shimmer_alpha_hi * 255),
                      tc.accent.GetR(), tc.accent.GetG(), tc.accent.GetB());
        Color glow_lo(0, tc.accent.GetR(), tc.accent.GetG(), tc.accent.GetB());
        LinearGradientBrush glowBrush(PointF(glow_x, 0), PointF(glow_x + glow_w, 0),
                                      glow_lo, glow_lo);
        Color gc[] = {glow_lo, glow_hi, glow_lo};
        REAL gp[] = {0.0f, 0.5f, 1.0f};
        glowBrush.SetInterpolationColors(gc, gp, 3);
        g.FillRectangle(&glowBrush, glow_x, h - kCompactBarH, glow_w, kCompactBarH);
        break;
      }
      case OverlayVisualState::kDone: {
        // Solid success color at 80% alpha
        Color success(0xCC, tc.success_color.GetR(), tc.success_color.GetG(),
                      tc.success_color.GetB());
        SolidBrush brush(success);
        g.FillRectangle(&brush, 0.0f, h - kCompactBarH, w, kCompactBarH);
        break;
      }
      default:
        break;
    }
    g.Restore(saved);
  }

  // Content area height (excluding progress bar)
  float content_h = h - kCompactBarH;
  float center_y = content_h / 2.0f;

  // Cancel button — left side, 28×28 circle
  float close_x = 10.0f;
  float close_y = center_y - kCompactBtnSize / 2.0f;
  PaintCloseButton(g, close_x, close_y, kCompactBtnSize);

  float x = close_x + kCompactBtnSize + 8.0f;

  // Phase dot (recording only)
  if (snap_.state == OverlayVisualState::kRecording) {
    float dot_y = center_y - kDotSize / 2.0f;
    PaintPhaseDot(g, x, dot_y, kDotSize);
    x += kDotSize + 6.0f;
  }

  // Content depends on state
  switch (snap_.state) {
    case OverlayVisualState::kRecording: {
      // Timer
      float text_y = center_y - 6.5f;
      PaintText(g, snap_.elapsed, x, text_y, 42.0f, 13.0f,
               DWRITE_FONT_WEIGHT_BOLD, tc.text_primary, true);
      x += 42.0f + 6.0f;

      // Mini waveform (8 bars) — stateless render from Dart-pushed array.
      // Sample every other bar so the 8-slot compact view spans the full
      // 30-bar source.
      float wf_h = 16.0f;
      float wf_y = center_y - wf_h / 2.0f;
      float mini_bar_w = 2.5f;
      float mini_bar_gap = 1.5f;
      int mini_bars = 8;
      for (int i = 0; i < mini_bars; ++i) {
        int src = (i * 2) % kWaveformBars;
        double raw = (src < static_cast<int>(waveform_bars_.size()))
                         ? waveform_bars_[src]
                         : 0.0;
        float bar = static_cast<float>(std::clamp(raw, 0.0, 1.0));
        float bar_h = kMinBarHeightPx + bar * (wf_h - kMinBarHeightPx);
        float bx = x + i * (mini_bar_w + mini_bar_gap);
        float by = wf_y + (wf_h - bar_h) / 2.0f;
        Color color = (bar >= kActiveColorThreshold) ? tc.waveform_active
                                                      : tc.waveform_muted;
        SolidBrush brush(color);
        GraphicsPath barPath;
        GdiPlusHelper::MakeRoundedRect(&barPath, bx, by, mini_bar_w, bar_h, 1.0f);
        g.FillPath(&brush, &barPath);
      }

      // Stop button — right side, 28×28 circle
      {
        float stop_x = w - 10.0f - kCompactBtnSize;
        float stop_y = center_y - kCompactBtnSize / 2.0f;
        // Red gradient circle
        LinearGradientBrush bgBrush2(PointF(stop_x, stop_y),
                                     PointF(stop_x + kCompactBtnSize, stop_y + kCompactBtnSize),
                                     Color(255, 0xEF, 0x44, 0x44),
                                     Color(255, 0xDC, 0x26, 0x26));
        GraphicsPath circle;
        circle.AddEllipse(stop_x, stop_y, kCompactBtnSize, kCompactBtnSize);
        g.FillPath(&bgBrush2, &circle);
        // Hover overlay
        if (stop_hover_) {
          SolidBrush hover(Color(0x1A, 0xFF, 0xFF, 0xFF));
          g.FillPath(&hover, &circle);
        }
        // White square OUTLINE icon (match Lucide square stroke style)
        float icon_inset = (kCompactBtnSize - kCompactStopIcon) / 2.0f;
        Pen iconPen(Color(255, 255, 255, 255), 2.0f);
        iconPen.SetLineJoin(LineJoinRound);
        GraphicsPath iconPath;
        GdiPlusHelper::MakeRoundedRect(&iconPath, stop_x + icon_inset, stop_y + icon_inset,
                                       kCompactStopIcon, kCompactStopIcon, 2.0f);
        g.DrawPath(&iconPen, &iconPath);
      }
      break;
    }
    case OverlayVisualState::kTranscribing:
    case OverlayVisualState::kProcessing: {
      // Spinning arc (12px) — use theme accent color (not gradient amber)
      if (spinner_origin_ == 0) spinner_origin_ = GetTickCount();
      float angle = static_cast<float>(
          ((GetTickCount() - spinner_origin_) % kSpinnerMs) * 360.0 / kSpinnerMs);
      float spin_size = 12.0f;
      float spin_y = center_y - spin_size / 2.0f;
      Pen spinPen(tc.accent, 1.5f);
      spinPen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawArc(&spinPen, x, spin_y, spin_size, spin_size, angle, 270.0f);
      x += spin_size + 6.0f;
      // Label — use accent color
      float text_y = center_y - 6.5f;
      std::wstring label = snap_.state == OverlayVisualState::kProcessing
          ? (snap_.processing_label.empty() ? L"Processing..." : snap_.processing_label)
          : snap_.label;
      PaintText(g, label, x, text_y, w - x - 14.0f, 13.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, tc.accent);
      break;
    }
    case OverlayVisualState::kDone: {
      // Check circle (12px) — use theme success color
      float icon_size = 12.0f;
      float icon_y = center_y - icon_size / 2.0f;
      Pen checkPen(tc.success_color, 1.5f);
      checkPen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawEllipse(&checkPen, x, icon_y, icon_size, icon_size);
      float cs = icon_size / 24.0f;
      g.DrawLine(&checkPen, x + 8 * cs, icon_y + 13 * cs,
                 x + 11 * cs, icon_y + 16 * cs);
      g.DrawLine(&checkPen, x + 11 * cs, icon_y + 16 * cs,
                 x + 16 * cs, icon_y + 10 * cs);
      x += icon_size + 6.0f;
      // Done message — use theme success color
      float text_y = center_y - 6.5f;
      std::wstring msg = snap_.done_message.empty() ? L"Done" : snap_.done_message;
      PaintText(g, msg, x, text_y, w - x - 14.0f, 13.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, tc.success_color);
      break;
    }
    case OverlayVisualState::kError: {
      // Error icon (12px) — use theme error color
      float icon_size = 12.0f;
      float icon_y = center_y - icon_size / 2.0f;
      Pen errPen(tc.error_color, 1.5f);
      errPen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawEllipse(&errPen, x, icon_y, icon_size, icon_size);
      float es = icon_size / 24.0f;
      g.DrawLine(&errPen, x + 12 * es, icon_y + 8 * es,
                 x + 12 * es, icon_y + 13 * es);
      SolidBrush dotBrush(tc.error_color);
      g.FillEllipse(&dotBrush, x + 11 * es, icon_y + 16 * es, 2 * es, 2 * es);
      x += icon_size + 6.0f;
      // Error message — use theme error color
      float text_y = center_y - 6.5f;
      std::wstring msg = snap_.error_message.empty() ? L"Error" : snap_.error_message;
      PaintText(g, msg, x, text_y, w - x - 14.0f, 13.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, tc.error_color);
      break;
    }
    default:
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sub-rendering helpers
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::PaintShadow(Graphics& g, float w, float h,
                                         float radius) {
  ThemeColors tc = GetThemeColors();

  auto draw_layer = [&](float blur, float offset_y, const Color& color) {
    GdiPlusHelper::PaintSoftShadowRect(g, 0, offset_y, w, h, radius, blur,
                                       color.GetA());
  };

  draw_layer(kShadowBlur1, kShadowOffsetY1, tc.shadow1);
  draw_layer(kShadowBlur2, kShadowOffsetY2, tc.shadow2);
}

void FloatingOverlayWindow::PaintAccentBar(Graphics& g, float w,
                                            float radius) {
  auto accent = GetAccentColors();

  // Accent bar clipped to top corners
  GraphicsState saved = g.Save();
  GraphicsPath clipPath;
  GdiPlusHelper::MakeRoundedRect(&clipPath, 0, 0, w, radius * 2, radius);
  Region clipRegion(&clipPath);
  Region rectRegion(RectF(0, 0, w, kAccentBarHeight));
  clipRegion.Intersect(&rectRegion);
  g.SetClip(&clipRegion);

  LinearGradientBrush brush(PointF(0, 0), PointF(w, 0), accent.c0, accent.c1);
  g.FillRectangle(&brush, 0.0f, 0.0f, w, kAccentBarHeight);

  g.Restore(saved);
}

void FloatingOverlayWindow::PaintPhaseDot(Graphics& g, float x, float y,
                                           float size) {
  BYTE alpha = 255;
  if (snap_.state == OverlayVisualState::kRecording) {
    DWORD now = GetTickCount();
    float t = PingPong(AnimProgress(now, anim_origin_, kDotPulseMs));
    alpha = static_cast<BYTE>(115 + 140 * EaseInOut(t));  // 45%–100%
  }

  // Fixed recording dot color matching Flutter RecordingPill (0xFF5252)
  Color dotColor(alpha, 0xFF, 0x52, 0x52);
  SolidBrush dotBrush(dotColor);
  g.FillEllipse(&dotBrush, x, y, size, size);
}

void FloatingOverlayWindow::PaintWaveform(Graphics& g, float x, float y,
                                           float w, float h) {
  ThemeColors tc = GetThemeColors();

  float total_bar_w = kWaveformBars * kBarWidth +
                      (kWaveformBars - 1) * kBarGap;
  float start_x = x + (w - total_bar_w) / 2.0f;

  // Stateless render: heights come straight from the Dart-side
  // WaveformPipeline via SetWaveformBars. No smoothing, no fallback.
  for (int i = 0; i < kWaveformBars; ++i) {
    double raw = (i < static_cast<int>(waveform_bars_.size()))
                     ? waveform_bars_[i]
                     : 0.0;
    float bar = static_cast<float>(std::clamp(raw, 0.0, 1.0));
    float bar_h = kMinBarHeightPx + bar * (h - kMinBarHeightPx);
    float bar_x = start_x + i * (kBarWidth + kBarGap);
    float bar_y = y + (h - bar_h) / 2.0f;

    Color color = (bar >= kActiveColorThreshold) ? tc.waveform_active
                                                  : tc.waveform_muted;
    SolidBrush brush(color);

    GraphicsPath barPath;
    GdiPlusHelper::MakeRoundedRect(&barPath, bar_x, bar_y, kBarWidth, bar_h,
                                   kBarRadius);
    g.FillPath(&brush, &barPath);
  }
}

void FloatingOverlayWindow::PaintShimmerBar(Graphics& g, float x, float y,
                                             float w, float h) {
  ThemeColors tc = GetThemeColors();
  auto accent = GetAccentColors();

  DWORD now = GetTickCount();
  float t = AnimProgress(now, anim_origin_, kShimmerMs);

  // Shimmer sweep position: -0.3 to 1.3 (so gradient slides fully across)
  float sweep = -0.3f + t * 1.6f;

  // Background bar
  GraphicsPath barPath;
  GdiPlusHelper::MakeRoundedRect(&barPath, x, y, w, h, h / 2.0f);

  Color base(static_cast<BYTE>(tc.shimmer_alpha_lo * 255),
             accent.c0.GetR(), accent.c0.GetG(), accent.c0.GetB());
  SolidBrush baseBrush(base);
  g.FillPath(&baseBrush, &barPath);

  // Gradient highlight
  GraphicsState saved = g.Save();
  g.SetClip(&barPath);

  float glow_w = w * 0.3f;
  float glow_x = x + sweep * w - glow_w / 2.0f;
  Color glow_color(static_cast<BYTE>(tc.shimmer_alpha_hi * 255),
                   accent.c0.GetR(), accent.c0.GetG(), accent.c0.GetB());
  Color glow_edge(0, accent.c0.GetR(), accent.c0.GetG(), accent.c0.GetB());
  LinearGradientBrush glowBrush(PointF(glow_x, y),
                                PointF(glow_x + glow_w, y),
                                glow_edge, glow_edge);
  Color glowColors[] = {glow_edge, glow_color, glow_edge};
  REAL glowPositions[] = {0.0f, 0.5f, 1.0f};
  glowBrush.SetInterpolationColors(glowColors, glowPositions, 3);
  g.FillRectangle(&glowBrush, glow_x, y, glow_w, h);

  g.Restore(saved);
}

void FloatingOverlayWindow::PaintProgressBar(Graphics& g, float x, float y,
                                              float w, float h) {
  // Done state: solid green bar
  Color green(0xCC, 0x16, 0xA3, 0x4A);  // 80% dark, 70% light
  if (!snap_.is_dark) green = Color(0xB3, 0x16, 0xA3, 0x4A);

  GraphicsPath barPath;
  GdiPlusHelper::MakeRoundedRect(&barPath, x, y, w, h, h / 2.0f);
  SolidBrush brush(green);
  g.FillPath(&brush, &barPath);
}

void FloatingOverlayWindow::PaintCloseButton(Graphics& g, float x, float y,
                                              float size) {
  ThemeColors tc = GetThemeColors();

  // Circular hover background (36x36 circle)
  if (close_hover_) {
    SolidBrush hoverBg(tc.close_hover_bg);
    g.FillEllipse(&hoverBg, x, y, size, size);
  }

  // ✕ icon (Lucide X: 18px icon centered in 36px button,
  // lines span 6→18 in 24px viewbox → pad = (9+4.5)/36 = 0.375)
  float pad = size * 0.375f;
  float x0 = x + pad, y0 = y + pad;
  float x1 = x + size - pad, y1 = y + size - pad;
  Pen pen(tc.close_icon, 2.0f);
  pen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
  g.DrawLine(&pen, x0, y0, x1, y1);
  g.DrawLine(&pen, x1, y0, x0, y1);
}

void FloatingOverlayWindow::PaintStopButton(Graphics& g, float x, float y) {
  // 36x36 circle with red gradient (match _PillStopButton)
  auto accent = GetAccentColors();
  float size = kStopBtnSize;

  // Red gradient circle background
  LinearGradientBrush bgBrush(PointF(x, y), PointF(x + size, y + size),
                               accent.c0, accent.c1);
  g.FillEllipse(&bgBrush, x, y, size, size);

  // Hover: 10% white overlay
  if (stop_hover_) {
    SolidBrush hoverOverlay(Color(0x1A, 0xFF, 0xFF, 0xFF));
    g.FillEllipse(&hoverOverlay, x, y, size, size);
  }

  // White square OUTLINE (Lucide square icon — stroked, not filled)
  float sq = kStopIconSize;
  float sx = x + (size - sq) / 2.0f;
  float sy = y + (size - sq) / 2.0f;
  GraphicsPath sqPath;
  GdiPlusHelper::MakeRoundedRect(&sqPath, sx, sy, sq, sq, 1.5f);
  Pen whitePen(Color(255, 255, 255, 255), 2.0f);
  whitePen.SetLineJoin(LineJoinRound);
  g.DrawPath(&whitePen, &sqPath);
}

void FloatingOverlayWindow::PaintBottomProgressBar(Graphics& g, float w,
                                                     float h, float radius) {
  if (snap_.state == OverlayVisualState::kError) return;

  GraphicsState saved = g.Save();
  GraphicsPath clipPath;
  GdiPlusHelper::MakeRoundedRect(&clipPath, 0, 0, w, h, radius);
  Region clipRegion(&clipPath);
  Region barRect(RectF(0, h - kProgressBarH, w, kProgressBarH));
  clipRegion.Intersect(&barRect);
  g.SetClip(&clipRegion);

  ThemeColors tc = GetThemeColors();

  switch (snap_.state) {
    case OverlayVisualState::kRecording: {
      if (snap_.progress > 0.0f) {
        // Recording with time limit — match Flutter _timerColor() logic:
        // 0-74%: textPrimary, >=75%: amber 0xFFC107, >=90%: red 0xFF5252
        float fill_w = w * (std::min)(snap_.progress, 1.0f);
        Color fill_color = tc.text_primary;
        if (snap_.progress >= 0.90f) {
          fill_color = Color(255, 0xFF, 0x52, 0x52);
        } else if (snap_.progress >= 0.75f) {
          fill_color = Color(255, 0xFF, 0xC1, 0x07);
        }
        SolidBrush fillBrush(fill_color);
        g.FillRectangle(&fillBrush, 0.0f, h - kProgressBarH,
                        fill_w, kProgressBarH);
      } else {
        // Unlimited recording — thin accent line at 30% alpha
        Color subtle(0x4D, tc.accent.GetR(), tc.accent.GetG(),
                     tc.accent.GetB());
        SolidBrush subtleBrush(subtle);
        g.FillRectangle(&subtleBrush, 0.0f, h - kProgressBarH,
                        w, kProgressBarH);
      }
      break;
    }
    case OverlayVisualState::kTranscribing:
    case OverlayVisualState::kProcessing: {
      // Shimmer uses accent color (cyan)
      DWORD now = GetTickCount();
      float t = AnimProgress(now, anim_origin_, kShimmerMs);
      float sweep = -0.3f + t * 1.6f;

      Color base(static_cast<BYTE>(tc.shimmer_alpha_lo * 255),
                 tc.accent.GetR(), tc.accent.GetG(), tc.accent.GetB());
      SolidBrush baseBrush(base);
      g.FillRectangle(&baseBrush, 0.0f, h - kProgressBarH, w, kProgressBarH);

      float glow_w = w * 0.3f;
      float glow_x = sweep * w - glow_w / 2.0f;
      Color glow_hi(static_cast<BYTE>(tc.shimmer_alpha_hi * 255),
                    tc.accent.GetR(), tc.accent.GetG(), tc.accent.GetB());
      Color glow_lo(0, tc.accent.GetR(), tc.accent.GetG(), tc.accent.GetB());
      LinearGradientBrush glowBrush(PointF(glow_x, 0),
                                    PointF(glow_x + glow_w, 0),
                                    glow_lo, glow_lo);
      Color gc[] = {glow_lo, glow_hi, glow_lo};
      REAL gp[] = {0.0f, 0.5f, 1.0f};
      glowBrush.SetInterpolationColors(gc, gp, 3);
      g.FillRectangle(&glowBrush, glow_x, h - kProgressBarH,
                      glow_w, kProgressBarH);
      break;
    }
    case OverlayVisualState::kDone: {
      // Solid success color at 80% alpha (match RecordingPill)
      Color success(0xCC, tc.success_color.GetR(), tc.success_color.GetG(),
                    tc.success_color.GetB());
      SolidBrush brush(success);
      g.FillRectangle(&brush, 0.0f, h - kProgressBarH, w, kProgressBarH);
      break;
    }
    default:
      break;
  }

  g.Restore(saved);
}

float FloatingOverlayWindow::PaintPrivacyBadge(Graphics& g, float x, float y) {
  ThemeColors tc = GetThemeColors();

  bool is_local = (snap_.privacy_mode == L"local");
  Color bg = is_local ? tc.badge_local_bg : tc.badge_cloud_bg;
  Color text_color = is_local ? tc.badge_local_text : tc.badge_cloud_text;

  // Measure badge text to determine dynamic width
  std::wstring badge_text = is_local ? L"Local" : L"Cloud";
  Font measureFont(L"Segoe UI", 10.0f, FontStyleBold, UnitPixel);
  RectF measureRect(0, 0, 200.0f, kBadgeHeight);
  StringFormat sf;
  sf.SetFormatFlags(StringFormatFlagsNoWrap);
  RectF textBounds;
  g.MeasureString(badge_text.c_str(), -1, &measureFont, measureRect,
                  &sf, &textBounds);

  // Badge: icon(14) + gap(4) + text + padding(5+5)
  constexpr float kBadgeIconSize = 14.0f;
  float badge_w = kBadgeIconSize + 4.0f + textBounds.Width + 12.0f;
  float badge_h = kBadgeHeight;

  // Pill background
  GraphicsPath badgePath;
  GdiPlusHelper::MakeRoundedRect(&badgePath, x, y, badge_w, badge_h,
                                 badge_h / 2.0f);
  SolidBrush bgBrush(bg);
  g.FillPath(&bgBrush, &badgePath);

  // Icon (14px bounding box, Lucide 24px viewbox scaled)
  float icon_x = x + 5.0f;
  float icon_y = y + (badge_h - kBadgeIconSize) / 2.0f;
  float s = kBadgeIconSize;
  float sx = s / 24.0f;
  Pen iconPen(text_color, 1.2f);
  iconPen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
  iconPen.SetLineJoin(LineJoinRound);
  if (is_local) {
    // ShieldCheck
    GraphicsPath sp;
    sp.AddLine(PointF(icon_x+12*sx, icon_y+2*sx),
               PointF(icon_x+20*sx, icon_y+5*sx));
    sp.AddLine(PointF(icon_x+20*sx, icon_y+5*sx),
               PointF(icon_x+20*sx, icon_y+12*sx));
    sp.AddBezier(PointF(icon_x+20*sx, icon_y+12*sx),
                 PointF(icon_x+20*sx, icon_y+17*sx),
                 PointF(icon_x+16*sx, icon_y+20*sx),
                 PointF(icon_x+12*sx, icon_y+22*sx));
    sp.AddBezier(PointF(icon_x+12*sx, icon_y+22*sx),
                 PointF(icon_x+8*sx, icon_y+20*sx),
                 PointF(icon_x+4*sx, icon_y+17*sx),
                 PointF(icon_x+4*sx, icon_y+12*sx));
    sp.AddLine(PointF(icon_x+4*sx, icon_y+12*sx),
               PointF(icon_x+4*sx, icon_y+5*sx));
    sp.CloseFigure();
    g.DrawPath(&iconPen, &sp);
    g.DrawLine(&iconPen, icon_x+9*sx, icon_y+12*sx,
               icon_x+11*sx, icon_y+14*sx);
    g.DrawLine(&iconPen, icon_x+11*sx, icon_y+14*sx,
               icon_x+15*sx, icon_y+10*sx);
  } else {
    // Cloud
    GraphicsPath cp;
    cp.AddArc(icon_x+6*sx, icon_y+2*sx, 12*sx, 12*sx, 210, 300);
    cp.AddArc(icon_x+2*sx, icon_y+8*sx, 8*sx, 10*sx, 180, 120);
    cp.AddLine(PointF(icon_x+4*sx, icon_y+18*sx),
               PointF(icon_x+20*sx, icon_y+18*sx));
    cp.AddArc(icon_x+14*sx, icon_y+8*sx, 8*sx, 10*sx, 300, 120);
    cp.CloseFigure();
    g.DrawPath(&iconPen, &cp);
  }

  // Badge text (after icon + gap)
  PaintText(g, badge_text, x + kBadgeIconSize + 4.0f + 5.0f, y + 1.0f,
           badge_w - kBadgeIconSize - 4.0f - 10.0f, 10.0f,
           DWRITE_FONT_WEIGHT_SEMI_BOLD, text_color);

  return badge_w;
}

void FloatingOverlayWindow::PaintErrorButtons(Graphics& g, float x, float y) {
  ThemeColors tc = GetThemeColors();

  float btn_w = 60.0f;
  float btn_h = kButtonHeight;
  float btn_r = btn_h / 2.0f;

  // Retry button
  GraphicsPath retryPath;
  GdiPlusHelper::MakeRoundedRect(&retryPath, x, y, btn_w, btn_h, btn_r);
  SolidBrush retryBg(tc.retry_bg);
  g.FillPath(&retryBg, &retryPath);
  PaintText(g, L"Retry", x + 6.0f, y + 2.0f, btn_w - 12.0f, 11.0f,
           DWRITE_FONT_WEIGHT_MEDIUM, tc.retry_text);

  // Dismiss button
  float dismiss_x = x + btn_w + kButtonGap;
  PaintText(g, L"Dismiss", dismiss_x + 4.0f, y + 2.0f, btn_w, 11.0f,
           DWRITE_FONT_WEIGHT_MEDIUM, tc.dismiss_text);
}

// ═══════════════════════════════════════════════════════════════════════
// DirectWrite text rendering
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::PaintText(Graphics& g, const std::wstring& text,
                                      float x, float y, float max_w,
                                      float size, DWRITE_FONT_WEIGHT weight,
                                      const Color& color,
                                      bool tabular_figures) {
  if (text.empty() || !dwrite_factory_) return;

  // Select pre-created format by size+weight
  IDWriteTextFormat* fmt = nullptr;
  if (size >= 14.0f && weight >= DWRITE_FONT_WEIGHT_SEMI_BOLD)
    fmt = text_format_label_;
  else if (size >= 14.0f)
    fmt = text_format_timer_;
  else if (size >= 13.0f)
    fmt = text_format_compact_;
  else if (size >= 12.0f)
    fmt = text_format_hint_;
  else if (size >= 11.0f)
    fmt = text_format_button_;
  else
    fmt = text_format_badge_;

  if (!fmt) return;

  // Create text layout for precise positioning
  IDWriteTextLayout* layout = nullptr;
  HRESULT hr = dwrite_factory_->CreateTextLayout(
      text.c_str(), static_cast<UINT32>(text.length()), fmt, max_w, size * 2,
      &layout);
  if (FAILED(hr) || !layout) return;

  // Enable tabular figures if requested
  if (tabular_figures) {
    IDWriteTypography* typo = nullptr;
    if (SUCCEEDED(dwrite_factory_->CreateTypography(&typo))) {
      DWRITE_FONT_FEATURE feature;
      feature.nameTag = DWRITE_FONT_FEATURE_TAG_TABULAR_FIGURES;
      feature.parameter = 1;
      typo->AddFontFeature(feature);
      DWRITE_TEXT_RANGE range = {0, static_cast<UINT32>(text.length())};
      layout->SetTypography(typo, range);
      typo->Release();
    }
  }

  // Trimming: single line + ellipsis
  layout->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
  IDWriteInlineObject* trimming_sign = nullptr;
  DWRITE_TRIMMING trimming = {};
  trimming.granularity = DWRITE_TRIMMING_GRANULARITY_CHARACTER;
  dwrite_factory_->CreateEllipsisTrimmingSign(fmt, &trimming_sign);
  if (trimming_sign) {
    layout->SetTrimming(&trimming, trimming_sign);
    trimming_sign->Release();
  }

  // Get metrics for vertical centering in compact mode
  DWRITE_TEXT_METRICS metrics;
  layout->GetMetrics(&metrics);

  // Render to GDI+ bitmap via GDI interop
  // Since UpdateLayeredWindow uses premultiplied alpha, we render text
  // directly using GDI+ for simplicity and compatibility.
  // GDI+ DrawString fallback — DirectWrite layout gives us metrics,
  // but GDI+ renders text on the ARGB surface reliably.
  Font fontPx(L"Segoe UI", size,
              (weight >= DWRITE_FONT_WEIGHT_SEMI_BOLD) ? FontStyleBold : FontStyleRegular,
              UnitPixel);

  SolidBrush textBrush(color);
  StringFormat sf;
  sf.SetFormatFlags(StringFormatFlagsNoWrap);
  sf.SetTrimming(StringTrimmingEllipsisCharacter);

  // Use vertical center for compact text at y=0
  if (y < 1.0f && snap_.compact) {
    float content_h = kCompactHeight;
    y = (content_h - size) / 2.0f;
  }

  RectF textRect(x, y, max_w, size * 1.5f);
  g.DrawString(text.c_str(), -1, &fontPx, textRect, &sf, &textBrush);

  layout->Release();
}

// ═══════════════════════════════════════════════════════════════════════
// Context menu
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::ShowContextMenu(int screen_x, int screen_y) {
  if (context_menu_items_.empty()) return;

  HMENU menu = CreatePopupMenu();
  if (!menu) return;

  for (size_t i = 0; i < context_menu_items_.size(); ++i) {
    AppendMenuW(menu, MF_STRING, i + 1, context_menu_items_[i].label.c_str());
  }

  // TrackPopupMenu blocks until selection is made
  int result = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY,
                              screen_x, screen_y, 0, hwnd_, nullptr);
  DestroyMenu(menu);

  if (result > 0 && result <= static_cast<int>(context_menu_items_.size())) {
    const std::wstring& action_w = context_menu_items_[result - 1].id;
    // Safe narrow conversion — menu IDs are ASCII
    int len = WideCharToMultiByte(CP_UTF8, 0, action_w.c_str(),
                                  static_cast<int>(action_w.size()),
                                  nullptr, 0, nullptr, nullptr);
    std::string action(len, '\0');
    WideCharToMultiByte(CP_UTF8, 0, action_w.c_str(),
                        static_cast<int>(action_w.size()),
                        &action[0], len, nullptr, nullptr);
    if (!shutting_down_ && context_menu_cb_) context_menu_cb_(action);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Backbuffer management (reserved for future optimization)
// ═══════════════════════════════════════════════════════════════════════

void FloatingOverlayWindow::EnsureBackbuffer(int phys_w, int phys_h) {
  if (backbuffer_ && backbuffer_w_ == phys_w && backbuffer_h_ == phys_h) return;
  backbuffer_ = std::make_unique<Bitmap>(phys_w, phys_h, PixelFormat32bppPARGB);
  backbuffer_w_ = phys_w;
  backbuffer_h_ = phys_h;
}
