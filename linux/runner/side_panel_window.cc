#include "side_panel_window.h"

#include <gdk/gdk.h>

#include <algorithm>
#include <cmath>

#include "secondary_engine.h"
#include "secondary_plugin_registrant.h"
#include "positioned_window_type.h"

// ══════════════════════════════════════════════════════════════════════
// SidePanelSensorWindow
// ══════════════════════════════════════════════════════════════════════

SidePanelSensorWindow::SidePanelSensorWindow() = default;
SidePanelSensorWindow::~SidePanelSensorWindow() { Destroy(); }

bool SidePanelSensorWindow::Create(int x, int y, int width, int height,
                                    int dwell_ms) {
  if (window_) return true;
  dwell_ms_ = dwell_ms;

  // TOPLEVEL (not POPUP/override-redirect) -- mirrors floating_overlay
  // _window.cc/snippet_picker_window.cc: a regular, WM-managed window that
  // just asks not to be decorated/activated/listed, so `gtk_window_set_
  // keep_above` and the NOTIFICATION type hint below actually mean something
  // to the WM (an override-redirect POPUP window bypasses the WM entirely,
  // which loses both). Tiling WMs are the exception: they would tile the
  // strip into a black half-screen pane, so there it bypasses the WM
  // (XP-6-10, PositionedHelperWindowType).
  window_ = gtk_window_new(PositionedHelperWindowType());

  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  // Never take focus -- see side_panel_window.h's file comment.
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);
  gtk_window_set_type_hint(GTK_WINDOW(window_),
                            GDK_WINDOW_TYPE_HINT_NOTIFICATION);

  gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
  gtk_widget_set_size_request(window_, width, height);

  // ── RGBA / transparency ──────────────────────────────────────────────
  // A hit-test target only, never actually painted -- mirrors
  // SidePanelSensorPanel's isOpaque=false/clear background (macOS) and the
  // 1/255-alpha layered window (Windows). Unlike Win32, GDK/X11 input
  // hit-testing is independent of paint alpha, so a fully transparent draw
  // (see OnDraw) is enough; there is no click-through trap to work around.
  gtk_widget_set_app_paintable(window_, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(window_);
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(window_, rgba_visual);
  }
  g_signal_connect(window_, "draw", G_CALLBACK(OnDraw), nullptr);

  gtk_widget_add_events(window_, GDK_ENTER_NOTIFY_MASK |
                                      GDK_LEAVE_NOTIFY_MASK |
                                      GDK_POINTER_MOTION_MASK);
  g_signal_connect(window_, "enter-notify-event", G_CALLBACK(OnEnterNotify),
                    this);
  g_signal_connect(window_, "leave-notify-event", G_CALLBACK(OnLeaveNotify),
                    this);

  gtk_window_move(GTK_WINDOW(window_), x, y);
  gtk_widget_show(window_);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);

  return true;
}

void SidePanelSensorWindow::Destroy() {
  if (dwell_timer_id_) {
    g_source_remove(dwell_timer_id_);
    dwell_timer_id_ = 0;
  }
  on_hover_entered = nullptr;
  on_raw_enter = nullptr;
  on_raw_exit = nullptr;
  if (window_) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
  }
}

// static
gboolean SidePanelSensorWindow::OnDraw(GtkWidget* /*widget*/, cairo_t* cr,
                                        gpointer /*user_data*/) {
  cairo_save(cr);
  cairo_set_source_rgba(cr, 0, 0, 0, 0);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_paint(cr);
  cairo_restore(cr);
  return FALSE;
}

// static
gboolean SidePanelSensorWindow::OnEnterNotify(GtkWidget* /*widget*/,
                                               GdkEventCrossing* event,
                                               gpointer user_data) {
  // Ignore inferior crossings (pointer moving between this window and its
  // own descendants) -- this window has no children, so in practice every
  // crossing is a genuine boundary one, but filtering explicitly mirrors the
  // same NORMAL-only intent as the tracking areas on macOS/Windows.
  if (event->detail == GDK_NOTIFY_INFERIOR) return FALSE;
  static_cast<SidePanelSensorWindow*>(user_data)->HandleEnter();
  return FALSE;
}

// static
gboolean SidePanelSensorWindow::OnLeaveNotify(GtkWidget* /*widget*/,
                                               GdkEventCrossing* event,
                                               gpointer user_data) {
  if (event->detail == GDK_NOTIFY_INFERIOR) return FALSE;
  static_cast<SidePanelSensorWindow*>(user_data)->HandleLeave();
  return FALSE;
}

// static
gboolean SidePanelSensorWindow::OnDwellTimeout(gpointer user_data) {
  auto* self = static_cast<SidePanelSensorWindow*>(user_data);
  self->dwell_timer_id_ = 0;
  if (self->on_hover_entered) self->on_hover_entered();
  return G_SOURCE_REMOVE;
}

