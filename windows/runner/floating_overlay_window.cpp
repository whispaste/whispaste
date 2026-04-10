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
constexpr float kNormalWidth = 360.0f;
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
constexpr float kWaveformHeight = 28.0f;
constexpr float kBarWidth = 2.5f;           // match in-app pill
constexpr float kBarGap = 1.5f;             // match in-app pill
constexpr float kBarRadius = 1.25f;
constexpr float kShimmerHeight = 4.0f;
constexpr float kProgressHeight = 4.0f;
constexpr float kGapAfterViz = 8.0f;
constexpr float kHintHeight = 14.0f;
constexpr float kErrorMsgHeight = 16.0f;
constexpr float kButtonHeight = 24.0f;
constexpr float kButtonGap = 8.0f;
constexpr float kDotSize = 8.0f;
constexpr float kCloseSize = 20.0f;
constexpr float kBadgeHeight = 18.0f;

// ── Pill mode layout (normal, horizontal) ─────────────────────────────
constexpr float kPillHeight = 48.0f;
constexpr float kPillPadH = 14.0f;
constexpr float kPillGap = 8.0f;
constexpr float kProgressBarH = 4.0f;
constexpr float kStopBtnW = 32.0f;
constexpr float kStopBtnH = 28.0f;
constexpr float kStopIconSize = 10.0f;

// ── Shadow (WpShadows.elevated) ───────────────────────────────────────
constexpr float kShadowBlur1 = 16.0f;
constexpr float kShadowOffsetY1 = 6.0f;
constexpr BYTE  kShadowAlpha1Dark = 0x4D;    // 30%
constexpr BYTE  kShadowAlpha1Light = 0x33;   // 20%
constexpr float kShadowBlur2 = 3.0f;
constexpr float kShadowOffsetY2 = 1.0f;
constexpr BYTE  kShadowAlpha2Dark = 0x1A;    // 10%
constexpr BYTE  kShadowAlpha2Light = 0x14;   // 8%
constexpr float kShadowPad = 24.0f;          // extra space for shadow

// ── Animation durations (ms) ──────────────────────────────────────────
constexpr DWORD kShowMs = 200;
constexpr DWORD kHideMs = 150;
constexpr DWORD kDotPulseMs = 900;           // matching RecordingPill
constexpr DWORD kShimmerMs = 1200;
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
      return {Color(255, 0x4A, 0xDE, 0x80), Color(255, 0x16, 0xA3, 0x4A)};
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

FloatingOverlayWindow::FloatingOverlayWindow() {
  for (int i = 0; i < kWaveformBars; ++i) {
    waveform_levels_[i] = 0.0f;
    waveform_display_[i] = 0.0f;
  }
}

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
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
      kClassName, L"", WS_POPUP, -9999, -9999, 1, 1, owner, nullptr,
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

  if (!makeFormat(14.0f, DWRITE_FONT_WEIGHT_SEMI_BOLD, &text_format_label_)) return false;
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

