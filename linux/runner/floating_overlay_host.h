#ifndef FLUTTER_FLOATING_OVERLAY_HOST_H_
#define FLUTTER_FLOATING_OVERLAY_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <string>
#include <utility>
#include <vector>

#include "floating_overlay_window.h"

// Owns the public MethodChannel com.whispaste.floating_overlay on the MAIN
// engine and bridges it to the private render channel on the second engine
// (com.whispaste.floating_overlay_render).
//
// Architecture mirrors FloatingOverlayHost.swift (macOS):
//
//   main engine  ←→  FloatingOverlayHost  ←→  FloatingOverlayWindow
//        ↕               (relay / translate)        ↕
//  public channel                           render channel (2nd engine)
//
// Lifecycle:
//   - Created in my_application_activate() once the main FlView is live.
//   - Overlay window is created lazily on the first updateSnapshot(visible:true).
//   - Destroyed (via delete) in my_application_dispose().
class FloatingOverlayHost {
 public:
  explicit FloatingOverlayHost(FlBinaryMessenger* main_messenger);
  ~FloatingOverlayHost();

  // Non-copyable.
  FloatingOverlayHost(const FloatingOverlayHost&) = delete;
  FloatingOverlayHost& operator=(const FloatingOverlayHost&) = delete;

 private:
  // ── Public channel (main engine) ─────────────────────────────────────────
  FlMethodChannel* channel_ = nullptr;

  static void OnMethodCall(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data);
  void HandleMethodCall(FlMethodCall* method_call);

  // ── Overlay window + render channel (2nd engine) ─────────────────────────
  FloatingOverlayWindow* overlay_window_ = nullptr;
  FlMethodChannel* render_channel_ = nullptr;

  // Boot-race cache: the 2nd engine's Dart handler is not live until "ready"
  // fires. We cache the last snapshot and bars here and flush on ready —
  // matching the macOS renderReady/latestSnapshotArgs/latestBars pattern.
  bool render_ready_ = false;
  FlValue* latest_snapshot_args_ = nullptr;  // Retained; unref'd in dtor.
  FlValue* latest_bars_args_ = nullptr;      // Retained; unref'd in dtor.

  void EnsureOverlayWindow();
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
    FloatingOverlayHost* host;
    std::string id;
  };
  static void OnMenuItemActivated(GtkMenuItem* item, gpointer user_data);

  // ── Drag / position state ─────────────────────────────────────────────────
  std::string pending_anchor_mode_ = "topCenter";
  // Suppress configure-event → onDragEnded relay during programmatic moves.
  // Set to true just before gtk_window_move (via MoveTo), cleared by the
  // configure-event handler on its next invocation.
  bool suppress_next_configure_ = false;

  static void OnWindowMoved(int x, int y, void* user_data);

  // ── Compact / position cache ──────────────────────────────────────────────
  bool is_compact_ = false;
  // Pending position applied when the window is first created.
  bool has_pending_position_ = false;
  int pending_x_ = 0;
  int pending_y_ = 0;

  // ── Anchor → screen coordinate resolution ────────────────────────────────
  //
  // Mirrors FloatingOverlayHost.swift resolvePosition():
  //   topCenter    → centered horizontally, 16px from top of work area
  //   bottomCenter → centered horizontally, 16px from bottom of work area
  //   topLeft      → raw x, y
  std::pair<int, int> ResolvePosition(double x, double y,
                                       const std::string& anchor_mode);

  // ── Helpers ───────────────────────────────────────────────────────────────
  // Fire-and-forget invoke on the main engine channel.
  void InvokeMainChannel(const char* method, FlValue* args);
  // Fire-and-forget invoke on the render channel (no-op if not ready/created).
  void InvokeRenderChannel(const char* method, FlValue* args);

  // Async result handler used for all fire-and-forget channel invocations.
  static void OnInvokeDone(GObject* source, GAsyncResult* result,
                            gpointer user_data);
};

#endif  // FLUTTER_FLOATING_OVERLAY_HOST_H_
