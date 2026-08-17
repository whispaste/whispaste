// Runner-owned MethodChannel bridge for the Snippet-Picker (visual-refresh-
// 2026 ticket 29). Structural precedent: floating_button_host.{h,cpp} (ADR
// 0002 Phase 2 — second-Flutter-engine shell). Protocol/behavioral
// precedent: macos/Runner/SnippetPickerHost.swift — same channel names, same
// method contract, so the Dart side (snippet_picker_controller_mixin.dart,
// snippet_picker_render_channel.dart) needs zero platform branching.
//
// Channel contract (shared with macOS — see
// snippet_picker_controller_interface.dart's cross-platform shell contract):
//   PUBLIC  "com.whispaste.snippet_picker"         show/hide/destroy in;
//                                                   onItemSelected/
//                                                   onCancelled/
//                                                   onRenderEngineDiagnostic
//                                                   out.
//   PRIVATE "com.whispaste.snippet_picker_render"  setItems/panelHidden to
//                                                   render; ready/selectItem/
//                                                   cancel/reportError from
//                                                   render.
//
// Panel size is fixed at 360×420 logical px (never content-measured — see
// the interface doc). Position is read natively (GetCursorPos), never
// passed from Dart, and clamped to the cursor's own monitor's work area —
// same rationale as SnippetPickerHost.swift's clampToVisibleScreen.
//
// Unlike the floating button/overlay hosts, this shell has no
// previousFrontApp save/restore: DesktopPasteHost::BringTargetToForeground()
// force-reactivates its own stored target HWND at paste time regardless of
// current foreground state, so nothing here needs to hand focus back for
// the paste path to work. (macOS needs this because its paste re-capture
// has a different invariant — see DesktopPasteHost.captureTarget() there.)
//
// Lifetime invariant: must be destroyed BEFORE the main engine tears down
// (managed by FlutterWindow::OnDestroy, same as the other second-engine
// hosts).

#ifndef SNIPPET_PICKER_HOST_H_
#define SNIPPET_PICKER_HOST_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "snippet_picker_window.h"

class SnippetPickerHost {
 public:
  // |main_engine| must outlive this object. |owner| is the main Flutter HWND
  // (used only as the CreateWindowEx-parity argument to SnippetPickerWindow;
  // see that class's Create() doc — no Win32 parent relationship results).
  SnippetPickerHost(flutter::FlutterEngine* main_engine, HWND owner);
  ~SnippetPickerHost();

  SnippetPickerHost(const SnippetPickerHost&) = delete;
  SnippetPickerHost& operator=(const SnippetPickerHost&) = delete;

  // Tear down native resources (shell + render engine). Safe to call
  // multiple times. Must be called before main engine teardown.
  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Called on first "show" — boots render engine + creates shell.
  // Returns false on failure (result->Error already called by caller).
  bool EnsureEngineAndShell();

  // Cursor-anchored, monitor-DPI-aware panel rect in physical pixels — see
  // SnippetPickerHost.swift's show()/clampToVisibleScreen for the algorithm
  // this mirrors (screen/monitor picked by the raw cursor point, not the
  // already-offset origin).
  void ComputePanelRect(int* px, int* py, int* pwidth, int* pheight) const;

  void Show(const std::vector<flutter::EncodableMap>& items);

  // Closes the panel. |fire_cancelled| reports the dismissal to the main
  // engine as onCancelled — false for a pick (already reported via
  // onItemSelected) or an explicit Dart-side hide(). Mirrors
  // SnippetPickerHost.swift's dismiss(fireCancelled:).
  void Dismiss(bool fire_cancelled);

  // Handle calls coming from the render engine.
  void HandleRenderCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void RelaySetItems(const std::vector<flutter::EncodableMap>& items);

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
  std::unique_ptr<SnippetPickerWindow> window_;

  // ── Boot-race handshake ──────────────────────────────────────────
  // Mirrors FloatingButtonHost's render_ready_/latest_state_ pattern: the
  // render engine's Dart handler is ready only a few message-loop ticks
  // after the controller is created, so a show() that races the boot caches
  // its items and flushes them from HandleRenderCall("ready").
  bool render_ready_ = false;
  bool has_pending_items_ = false;
  std::vector<flutter::EncodableMap> pending_items_;

  // ── Re-entrancy guard ─────────────────────────────────────────────
  // Mirrors SnippetPickerHost.swift's isDismissing — Dismiss() orders the
  // shell out and relays panelHidden before firing onCancelled; the shell's
  // own WM_ACTIVATE(WA_INACTIVE) callback (fired by that same order-out)
  // must not re-enter Dismiss().
  bool is_dismissing_ = false;
};

#endif  // SNIPPET_PICKER_HOST_H_