void SidePanelSensorWindow::HandleEnter() {
  if (on_raw_enter) on_raw_enter();
  if (dwell_timer_id_) g_source_remove(dwell_timer_id_);
  dwell_timer_id_ =
      g_timeout_add(static_cast<guint>(dwell_ms_), OnDwellTimeout, this);
}

void SidePanelSensorWindow::HandleLeave() {
  if (dwell_timer_id_) {
    g_source_remove(dwell_timer_id_);
    dwell_timer_id_ = 0;
  }
  if (on_raw_exit) on_raw_exit();
}

// ══════════════════════════════════════════════════════════════════════
// SidePanelContentWindow
// ══════════════════════════════════════════════════════════════════════

SidePanelContentWindow::SidePanelContentWindow() = default;
SidePanelContentWindow::~SidePanelContentWindow() { Destroy(); }

bool SidePanelContentWindow::Create(int x, int y, int width, int height) {
  if (window_) return true;

  // Same window type rule as SidePanelSensorWindow::Create above.
  window_ = gtk_window_new(PositionedHelperWindowType());

  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  // Never take focus -- see side_panel_window.h's file comment (the row
  // click -> uinput Ctrl+V paste path requires the target app to still hold
  // real keyboard focus).
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);
  gtk_window_set_type_hint(GTK_WINDOW(window_),
                            GDK_WINDOW_TYPE_HINT_NOTIFICATION);

  gtk_window_set_default_size(GTK_WINDOW(window_), width, height);
  gtk_widget_set_size_request(window_, width, height);

  // ── RGBA / transparency ──────────────────────────────────────────────
  gtk_widget_set_app_paintable(window_, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(window_);
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(window_, rgba_visual);
  }

  // ── Second Flutter engine (entrypoint arg: --side-panel) ─────────────
  g_autoptr(FlDartProject) project = secondary_project_new("--side-panel");

  FlView* view = fl_view_new(project);
  secondary_view_watch_first_frame(view, "Side panel");
  fl_view_ = view;  // Non-owning; container holds the strong ref.

  GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(fl_view_, &transparent);

  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(fl_view_));
  fl_register_secondary_plugins(FL_PLUGIN_REGISTRY(fl_view_));
  gtk_widget_show(GTK_WIDGET(fl_view_));

  gtk_widget_add_events(window_, GDK_ENTER_NOTIFY_MASK |
                                      GDK_LEAVE_NOTIFY_MASK |
                                      GDK_POINTER_MOTION_MASK);
  g_signal_connect(window_, "enter-notify-event", G_CALLBACK(OnEnterNotify),
                    this);
  g_signal_connect(window_, "leave-notify-event", G_CALLBACK(OnLeaveNotify),
                    this);

  // A drag must start from the button press that began it (Wayland checks
  // its serial), but the render engine reports the drag only later over its
  // channel. A capture-phase gesture records each press before the Flutter
  // view handles it; it never claims the press, so Flutter still gets it.
  press_gesture_ = gtk_gesture_multi_press_new(window_);
  gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(press_gesture_),
                                GDK_BUTTON_PRIMARY);
  gtk_event_controller_set_propagation_phase(
      GTK_EVENT_CONTROLLER(press_gesture_), GTK_PHASE_CAPTURE);
  g_signal_connect(press_gesture_, "pressed", G_CALLBACK(OnPressed), this);
  g_signal_connect(press_gesture_, "released", G_CALLBACK(OnReleased), this);
  g_signal_connect(window_, "drag-data-get", G_CALLBACK(OnDragDataGet), this);
  g_signal_connect(window_, "drag-end", G_CALLBACK(OnDragEnd), this);

  gtk_window_move(GTK_WINDOW(window_), x, y);

  // Realize (not show) so the engine starts booting immediately, while the
  // window itself stays off-screen/hidden until SlideIn() is called.
  gtk_widget_realize(window_);
  return true;
}

FlBinaryMessenger* SidePanelContentWindow::GetRenderMessenger() {
  if (!fl_view_) return nullptr;
  FlEngine* engine = fl_view_get_engine(fl_view_);
  if (!engine) return nullptr;
  return fl_engine_get_binary_messenger(engine);
}

void SidePanelContentWindow::SetRect(int x, int y, int width, int height) {
  if (!window_ || visible_) return;
  gtk_window_move(GTK_WINDOW(window_), x, y);
  gtk_window_resize(GTK_WINDOW(window_), width, height);
  gtk_widget_set_size_request(window_, width, height);
}

