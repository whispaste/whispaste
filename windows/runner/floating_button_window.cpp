// Native Win32 floating button — GDI+ rendered layered popup window.
// Crash-proof: no Flutter engine, no ANGLE, no GPU contention.
// See plan.md Phase 3.1 for full specification.

#include "floating_button_window.h"
#include "gdiplus_helper.h"

#include <windowsx.h>  // GET_X_LPARAM, GET_Y_LPARAM
#include <algorithm>
#include <cmath>

#pragma comment(lib, "gdiplus.lib")

using namespace Gdiplus;

namespace {

// ── Layout constants (logical pixels) ─────────────────────────────────
constexpr float kPulseMaxScale = 1.8f;
constexpr float kRingStroke = 2.5f;
constexpr float kShadowBlur1 = 14.0f;
constexpr float kShadowOffset1 = 3.0f;
constexpr BYTE kShadowAlpha1 = 0x08;   // ~3% per layer → ~17% composite (12 layers)
constexpr float kShadowBlur2 = 2.0f;
constexpr float kShadowOffset2 = 0.0f;
constexpr BYTE kShadowAlpha2 = 0x04;   // ~1.6% per layer → ~8% composite
constexpr float kSafetyPad = 2.0f;
constexpr float kIconSize = 24.0f;     // Lucide viewbox
constexpr float kIconStroke = 2.0f;    // Lucide default stroke-width

// ── Animation durations (ms) ──────────────────────────────────────────
constexpr DWORD kPulseRingMs = 1400;
constexpr DWORD kBodyPulseMs = 1800;
constexpr DWORD kSpinnerMs = 1200;
constexpr DWORD kIdleBreatheMs = 3000;
constexpr DWORD kTransitionMs = 200;
constexpr UINT kTimerIntervalMs = 33;  // ~30 fps
constexpr UINT_PTR kTimerId = 0xFB01;  // arbitrary, unique within the window

// ── Window class name ─────────────────────────────────────────────────
constexpr const wchar_t kClassName[] = L"WHISPASTE_FLOATING_BTN";

// ── Easing curves — delegate to GdiPlusHelper ─────────────────────────
// Local wrappers kept for brevity at call sites.
float EaseOut(float t) { return GdiPlusHelper::EaseOut(t); }
float EaseInOut(float t) { return GdiPlusHelper::EaseInOut(t); }
float PingPong(float t) { return GdiPlusHelper::PingPong(t); }
float AnimProgress(DWORD now, DWORD origin, DWORD period_ms) {
  return GdiPlusHelper::AnimProgress(now, origin, period_ms);
}

}  // namespace

// ── Static members ────────────────────────────────────────────────────
bool FloatingButtonWindow::class_registered_ = false;
int FloatingButtonWindow::gdiplus_ref_count_ = 0;
ULONG_PTR FloatingButtonWindow::gdiplus_token_ = 0;

// ══════════════════════════════════════════════════════════════════════
// GDI+ ref-counted startup / shutdown — delegates to GdiPlusHelper
// ══════════════════════════════════════════════════════════════════════

bool FloatingButtonWindow::AddGdiPlusRef() {
  return GdiPlusHelper::AddRef();
}

void FloatingButtonWindow::ReleaseGdiPlusRef() {
  GdiPlusHelper::Release();
}

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
                                  int logical_size) {
  if (hwnd_) return true;  // already created

  if (!AddGdiPlusRef()) return false;
  gdi_plus_acquired_ = true;

  if (!EnsureClassRegistered()) {
    ReleaseGdiPlusRef();
    gdi_plus_acquired_ = false;
    OutputDebugStringW(L"[FloatingButton] RegisterClassEx failed\n");
    return false;
  }

  owner_ = owner;
  logical_size_ = std::max(logical_size, 16);
  logical_x_ = lx;
  logical_y_ = ly;

  // Use owner DPI before hwnd_ exists.
  double dpi = GetDpiScaleForOwner();
  float body_r = static_cast<float>(logical_size_ / 2.0);
  float ring_extent = body_r * kPulseMaxScale + kRingStroke / 2.0f;
  float shadow_extent = body_r + kShadowBlur1 + kShadowOffset1;
  float outer_r = std::max(ring_extent, shadow_extent) + kSafetyPad;
  int outer = static_cast<int>(std::ceil(outer_r * 2.0 * dpi));
  int px = static_cast<int>(std::round(lx * dpi)) - outer / 2;
  int py = static_cast<int>(std::round(ly * dpi)) - outer / 2;

  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED | WS_EX_NOACTIVATE,
      kClassName, L"", WS_POPUP, px, py, outer, outer, owner, nullptr,
      GetModuleHandle(nullptr), this);

  if (!hwnd_) {
    OutputDebugStringW(L"[FloatingButton] CreateWindowEx failed\n");
    ReleaseGdiPlusRef();
    gdi_plus_acquired_ = false;
    return false;
  }

  creating_thread_id_ = GetCurrentThreadId();
  anim_origin_ = GetTickCount();
  transition_start_ = anim_origin_;
  return true;
}

