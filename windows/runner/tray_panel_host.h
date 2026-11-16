#ifndef TRAY_PANEL_HOST_H_
#define TRAY_PANEL_HOST_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "snippet_picker_window.h"

// Native shell of the tray panel on Windows (#920, ADR 0038). Mirrors
// macos/Runner/TrayPanelHost.swift: the main engine calls `toggle(content)`
// on com.whispaste.tray_panel, this host lazily boots a second Flutter engine
// (entrypoint `trayPanelMain`) in a borderless top-most popup next to the
// tray icon and relays the snapshot over com.whispaste.tray_panel_render.
//
// - The engine boots on the first click (no idle cost). If it is not ready
//   within the boot budget, `toggle` answers `ok: false` and the main engine
//   opens the native menu instead.
// - The popup closes on an action, on Escape (`cancel`), on deactivation
//   (click outside) and on a second icon click. Every dismissal sends
//   `panelHidden` to the render engine and `onDismissed` to the main engine.
// - Arrow keys never reach the Flutter child of a reparented view, so the
//   shell forwards them as `moveFocus{delta}`.
//
// The popup window itself is the shared focusable shell of the snippet
// picker (SnippetPickerWindow); only content and anchoring differ.
class TrayPanelHost {
 public:
  TrayPanelHost(flutter::FlutterEngine* main_engine, HWND owner);
  ~TrayPanelHost();

  TrayPanelHost(const TrayPanelHost&) = delete;
  TrayPanelHost& operator=(const TrayPanelHost&) = delete;

  void Destroy();

 private:
  using Result = flutter::MethodResult<flutter::EncodableValue>;

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<Result> result);
  void HandleRenderCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<Result> result);

  void Toggle(const flutter::EncodableValue& content,
              std::unique_ptr<Result> result);
  bool EnsureEngineAndShell();
  void Present(const flutter::EncodableValue& content);
  void Dismiss();
  void TearDownEngine();

  // Physical rect for [logical_height] anchored at [anchor_] on its monitor:
  // horizontally centred on the click, above it when the click is in the
  // lower half of the monitor (taskbar at the bottom), below it otherwise.
  RECT ComputeRect(double logical_height) const;

  void StartBootTimer();
  void CancelBootTimer();
  static void CALLBACK OnBootTimer(HWND hwnd, UINT msg, UINT_PTR id,
                                   DWORD time);

  void SendEvent(const char* method, const flutter::EncodableValue& args);
  void SendRender(const char* method, const flutter::EncodableValue& args);

  static TrayPanelHost* instance_;

  flutter::FlutterEngine* main_engine_;  // Not owned.
  HWND owner_;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::DartProject> render_project_;
  std::unique_ptr<flutter::FlutterViewController> render_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      render_channel_;
  std::unique_ptr<SnippetPickerWindow> window_;

  bool render_ready_ = false;
  bool is_dismissing_ = false;
  ULONGLONG last_dismiss_at_ = 0;
  POINT anchor_ = {0, 0};
  double logical_height_;

  std::unique_ptr<Result> pending_result_;
  flutter::EncodableValue pending_content_;
  UINT_PTR boot_timer_ = 0;
};

#endif  // TRAY_PANEL_HOST_H_
