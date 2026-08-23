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

  // Win32Window::Create() unconditionally calls Destroy() (-> OnDestroy())
  // before the window even exists, which latches is_destroying_ = true on
  // every single launch. Reset it here so HandleTopLevelWindowProc below
  // actually runs for the live window (window_manager's hidden-title-bar
  // suppression depends on it); real teardown still re-latches it in
  // OnDestroy() before this instance is ever recreated.
  is_destroying_ = false;

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

  // Create the taskbar-flash attention host AFTER plugins are registered.
  attention_host_ = std::make_unique<AttentionHost>(
      flutter_controller_->engine(), GetHandle());

  // Create the RawInput key-up monitor (push-to-talk on Windows, #39).
  keyboard_monitor_host_ = std::make_unique<KeyboardMonitorHost>(
      flutter_controller_->engine(), GetHandle());

  // Create the native Snippet-Picker host AFTER plugins are registered
  // (visual-refresh-2026 ticket 29).
  snippet_picker_host_ = std::make_unique<SnippetPickerHost>(
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
  // Block reentrant forwarding into flutter_controller_ for the whole
  // teardown, not just the engine-destruction step below: DestroyWindow()
  // calls from the host teardowns below can also re-enter MessageHandler.
  is_destroying_ = true;

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
  if (attention_host_) {
    attention_host_->Destroy();
    attention_host_.reset();
  }
  if (keyboard_monitor_host_) {
    keyboard_monitor_host_->Destroy();
    keyboard_monitor_host_.reset();
  }
  if (snippet_picker_host_) {
    snippet_picker_host_->Destroy();
    snippet_picker_host_.reset();
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

  // Observe RawInput for the global hotkey's key-up (push-to-talk, #39). This
  // never consumes the message — it falls through to DefWindowProc so RawInput
  // is cleaned up and normal key delivery is unaffected.
  if (message == WM_INPUT && keyboard_monitor_host_) {
    keyboard_monitor_host_->HandleRawInput(
        reinterpret_cast<HRAWINPUT>(lparam));
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  // Skipped while tearing down: flutter_controller_ can be non-null but
  // mid-destruction here (see is_destroying_ above).
  if (flutter_controller_ && !is_destroying_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (message == WM_FONTCHANGE && flutter_controller_ && !is_destroying_) {
    flutter_controller_->engine()->ReloadSystemFonts();
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
