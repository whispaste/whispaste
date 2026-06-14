#ifndef FLUTTER_FLOATING_OVERLAY_WINDOW_H_
#define FLUTTER_FLOATING_OVERLAY_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Window dimensions that mirror OverlayDesignSpec.windowSize in Dart.
// Normal: 346×80 / Compact: 236×56  (same values as macOS/Windows).
constexpr int kOverlayNormalW = 346;
constexpr int kOverlayNormalH = 80;
constexpr int kOverlayCompactW = 236;
constexpr int kOverlayCompactH = 56;

// Lifecycle-only decorationless GtkWindow that hosts the second Flutter engine
// for the floating overlay (ADR 0002 phase 2, Linux).
//
// The GTK embedder exposes no named-entrypoint API, so we boot the second
// engine by passing "--floating-overlay" as a Dart entrypoint argument via
// fl_dart_project_set_dart_entrypoint_arguments. Dart main() branches on that
// arg and calls runFloatingOverlayEngine() instead of the full app bootstrap.
//
// Transparency requires a compositor (GNOME+XWayland always provides one).
// Always-on-top and absolute positioning require X11/XWayland; see main.cc
// for the GDK_BACKEND=x11 forcing that makes this reliable on GNOME/Mutter.
class FloatingOverlayWindow {
 public:
  FloatingOverlayWindow();
  ~FloatingOverlayWindow();

  // Non-copyable / non-movable — owns a GtkWidget* and a raw engine pointer.
  FloatingOverlayWindow(const FloatingOverlayWindow&) = delete;
  FloatingOverlayWindow& operator=(const FloatingOverlayWindow&) = delete;

  // Creates the GtkWindow, boots the 2nd Flutter engine, realizes the shell.
  // Must be called before any other method. Call at most once.
  void Create();

  // Returns the binary messenger of the 2nd engine so the host can open the
  // private render channel (com.whispaste.floating_overlay_render).
  // Returns nullptr before Create() or after Destroy().
  //
  // COMPILE RISK: fl_view_get_engine / fl_engine_get_binary_messenger are
  // present in flutter_linux >= 3.3. Older SDK builds may need a version guard.
  FlBinaryMessenger* GetRenderMessenger();

  // Resize the shell between normal (346×80) and compact (236×56) mode.
  void SetCompact(bool compact);

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
  // gdk_window_begin_move_drag for interactive window moves). May be nullptr
  // before Create() or after Destroy().
  GtkWidget* GetGtkWindow() const { return window_; }

  // Callback fired from the configure-event signal whenever the window's
  // position or size changes (user drag or programmatic move).
  // x, y are root-window coordinates of the window's top-left corner.
  // TUNING NOTE: this fires for both user drags and programmatic moves; the
  // host uses a suppress flag to filter out the latter (see floating_overlay_host.cc).
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

#endif  // FLUTTER_FLOATING_OVERLAY_WINDOW_H_
