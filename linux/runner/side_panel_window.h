#ifndef FLUTTER_SIDE_PANEL_WINDOW_H_
#define FLUTTER_SIDE_PANEL_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <functional>

// Native shell windows for the clipboard quick-paste side panel (issue 06,
// Linux/XWayland port). Structural precedent: floating_overlay_window
// .{h,cc} (decorationless, always-on-top, second-Flutter-engine shell driven
// entirely by GDK/X11, no named-entrypoint API). Behavioral precedent:
// macos/Runner/SidePanelWindow.swift + SidePanelHost.swift and
// windows/runner/side_panel_window.{h,cpp} (dwell-to-open, close-grace,
// slide animation).
//
// Two window classes, mirroring the macOS/Windows pair:
//   * SidePanelSensorWindow  -- one per monitor, hugs the LEFT edge (see
//     SidePanelWindow.swift's file comment for why left, and why a few
//     points wide rather than 1px -- avoids the GNOME Activities hot corner).
//     Reports a raw enter/exit immediately (GDK crossing events) and a
//     dwelled "hover entered" after a short delay (a plain GLib timeout --
//     GTK has no TrackMouseEvent(TME_HOVER) equivalent, so this is a
//     from-scratch timer rather than a system-owned one, closer to the
//     macOS Timer.scheduledTimer approach than the Windows one).
//   * SidePanelContentWindow -- the actual panel: a WS_POPUP-equivalent
//     (override-redirect-free, decorationless, non-activating GtkWindow)
//     hosting the render engine's FlView, slid in/out along X with a
//     self-driven GLib-timeout animation (GTK has no NSAnimationContext
//     equivalent either).
//
// Deliberately NEVER takes keyboard focus (gtk_window_set_accept_focus
// (FALSE) on BOTH windows, unlike SnippetPickerWindow) -- see
// side_panel_host.h's file comment for why: Linux's Auto-Paste bridge
// (DesktopPasteHost, uinput-based) has no window-targeting concept at all,
// it just emits Ctrl+V on whatever the compositor currently considers
// focused, with no macOS/Windows-style "reactivate the captured target
// first" step to fall back on. If this panel ever took real keyboard focus,
// a row click's paste() would fire uinput's Ctrl+V into the panel itself,
// not the app the user was dictating into. So the search field (issue 09,
// shipped on macOS/Windows) has no Linux equivalent yet -- mouse hover/click
// only, a documented platform limitation rather than an oversight.
class SidePanelSensorWindow {
 public:
  SidePanelSensorWindow();
  ~SidePanelSensorWindow();

  SidePanelSensorWindow(const SidePanelSensorWindow&) = delete;
  SidePanelSensorWindow& operator=(const SidePanelSensorWindow&) = delete;

  // |x|/|y|/|width|/|height| are the strip's rect in GTK application
  // (logical) pixels -- GDK resolves the per-monitor scale factor itself, no
  // manual DPI math needed (see snippet_picker_window.h's file comment for
  // the same point).
  bool Create(int x, int y, int width, int height, int dwell_ms);
  void Destroy();

  // Fired after the dwell elapses.
  std::function<void()> on_hover_entered;
  // Fired immediately on the raw GDK enter/leave-notify -- see the file
  // comment on why these exist alongside the dwelled signal (keeps an
  // already-open panel alive while the pointer sits on this strip instead of
  // the content panel proper).
  std::function<void()> on_raw_enter;
  std::function<void()> on_raw_exit;

 private:
  static gboolean OnEnterNotify(GtkWidget* widget, GdkEventCrossing* event,
                                 gpointer user_data);
  static gboolean OnLeaveNotify(GtkWidget* widget, GdkEventCrossing* event,
                                 gpointer user_data);
  static gboolean OnDwellTimeout(gpointer user_data);
  static gboolean OnDraw(GtkWidget* widget, cairo_t* cr, gpointer user_data);

  void HandleEnter();
  void HandleLeave();

  GtkWidget* window_ = nullptr;
  int dwell_ms_ = 60;
  guint dwell_timer_id_ = 0;
};

// ═══════════════════════════════════════════════════════════════════════
// SidePanelContentWindow -- the actual panel shell
// ═══════════════════════════════════════════════════════════════════════
class SidePanelContentWindow {
 public:
  SidePanelContentWindow();
  ~SidePanelContentWindow();

  SidePanelContentWindow(const SidePanelContentWindow&) = delete;
  SidePanelContentWindow& operator=(const SidePanelContentWindow&) = delete;

  // Creates the GtkWindow, boots the 2nd Flutter engine (entrypoint arg
  // "--side-panel"), realizes the shell off-screen and hidden. Must be
  // called before any other method. Call at most once.
  bool Create(int x, int y, int width, int height);

  // Returns the binary messenger of the 2nd engine so the host can open the
  // private render channel (com.whispaste.side_panel_render).
  FlBinaryMessenger* GetRenderMessenger();

  // Places the window at (staging_x, y, width, height) instantly, shows it
  // non-activated, then animates x from staging_x to shown_x over
  // |duration_ms| -- mirrors SidePanelContentWindow::SlideIn on Windows /
  // SidePanelHost.slideIn's setFrame-then-animate ordering on macOS.
  void SlideIn(int staging_x, int shown_x, int y, int width, int height,
               int duration_ms);

  // Animates x from the current position back to staging_x over
  // |duration_ms|, hiding the window once it lands.
  void SlideOut(int staging_x, int duration_ms);

  // Instant reposition while NOT shown -- mirrors positionPanel's "not
  // currently shown -- safe to relocate" branch (e.g. the user hovered a
  // different monitor's edge this time).
  void SetRect(int x, int y, int width, int height);

  bool visible() const { return visible_; }
  bool IsCreated() const { return window_ != nullptr; }

  void Destroy();

  // Native close-grace fallback, mirrors SidePanelContentHoverTracker
  // (macOS) / SidePanelContentWindow::on_content_enter/exit (Windows).
  std::function<void()> on_content_enter;
  std::function<void()> on_content_exit;

 private:
  static gboolean OnEnterNotify(GtkWidget* widget, GdkEventCrossing* event,
                                 gpointer user_data);
  static gboolean OnLeaveNotify(GtkWidget* widget, GdkEventCrossing* event,
                                 gpointer user_data);
  static gboolean OnAnimationTick(gpointer user_data);

  void StartAnimation(int from_x, int to_x, int duration_ms,
                       bool hide_on_done);
  void StepAnimation();

  GtkWidget* window_ = nullptr;
  FlView* fl_view_ = nullptr;  // Non-owning; container holds the ref.

  bool visible_ = false;

  // ── Animation state ─────────────────────────────────────────────────
  guint anim_timer_id_ = 0;
  bool anim_hide_on_done_ = false;
  int anim_from_x_ = 0;
  int anim_to_x_ = 0;
  int anim_y_ = 0;
  int anim_w_ = 0;
  int anim_h_ = 0;
  gint64 anim_start_us_ = 0;
  int anim_duration_ms_ = 220;

  static constexpr guint kAnimIntervalMs = 16;  // ~60fps
};

#endif  // FLUTTER_SIDE_PANEL_WINDOW_H_
