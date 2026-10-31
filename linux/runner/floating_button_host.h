#ifndef FLUTTER_FLOATING_BUTTON_HOST_H_
#define FLUTTER_FLOATING_BUTTON_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>
#include <vector>

#include "floating_button_window.h"

// Owns the public MethodChannel com.whispaste.floating_button on the MAIN
// engine and bridges it to the private render channel on the second engine
// (com.whispaste.floating_button_render).
//
// Architecture mirrors FloatingButtonHost.swift (macOS) and FloatingOverlayHost
// (Linux):
//
//   main engine  ←→  FloatingButtonHost  ←→  FloatingButtonWindow
//        ↕              (relay / translate)        ↕
//  public channel                          render channel (2nd engine)
//
// Lifecycle:
//   - Created in my_application_activate() once the main FlView is live.
//   - Button window is created lazily on the first show() call.
//   - Destroyed (via delete) in my_application_dispose().
class FloatingButtonHost {
 public:
  explicit FloatingButtonHost(FlBinaryMessenger* main_messenger);
  ~FloatingButtonHost();

  // Non-copyable.
  FloatingButtonHost(const FloatingButtonHost&) = delete;
  FloatingButtonHost& operator=(const FloatingButtonHost&) = delete;

 private:
  // ── Public channel (main engine) ─────────────────────────────────────────
  FlMethodChannel* channel_ = nullptr;

  static void OnMethodCall(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data);
  void HandleMethodCall(FlMethodCall* method_call);

  // ── Button window + render channel (2nd engine) ───────────────────────────
  FloatingButtonWindow* button_window_ = nullptr;
  FlMethodChannel* render_channel_ = nullptr;

  // Boot-race cache: the 2nd engine's Dart handler is not live until "ready"
  // fires. Cache the last state and diameter here and flush on ready —
  // matching the macOS renderReady/latestSnapshotArgs pattern.
  bool render_ready_ = false;
  std::string pending_state_ = "idle";
  int pending_diameter_ = kButtonDefaultDiameter;

  void EnsureButtonWindow();
  void OpenRenderChannel();

  // ── Render channel (2nd engine → host) ───────────────────────────────────
  static void OnRenderMethodCall(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data);
  void HandleRenderMethodCall(FlMethodCall* method_call);

  // ── Context menu ─────────────────────────────────────────────────────────
  struct MenuItem {
    std::string id;
    std::string label;
  };
  std::vector<MenuItem> context_menu_items_;
  void ShowContextMenu();

  struct MenuItemCallbackData {
    FloatingButtonHost* host;
    std::string id;
  };
  static void OnMenuItemActivated(GtkMenuItem* item, gpointer user_data);

  // ── Drag / position state ─────────────────────────────────────────────────
  // Suppress configure-event → onDragEnded relay during programmatic moves.
  // Set to true just before gtk_window_move (via MoveTo), cleared by the
  // configure-event handler on its next invocation.
  bool suppress_next_configure_ = false;

  // Last known window position (updated on configure-event and programmatic
  // moves). Used to answer getPosition() without a GTK round-trip when the
  // window has not been created yet.
  int current_x_ = 200;
  int current_y_ = 200;

  // Pending position/size applied when the window is first created.
  bool has_pending_position_ = false;
  int pending_x_ = 200;
  int pending_y_ = 200;

  static void OnWindowMoved(int x, int y, void* user_data);

  // ── Helpers ───────────────────────────────────────────────────────────────
  // Fire-and-forget invoke on the main engine channel.
  void InvokeMainChannel(const char* method, FlValue* args);
  // Fire-and-forget invoke on the render channel (no-op if not ready/created).
  void InvokeRenderChannel(const char* method, FlValue* args);

  // Async result handler used for all fire-and-forget channel invocations.
  static void OnInvokeDone(GObject* source, GAsyncResult* result,
                            gpointer user_data);
};

#endif  // FLUTTER_FLOATING_BUTTON_HOST_H_
