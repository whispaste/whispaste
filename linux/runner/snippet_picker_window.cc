#include "snippet_picker_window.h"

#include <gdk/gdk.h>

#include "flutter/generated_plugin_registrant.h"

SnippetPickerWindow::SnippetPickerWindow() = default;

SnippetPickerWindow::~SnippetPickerWindow() {
  Destroy();
}

void SnippetPickerWindow::Create() {
  // ── GtkWindow shell ──────────────────────────────────────────────────────
  window_ = gtk_window_new(GTK_WINDOW_TOPLEVEL);

  gtk_window_set_decorated(GTK_WINDOW(window_), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window_), TRUE);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);

  // Unlike the floating button/overlay: this window DOES want keyboard
  // focus (the search field must be usable without a manual click) and
  // uses UTILITY rather than NOTIFICATION — UTILITY windows stay in the
  // WM's normal focus-managed stack, which is what makes focus-return on
  // hide work at all (see the class comment).
  gtk_window_set_accept_focus(GTK_WINDOW(window_), TRUE);
  gtk_window_set_type_hint(GTK_WINDOW(window_), GDK_WINDOW_TYPE_HINT_UTILITY);

  gtk_window_set_default_size(GTK_WINDOW(window_), kSnippetPickerWidth,
                              kSnippetPickerHeight);
  gtk_widget_set_size_request(window_, kSnippetPickerWidth,
                              kSnippetPickerHeight);

  // ── RGBA / transparency ──────────────────────────────────────────────────
  gtk_widget_set_app_paintable(window_, TRUE);
  GdkScreen* screen = gtk_widget_get_screen(window_);
  GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
  if (rgba_visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(window_, rgba_visual);
  }

  // ── Second Flutter engine (entrypoint arg: --snippet-picker) ─────────────
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  const gchar* picker_args[] = {"--snippet-picker", nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(
      project, const_cast<gchar**>(picker_args));

  FlView* view = fl_view_new(project);
  fl_view_ = view;  // Non-owning; container holds the strong ref.

  GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(fl_view_, &transparent);

  gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(fl_view_));

  fl_register_plugins(FL_PLUGIN_REGISTRY(fl_view_));

  gtk_widget_show(GTK_WIDGET(fl_view_));

  // focus-out-event fires when the WM activates a different window while
  // this one is visible — the click-outside-to-cancel signal.
  g_signal_connect(window_, "focus-out-event", G_CALLBACK(OnFocusOutEvent),
                   this);

  // Realize (not show) so the engine starts booting immediately, while the
  // window itself stays off-screen until Show() is called.
  gtk_widget_realize(window_);
}

FlBinaryMessenger* SnippetPickerWindow::GetRenderMessenger() {
  if (!fl_view_) return nullptr;
  FlEngine* engine = fl_view_get_engine(fl_view_);
  if (!engine) return nullptr;
  return fl_engine_get_binary_messenger(engine);
}

void SnippetPickerWindow::MoveTo(int x, int y) {
  if (!window_) return;
  gtk_window_move(GTK_WINDOW(window_), x, y);
}

void SnippetPickerWindow::Show() {
  if (!window_) return;
  gtk_widget_show(window_);
  gtk_window_set_keep_above(GTK_WINDOW(window_), TRUE);
  // gtk_window_present (rather than plain show) asks the WM to activate —
  // i.e. actually give this window input focus, not just map it on top.
  gtk_window_present(GTK_WINDOW(window_));
}

void SnippetPickerWindow::Hide() {
  if (!window_) return;
  gtk_widget_hide(window_);
}

void SnippetPickerWindow::Destroy() {
  if (window_) {
    gtk_widget_destroy(window_);
    window_ = nullptr;
    fl_view_ = nullptr;
  }
}

void SnippetPickerWindow::SetOnFocusLost(OnFocusLostCallback cb,
                                         void* user_data) {
  on_focus_lost_cb_ = cb;
  on_focus_lost_user_data_ = user_data;
}

// static
gboolean SnippetPickerWindow::OnFocusOutEvent(GtkWidget* /*widget*/,
                                              GdkEventFocus* /*event*/,
                                              gpointer user_data) {
  auto* self = static_cast<SnippetPickerWindow*>(user_data);
  if (self->on_focus_lost_cb_) {
    self->on_focus_lost_cb_(self->on_focus_lost_user_data_);
  }
  return FALSE;  // Do not consume — let GTK propagate.
}
