// Runner-owned MethodChannel bridge for the floating overlay (ADR 0002 Phase 2).
//
// Migration from GDI+/DirectWrite drawing (Phase 1) to second Flutter engine
// (Phase 2). Mirrors the already-shipped macOS FloatingOverlayHost.swift
// (commit 13fce43f) and structurally mirrors FloatingButtonHost (the canonical
// Windows template for this pattern).
//
// Architecture:
//   Main engine  ──[com.whispaste.floating_overlay]──▶ FloatingOverlayHost
//                ◀─[onDragEnded / onBodyClicked / onContextMenu / ...]───
//
//   FloatingOverlayHost ──[com.whispaste.floating_overlay_render]──▶ Dart
//                        ◀─[startDrag / bodyClicked / showContextMenu / ready]─
//
// Public channel contract (com.whispaste.floating_overlay) — UNCHANGED:
//   Inbound (Dart → host):
//     updateSnapshot{visible,state,isDark,compact,label,elapsed,...}
//     setWaveformBars{bars:List<double>}
//     setPosition{x,y,anchorMode}
//     setContextMenuItems{items:[{id,label}]}   ← BUG FIX: unwrap "items" key
//     setOpacity{opacity}                       ← accepted as no-op (issue 11)
//     destroy
//   Outbound (host → Dart):
//     onDragEnded{x,y,anchorMode}
//     onCloseClicked   (defined; unused by shared view — may fire in future)
//     onBodyClicked
//     onRetryClicked   (defined; unused by shared view — may fire in future)
//     onContextMenu{action}
//
// Plugin registration decision:
//   The render engine (floatingOverlayMain) uses only the private render
//   MethodChannel and no Flutter plugins. RegisterPlugins() is skipped to
//   avoid re-registering singletons already alive on the main engine.
//   (Same rationale as FloatingButtonHost — see its file-level comment.)
//
// Anchor-mode position resolution (mirrors macOS resolvePosition):
//   topCenter    — horizontally centred, 16 logical px from top of work area
//   bottomCenter — horizontally centred, 16 logical px from bottom of work area
//   topLeft      — raw logical top-left (custom drag position)
//
// Window sizing (mirrors OverlayDesignSpec.windowSize in Dart):
//   Normal:  346 × 80 logical px   (pill + 8 px shadow padding each side)
//   Compact: 236 × 56 logical px
//
// Lifetime invariant: must be destroyed BEFORE the main engine tears down
// (managed by FlutterWindow::OnDestroy, same as before).

#ifndef FLOATING_OVERLAY_HOST_H_
#define FLOATING_OVERLAY_HOST_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "floating_overlay_window.h"

class FloatingOverlayHost {
 public:
  // |main_engine| must outlive this object. |owner| is the main Flutter HWND
  // (used for DPI lookups and as a non-owned reference for positioning).
  FloatingOverlayHost(flutter::FlutterEngine* main_engine, HWND owner);
  ~FloatingOverlayHost();

  FloatingOverlayHost(const FloatingOverlayHost&) = delete;
  FloatingOverlayHost& operator=(const FloatingOverlayHost&) = delete;

  // Tear down native resources (shell + render engine). Safe to call multiple
  // times. Must be called before main engine teardown.
  void Destroy();

  // Re-asserts HWND_TOPMOST. Called from FlutterWindow::MessageHandler on
  // WM_SIZE(minimize) and WM_ACTIVATEAPP.
  void RefreshTopmost();

 private:
  // ── Channel handlers ──────────────────────────────────────────────────
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleRenderCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ── Engine / shell lifecycle ──────────────────────────────────────────
  // Called on first updateSnapshot with visible:true. Returns false on failure.
  bool EnsureEngineAndShell(bool compact);

  // Resize the shell (and re-anchor) on a compact ↔ normal switch.
  void ResizeShell(bool compact);

  // Compute the logical top-left of the shell from the current anchor mode.
  // Returns {logical_x, logical_y} using the main window's monitor.
  std::pair<double, double> ResolveAnchorPosition() const;

  // ── Render channel relay helpers ──────────────────────────────────────
  // Relay the cached snapshot to the render engine.
  void RelaySnapshot();
  // Relay the cached waveform bars to the render engine.
  void RelayBars();

  // ── Interactions (render engine → native → main engine) ──────────────
  // OS-managed window move via NCLBUTTONDOWN/HTCAPTION trick.
  void BeginDrag();
  // Build and show a native TrackPopupMenu from context_menu_items_.
  void ShowNativeContextMenu();

  // ── Fire-and-forget event to the main Dart engine ─────────────────────
  void SendEvent(const std::string& method,
                 const flutter::EncodableValue& args);
  void SendEvent(const std::string& method);

  // ── Main-engine side ──────────────────────────────────────────────────
  flutter::FlutterEngine* main_engine_;  // Not owned
  HWND owner_;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // ── Render-engine side (lazy-created on first visible updateSnapshot) ──
  std::unique_ptr<flutter::DartProject> render_project_;
  std::unique_ptr<flutter::FlutterViewController> render_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      render_channel_;

  // ── Shell window ──────────────────────────────────────────────────────
  std::unique_ptr<FloatingOverlayWindow> window_;

  // ── Boot-race handshake ───────────────────────────────────────────────
  // The render engine's Dart handler is ready only a few message-loop ticks
  // after the controller is created. Until the engine sends "ready" we cache
  // the latest relay payloads and flush them in HandleRenderCall("ready").
  // Flush order: setWaveformBars first, then updateSnapshot (mirrors macOS).
  bool render_ready_ = false;
  std::optional<flutter::EncodableValue> latest_snapshot_args_;
  std::optional<flutter::EncodableValue> latest_bars_args_;

  // ── Overlay state ─────────────────────────────────────────────────────
  bool is_compact_ = false;

  // Anchor mode: "topCenter" | "bottomCenter" | "topLeft".
  // "topLeft" = raw drag position; others = monitor-relative calculation.
  std::string anchor_mode_ = "topCenter";

  // Logical top-left (only meaningful in "topLeft" anchor mode; for
  // topCenter/bottomCenter the position is recomputed from the monitor).
  double anchor_x_ = 0.0;
  double anchor_y_ = 0.0;

  // ── Context menu items (id, wide-string label) ────────────────────────
  std::vector<std::pair<std::string, std::wstring>> context_menu_items_;
};

#endif  // FLOATING_OVERLAY_HOST_H_
