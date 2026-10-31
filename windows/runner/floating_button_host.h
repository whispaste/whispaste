// Runner-owned MethodChannel bridge for the floating button (ADR 0002 Phase 2).
//
// Phase 2 change: this host no longer commands a GDI+ window — it boots a
// dedicated second Flutter engine (entrypoint "floatingButtonMain") and hosts
// its view HWND inside a thin WS_POPUP shell (FloatingButtonWindow).
//
// Channel contract (unchanged from Phase 1 — Dart side sees no difference):
//   PUBLIC  "com.whispaste.floating_button"
//   PRIVATE "com.whispaste.floating_button_render"  ← new, render engine only
//
// Lifetime invariant: must be destroyed BEFORE the main engine tears down
// (managed by FlutterWindow::OnDestroy, same as before).

#ifndef FLOATING_BUTTON_HOST_H_
#define FLOATING_BUTTON_HOST_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "floating_button_window.h"

class FloatingButtonHost {
 public:
  // |main_engine| must outlive this object. |owner| is the main Flutter HWND
  // (used for DPI lookups and as a non-owned reference for positioning).
  FloatingButtonHost(flutter::FlutterEngine* main_engine, HWND owner);
  ~FloatingButtonHost();

  FloatingButtonHost(const FloatingButtonHost&) = delete;
  FloatingButtonHost& operator=(const FloatingButtonHost&) = delete;

  // Tear down native resources (shell + render engine). Safe to call multiple
  // times. Must be called before main engine teardown.
  void Destroy();

  // Re-asserts HWND_TOPMOST. Called from FlutterWindow::MessageHandler on
  // WM_SIZE(minimize) and WM_ACTIVATEAPP.
  void RefreshTopmost();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Called on first "show" — boots render engine + creates shell.
  // Returns false on failure (result->Error already called by caller).
  bool EnsureEngineAndShell(double lx, double ly, int disc_size);

  // Relay helpers → render engine
  void RelaySetState(const std::string& state);
  void RelaySetDiameter(int disc_size);
  void RelaySetTheme(bool is_dark);

  // Handle calls coming from the render engine.
  void HandleRenderCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Begin OS-managed window drag (NCLBUTTONDOWN / HTCAPTION trick).
  // Dart fires "startDrag" on pan-start; we let the OS move the shell and
  // report the final position as "onDragEnded".
  void BeginDrag();

  // Build and show a native TrackPopupMenu from context_menu_items_.
  void ShowNativeContextMenu();

  // Fire-and-forget event to the main Dart engine (safe if no listener).
  void SendEvent(const std::string& method,
                 const flutter::EncodableValue& args);
  void SendEvent(const std::string& method);

  // ── Main-engine side ─────────────────────────────────────────────
  flutter::FlutterEngine* main_engine_;  // Not owned
  HWND owner_;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // ── Render-engine side (lazy-created on first show) ──────────────
  std::unique_ptr<flutter::DartProject> render_project_;
  std::unique_ptr<flutter::FlutterViewController> render_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      render_channel_;

  // ── Shell window ─────────────────────────────────────────────────
  std::unique_ptr<FloatingButtonWindow> window_;

  // ── Boot-race handshake ──────────────────────────────────────────
  // The render engine's Dart handler is ready only a few message-loop ticks
  // after the controller is created. Until the engine sends "ready" we cache
  // the latest state/diameter and flush them in HandleRenderCall("ready").
  bool render_ready_ = false;
  std::string latest_state_ = "idle";
  int latest_disc_size_ = 56;  // logical pixels (without shadow padding)

  // ── Context menu items ────────────────────────────────────────────
  std::vector<std::pair<std::string, std::wstring>> context_menu_items_;
};

#endif  // FLOATING_BUTTON_HOST_H_
