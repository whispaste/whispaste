// Native Win32 floating overlay window — GDI+ + DirectWrite rendered.
// Shows recording/transcription status as an always-on-top layered panel.
// No Flutter dependency. Pure Win32/GDI+/DirectWrite.

#ifndef FLOATING_OVERLAY_WINDOW_H_
#define FLOATING_OVERLAY_WINDOW_H_

#include <windows.h>
#include <dwrite.h>
#include <gdiplus.h>

#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

// Visual state of the overlay (set from Dart snapshot).
enum class OverlayVisualState {
  kRecording = 0,
  kTranscribing,
  kProcessing,
  kDone,
  kError,
};

// How the overlay anchors its position.
enum class OverlayAnchorMode {
  kTopCenter = 0,
  kBottomCenter,
  kTopLeft,  // custom drag position
};

// Complete view-model received from Dart. C++ renders from this exclusively.
struct OverlaySnapshot {
  bool visible = false;
  OverlayVisualState state = OverlayVisualState::kRecording;
  bool is_dark = true;
  bool compact = false;
  std::wstring label;          // "Recording", "Transcribing…", etc.
  std::wstring elapsed;        // "0:05"
  std::wstring hint;           // "Press Ctrl+Shift+D to stop"
  std::wstring transcript;     // Short preview of result
  std::wstring error_message;  // Error description
  std::wstring done_message;   // "Pasted!", "Copied & Pasted!", etc.
  std::wstring processing_label;  // "Processing locally…"
  std::wstring privacy_mode;      // "local" or "cloud"
  bool show_retry = false;
  float progress = 0.0f;         // 0.0–1.0 recording progress (elapsed/limit)
};

// Context menu item sent from Dart (localized).
struct OverlayContextMenuItem {
  std::wstring id;     // "cancel", "switch_normal", "switch_compact", "hide"
  std::wstring label;  // Localized display text
};

class FloatingOverlayWindow {
 public:
  using DragEndCallback =
      std::function<void(double x, double y, const std::string& anchor)>;
  using SimpleCallback = std::function<void()>;
  using ContextMenuCallback = std::function<void(const std::string& action)>;

  FloatingOverlayWindow();
  ~FloatingOverlayWindow();

  FloatingOverlayWindow(const FloatingOverlayWindow&) = delete;
  FloatingOverlayWindow& operator=(const FloatingOverlayWindow&) = delete;

  // Create the native window owned by |owner|.
  bool Create(HWND owner);
  void Destroy();

  // Core API: Dart pushes complete snapshots.
  void UpdateSnapshot(const OverlaySnapshot& snapshot);

  // Push a pre-computed bar array (length kWaveformBars) with values in
  // 0.0–1.0. Sole input to the waveform — the renderer owns no audio state.
  // Keep in sync with the Dart-side `WaveformPipeline` /
  // `FloatingOverlayService` (lib/services/floating_overlay/).
  void SetWaveformBars(const std::vector<double>& bars);

  // Programmatic positioning (start positions).
  void SetPosition(double logical_x, double logical_y,
                   OverlayAnchorMode anchor);

  // Context menu items (sent once at init, localized by Dart).
  void SetContextMenuItems(std::vector<OverlayContextMenuItem> items);

  /// Set overlay opacity (0.0–1.0). Applied on next render.
  void SetOpacity(double opacity);

  HWND GetHandle() const { return hwnd_; }
  bool IsVisible() const { return visible_; }

  // Callbacks (set by host before Create).
  void SetDragEndCallback(DragEndCallback cb) { drag_end_cb_ = std::move(cb); }
  void SetCloseCallback(SimpleCallback cb) { close_cb_ = std::move(cb); }
  void SetBodyClickCallback(SimpleCallback cb) {
    body_click_cb_ = std::move(cb);
  }
  void SetRetryCallback(SimpleCallback cb) { retry_cb_ = std::move(cb); }
  void SetContextMenuCallback(ContextMenuCallback cb) {
    context_menu_cb_ = std::move(cb);
  }

