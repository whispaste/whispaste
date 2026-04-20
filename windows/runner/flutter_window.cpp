#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Create the native floating button host AFTER plugins are registered.
  floating_button_host_ = std::make_unique<FloatingButtonHost>(
      flutter_controller_->engine(), GetHandle());

  // Create the native floating overlay host AFTER plugins are registered.
  floating_overlay_host_ = std::make_unique<FloatingOverlayHost>(
      flutter_controller_->engine(), GetHandle());

  // Create the native desktop paste host AFTER plugins are registered.
  desktop_paste_host_ = std::make_unique<DesktopPasteHost>(
      flutter_controller_->engine(), GetHandle());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Destroy overlay and button BEFORE engine teardown (Invariant #4).
  if (floating_overlay_host_) {
    floating_overlay_host_->Destroy();
    floating_overlay_host_.reset();
  }
  if (floating_button_host_) {
    floating_button_host_->Destroy();
    floating_button_host_.reset();
  }
  if (desktop_paste_host_) {
    desktop_paste_host_->Destroy();
    desktop_paste_host_.reset();
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Re-assert TOPMOST on floating windows whenever the main window is
  // minimized or the application regains foreground. This must happen BEFORE
  // HandleTopLevelWindowProc because window_manager may consume WM_SIZE.
  if ((message == WM_SIZE && wparam == SIZE_MINIMIZED) ||
      (message == WM_ACTIVATEAPP && wparam)) {
    if (floating_button_host_) floating_button_host_->RefreshTopmost();
    if (floating_overlay_host_) floating_overlay_host_->RefreshTopmost();
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