void FloatingButtonWindow::Destroy() {
  if (shutting_down_) return;
  if (!IsOnCreatingThread()) {
    OutputDebugStringW(
        L"[FloatingButton] Destroy() called from wrong thread!\n");
    return;
  }
  shutting_down_ = true;

  // Invariant #4: strict teardown order
  StopAnimTimer();

  if (hwnd_ && GetCapture() == hwnd_) ReleaseCapture();

  click_cb_ = nullptr;
  secondary_click_cb_ = nullptr;
  drag_end_cb_ = nullptr;

  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
  visible_ = false;
  owner_ = nullptr;

  if (gdi_plus_acquired_) {
    ReleaseGdiPlusRef();
    gdi_plus_acquired_ = false;
  }

  shutting_down_ = false;  // allow re-creation
}

// ══════════════════════════════════════════════════════════════════════
// Thread affinity
// ══════════════════════════════════════════════════════════════════════

bool FloatingButtonWindow::IsOnCreatingThread() const {
  // Before Create(), any thread is fine (creating_thread_id_ == 0).
  if (creating_thread_id_ == 0) return true;
  return GetCurrentThreadId() == creating_thread_id_;
}

// ══════════════════════════════════════════════════════════════════════
// Show / Hide
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonWindow::Show() {
  if (!hwnd_ || shutting_down_ || !IsOnCreatingThread()) return;
  ValidatePosition();
  ApplyWindowPosition();
  Render();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  BringToTopmost();
  visible_ = true;
  if (NeedsAnimation()) StartAnimTimer();
}

void FloatingButtonWindow::Hide() {
  if (!hwnd_ || shutting_down_ || !IsOnCreatingThread()) return;
  StopAnimTimer();
  ShowWindow(hwnd_, SW_HIDE);
  visible_ = false;
}