  // Re-asserts HWND_TOPMOST z-order. Safe to call at any time (no-op if
  // window does not exist or is not currently visible).
  void RefreshTopmost();

 private:
  // ── Win32 ────────────────────────────────────────────────────────────
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
  LRESULT HandleMessage(UINT msg, WPARAM wp, LPARAM lp);
  void BringToTopmost();
  static bool EnsureClassRegistered();
  static bool class_registered_;

  // ── Rendering ────────────────────────────────────────────────────────
  void Render();
  void RenderNormal(Gdiplus::Graphics& g, float w, float h);
  void RenderCompact(Gdiplus::Graphics& g, float w, float h);
  void EnsureBackbuffer(int phys_w, int phys_h);

  // Sub-rendering helpers
  void PaintShadow(Gdiplus::Graphics& g, float w, float h, float radius);
  void PaintAccentBar(Gdiplus::Graphics& g, float w, float radius);
  void PaintPhaseDot(Gdiplus::Graphics& g, float x, float y, float size);
  void PaintWaveform(Gdiplus::Graphics& g, float x, float y, float w,
                     float h);
  void PaintShimmerBar(Gdiplus::Graphics& g, float x, float y, float w,
                       float h);
  void PaintProgressBar(Gdiplus::Graphics& g, float x, float y, float w,
                        float h);
  void PaintCloseButton(Gdiplus::Graphics& g, float x, float y, float size);
  float PaintPrivacyBadge(Gdiplus::Graphics& g, float x, float y);
  void PaintErrorButtons(Gdiplus::Graphics& g, float x, float y);
  void PaintStopButton(Gdiplus::Graphics& g, float x, float y);
  void PaintBottomProgressBar(Gdiplus::Graphics& g, float w, float h,
                              float radius);

  // DirectWrite text rendering
  bool InitDirectWrite();
  void PaintText(Gdiplus::Graphics& g, const std::wstring& text, float x,
                 float y, float max_w, float size, DWRITE_FONT_WEIGHT weight,
                 const Gdiplus::Color& color, bool tabular_figures = false);

  // ── Animation ────────────────────────────────────────────────────────
  void OnAnimTick();
  void StartAnimTimer();
  void StopAnimTimer();
  bool NeedsAnimation() const;

  // Show/hide transition
  void StartShowAnimation();
  void StartHideAnimation();
  void OnShowHideAnimTick();

  // ── Hit-testing ──────────────────────────────────────────────────────
  enum class HitZone { kNone, kClose, kDragHeader, kBody, kRetry, kDismiss, kStop };
  HitZone HitTest(int local_x, int local_y) const;
  bool IsInsideRoundedRect(int x, int y) const;

  // ── Positioning ──────────────────────────────────────────────────────
  int CalculateHeight() const;
  int CalculateWidth() const;
  void RecalcPosition();
  void ValidateOnScreen();

  // ── DPI ──────────────────────────────────────────────────────────────
  double GetDpiScale() const;
  int ToPhysical(double logical) const;
  double ToLogical(int physical) const;

  // ── Color helpers ────────────────────────────────────────────────────
  struct ThemeColors {
    Gdiplus::Color background;
    Gdiplus::Color border;
    Gdiplus::Color text_primary;
    Gdiplus::Color text_muted;
    Gdiplus::Color shadow1;
    Gdiplus::Color shadow2;
    Gdiplus::Color close_hover_bg;
    Gdiplus::Color close_icon;
    Gdiplus::Color waveform_active;
    Gdiplus::Color waveform_muted;
    Gdiplus::Color badge_local_bg;
    Gdiplus::Color badge_local_text;
    Gdiplus::Color badge_cloud_bg;
    Gdiplus::Color badge_cloud_text;
    Gdiplus::Color accent;          // WpColors.accent (cyan)
    Gdiplus::Color success_color;   // WpColors.success
    Gdiplus::Color error_color;     // WpColors.error
    Gdiplus::Color retry_bg;
    Gdiplus::Color retry_text;
    Gdiplus::Color dismiss_text;
    float shimmer_alpha_lo;
    float shimmer_alpha_hi;
  };
  ThemeColors GetThemeColors() const;