void SidePanelContentWindow::Destroy() {
  if (anim_timer_id_) {
    g_source_remove(anim_timer_id_);
    anim_timer_id_ = 0;
  }
  on_content_enter = nullptr;
  on_content_exit = nullptr;
  if (press_gesture_) {
    g_object_unref(press_gesture_);
    press_gesture_ = nullptr;
  }
  if (last_press_) {
    gdk_event_free(last_press_);
    last_press_ = nullptr;
  }
  if (window_) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
    fl_view_ = nullptr;  // Destroyed with window_.
  }
  visible_ = false;
}

// ══════════════════════════════════════════════════════════════════════
// Drag-out (issue 11), see SidePanelHost.swift's beginNativeDrag
// ══════════════════════════════════════════════════════════════════════

namespace {
constexpr guint kDragText = 1;
constexpr guint kDragImage = 2;
}  // namespace

// static
void SidePanelContentWindow::OnPressed(GtkGestureMultiPress* gesture,
                                       gint /*n_press*/, gdouble /*x*/,
                                       gdouble /*y*/, gpointer user_data) {
  auto* self = static_cast<SidePanelContentWindow*>(user_data);
  GdkEventSequence* sequence =
      gtk_gesture_single_get_current_sequence(GTK_GESTURE_SINGLE(gesture));
  const GdkEvent* event =
      gtk_gesture_get_last_event(GTK_GESTURE(gesture), sequence);
  if (!event) return;
  if (self->last_press_) gdk_event_free(self->last_press_);
  self->last_press_ = gdk_event_copy(event);
  self->button_held_ = true;
}

// static
void SidePanelContentWindow::OnReleased(GtkGestureMultiPress* /*gesture*/,
                                        gint /*n_press*/, gdouble /*x*/,
                                        gdouble /*y*/, gpointer user_data) {
  static_cast<SidePanelContentWindow*>(user_data)->button_held_ = false;
}

// static
void SidePanelContentWindow::OnDragEnd(GtkWidget* /*widget*/,
                                       GdkDragContext* /*context*/,
                                       gpointer user_data) {
  static_cast<SidePanelContentWindow*>(user_data)->ReleaseHeldButton();
}

// A drag-out grabs the pointer, and a panel that slides out under a held
// button loses its window: either way the release never reaches the Flutter
// view, which then keeps the pointer down and ignores every later press.
// Hand it the release it missed, at the press position.
void SidePanelContentWindow::ReleaseHeldButton() {
  if (!button_held_ || !last_press_) return;
  button_held_ = false;
  GdkEvent* release = gdk_event_copy(last_press_);
  release->type = GDK_BUTTON_RELEASE;
  release->button.state |= GDK_BUTTON1_MASK;
  const guint32 now = gtk_get_current_event_time();
  if (now != GDK_CURRENT_TIME) release->button.time = now;
  gtk_main_do_event(release);
  gdk_event_free(release);
}

bool SidePanelContentWindow::BeginDrag(const std::string& text,
                                       const std::vector<uint8_t>& png) {
  if (!window_ || !last_press_) return false;
  const bool image = !png.empty();
  if (!image && text.empty()) return false;
  drag_text_ = text;
  drag_png_ = png;

  GtkTargetList* targets = gtk_target_list_new(nullptr, 0);
  if (image) {
    gtk_target_list_add_image_targets(targets, kDragImage, TRUE);
  } else {
    gtk_target_list_add_text_targets(targets, kDragText);
  }
  GdkDragContext* context = gtk_drag_begin_with_coordinates(
      window_, targets, GDK_ACTION_COPY, GDK_BUTTON_PRIMARY, last_press_, -1,
      -1);
  gtk_target_list_unref(targets);
  return context != nullptr;
}

// static
void SidePanelContentWindow::OnDragDataGet(GtkWidget* /*widget*/,
                                           GdkDragContext* /*context*/,
                                           GtkSelectionData* data, guint info,
                                           guint /*time*/,
                                           gpointer user_data) {
  auto* self = static_cast<SidePanelContentWindow*>(user_data);
  if (info == kDragText) {
    gtk_selection_data_set_text(data, self->drag_text_.c_str(),
                                static_cast<gint>(self->drag_text_.size()));
    return;
  }
  if (info != kDragImage || self->drag_png_.empty()) return;
  // gtk_selection_data_set_pixbuf converts to whichever image target the
  // drop site asked for (PNG, JPEG, BMP ...).
  GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
  if (gdk_pixbuf_loader_write(loader, self->drag_png_.data(),
                              self->drag_png_.size(), nullptr) &&
      gdk_pixbuf_loader_close(loader, nullptr)) {
    if (GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader)) {
      gtk_selection_data_set_pixbuf(data, pixbuf);
    }
  } else {
    gdk_pixbuf_loader_close(loader, nullptr);
  }
  g_object_unref(loader);
}

