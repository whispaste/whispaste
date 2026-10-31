// Shared GDI+ utilities for native floating windows.
// Ref-counted GDI+ init/shutdown, color helpers, easing, and rounded-rect paths.
// Used by FloatingButtonWindow and FloatingOverlayWindow.

#ifndef GDIPLUS_HELPER_H_
#define GDIPLUS_HELPER_H_

#include <windows.h>
#include <gdiplus.h>

namespace GdiPlusHelper {

// Ref-counted GDI+ lifecycle — call from each window's Create()/Destroy().
// Thread-safe for single-threaded UI model (all calls on the UI thread).
bool AddRef();
void Release();

// ── Color helpers ──────────────────────────────────────────────────────

// Linear interpolation between two GDI+ colors.
Gdiplus::Color LerpColor(const Gdiplus::Color& a, const Gdiplus::Color& b,
                         float t);

// Create a Color from hex ARGB. Example: FromArgb(0xF0171D2C).
inline Gdiplus::Color FromArgb(UINT argb) {
  return Gdiplus::Color(
      static_cast<BYTE>((argb >> 24) & 0xFF),
      static_cast<BYTE>((argb >> 16) & 0xFF),
      static_cast<BYTE>((argb >> 8) & 0xFF),
      static_cast<BYTE>(argb & 0xFF));
}

// Create a Color from RGB + alpha byte. Example: WithAlpha(0xFF7B7B, 0xCC).
inline Gdiplus::Color WithAlpha(UINT rgb, BYTE alpha) {
  return Gdiplus::Color(
      alpha,
      static_cast<BYTE>((rgb >> 16) & 0xFF),
      static_cast<BYTE>((rgb >> 8) & 0xFF),
      static_cast<BYTE>(rgb & 0xFF));
}

// ── Path helpers ───────────────────────────────────────────────────────

// Build a rounded-rectangle GraphicsPath. Caller owns the returned pointer.
Gdiplus::GraphicsPath* MakeRoundedRect(float x, float y, float w, float h,
                                       float radius);

// Fill an existing GraphicsPath with a rounded rectangle (resets path first).
void MakeRoundedRect(Gdiplus::GraphicsPath* path, float x, float y, float w,
                     float h, float radius);

// ── Easing curves ──────────────────────────────────────────────────────

float EaseOut(float t);
float EaseInOut(float t);

// Ping-pong: 0→1→0 over one full period.
float PingPong(float t);

// Normalised animation progress [0,1] from tick count.
float AnimProgress(DWORD now, DWORD origin, DWORD period_ms);

// ── Shadow helpers ─────────────────────────────────────────────────────

// Paint smooth shadows using multi-layer concentric shapes.
// Draws N additive layers from body edge outward, creating smooth falloff.

// Circular variant — for round FAB-style shadows.
// |cx|, |cy|: center; |body_r|: body radius; |blur|: spread distance.
void PaintSoftShadowCircular(Gdiplus::Graphics& g, float cx, float cy,
                              float body_r, float blur, BYTE peak_alpha);

// Rectangular variant — for rounded-rect overlay shadows.
// |x|, |y|, |w|, |h|: body rect; |radius|: corner radius; |blur|: spread.
void PaintSoftShadowRect(Gdiplus::Graphics& g, float x, float y, float w,
                          float h, float radius, float blur,
                          BYTE peak_alpha);

}  // namespace GdiPlusHelper

#endif  // GDIPLUS_HELPER_H_