void FloatingButtonWindow::BringToTopmost() {
  if (!hwnd_) return;
  SetWindowPos(hwnd_, HWND_TOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

// ══════════════════════════════════════════════════════════════════════
// Public setters
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonWindow::SetState(FloatingButtonState s) {
  if (s == state_) return;
  prev_state_ = state_;
  state_ = s;
  transition_start_ = GetTickCount();
  anim_origin_ = transition_start_;
  if (visible_ && hwnd_) {
    if (NeedsAnimation())
      StartAnimTimer();
    else
      StopAnimTimer();
    Render();
  }
}

void FloatingButtonWindow::SetTheme(bool dark) {
  if (dark == is_dark_) return;
  is_dark_ = dark;
  if (visible_ && hwnd_) Render();
}

void FloatingButtonWindow::SetOpacity(double o) {
  opacity_ = std::clamp(o, 0.0, 1.0);
  if (visible_ && hwnd_) Render();
}

void FloatingButtonWindow::SetSize(int s) {
  s = std::max(s, 16);
  if (s == logical_size_) return;
  logical_size_ = s;
  if (hwnd_) {
    int outer = GetOuterPhysical();
    SetWindowPos(hwnd_, nullptr, 0, 0, outer, outer,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    ApplyWindowPosition();
    if (visible_) Render();
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

    // ── Hit testing (circle math) ─────────────────────────────────────
    case WM_NCHITTEST: {
      POINT pt = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
      ScreenToClient(hwnd_, &pt);
      int outer = GetOuterPhysical();
      float cx = outer / 2.0f;
      float cy = outer / 2.0f;
      float r = ToPhysical(logical_size_) / 2.0f;
      float dx = pt.x - cx;
      float dy = pt.y - cy;
      if (dx * dx + dy * dy <= r * r) return HTCLIENT;
      return HTTRANSPARENT;
    }

    // ── Click / drag ──────────────────────────────────────────────────
    case WM_LBUTTONDOWN: {
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
      if (!dragging_) break;
      POINT cur;
      GetCursorPos(&cur);
      int dx = cur.x - drag_cursor_start_.x;
      int dy = cur.y - drag_cursor_start_.y;
      if (!drag_moved_ && (abs(dx) < GetSystemMetrics(SM_CXDRAG) &&
                           abs(dy) < GetSystemMetrics(SM_CYDRAG)))
        return 0;
      drag_moved_ = true;
      SetWindowPos(hwnd_, nullptr, drag_window_start_.x + dx,
                   drag_window_start_.y + dy, 0, 0,
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_LBUTTONUP: {
      if (!dragging_) break;
      ReleaseCapture();
      dragging_ = false;
      if (drag_moved_) {
        // Update logical position from current window rect.
        RECT rc;
        GetWindowRect(hwnd_, &rc);
        int outer = GetOuterPhysical();
        int center_x = rc.left + outer / 2;
        int center_y = rc.top + outer / 2;
        logical_x_ = ToLogical(center_x);
        logical_y_ = ToLogical(center_y);
        if (drag_end_cb_) drag_end_cb_(logical_x_, logical_y_);
      } else {
        if (click_cb_) click_cb_();
      }
      return 0;
    }
    case WM_RBUTTONUP: {
      if (secondary_click_cb_) secondary_click_cb_();
      return 0;
    }

    // ── Capture lost (e.g. another window grabs it) ───────────────────
    case WM_CAPTURECHANGED:
    case WM_CANCELMODE:
      dragging_ = false;
      return 0;

    // ── DPI change ────────────────────────────────────────────────────
    case WM_DPICHANGED: {
      // Recompute size+position at new DPI (GetDpiForWindow already
      // returns the updated value during WM_DPICHANGED processing).
      ApplyWindowPosition();
      if (visible_) Render();
      return 0;
    }

    // ── Display change (monitor plug/unplug) ──────────────────────────
    case WM_DISPLAYCHANGE:
      if (visible_) {
        ValidatePosition();
        ApplyWindowPosition();
        Render();
      }
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

    // ── No-op paint (layered windows don't receive WM_PAINT) ──────────
    case WM_PAINT: {
      PAINTSTRUCT ps;
      BeginPaint(hwnd_, &ps);
      EndPaint(hwnd_, &ps);
      return 0;
    }

    case WM_DESTROY:
      return 0;

    // ── External destruction safety ───────────────────────────────────
    // If the owner window tears us down implicitly, clear our state so
    // no stale HWND is used later.
    case WM_NCDESTROY:
      SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
      StopAnimTimer();
      if (GetCapture() == hwnd_) ReleaseCapture();
      hwnd_ = nullptr;
      owner_ = nullptr;
      visible_ = false;
      dragging_ = false;
      if (gdi_plus_acquired_) {
        ReleaseGdiPlusRef();
        gdi_plus_acquired_ = false;
      }
      return 0;
  }

  return DefWindowProcW(hwnd_, msg, wp, lp);
}

// ══════════════════════════════════════════════════════════════════════
// Render pipeline
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonWindow::Render() {
  if (!hwnd_ || shutting_down_) return;

  double dpi = GetDpiScale();
  int outer = GetOuterPhysical();
  float cx = outer / 2.0f;
  float cy = outer / 2.0f;
  float body_r = static_cast<float>(logical_size_ / 2.0 * dpi);

  // Transition progress [0,1].
  DWORD now = GetTickCount();
  float tProg = 1.0f;
  if (now - transition_start_ < kTransitionMs)
    tProg = EaseOut(static_cast<float>(now - transition_start_) / kTransitionMs);

  // ── Create 32-bit ARGB DIB section ──────────────────────────────────
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = outer;
  bmi.bmiHeader.biHeight = -outer;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP dib = CreateDIBSection(nullptr, &bmi, DIB_RGB_COLORS, &bits,
                                 nullptr, 0);
  if (!dib) return;

  // Wrap DIB bits with GDI+ Bitmap for drawing.
  Bitmap bmp(outer, outer, outer * 4, PixelFormat32bppPARGB,
             static_cast<BYTE*>(bits));
  Graphics g(&bmp);
  g.SetSmoothingMode(SmoothingModeHighQuality);
  g.SetInterpolationMode(InterpolationModeHighQualityBicubic);
  g.Clear(Color(0, 0, 0, 0));

  // ── Pulse ring (recording only) ────────────────────────────────────
  if (state_ == FloatingButtonState::kRecording)
    PaintPulseRing(g, cx, cy, body_r);

  // ── Shadow ─────────────────────────────────────────────────────────
  PaintShadow(g, cx, cy, body_r);

  // ── Body ───────────────────────────────────────────────────────────
  // Apply body pulse (recording) or idle breathe.
  float body_scale = 1.0f;
  if (state_ == FloatingButtonState::kRecording) {
    float t = PingPong(AnimProgress(now, anim_origin_, kBodyPulseMs));
    body_scale = 1.0f + 0.04f * EaseInOut(t);
  }
  PaintBody(g, cx, cy, body_r * body_scale);

  // ── Icon (scaled proportionally with button size) ───────────────────
  float icon_ratio = static_cast<float>(logical_size_) / 56.0f;
  float icon_phys = static_cast<float>(kIconSize * icon_ratio * dpi);
  PaintIcon(g, cx, cy, icon_phys);

  // Flush GDI+ writes before handing to GDI.
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
  SIZE sz = {outer, outer};
  POINT src = {0, 0};
  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha =
      static_cast<BYTE>(std::clamp(opacity_, 0.0, 1.0) * 255);
  blend.AlphaFormat = AC_SRC_ALPHA;

  UpdateLayeredWindow(hwnd_, screen, &dst, &sz, mem, &src, 0, &blend,
                      ULW_ALPHA);

  SelectObject(mem, old_bmp);
  DeleteDC(mem);
  ReleaseDC(nullptr, screen);
  DeleteObject(dib);
}

// ── Shadow via multi-layer concentric circles ─────────────────────────

void FloatingButtonWindow::PaintShadow(Graphics& g, float cx, float cy,
                                       float body_r) {
  double dpi = GetDpiScale();
  auto draw_layer = [&](float blur, float offset_y, BYTE alpha) {
    float b = static_cast<float>(blur * dpi);
    float oy = static_cast<float>(offset_y * dpi);
    GdiPlusHelper::PaintSoftShadowCircular(g, cx, cy + oy, body_r, b, alpha);
  };

  draw_layer(kShadowBlur1, kShadowOffset1, kShadowAlpha1);
  draw_layer(kShadowBlur2, kShadowOffset2, kShadowAlpha2);
}

// ── Body circle with gradient ─────────────────────────────────────────

void FloatingButtonWindow::PaintBody(Graphics& g, float cx, float cy,
                                     float r) {
  DWORD now = GetTickCount();
  float tProg = 1.0f;
  if (now - transition_start_ < kTransitionMs)
    tProg = EaseOut(static_cast<float>(now - transition_start_) / kTransitionMs);

  Gradient cur = ColorsFor(state_);
  Gradient prev = ColorsFor(prev_state_);

  // Interpolate during transition.
  auto c0 = LerpColor(prev.c0, cur.c0, tProg);
  auto c1 = LerpColor(prev.c1, cur.c1, tProg);
  auto c2 = LerpColor(prev.c2, cur.c2, tProg);

  PointF p1(cx - r, cy - r);
  PointF p2(cx + r, cy + r);
  LinearGradientBrush brush(p1, p2, c0, c2);

  // Apply 3-stop interpolation.
  Color colors[] = {c0, c1, c2};
  REAL positions[] = {0.0f, 0.5f, 1.0f};
  brush.SetInterpolationColors(colors, positions, 3);

  g.FillEllipse(&brush, cx - r, cy - r, r * 2, r * 2);
}

// ── Icon ──────────────────────────────────────────────────────────────

void FloatingButtonWindow::PaintIcon(Graphics& g, float cx, float cy,
                                     float icon_size) {
  auto saved = g.Save();

  float scale = icon_size / 24.0f;
  g.TranslateTransform(cx - icon_size / 2.0f, cy - icon_size / 2.0f);
  g.ScaleTransform(scale, scale);

  Pen pen(Color(255, 255, 255, 255), kIconStroke);
  pen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
  pen.SetLineJoin(LineJoinRound);

  switch (state_) {
    case FloatingButtonState::kIdle:
      DrawMicIcon(g, pen);
      break;
    case FloatingButtonState::kRecording:
      DrawSquareIcon(g, pen);
      break;
    case FloatingButtonState::kTranscribing: {
      DWORD now = GetTickCount();
      float deg = AnimProgress(now, anim_origin_, kSpinnerMs) * 360.0f;
      DrawLoaderIcon(g, pen, deg);
      break;
    }
    case FloatingButtonState::kDone:
      DrawCheckIcon(g, pen);
      break;
    case FloatingButtonState::kError:
      DrawAlertIcon(g, pen);
      break;
    case FloatingButtonState::kDisabled:
      DrawMicIcon(g, pen);
      break;
  }

  g.Restore(saved);
}

// ── Pulse ring ────────────────────────────────────────────────────────

void FloatingButtonWindow::PaintPulseRing(Graphics& g, float cx, float cy,
                                          float base_r) {
  DWORD now = GetTickCount();
  float t = AnimProgress(now, anim_origin_, kPulseRingMs);
  float ring_scale = 1.0f + (kPulseMaxScale - 1.0f) * EaseOut(t);
  float ring_alpha = (1.0f - EaseOut(t)) * 0.5f;

  if (ring_alpha < 0.01f) return;

  Gradient cols = ColorsFor(state_);
  Color ring_color(static_cast<BYTE>(ring_alpha * 255), cols.c0.GetR(),
                   cols.c0.GetG(), cols.c0.GetB());

  double dpi = GetDpiScale();
  float stroke = static_cast<float>(kRingStroke * dpi);
  Pen pen(ring_color, stroke);

  float rr = base_r * ring_scale;
  g.DrawEllipse(&pen, cx - rr, cy - rr, rr * 2, rr * 2);
}

// ══════════════════════════════════════════════════════════════════════
// Lucide icon drawing (24×24 coordinate space)
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonWindow::DrawMicIcon(Graphics& g, Pen& pen) {
  // Capsule body: top at y=2, sides y=5→12, bottom curve through y=15, r=3
  GraphicsPath body;
  body.AddArc(9.0f, 2.0f, 6.0f, 6.0f, 180.0f, 180.0f);   // top cap
  body.AddLine(15.0f, 5.0f, 15.0f, 12.0f);                 // right side
  body.AddArc(9.0f, 9.0f, 6.0f, 6.0f, 0.0f, 180.0f);      // bottom cap
  body.CloseFigure();
  g.DrawPath(&pen, &body);

  // Holder arc with vertical ends
  GraphicsPath holder;
  holder.AddLine(19.0f, 10.0f, 19.0f, 12.0f);
  holder.AddArc(5.0f, 5.0f, 14.0f, 14.0f, 0.0f, 180.0f);
  holder.AddLine(5.0f, 12.0f, 5.0f, 10.0f);
  g.DrawPath(&pen, &holder);

  // Stem (no base line — matches Lucide mic v3.1.12)
  g.DrawLine(&pen, 12.0f, 19.0f, 12.0f, 22.0f);
}

void FloatingButtonWindow::DrawSquareIcon(Graphics& g, Pen& pen) {
  // Rounded rect: (3,3) 18×18, rx=ry=2
  constexpr float x = 3, y = 3, w = 18, h = 18, r = 2;
  GraphicsPath path;
  path.AddArc(x, y, r * 2, r * 2, 180.0f, 90.0f);
  path.AddLine(x + r, y, x + w - r, y);
  path.AddArc(x + w - r * 2, y, r * 2, r * 2, 270.0f, 90.0f);
  path.AddLine(x + w, y + r, x + w, y + h - r);
  path.AddArc(x + w - r * 2, y + h - r * 2, r * 2, r * 2, 0.0f, 90.0f);
  path.AddLine(x + w - r, y + h, x + r, y + h);
  path.AddArc(x, y + h - r * 2, r * 2, r * 2, 90.0f, 90.0f);
  path.CloseFigure();
  g.DrawPath(&pen, &path);
}

void FloatingButtonWindow::DrawLoaderIcon(Graphics& g, Pen& pen,
                                          float rotation_deg) {
  // Nearly-full circle arc (~288°) with a gap.
  auto saved = g.Save();
  g.TranslateTransform(12.0f, 12.0f);
  g.RotateTransform(rotation_deg);
  g.TranslateTransform(-12.0f, -12.0f);

  GraphicsPath path;
  path.AddArc(3.0f, 3.0f, 18.0f, 18.0f, -72.0f, 288.0f);
  g.DrawPath(&pen, &path);

  g.Restore(saved);
}

void FloatingButtonWindow::DrawCheckIcon(Graphics& g, Pen& pen) {
  // M20 6 → 9 17 → 4 12
  GraphicsPath path;
  path.AddLine(20.0f, 6.0f, 9.0f, 17.0f);
  path.AddLine(9.0f, 17.0f, 4.0f, 12.0f);
  g.DrawPath(&pen, &path);
}

void FloatingButtonWindow::DrawAlertIcon(Graphics& g, Pen& pen) {
  // Triangle outline
  GraphicsPath tri;
  tri.AddLine(12.0f, 3.0f, 2.0f, 21.0f);
  tri.AddLine(2.0f, 21.0f, 22.0f, 21.0f);
  tri.CloseFigure();
  g.DrawPath(&pen, &tri);

  // Exclamation line
  g.DrawLine(&pen, 12.0f, 9.0f, 12.0f, 13.0f);

  // Dot (small filled circle)
  SolidBrush white(Color(255, 255, 255, 255));
  g.FillEllipse(&white, 11.0f, 16.0f, 2.0f, 2.0f);
}

// ══════════════════════════════════════════════════════════════════════
// Animation timer
// ══════════════════════════════════════════════════════════════════════

void CALLBACK FloatingButtonWindow::AnimTimerProc(HWND hwnd, UINT, UINT_PTR,
                                                  DWORD) {
  auto* self = reinterpret_cast<FloatingButtonWindow*>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self && !self->shutting_down_) self->OnAnimTick();
}

void FloatingButtonWindow::OnAnimTick() {
  if (!visible_ || shutting_down_) return;
  Render();
  if (!NeedsAnimation()) StopAnimTimer();
}

void FloatingButtonWindow::StartAnimTimer() {
  if (anim_timer_ || !hwnd_) return;
  anim_timer_ = SetTimer(hwnd_, kTimerId, kTimerIntervalMs, AnimTimerProc);
}

void FloatingButtonWindow::StopAnimTimer() {
  if (!anim_timer_ || !hwnd_) return;
  KillTimer(hwnd_, kTimerId);
  anim_timer_ = 0;
}

bool FloatingButtonWindow::NeedsAnimation() const {
  if (state_ == FloatingButtonState::kRecording) return true;
  if (state_ == FloatingButtonState::kTranscribing) return true;
  if (state_ == FloatingButtonState::kIdle) return true;  // breathe
  // Active transition still fading.
  if (GetTickCount() - transition_start_ < kTransitionMs) return true;
  return false;
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
  // Fallback: primary monitor DPI.
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
  return (dpi > 0) ? physical / dpi : physical;
}

int FloatingButtonWindow::GetOuterPhysical() const {
  double dpi = GetDpiScale();
  float body_r = static_cast<float>(logical_size_ / 2.0);
  float ring_extent = body_r * kPulseMaxScale + kRingStroke / 2.0f;
  float shadow_extent = body_r + kShadowBlur1 + kShadowOffset1;
  float outer_r = std::max(ring_extent, shadow_extent) + kSafetyPad;
  return static_cast<int>(std::ceil(outer_r * 2.0 * dpi));
}

// ══════════════════════════════════════════════════════════════════════
// Position helpers
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonWindow::ApplyWindowPosition() {
  if (!hwnd_) return;
  int outer = GetOuterPhysical();
  int px = ToPhysical(logical_x_) - outer / 2;
  int py = ToPhysical(logical_y_) - outer / 2;
  SetWindowPos(hwnd_, nullptr, px, py, outer, outer,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FloatingButtonWindow::ValidatePosition() {
  // Off-screen recovery: clamp to nearest monitor's work area.
  POINT pt = {ToPhysical(logical_x_), ToPhysical(logical_y_)};
  HMONITOR mon = MonitorFromPoint(pt, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(mon, &mi)) return;

  const RECT& wa = mi.rcWork;
  // Use full outer extent so shadow/pulse stay visible.
  int margin = GetOuterPhysical() / 2;
  int clamped_x = std::clamp(pt.x, wa.left + margin, wa.right - margin);
  int clamped_y = std::clamp(pt.y, wa.top + margin, wa.bottom - margin);

  if (clamped_x != pt.x || clamped_y != pt.y) {
    logical_x_ = ToLogical(clamped_x);
    logical_y_ = ToLogical(clamped_y);
  }
}

// ══════════════════════════════════════════════════════════════════════
// Gradient color helpers
// ══════════════════════════════════════════════════════════════════════

FloatingButtonWindow::Gradient FloatingButtonWindow::ColorsFor(
    FloatingButtonState s) const {
  // All hex values match fab.dart + colors.dart exactly.
  switch (s) {
    case FloatingButtonState::kIdle:
      if (is_dark_)
        return {{255, 0x38, 0xD9, 0xF0},
                {255, 0x14, 0xB8, 0xD4},
                {255, 0x0A, 0x99, 0xB8},
                true};
      else
        return {{255, 0x08, 0x91, 0xB2},
                {255, 0x0E, 0x74, 0x90},
                {255, 0x15, 0x5E, 0x75},
                true};

    case FloatingButtonState::kRecording:
      return {{255, 0xEF, 0x44, 0x44},
              // Synthesize mid for uniform 3-stop interpolation.
              {255, (0xEF + 0xDC) / 2, (0x44 + 0x26) / 2, (0x44 + 0x26) / 2},
              {255, 0xDC, 0x26, 0x26},
              false};

    case FloatingButtonState::kTranscribing:
      return {{255, 0xF5, 0x9E, 0x0B},
              {255, (0xF5 + 0xD9) / 2, (0x9E + 0x77) / 2, (0x0B + 0x06) / 2},
              {255, 0xD9, 0x77, 0x06},
              false};

    case FloatingButtonState::kDone:
      return {{255, 0x4A, 0xDE, 0x80},
              {255, (0x4A + 0x16) / 2, (0xDE + 0xA3) / 2, (0x80 + 0x4A) / 2},
              {255, 0x16, 0xA3, 0x4A},
              false};

    case FloatingButtonState::kError:
      return {{255, 0xFF, 0x7B, 0x7B},
              {255, (0xFF + 0xEF) / 2, (0x7B + 0x44) / 2, (0x7B + 0x44) / 2},
              {255, 0xEF, 0x44, 0x44},
              false};

    case FloatingButtonState::kDisabled:
      if (is_dark_)
        return {{255, 0x52, 0x52, 0x5B},
                {255, (0x52 + 0x3F) / 2, (0x52 + 0x3F) / 2,
                 (0x5B + 0x46) / 2},
                {255, 0x3F, 0x3F, 0x46},
                false};
      else
        return {{255, 0x9C, 0xA3, 0xAF},
                {255, (0x9C + 0x6B) / 2, (0xA3 + 0x72) / 2,
                 (0xAF + 0x80) / 2},
                {255, 0x6B, 0x72, 0x80},
                false};
  }

  // Fallback (should never reach here).
  return {{255, 0x38, 0xD9, 0xF0},
          {255, 0x14, 0xB8, 0xD4},
          {255, 0x0A, 0x99, 0xB8},
          true};
}

Color FloatingButtonWindow::LerpColor(const Color& a, const Color& b,
                                      float t) {
  return GdiPlusHelper::LerpColor(a, b, t);
}