  struct AccentGradient {
    Gdiplus::Color c0, c1;
  };
  AccentGradient GetAccentColors() const;

  // ── Context menu ─────────────────────────────────────────────────────
  void ShowContextMenu(int screen_x, int screen_y);

  // ── State ────────────────────────────────────────────────────────────
  HWND hwnd_ = nullptr;
  HWND owner_ = nullptr;
  bool shutting_down_ = false;
  bool visible_ = false;
  DWORD creating_thread_id_ = 0;

  // Snapshot (latest from Dart)
  OverlaySnapshot snap_;
  OverlaySnapshot prev_snap_;

  // Positioning
  OverlayAnchorMode anchor_mode_ = OverlayAnchorMode::kTopCenter;
  double anchor_x_ = 0.0;  // Logical
  double anchor_y_ = 0.0;  // Logical

  // Backbuffer
  std::unique_ptr<Gdiplus::Bitmap> backbuffer_;
  int backbuffer_w_ = 0;
  int backbuffer_h_ = 0;

  // Animation
  UINT_PTR anim_timer_ = 0;
  DWORD anim_origin_ = 0;
  DWORD transition_start_ = 0;

  // Show/hide animation
  float show_hide_progress_ = 1.0f;  // 0→1 during show, 1→0 during hide
  bool is_showing_ = false;
  bool is_hiding_ = false;
  DWORD show_hide_start_ = 0;

  // Done celebration
  float celebration_progress_ = -1.0f;  // <0 = inactive
  DWORD celebration_start_ = 0;

  // Transcribing spinner
  DWORD spinner_origin_ = 0;

  // Waveform contract — Dart owns the WaveformPipeline and pushes a
  // pre-computed bar array via SetWaveformBars. The renderer is stateless.
  // Keep in sync with `lib/services/floating_overlay/floating_overlay_service.dart`
  // and `lib/services/floating_overlay/waveform_pipeline.dart`.
  static constexpr int kWaveformBars = 30;
  static constexpr float kMinBarHeightPx = 3.0f;
  static constexpr float kActiveColorThreshold = 0.30f;

  // Pre-computed bars pushed via SetWaveformBars. Empty until the first push;
  // PaintWaveform then renders bar `i` at `kMinBarHeightPx + bars[i] × (h −
  // kMinBarHeightPx)` with the active/muted colour decided by
  // `bars[i] >= kActiveColorThreshold`.
  std::vector<double> waveform_bars_;

  // Drag
  bool dragging_ = false;
  bool drag_moved_ = false;
  POINT drag_cursor_start_ = {};
  POINT drag_window_start_ = {};

  // Close / stop button hover
  bool close_hover_ = false;
  bool stop_hover_ = false;
  bool tracking_mouse_ = false;

  // DirectWrite
  IDWriteFactory* dwrite_factory_ = nullptr;
  IDWriteTextFormat* text_format_label_ = nullptr;
  IDWriteTextFormat* text_format_timer_ = nullptr;
  IDWriteTextFormat* text_format_hint_ = nullptr;
  IDWriteTextFormat* text_format_badge_ = nullptr;
  IDWriteTextFormat* text_format_button_ = nullptr;
  IDWriteTextFormat* text_format_compact_ = nullptr;

  // Context menu items
  std::vector<OverlayContextMenuItem> context_menu_items_;

  // Opacity (0.0–1.0, default 1.0)
  double opacity_ = 1.0;

  // Callbacks
  DragEndCallback drag_end_cb_;
  SimpleCallback close_cb_;
  SimpleCallback body_click_cb_;
  SimpleCallback retry_cb_;
  ContextMenuCallback context_menu_cb_;
};

#endif  // FLOATING_OVERLAY_WINDOW_H_
