#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "attention_host.h"
#include "desktop_paste_host.h"
#include "floating_button_host.h"
#include "floating_overlay_host.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native floating button (runner-owned, destroyed before engine teardown).
  std::unique_ptr<FloatingButtonHost> floating_button_host_;

  // Native floating overlay (runner-owned, destroyed before engine teardown).
  std::unique_ptr<FloatingOverlayHost> floating_overlay_host_;

  // Native desktop paste bridge (runner-owned, destroyed before engine teardown).
  std::unique_ptr<DesktopPasteHost> desktop_paste_host_;

  // Taskbar-flash attention bridge for cross-platform parity with the
  // macOS Dock-bounce request — used to surface action items when the
  // main window is hidden.
  std::unique_ptr<AttentionHost> attention_host_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