void FloatingOverlayWindow::SetAudioLevel(double level) {
  if (!hwnd_ || shutting_down_) return;
  if (snap_.state != OverlayVisualState::kRecording) return;

  // Push into ring buffer with sqrt boost (matching WpWaveformBars)
  float boosted = static_cast<float>(std::sqrt(std::clamp(level, 0.0, 1.0)) * 1.5);
  boosted = std::clamp(boosted, 0.0f, 1.0f);
  waveform_levels_[waveform_write_idx_] = boosted;
  waveform_write_idx_ = (waveform_write_idx_ + 1) % kWaveformBars;
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
    // Compact mode: close button at right
    float cx = kCompactWidth - 10.0f - kCloseSize;
    float cy = (kCompactHeight - 3.0f - kCloseSize) / 2.0f;
    if (lx >= cx && lx <= cx + kCloseSize &&
        ly >= cy && ly <= cy + kCloseSize) {
      return HitZone::kClose;
    }
    return HitZone::kBody;
  }

  // Normal (pill) mode
  float content_h = kPillHeight - kProgressBarH;
  float cy = content_h / 2.0f;

  // Close button: left side
  float close_x = kPillPadH;
  float close_y = cy - kCloseSize / 2.0f;
  if (lx >= close_x && lx <= close_x + kCloseSize &&
      ly >= close_y && ly <= close_y + kCloseSize) {
    return HitZone::kClose;
  }

  // Stop button: right side (recording only)
  if (snap_.state == OverlayVisualState::kRecording) {
    float stop_x = kNormalWidth - kPillPadH - kStopBtnW;
    float stop_y = cy - kStopBtnH / 2.0f;
    if (lx >= stop_x && lx <= stop_x + kStopBtnW &&
        ly >= stop_y && ly <= stop_y + kStopBtnH) {
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
    c.background = Color(0xF0, 0x17, 0x1D, 0x2C);       // 94% alpha
    c.border = Color(0x14, 0xFF, 0xFF, 0xFF);            // 8% white
    c.text_primary = Color(255, 0xE2, 0xE8, 0xF0);
    c.text_muted = Color(255, 0x94, 0xA3, 0xB8);
    c.shadow1 = Color(kShadowAlpha1Dark, 0, 0, 0);
    c.shadow2 = Color(kShadowAlpha2Dark, 0, 0, 0);
    c.close_hover_bg = Color(0x1A, 0xFF, 0xFF, 0xFF);    // 10% white
    c.close_icon = Color(255, 0x94, 0xA3, 0xB8);
    c.waveform_active = Color(0xD9, 0xFF, 0xFF, 0xFF);   // 85% white
    c.waveform_muted = Color(0x66, 0xFF, 0xFF, 0xFF);    // 40% white
    c.badge_local_bg = Color(0x26, 0x22, 0xC5, 0x5E);    // 15%
    c.badge_local_text = Color(255, 0x4A, 0xDE, 0x80);
    c.badge_cloud_bg = Color(0x26, 0x38, 0xD9, 0xF0);    // 15%
    c.badge_cloud_text = Color(255, 0x38, 0xD9, 0xF0);
    c.retry_bg = Color(0x1A, 0xFF, 0xFF, 0xFF);          // 10% white
    c.retry_text = Color(255, 0xE2, 0xE8, 0xF0);
    c.dismiss_text = Color(255, 0x94, 0xA3, 0xB8);
    c.shimmer_alpha_lo = 0.15f;
    c.shimmer_alpha_hi = 0.60f;
  } else {
    c.background = Color(0xF5, 0xFA, 0xFB, 0xFD);       // 96% alpha
    c.border = Color(0x14, 0x0F, 0x17, 0x2A);            // 8% dark
    c.text_primary = Color(255, 0x10, 0x18, 0x28);
    c.text_muted = Color(255, 0x5B, 0x69, 0x7E);
    c.shadow1 = Color(kShadowAlpha1Light, 0, 0, 0);
    c.shadow2 = Color(kShadowAlpha2Light, 0, 0, 0);
    c.close_hover_bg = Color(0x14, 0x00, 0x00, 0x00);    // 8% black
    c.close_icon = Color(255, 0x5B, 0x69, 0x7E);
    c.waveform_active = Color(0xB3, 0x38, 0xD9, 0xF0);   // 70% accent
    c.waveform_muted = Color(0x59, 0x38, 0xD9, 0xF0);    // 35% accent
    c.badge_local_bg = Color(0x1F, 0x22, 0xC5, 0x5E);    // 12%
    c.badge_local_text = Color(255, 0x16, 0xA3, 0x4A);
    c.badge_cloud_bg = Color(0x1F, 0x08, 0x91, 0xB2);    // 12%
    c.badge_cloud_text = Color(255, 0x08, 0x91, 0xB2);
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

  // Waveform interpolation (smooth bar heights) — both normal and compact
  if (snap_.state == OverlayVisualState::kRecording) {
    for (int i = 0; i < kWaveformBars; ++i) {
      float target = waveform_levels_[(waveform_write_idx_ + i) % kWaveformBars];
      float diff = target - waveform_display_[i];
      waveform_display_[i] += diff * 0.3f;  // smooth interpolation
    }
  }

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
  float scale_factor = 1.0f;
  if (celebration_progress_ >= 0.0f) {
    float t = PingPong(celebration_progress_);
    scale_factor = 1.0f + 0.05f * EaseInOut(t);
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

  POINT dst = {};
  {
    RECT rc;
    GetWindowRect(hwnd_, &rc);
    dst = {rc.left, rc.top};
  }
  SIZE sz = {phys_w, phys_h};
  POINT src = {0, 0};
  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha =
      static_cast<BYTE>(std::clamp(show_hide_progress_, 0.0f, 1.0f) * 255);
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

  // 5a. Close/cancel button (left)
  PaintCloseButton(g, x, cy - kCloseSize / 2.0f, kCloseSize);
  x += kCloseSize + kPillGap;

  // 5b. Privacy badge (during active states)
  if (active && !snap_.privacy_mode.empty()) {
    PaintPrivacyBadge(g, x, cy - kBadgeHeight / 2.0f);
    x += 48.0f + kPillGap;
  }

  // 5c. Phase dot (recording/transcribing/processing)
  if (active) {
    PaintPhaseDot(g, x, cy - kDotSize / 2.0f, kDotSize);
    x += kDotSize + 6.0f;
  }

  // 5d. Right boundary (reserve space for stop button)
  float right_edge = w - kPillPadH;
  if (snap_.state == OverlayVisualState::kRecording)
    right_edge -= kStopBtnW + kPillGap;

  // 5e. Phase-specific center content
  switch (snap_.state) {
    case OverlayVisualState::kRecording: {
      PaintText(g, snap_.elapsed, x, cy - 7.0f, 52.0f, 14.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, tc.text_primary, true);
      x += 52.0f + kPillGap;
      float wf_w = right_edge - x;
      if (wf_w > 20.0f) PaintWaveform(g, x, cy - 14.0f, wf_w, 28.0f);
      break;
    }
    case OverlayVisualState::kTranscribing:
    case OverlayVisualState::kProcessing: {
      auto accent = GetAccentColors();
      PaintText(g, snap_.label, x, cy - 6.5f, 110.0f, 13.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, accent.c0);
      x += 100.0f + 6.0f;
      PaintText(g, snap_.elapsed, x, cy - 6.0f, 45.0f, 12.0f,
               DWRITE_FONT_WEIGHT_REGULAR, tc.text_muted, true);
      break;
    }
    case OverlayVisualState::kDone: {
      auto da = AccentColorsFor(OverlayVisualState::kDone);
      float is = 16.0f;
      float sc = is / 24.0f;
      float ix = x, iy = cy - is / 2.0f;
      Pen cp(da.c0, 1.5f);
      cp.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawEllipse(&cp, ix + 2 * sc, iy + 2 * sc, 20 * sc, 20 * sc);
      g.DrawLine(&cp, ix + 9 * sc, iy + 12 * sc,
                 ix + 11 * sc, iy + 14 * sc);
      g.DrawLine(&cp, ix + 11 * sc, iy + 14 * sc,
                 ix + 15 * sc, iy + 10 * sc);
      x += is + 6.0f;
      PaintText(g, snap_.done_message, x, cy - 6.5f, right_edge - x, 13.0f,
               DWRITE_FONT_WEIGHT_SEMI_BOLD, da.c0);
      break;
    }
    case OverlayVisualState::kError: {
      auto ea = AccentColorsFor(OverlayVisualState::kError);
      float is = 16.0f;
      float sc = is / 24.0f;
      float ix = x, iy = cy - is / 2.0f;
      Pen ep(ea.c0, 1.5f);
      ep.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
      g.DrawEllipse(&ep, ix + 2 * sc, iy + 2 * sc, 20 * sc, 20 * sc);
      g.DrawLine(&ep, ix + 12 * sc, iy + 8 * sc,
                 ix + 12 * sc, iy + 12 * sc);
      SolidBrush db(ea.c0);
      g.FillEllipse(&db, ix + 11.25f * sc, iy + 15.25f * sc,
                    1.5f * sc, 1.5f * sc);
      x += is + 6.0f;
      PaintText(g, snap_.error_message, x, cy - 6.5f, right_edge - x, 13.0f,
               DWRITE_FONT_WEIGHT_MEDIUM, ea.c0);
      break;
    }
  }

  // 5f. Stop button (right side, recording only)
  if (snap_.state == OverlayVisualState::kRecording) {
    PaintStopButton(g, w - kPillPadH - kStopBtnW, cy - kStopBtnH / 2.0f);
  }
}

// ── Compact mode rendering ────────────────────────────────────────────

void FloatingOverlayWindow::RenderCompact(Graphics& g, float w, float h) {
  ThemeColors tc = GetThemeColors();
  float r = kCompactRadius;

  PaintShadow(g, w, h, r);

  // Background (pill)
  GraphicsPath bgPath;
  GdiPlusHelper::MakeRoundedRect(&bgPath, 0, 0, w, h, r);
  SolidBrush bgBrush(tc.background);
  g.FillPath(&bgBrush, &bgPath);

  Pen borderPen(tc.border, 1.0f);
  g.DrawPath(&borderPen, &bgPath);

  // Bottom accent phase bar (3px, clipped to bottom corners of pill)
  {
    auto accent = GetAccentColors();
    GraphicsState saved = g.Save();
    GraphicsPath clipPath;
    GdiPlusHelper::MakeRoundedRect(&clipPath, 0, h - r * 2, w, r * 2, r);
    Region clipRegion(&clipPath);
    Region rectRegion(RectF(0, h - 3.0f, w, 3.0f));
    clipRegion.Intersect(&rectRegion);
    g.SetClip(&clipRegion);
    LinearGradientBrush barBrush(PointF(0, 0), PointF(w, 0),
                                 accent.c0, accent.c1);
    g.FillRectangle(&barBrush, 0.0f, h - 3.0f, w, 3.0f);
    g.Restore(saved);
  }

  // Phase dot
  float content_y = (h - 3.0f - kDotSize) / 2.0f;  // centered in content area
  float dot_x = 12.0f;
  PaintPhaseDot(g, dot_x, content_y, kDotSize);

  // Label
  float label_x = dot_x + kDotSize + 6.0f;
  float text_y = (h - 3.0f - 13.0f) / 2.0f;  // vertically center text
  PaintText(g, snap_.label, label_x, text_y, 90.0f, 13.0f,
           DWRITE_FONT_WEIGHT_SEMI_BOLD, tc.text_primary);

  // Timer (right of label)
  float timer_x = label_x + 90.0f + 4.0f;
  PaintText(g, snap_.elapsed, timer_x, text_y, 42.0f, 13.0f,
           DWRITE_FONT_WEIGHT_REGULAR, tc.text_muted, true);

  // Mini waveform during recording (8 bars, compact)
  if (snap_.state == OverlayVisualState::kRecording) {
    float mini_bar_w = 2.5f;
    float mini_bar_gap = 1.5f;
    int mini_bars = 8;
    float wf_x = timer_x + 42.0f + 8.0f;
    float wf_h = 16.0f;
    float wf_y = (h - 3.0f - wf_h) / 2.0f;

    for (int i = 0; i < mini_bars; ++i) {
      // Sample every other bar from the 16-bar buffer
      int src = (i * 2) % kWaveformBars;
      float level = waveform_display_[src];
      float bar_h = 3.0f + level * (wf_h - 3.0f);
      float bx = wf_x + i * (mini_bar_w + mini_bar_gap);
      float by = wf_y + (wf_h - bar_h) / 2.0f;

      Color color = (level > 0.30f) ? tc.waveform_active : tc.waveform_muted;
      SolidBrush brush(color);
      GraphicsPath barPath;
      GdiPlusHelper::MakeRoundedRect(&barPath, bx, by, mini_bar_w, bar_h, 1.0f);
      g.FillPath(&brush, &barPath);
    }
  }

  // Close button (always visible in compact, but subtle)
  float cx = w - 10.0f - kCloseSize;
  float cy = (h - 3.0f - kCloseSize) / 2.0f;
  PaintCloseButton(g, cx, cy, kCloseSize);
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
  auto accent = GetAccentColors();

  BYTE alpha = 255;
  if (snap_.state == OverlayVisualState::kRecording) {
    DWORD now = GetTickCount();
    float t = PingPong(AnimProgress(now, anim_origin_, kDotPulseMs));
    alpha = static_cast<BYTE>(115 + 140 * EaseInOut(t));  // 45%–100%
  }

  Color dotColor(alpha, accent.c0.GetR(), accent.c0.GetG(), accent.c0.GetB());
  SolidBrush dotBrush(dotColor);
  g.FillEllipse(&dotBrush, x, y, size, size);
}

void FloatingOverlayWindow::PaintWaveform(Graphics& g, float x, float y,
                                           float w, float h) {
  ThemeColors tc = GetThemeColors();

  float total_bar_w = kWaveformBars * kBarWidth +
                      (kWaveformBars - 1) * kBarGap;
  float start_x = x + (w - total_bar_w) / 2.0f;

  for (int i = 0; i < kWaveformBars; ++i) {
    float level = waveform_display_[i];
    float bar_h = 4.0f + level * (h - 4.0f);  // 4px min → h max
    float bar_x = start_x + i * (kBarWidth + kBarGap);
    float bar_y = y + (h - bar_h) / 2.0f;  // vertically centered

    Color color = (level > 0.30f) ? tc.waveform_active : tc.waveform_muted;
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

  // Hover background
  if (close_hover_) {
    SolidBrush hoverBg(tc.close_hover_bg);
    GraphicsPath hoverPath;
    GdiPlusHelper::MakeRoundedRect(&hoverPath, x, y, size, size, 4.0f);
    g.FillPath(&hoverBg, &hoverPath);
  }

  // ✕ icon (simple X)
  float pad = size * 0.3f;
  float x0 = x + pad, y0 = y + pad;
  float x1 = x + size - pad, y1 = y + size - pad;
  Pen pen(tc.close_icon, 1.5f);
  pen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
  g.DrawLine(&pen, x0, y0, x1, y1);
  g.DrawLine(&pen, x1, y0, x0, y1);
}

void FloatingOverlayWindow::PaintStopButton(Graphics& g, float x, float y) {
  auto accent = GetAccentColors();
  float btn_r = kStopBtnH / 2.0f;

  GraphicsPath btnPath;
  GdiPlusHelper::MakeRoundedRect(&btnPath, x, y, kStopBtnW, kStopBtnH, btn_r);

  Color bg = accent.c0;
  if (stop_hover_) {
    int r = (std::min)(static_cast<int>(accent.c0.GetR()) + 20, 255);
    int gg = (std::min)(static_cast<int>(accent.c0.GetG()) + 10, 255);
    bg = Color(255, static_cast<BYTE>(r), static_cast<BYTE>(gg),
               accent.c0.GetB());
  }
  SolidBrush bgBrush(bg);
  g.FillPath(&bgBrush, &btnPath);

  float sq = kStopIconSize;
  float sx = x + (kStopBtnW - sq) / 2.0f;
  float sy = y + (kStopBtnH - sq) / 2.0f;
  GraphicsPath sqPath;
  GdiPlusHelper::MakeRoundedRect(&sqPath, sx, sy, sq, sq, 2.0f);
  SolidBrush white(Color(255, 255, 255, 255));
  g.FillPath(&white, &sqPath);
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

  auto accent = GetAccentColors();

  switch (snap_.state) {
    case OverlayVisualState::kRecording:
      // No progress data in snapshot yet -- recording uses accent strip only
      break;
    case OverlayVisualState::kTranscribing:
    case OverlayVisualState::kProcessing: {
      ThemeColors tc = GetThemeColors();
      DWORD now = GetTickCount();
      float t = AnimProgress(now, anim_origin_, kShimmerMs);
      float sweep = -0.3f + t * 1.6f;

      Color base(static_cast<BYTE>(tc.shimmer_alpha_lo * 255),
                 accent.c0.GetR(), accent.c0.GetG(), accent.c0.GetB());
      SolidBrush baseBrush(base);
      g.FillRectangle(&baseBrush, 0.0f, h - kProgressBarH, w, kProgressBarH);

      float glow_w = w * 0.3f;
      float glow_x = sweep * w - glow_w / 2.0f;
      Color glow_hi(static_cast<BYTE>(tc.shimmer_alpha_hi * 255),
                    accent.c0.GetR(), accent.c0.GetG(), accent.c0.GetB());
      Color glow_lo(0, accent.c0.GetR(), accent.c0.GetG(), accent.c0.GetB());
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
      LinearGradientBrush brush(PointF(0, 0), PointF(w, 0),
                                accent.c0, accent.c1);
      g.FillRectangle(&brush, 0.0f, h - kProgressBarH, w, kProgressBarH);
      break;
    }
    default:
      break;
  }

  g.Restore(saved);
}

void FloatingOverlayWindow::PaintPrivacyBadge(Graphics& g, float x, float y) {
  ThemeColors tc = GetThemeColors();

  bool is_local = (snap_.privacy_mode == L"local");
  Color bg = is_local ? tc.badge_local_bg : tc.badge_cloud_bg;
  Color text_color = is_local ? tc.badge_local_text : tc.badge_cloud_text;

  float badge_w = 48.0f;  // approximate
  float badge_h = kBadgeHeight;

  GraphicsPath badgePath;
  GdiPlusHelper::MakeRoundedRect(&badgePath, x, y + 1.0f, badge_w, badge_h,
                                 badge_h / 2.0f);
  SolidBrush bgBrush(bg);
  g.FillPath(&bgBrush, &badgePath);

  // Lucide-style icons (10px bounding box)
  float icon_x = x + 6.0f;
  float icon_y = y + 4.0f;
  float s = 10.0f;
  float sx = s / 24.0f;  // Scale from Lucide 24px viewbox
  Pen iconPen(text_color, 1.2f);
  iconPen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
  iconPen.SetLineJoin(LineJoinRound);
  if (is_local) {
    // ShieldCheck: pointed shield + checkmark
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
    // Checkmark
    g.DrawLine(&iconPen, icon_x+9*sx, icon_y+12*sx,
               icon_x+11*sx, icon_y+14*sx);
    g.DrawLine(&iconPen, icon_x+11*sx, icon_y+14*sx,
               icon_x+15*sx, icon_y+10*sx);
  } else {
    // Cloud: top arc + bumps + flat bottom
    GraphicsPath cp;
    cp.AddArc(icon_x+6*sx, icon_y+2*sx, 12*sx, 12*sx, 210, 300);
    cp.AddArc(icon_x+2*sx, icon_y+8*sx, 8*sx, 10*sx, 180, 120);
    cp.AddLine(PointF(icon_x+4*sx, icon_y+18*sx),
               PointF(icon_x+20*sx, icon_y+18*sx));
    cp.AddArc(icon_x+14*sx, icon_y+8*sx, 8*sx, 10*sx, 300, 120);
    cp.CloseFigure();
    g.DrawPath(&iconPen, &cp);
  }

  // Badge text
  std::wstring badge_text = is_local ? L"Local" : L"Cloud";
  PaintText(g, badge_text, x + 18.0f, y + 1.0f, 28.0f, 10.0f,
           DWRITE_FONT_WEIGHT_SEMI_BOLD, text_color);
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
