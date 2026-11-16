#include "window_drag_mover.h"

namespace {

// ~60 Hz: smooth enough to follow the pointer, cheap enough to not matter.
constexpr guint kTickMs = 16;

// Root-window pointer position and whether the left button is down.
bool QueryPointer(int* x, int* y) {
  GdkDisplay* display = gdk_display_get_default();
  GdkDevice* pointer =
      gdk_seat_get_pointer(gdk_display_get_default_seat(display));
  GdkModifierType mask = static_cast<GdkModifierType>(0);
  gdk_device_get_state(pointer, gdk_get_default_root_window(), nullptr,
                       &mask);
  gdk_device_get_position(pointer, nullptr, x, y);
  return (mask & GDK_BUTTON1_MASK) != 0;
}

}  // namespace

WindowDragMover::WindowDragMover(OnEnded on_ended, void* user_data)
    : on_ended_(on_ended), user_data_(user_data) {}

WindowDragMover::~WindowDragMover() { Stop(); }

bool WindowDragMover::Start(GtkWindow* window) {
  Stop();
  int px = 0, py = 0;
  // A pan gesture reaches the native side one channel round-trip late; a
  // very short flick may already be over.
  if (!window || !QueryPointer(&px, &py)) return false;

  window_ = window;
  gtk_window_get_position(window_, &start_x_, &start_y_);
  last_x_ = start_x_;
  last_y_ = start_y_;
  offset_x_ = px - start_x_;
  offset_y_ = py - start_y_;
  timer_id_ = g_timeout_add(kTickMs, OnTick, this);
  return true;
}

// static
gboolean WindowDragMover::OnTick(gpointer user_data) {
  auto* self = static_cast<WindowDragMover*>(user_data);
  int px = 0, py = 0;
  const bool held = QueryPointer(&px, &py);
  const int x = px - self->offset_x_;
  const int y = py - self->offset_y_;
  if (held && (x != self->last_x_ || y != self->last_y_)) {
    gtk_window_move(self->window_, x, y);
    self->last_x_ = x;
    self->last_y_ = y;
  }
  if (held) return G_SOURCE_CONTINUE;

  // Returning G_SOURCE_REMOVE drops the source; only clear the id.
  self->timer_id_ = 0;
  const bool moved =
      self->last_x_ != self->start_x_ || self->last_y_ != self->start_y_;
  self->window_ = nullptr;
  if (moved && self->on_ended_) {
    self->on_ended_(self->last_x_, self->last_y_, self->user_data_);
  }
  return G_SOURCE_REMOVE;
}

void WindowDragMover::Stop() {
  if (timer_id_ != 0) {
    g_source_remove(timer_id_);
    timer_id_ = 0;
  }
  window_ = nullptr;
}
