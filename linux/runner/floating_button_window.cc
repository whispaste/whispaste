#include "floating_button_window.h"

#include <gdk/gdk.h>

#include "flutter/generated_plugin_registrant.h"

FloatingButtonWindow::FloatingButtonWindow() = default;

FloatingButtonWindow::~FloatingButtonWindow() {
  Destroy();
}

void FloatingButtonWindow::Create() {
  // ── GtkWindow shell ──────────────────────────────────────────────────────
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);

  // Decorationless: no title bar, no border.
  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);

  // Keep out of taskbar / pager / Alt-Tab.
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);

  // Always float above other windows.
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);

  // Never steal keyboard focus — the button is a pure HUD.
  gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE);

  // GDK_WINDOW_TYPE_HINT_NOTIFICATION is the most WM-friendly hint for
  // always-on-top HUDs on GNOME/XWayland (mirrors the overlay window).
  gtk_window_set_type_hint(GTK_WINDOW(window_),
                            GDK_WINDOW_TYPE_HINT_NOTIFICATION);

  // Default size: disc diameter (56) + 2 × shadow padding (8) = 72×72.
  const int default_side = kButtonDefaultDiameter + 2 * kButtonShadowPadding;
  gtk_window_set_default_size(GTK_WINDOW(window_), default_side, default_side);
  gtk_widget_set_size_request(window_, default_side, default_side);

  // ── RGBA / transparency ──────────────────────────────────────────────────
  gtk_widget_set_app_paintable(window_, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(window_);
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(window_, rgba_visual);
  }

  // ── Second Flutter engine (entrypoint arg: --floating-button) ────────────
  // The GTK embedder provides no named-entrypoint API. We pass the arg via
  // fl_dart_project_set_dart_entrypoint_arguments so Dart main() branches on
  // args.contains("--floating-button") → runFloatingButtonEngine().
  //
  // COMPILE RISK: fl_dart_project_set_dart_entrypoint_arguments expects
  // gchar** (non-const). We cast const away — safe because the embedder
  // copies the strings internally and does not mutate them.
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const gchar* button_args[] = {"--floating-button", nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(
      project, const_cast<gchar**>(button_args));

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

FlBinaryMessenger* FloatingButtonWindow::GetRenderMessenger() {
  if (!fl_view_) return nullptr;
  FlEngine* engine = fl_view_get_engine(fl_view_);
  if (!engine) return nullptr;
  return fl_engine_get_binary_messenger(engine);
}

void FloatingButtonWindow::SetDiameter(int diameter) {
  if (!window_) return;
  const int side = diameter + 2 * kButtonShadowPadding;
  gtk_window_resize(GTK_WINDOW(window_), side, side);
  gtk_widget_set_size_request(window_, side, side);
}

void FloatingButtonWindow::MoveTo(int x, int y) {
  if (!window_) return;
  // gtk_window_move is only reliable under X11/XWayland.
  // On native Wayland this is a no-op — see main.cc for GDK_BACKEND=x11.
  gtk_window_move(GTK_WINDOW(window_), x, y);
}

void FloatingButtonWindow::Show() {
  if (!window_) return;
  gtk_widget_show(window_);
  // Re-assert keep_above: some WMs reset this flag when a window becomes
  // visible. Re-applying after show keeps the button on top.
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
}

void FloatingButtonWindow::Hide() {
  if (!window_) return;
  gtk_widget_hide(window_);
}

void FloatingButtonWindow::Destroy() {
  if (window_) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
    fl_view_ = nullptr;  // Destroyed with window_.
  }
}

void FloatingButtonWindow::SetOnMoved(OnMovedCallback cb, void* user_data) {
  on_moved_cb_ = cb;
  on_moved_user_data_ = user_data;
}

// static
gboolean FloatingButtonWindow::OnConfigureEvent(GtkWidget* /*widget*/,
                                                  GdkEventConfigure* event,
                                                  gpointer user_data) {
  auto* self = static_cast<FloatingButtonWindow*>(user_data);
  if (self->on_moved_cb_) {
    self->on_moved_cb_(event->x, event->y, self->on_moved_user_data_);
  }
  return FALSE;  // Do not consume — let GTK propagate.
}
