#ifndef FLUTTER_WINDOW_DRAG_MOVER_H_
#define FLUTTER_WINDOW_DRAG_MOVER_H_

#include <gtk/gtk.h>

// Moves a window with the pointer while the left button stays down, without
// asking the window manager.
//
// The floating overlay and button are NOTIFICATION windows, so that they stay
// above other windows and never take focus. KWin treats that type as a
// special window that is not movable and ignores _NET_WM_MOVERESIZE, so
// gdk_window_begin_move_drag did nothing there (XP-5-10). A programmatic
// gtk_window_move is honoured by every X11 WM (setPosition relies on it), so
// the drag follows the pointer by polling it, which works no matter who holds
// the implicit pointer grab.
class WindowDragMover {
 public:
  // Called once when the button is released, with the window's final
  // top-left position. Not called when the window did not move.
  using OnEnded = void (*)(int x, int y, void* user_data);

  WindowDragMover(OnEnded on_ended, void* user_data);
  ~WindowDragMover();

  WindowDragMover(const WindowDragMover&) = delete;
  WindowDragMover& operator=(const WindowDragMover&) = delete;

  // Starts following the pointer. Returns false, and does nothing, if the
  // button is already up.
  bool Start(GtkWindow* window);

  // True between Start and the button release; configure-events of the
  // window are the mover's own moves then.
  bool IsActive() const { return timer_id_ != 0; }

 private:
  static gboolean OnTick(gpointer user_data);
  void Stop();

  OnEnded on_ended_;
  void* user_data_;
  GtkWindow* window_ = nullptr;
  guint timer_id_ = 0;
  int offset_x_ = 0, offset_y_ = 0;
  int start_x_ = 0, start_y_ = 0;
  int last_x_ = 0, last_y_ = 0;
};

#endif  // FLUTTER_WINDOW_DRAG_MOVER_H_
