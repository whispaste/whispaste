// Shared GDI+ utilities — implementation.
// See gdiplus_helper.h for API documentation.

#include "gdiplus_helper.h"

#include <algorithm>
#include <cmath>

using namespace Gdiplus;

namespace GdiPlusHelper {

// ── Ref-counted GDI+ startup/shutdown ──────────────────────────────────

static int g_ref_count = 0;
static ULONG_PTR g_token = 0;

bool AddRef() {
  if (g_ref_count++ == 0) {
    GdiplusStartupInput input;
    Status st = GdiplusStartup(&g_token, &input, nullptr);
    if (st != Ok) {
      g_ref_count--;
      OutputDebugStringW(L"[GdiPlusHelper] GdiplusStartup failed\n");
      return false;
    }
  }
  return true;
}

void Release() {
  if (--g_ref_count == 0) {
    GdiplusShutdown(g_token);
    g_token = 0;
  }
}

// ── Color helpers ──────────────────────────────────────────────────────

Color LerpColor(const Color& a, const Color& b, float t) {
  t = std::clamp(t, 0.0f, 1.0f);
  return Color(
      static_cast<BYTE>(a.GetA() + (b.GetA() - a.GetA()) * t),
      static_cast<BYTE>(a.GetR() + (b.GetR() - a.GetR()) * t),
      static_cast<BYTE>(a.GetG() + (b.GetG() - a.GetG()) * t),
      static_cast<BYTE>(a.GetB() + (b.GetB() - a.GetB()) * t));
}

// ── Path helpers ───────────────────────────────────────────────────────

GraphicsPath* MakeRoundedRect(float x, float y, float w, float h,
                              float radius) {
  auto* path = new GraphicsPath();
  float d = radius * 2.0f;
  // Clamp diameter to smallest dimension.
  d = (std::min)(d, (std::min)(w, h));

  path->AddArc(x, y, d, d, 180.0f, 90.0f);           // top-left
  path->AddArc(x + w - d, y, d, d, 270.0f, 90.0f);   // top-right
  path->AddArc(x + w - d, y + h - d, d, d, 0.0f, 90.0f);   // bottom-right
  path->AddArc(x, y + h - d, d, d, 90.0f, 90.0f);    // bottom-left
  path->CloseFigure();
  return path;
}

void MakeRoundedRect(GraphicsPath* path, float x, float y, float w, float h,
                     float radius) {
  path->Reset();
  float d = radius * 2.0f;
  d = (std::min)(d, (std::min)(w, h));
  path->AddArc(x, y, d, d, 180.0f, 90.0f);
  path->AddArc(x + w - d, y, d, d, 270.0f, 90.0f);
  path->AddArc(x + w - d, y + h - d, d, d, 0.0f, 90.0f);
  path->AddArc(x, y + h - d, d, d, 90.0f, 90.0f);
  path->CloseFigure();
}

// ── Easing curves ──────────────────────────────────────────────────────

float EaseOut(float t) {
  return 1.0f - (1.0f - t) * (1.0f - t);
}

float EaseInOut(float t) {
  return t < 0.5f ? 2.0f * t * t
                  : 1.0f - std::powf(-2.0f * t + 2.0f, 2.0f) / 2.0f;
}

float PingPong(float t) {
  return t < 0.5f ? t * 2.0f : 2.0f - t * 2.0f;
}

float AnimProgress(DWORD now, DWORD origin, DWORD period_ms) {
  DWORD elapsed = now - origin;
  return static_cast<float>(elapsed % period_ms) / period_ms;
}

// ── Shadow helpers ──────────────────────────────────────────────────────

void PaintGaussianShadowCircular(Graphics& g, GraphicsPath* path, float focus,
                                  BYTE alpha) {
  PathGradientBrush brush(path);

  Color center(alpha, 0, 0, 0);
  brush.SetCenterColor(center);
  int n = 1;
  Color edge(0, 0, 0, 0);
  brush.SetSurroundColors(&edge, &n);

  // 5-stop gaussian-like falloff: steep initial drop then long tail to zero.
  // Positions are 0.0 (center) → 1.0 (path edge).
  Color colors[] = {
      Color(alpha, 0, 0, 0),                               // center
      Color(alpha, 0, 0, 0),                               // body edge
      Color(static_cast<BYTE>(alpha * 0.30f), 0, 0, 0),   // rapid drop
      Color(static_cast<BYTE>(alpha * 0.06f), 0, 0, 0),   // almost gone
      Color(0, 0, 0, 0),                                    // outer edge
  };
  REAL positions[] = {
      0.0f,
      focus,
      focus + (1.0f - focus) * 0.35f,
      focus + (1.0f - focus) * 0.75f,
      1.0f,
  };
  brush.SetInterpolationColors(colors, positions, 5);
  g.FillPath(&brush, path);
}

void PaintGaussianShadowRect(Graphics& g, GraphicsPath* path, float fx,
                              float fy, BYTE alpha) {
  PathGradientBrush brush(path);

  Color center(alpha, 0, 0, 0);
  brush.SetCenterColor(center);
  int n = 1;
  Color edge(0, 0, 0, 0);
  brush.SetSurroundColors(&edge, &n);

  // Use average of fx/fy for 1D interpolation color positions.
  float focus = (fx + fy) / 2.0f;

  Color colors[] = {
      Color(alpha, 0, 0, 0),
      Color(alpha, 0, 0, 0),
      Color(static_cast<BYTE>(alpha * 0.30f), 0, 0, 0),
      Color(static_cast<BYTE>(alpha * 0.06f), 0, 0, 0),
      Color(0, 0, 0, 0),
  };
  REAL positions[] = {
      0.0f,
      focus,
      focus + (1.0f - focus) * 0.35f,
      focus + (1.0f - focus) * 0.75f,
      1.0f,
  };
  brush.SetInterpolationColors(colors, positions, 5);
  // Also set focus scales so the brush shape stays rectangular.
  brush.SetFocusScales(fx, fy);
  g.FillPath(&brush, path);
}

}  // namespace GdiPlusHelper
