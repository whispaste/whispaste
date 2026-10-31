#ifndef FLUTTER_FLOATING_BUTTON_WINDOW_H_
#define FLUTTER_FLOATING_BUTTON_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Shadow padding added on each side of the button disc so the painter's shadow
// does not clip at the window edge. The GTK window is always
// (diameter + 2*kButtonShadowPadding) square.
constexpr int kButtonShadowPadding = 8;

// Default button diameter in logical pixels — matches FloatingButtonView and
// the Windows/macOS shells.
constexpr int kButtonDefaultDiameter = 56;

// Lifecycle-only decorationless GtkWindow that hosts the second Flutter engine
// for the floating button (ADR 0002 phase 2, Linux).
//
// Mirrors FloatingOverlayWindow exactly: same GTK setup (decorationless, RGBA
// visual, keep_above, skip_taskbar, accept_focus=FALSE), same second-engine
// bootstrap via fl_dart_project_set_dart_entrypoint_arguments with arg
// "--floating-button". The Dart main() branches on that arg and calls
// runFloatingButtonEngine() instead of the full app bootstrap.
//
// Window size is always (diameter + 2*kButtonShadowPadding) square. Call
// SetDiameter() to resize as the Dart side changes the button size.
class FloatingButtonWindow {
 public:
  FloatingButtonWindow();
  ~FloatingButtonWindow();

  // Non-copyable / non-movable — owns a GtkWidget* and a raw engine pointer.
  FloatingButtonWindow(const FloatingButtonWindow&) = delete;
  FloatingButtonWindow& operator=(const FloatingButtonWindow&) = delete;

  // Creates the GtkWindow, boots the 2nd Flutter engine, realizes the shell.
  // Must be called before any other method. Call at most once.
  void Create();

  // Returns the binary messenger of the 2nd engine so the host can open the
  // private render channel (com.whispaste.floating_button_render).
  // Returns nullptr before Create() or after Destroy().
  FlBinaryMessenger* GetRenderMessenger();

  // Resize the shell to (diameter + 2*kButtonShadowPadding) square.
  void SetDiameter(int diameter);

  // Move the shell to absolute screen coordinates (X11 root, top-left origin).
  // gtk_window_move is reliable only when GDK_BACKEND=x11 is in effect.
  void MoveTo(int x, int y);

  // Show the shell window (gtk_widget_show + re-assert keep_above).
  void Show();

  // Hide the shell window (gtk_widget_hide).
  void Hide();

  // Tear down the GtkWindow and all its children (including the engine).
  void Destroy();

  bool IsCreated() const { return window_ != nullptr; }

  // Returns the underlying GtkWidget* so the host can call GDK APIs (e.g.
  // gdk_window_begin_move_drag for interactive window moves).
  GtkWidget* GetGtkWindow() const { return window_; }

  // Callback fired from the configure-event signal whenever the window's
  // position or size changes (user drag or programmatic move).
  // x, y are root-window coordinates of the window's top-left corner.
  using OnMovedCallback = void (*)(int x, int y, void* user_data);
  void SetOnMoved(OnMovedCallback cb, void* user_data);

 private:
  GtkWidget* window_ = nullptr;
  FlView* fl_view_ = nullptr;  // Non-owning; container holds the ref.

  OnMovedCallback on_moved_cb_ = nullptr;
  void* on_moved_user_data_ = nullptr;

  static gboolean OnConfigureEvent(GtkWidget* widget,
                                    GdkEventConfigure* event,
                                    gpointer user_data);
};

#endif  // FLUTTER_FLOATING_BUTTON_WINDOW_H_
