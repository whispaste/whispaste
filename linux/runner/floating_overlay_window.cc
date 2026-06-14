#include "floating_overlay_window.h"

#include <gdk/gdk.h>

#include "flutter/generated_plugin_registrant.h"

FloatingOverlayWindow::FloatingOverlayWindow() = default;

FloatingOverlayWindow::~FloatingOverlayWindow() {
  Destroy();
}

void FloatingOverlayWindow::Create() {
  // ── GtkWindow shell ──────────────────────────────────────────────────────
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);

  // Decorationless: no title bar, no border.
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);

  // Keep out of taskbar / pager / Alt-Tab.
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);

  // Always float above other windows.
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);

  // Never steal keyboard focus — the overlay is a pure HUD.
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);

  // TUNING: GDK_WINDOW_TYPE_HINT_NOTIFICATION is the most WM-friendly hint
  // for always-on-top HUDs on GNOME/XWayland. Alternatives if Mutter resets
  // keep_above: GDK_WINDOW_TYPE_HINT_DOCK or GDK_WINDOW_TYPE_HINT_UTILITY.
  gtk_window_set_type_hint(GTK_WINDOW(window_),
                            GDK_WINDOW_TYPE_HINT_NOTIFICATION);

  // Start at normal size; SetCompact() resizes later.
  gtk_window_set_default_size(GTK_WINDOW(window_), kOverlayNormalW,
                               kOverlayNormalH);
  gtk_widget_set_size_request(window_, kOverlayNormalW, kOverlayNormalH);

  // ── RGBA / transparency ──────────────────────────────────────────────────
  // Paint onto a clear surface so the Flutter painter's transparent regions
  // show through to the desktop. Only possible when a compositor is active;
  // GNOME+XWayland always provides one, so this should succeed in practice.
  gtk_widget_set_app_paintable(window_, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(window_);
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(window_, rgba_visual);
  }
  // TUNING: if transparency is broken (white/black background visible), check:
  // 1. Is a compositor running? (picom, mutter, kwin)
  // 2. Is gtk_widget_set_visual applied before gtk_widget_realize?
  // 3. Does fl_view_set_background_color get the RGBA surface? (see below)

  // ── Second Flutter engine (entrypoint arg: --floating-overlay) ───────────
  // The GTK embedder provides no named-entrypoint API. We pass the arg via
  // fl_dart_project_set_dart_entrypoint_arguments so Dart main() branches on
  // args.contains("--floating-overlay") → runFloatingOverlayEngine().
  //
  // COMPILE RISK: fl_dart_project_set_dart_entrypoint_arguments expects
  // gchar** (non-const). We cast const away — safe because the embedder
  // copies the strings internally and does not mutate them.
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const gchar* overlay_args[] = {"--floating-overlay", nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(
      project, const_cast<gchar**>(overlay_args));

  // fl_view_new takes its own strong ref to project; g_autoptr releases ours.
  FlView* view = fl_view_new(project);
  fl_view_ = view;  // Non-owning; container holds the strong ref.

  // Transparent Flutter surface: the Dart painter composites over clear pixels.
  GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(fl_view_, &transparent);

  // Add to container — GTK takes a strong ref; view ref from fl_view_new is
  // now "owned" by the container.
  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(fl_view_));

  // Register plugins BEFORE showing so platform channels are ready at boot.
  // The overlay engine uses only the render MethodChannel, but registering all
  // plugins is harmless and mirrors the main-engine setup.
  fl_register_plugins(FL_PLUGIN_REGISTRY(fl_view_));

  gtk_widget_show(GTK_WIDGET(fl_view_));

  // ── Position-change tracking ─────────────────────────────────────────────
  // configure-event fires after every WM-acknowledged position or size change.
  // The host uses this to detect the end of a user drag.
  g_signal_connect(window_, "configure-event",
                   G_CALLBACK(OnConfigureEvent), this);

  // Realize the window (create the GdkWindow) so the engine starts booting.
  // We do NOT call gtk_widget_show(window_) here — that is deferred to Show()
  // so the window stays off-screen until the host decides to display it.
  gtk_widget_realize(window_);
}

FlBinaryMessenger* FloatingOverlayWindow::GetRenderMessenger() {
  if (!fl_view_) return nullptr;
  FlEngine* engine = fl_view_get_engine(fl_view_);
  if (!engine) return nullptr;
  return fl_engine_get_binary_messenger(engine);
}

void FloatingOverlayWindow::SetCompact(bool compact) {
  if (!window_) return;
  int w = compact ? kOverlayCompactW : kOverlayNormalW;
  int h = compact ? kOverlayCompactH : kOverlayNormalH;
  gtk_window_resize(GTK_WINDOW(window_), w, h);
  gtk_widget_set_size_request(window_, w, h);
}

void FloatingOverlayWindow::MoveTo(int x, int y) {
  if (!window_) return;
  // gtk_window_move is only reliable under X11/XWayland.
  // On native Wayland this is a no-op — see main.cc for GDK_BACKEND=x11.
  gtk_window_move(GTK_WINDOW(window_), x, y);
}

void FloatingOverlayWindow::Show() {
  if (!window_) return;
  gtk_widget_show(window_);
  // Re-assert keep_above: some WMs (and Mutter via XWayland) reset this flag
  // when a window becomes visible. Re-applying after show keeps the HUD on top.
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
}

void FloatingOverlayWindow::Hide() {
  if (!window_) return;
  gtk_widget_hide(window_);
}

void FloatingOverlayWindow::Destroy() {
  if (window_) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
    fl_view_ = nullptr;  // Destroyed with window_.
  }
}

void FloatingOverlayWindow::SetOnMoved(OnMovedCallback cb, void* user_data) {
  on_moved_cb_ = cb;
  on_moved_user_data_ = user_data;
}

// static
gboolean FloatingOverlayWindow::OnConfigureEvent(GtkWidget* /*widget*/,
                                                   GdkEventConfigure* event,
                                                   gpointer user_data) {
  auto* self = static_cast<FloatingOverlayWindow*>(user_data);
  if (self->on_moved_cb_) {
    self->on_moved_cb_(event->x, event->y, self->on_moved_user_data_);
  }
  return FALSE;  // Do not consume — let GTK propagate.
}
