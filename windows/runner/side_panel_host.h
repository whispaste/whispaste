// Runner-owned MethodChannel bridge for the clipboard quick-paste side panel
// (issue 04/09 Windows port). Structural precedent: snippet_picker_host
// .{h,cpp} (a second-Flutter-engine shell that DOES take keyboard focus).
// Behavioral precedent: macos/Runner/SidePanelHost.swift -- same channel
// names, same method contract, so the Dart side needs zero platform
// branching.
//
// Channel contract (shared with macOS):
//   PUBLIC  "com.whispaste.side_panel"         updateSnapshot in; destroy in;
//                                               rowClicked/hoverLeft/
//                                               hoverEntered out.
//   PRIVATE "com.whispaste.side_panel_render"  updateSnapshot to render;
//                                               ready/rowClicked/hoverLeft/
//                                               reportError from render.
//
// One SidePanelSensorWindow per connected monitor (rebuilt on
// WM_DISPLAYCHANGE, mirrors SidePanelHost.rebuildSensors / NSScreen.screens
// .map), a single lazily-created SidePanelContentWindow + render engine
// (mirrors ensurePanel/bootRenderEngine).
//
// Unlike SnippetPickerHost, no previousFrontApp save/restore and no
// activation-settle suppression window: DesktopPasteHost::
// BringTargetToForeground() force-reactivates its own stored target HWND at
// paste time regardless of current foreground state (same asymmetry
// SnippetPickerHost.h already documents), and TrackMouseEvent(TME_HOVER)'s
// dwell is a system-owned timer with no run-loop-mode equivalent to be
// starved by an activation change -- see side_panel_window.h's file comment.
//
// Lifetime invariant: must be destroyed BEFORE the main engine tears down
// (managed by FlutterWindow::OnDestroy, same as the other second-engine
// hosts).

#ifndef SIDE_PANEL_HOST_H_
#define SIDE_PANEL_HOST_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "side_panel_window.h"

class SidePanelHost {
 public:
  // |main_engine| must outlive this object. |owner| is the main Flutter HWND
  // (parity argument only, no Win32 parent relationship results -- see
  // SnippetPickerHost's constructor doc).
  SidePanelHost(flutter::FlutterEngine* main_engine, HWND owner);
  ~SidePanelHost();

  SidePanelHost(const SidePanelHost&) = delete;
  SidePanelHost& operator=(const SidePanelHost&) = delete;

  // Tear down native resources (sensors + shell + render engine). Safe to
  // call multiple times. Must be called before main engine teardown.
  void Destroy();

  // Rebuilds the per-monitor sensor strips -- call on WM_DISPLAYCHANGE
  // (mirrors SidePanelHost.rebuildSensors's didChangeScreenParameters
  // observer).
  void RebuildSensors();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleUpdateSnapshot(const flutter::EncodableMap& args);

  // Lazily boots the render engine + content shell on first updateSnapshot
  // with visible=true. Mirrors SidePanelHost.ensurePanel/bootRenderEngine.
  bool EnsureEngineAndShell();

  void HandleRenderCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ── Sensor callbacks (one strip per monitor) ──────────────────────────
  void HandleHoverEntered(const RECT& work_area);
  void HandleRawEnter();
  void HandleRawExit();

  // ── Content-window callbacks ───────────────────────────────────────────
  void HandleContentEnter();
  void HandleContentExit();

  // Native close-grace fallback -- mirrors SidePanelHost.scheduleNativeClose
  // (a plain Win32 SetTimer here; no .eventTrackingRunLoopMode-style mode
  // split exists on Windows to starve it, see side_panel_window.h).
  void ScheduleNativeClose();
  void CancelNativeClose();
  static void CALLBACK NativeCloseTimerProc(HWND hwnd, UINT msg,
                                            UINT_PTR id, DWORD time);

  // Target rect (physical px) for the content panel on |work_area| --
  // mirrors SidePanelHost.targetRect. |shown| picks the resting position
  // (flush with the monitor edge) vs. the just-off-edge staging position.
  void ComputeTargetRect(const RECT& work_area, bool shown, int* px, int* py,
                         int* pwidth, int* pheight) const;

  void PositionPanel(const RECT& work_area);

  void SlideIn();
  void SlideOut();

  void RelayUpdateSnapshot(const flutter::EncodableMap& args);

  void SendEvent(const std::string& method,
                const flutter::EncodableValue& args);
  void SendEvent(const std::string& method);

  // ── Main-engine side ───────────────────────────────────────────────────
  flutter::FlutterEngine* main_engine_;  // Not owned
  HWND owner_;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // ── Render-engine side (lazy-created on first show) ───────────────────
  std::unique_ptr<flutter::DartProject> render_project_;
  std::unique_ptr<flutter::FlutterViewController> render_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      render_channel_;
  bool render_ready_ = false;
  std::optional<flutter::EncodableMap> latest_snapshot_args_;

  // ── Sensors (one per monitor) ──────────────────────────────────────────
  std::vector<std::unique_ptr<SidePanelSensorWindow>> sensors_;

  // ── Content shell ───────────────────────────────────────────────────────
  std::unique_ptr<SidePanelContentWindow> content_window_;
  bool is_shown_ = false;

  // The monitor work area the panel is currently anchored to -- set on
  // hover-enter, read by SlideIn/SlideOut. Mirrors currentScreenFrame.
  std::optional<RECT> current_work_area_;

  // Pending target rect for a content window not yet created -- mirrors
  // pendingFrame.
  std::optional<RECT> pending_rect_;

  // ── Native close-grace timer ────────────────────────────────────────────
  static constexpr UINT_PTR kCloseTimerId = 2;
  static constexpr int kCloseGraceMs = 350;
  bool close_timer_armed_ = false;

  // ── Layout constants (logical px, DPI-resolved per monitor) ───────────
  static constexpr int kSensorWidth = 6;
  static constexpr int kContentWidth = 320;
  static constexpr int kContentHeight = 640;
  static constexpr int kSlideDurationMs = 220;
  static constexpr int kDwellMs = 60;
};

#endif  // SIDE_PANEL_HOST_H_
