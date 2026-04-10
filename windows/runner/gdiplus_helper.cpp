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

// Gaussian-curve alpha for layer |i| of |total| layers.
// Inner layers stay close to peak_alpha; outer layers fade to near-zero.
static BYTE GaussianAlpha(int i, int total, BYTE peak_alpha) {
  float t = static_cast<float>(i + 1) / total;  // 0..1
  float a = peak_alpha * std::expf(-t * t * 3.0f);
  return static_cast<BYTE>((std::max)(1.0f, a));
}

void PaintSoftShadowCircular(Graphics& g, float cx, float cy, float body_r,
                              float blur, BYTE peak_alpha) {
  constexpr int kLayers = 12;
  for (int i = kLayers - 1; i >= 0; --i) {
    BYTE la = GaussianAlpha(i, kLayers, peak_alpha);
    SolidBrush brush(Color(la, 0, 0, 0));
    float expand = blur * static_cast<float>(i + 1) / kLayers;
    float r = body_r + expand;
    g.FillEllipse(&brush, cx - r, cy - r, r * 2.0f, r * 2.0f);
  }
}

void PaintSoftShadowRect(Graphics& g, float x, float y, float w, float h,
                          float radius, float blur, BYTE peak_alpha) {
  constexpr int kLayers = 12;
  for (int i = kLayers - 1; i >= 0; --i) {
    BYTE la = GaussianAlpha(i, kLayers, peak_alpha);
    SolidBrush brush(Color(la, 0, 0, 0));
    float expand = blur * static_cast<float>(i + 1) / kLayers;
    GraphicsPath path;
    MakeRoundedRect(&path, x - expand, y - expand,
                    w + expand * 2.0f, h + expand * 2.0f,
                    radius + expand);
    g.FillPath(&brush, &path);
  }
}

}  // namespace GdiPlusHelper