// ══════════════════════════════════════════════════════════════════════
// Hover tracking (native close-grace fallback)
// ══════════════════════════════════════════════════════════════════════

// static
gboolean SidePanelContentWindow::OnEnterNotify(GtkWidget* /*widget*/,
                                                GdkEventCrossing* event,
                                                gpointer user_data) {
  if (event->detail == GDK_NOTIFY_INFERIOR) return FALSE;
  auto* self = static_cast<SidePanelContentWindow*>(user_data);
  if (self->on_content_enter) self->on_content_enter();
  return FALSE;
}

// static
gboolean SidePanelContentWindow::OnLeaveNotify(GtkWidget* /*widget*/,
                                                GdkEventCrossing* event,
                                                gpointer user_data) {
  if (event->detail == GDK_NOTIFY_INFERIOR) return FALSE;
  auto* self = static_cast<SidePanelContentWindow*>(user_data);
  if (self->on_content_exit) self->on_content_exit();
  return FALSE;
}

// ══════════════════════════════════════════════════════════════════════
// Slide animation
// ══════════════════════════════════════════════════════════════════════

void SidePanelContentWindow::SlideIn(int staging_x, int shown_x, int y,
                                      int width, int height,
                                      int duration_ms) {
  if (!window_) return;

  anim_y_ = y;
  anim_w_ = width;
  anim_h_ = height;

  // Place instantly at the staging position, then show non-activated --
  // mirrors SidePanelContentWindow::SlideIn on Windows / SidePanelHost
  // .slideIn's setFrame(shown:false)/orderFront sequence on macOS.
  gtk_window_move(GTK_WINDOW(window_), staging_x, y);
  gtk_window_resize(GTK_WINDOW(window_), width, height);
  gtk_widget_set_size_request(window_, width, height);
  gtk_widget_show(window_);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  visible_ = true;

  StartAnimation(staging_x, shown_x, duration_ms, /*hide_on_done=*/false);
}

void SidePanelContentWindow::SlideOut(int staging_x, int duration_ms) {
  if (!window_ || !visible_) return;
  ReleaseHeldButton();
  gint current_x = 0, current_y = 0;
  gtk_window_get_position(GTK_WINDOW(window_), &current_x, &current_y);
  StartAnimation(current_x, staging_x, duration_ms, /*hide_on_done=*/true);
}

void SidePanelContentWindow::StartAnimation(int from_x, int to_x,
                                             int duration_ms,
                                             bool hide_on_done) {
  if (anim_timer_id_) {
    g_source_remove(anim_timer_id_);
    anim_timer_id_ = 0;
  }
  anim_from_x_ = from_x;
  anim_to_x_ = to_x;
  anim_duration_ms_ = std::max(duration_ms, 1);
  anim_hide_on_done_ = hide_on_done;
  anim_start_us_ = g_get_monotonic_time();
  anim_timer_id_ = g_timeout_add(kAnimIntervalMs, OnAnimationTick, this);
  // Paint the first frame immediately rather than waiting kAnimIntervalMs.
  StepAnimation();
}

// static
gboolean SidePanelContentWindow::OnAnimationTick(gpointer user_data) {
  auto* self = static_cast<SidePanelContentWindow*>(user_data);
  self->StepAnimation();
  // StepAnimation clears anim_timer_id_ to 0 once the animation completes;
  // a live id means "keep ticking".
  return self->anim_timer_id_ != 0 ? G_SOURCE_CONTINUE : G_SOURCE_REMOVE;
}

void SidePanelContentWindow::StepAnimation() {
  if (!window_) return;

  const gint64 elapsed_us = g_get_monotonic_time() - anim_start_us_;
  const double elapsed_ms = elapsed_us / 1000.0;
  double t = anim_duration_ms_ > 0 ? elapsed_ms / anim_duration_ms_ : 1.0;
  t = std::clamp(t, 0.0, 1.0);
  // Ease-out cubic -- matches CAMediaTimingFunction(.easeOut) / the Windows
  // port's eased curve closely enough for a 220ms slide.
  const double eased = 1.0 - std::pow(1.0 - t, 3.0);

  const int x = anim_from_x_ +
                static_cast<int>(std::round((anim_to_x_ - anim_from_x_) * eased));
  gtk_window_move(GTK_WINDOW(window_), x, anim_y_);

  if (t >= 1.0) {
    if (anim_timer_id_) {
      g_source_remove(anim_timer_id_);
      anim_timer_id_ = 0;
    }
    if (anim_hide_on_done_) {
      gtk_widget_hide(window_);
      visible_ = false;
    }
  }
}
