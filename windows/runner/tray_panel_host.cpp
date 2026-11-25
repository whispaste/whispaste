#include "tray_panel_host.h"

#include <flutter/encodable_value.h>
#include <flutter_windows.h>

#include <cmath>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;

namespace {

constexpr char kChannelName[] = "com.whispaste.tray_panel";
constexpr char kRenderChannelName[] = "com.whispaste.tray_panel_render";

// Same window size as macOS: 320 px card plus the 20 px shadow inset per side.
// The height is the start value; the render engine reports the painted one.
constexpr double kLogicalWidth = 360;
constexpr double kInitialLogicalHeight = 232;

// Gap between the click point and the panel edge.
constexpr int kLogicalGap = 4;

constexpr UINT kBootBudgetMs = 700;

// Clicking the tray icon deactivates the open panel before `toggle` arrives;
// a toggle this soon after a dismissal is that same click and keeps it closed.
constexpr ULONGLONG kReopenGuardMs = 300;

EncodableValue OkResult(bool ok) {
  EncodableMap m;
  m[EncodableValue("ok")] = EncodableValue(ok);
  return EncodableValue(m);
}

int Clamp(int value, int low, int high) {
  if (high < low) return low;
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

}  // namespace

TrayPanelHost* TrayPanelHost::instance_ = nullptr;

TrayPanelHost::TrayPanelHost(flutter::FlutterEngine* main_engine, HWND owner)
    : main_engine_(main_engine),
      owner_(owner),
      logical_height_(kInitialLogicalHeight) {
  instance_ = this;
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      main_engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<Result> result) {
        HandleMethodCall(call, std::move(result));
      });
}

TrayPanelHost::~TrayPanelHost() { Destroy(); }

void TrayPanelHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  TearDownEngine();
  if (instance_ == this) instance_ = nullptr;
}

void TrayPanelHost::TearDownEngine() {
  CancelBootTimer();
  if (pending_result_) {
    pending_result_->Success(OkResult(false));
    pending_result_.reset();
  }
  if (render_channel_) {
    render_channel_->SetMethodCallHandler(nullptr);
    render_channel_.reset();
    motion_channel_.reset();
  }
  if (window_) {
    window_->Destroy();
    window_.reset();
  }
  render_controller_.reset();
  render_project_.reset();
  render_ready_ = false;
}

// ─── Main channel ───────────────────────────────────────────────────────────

void TrayPanelHost::HandleMethodCall(const MethodCall<EncodableValue>& call,
                                     std::unique_ptr<Result> result) {
  if (destroyed_) {
    result->Success(OkResult(false));
    return;
  }
  const auto& method = call.method_name();
  const EncodableValue content =
      call.arguments() ? *call.arguments() : EncodableValue();

  if (method == "toggle") {
    if (!std::holds_alternative<EncodableMap>(content)) {
      result->Success(OkResult(false));
      return;
    }
    Toggle(content, std::move(result));
    return;
  }
  if (method == "update") {
    if (render_ready_ && window_ && window_->visible() &&
        std::holds_alternative<EncodableMap>(content)) {
      SendRender("setContent", content);
    }
    result->Success();
    return;
  }
  if (method == "hide") {
    Dismiss();
    result->Success();
    return;
  }
  if (method == "destroy") {
    Dismiss();
    TearDownEngine();
    result->Success();
    return;
  }
  result->NotImplemented();
}

void TrayPanelHost::Toggle(const EncodableValue& content,
                           std::unique_ptr<Result> result) {
  if (window_ && window_->visible()) {
    Dismiss();
    result->Success(OkResult(true));
    return;
  }
  if (GetTickCount64() - last_dismiss_at_ < kReopenGuardMs) {
    result->Success(OkResult(true));
    return;
  }
  // The anchor is where the user clicked the icon.
  GetCursorPos(&anchor_);
  if (!EnsureEngineAndShell()) {
    result->Success(OkResult(false));
    return;
  }
  if (render_ready_) {
    Present(content);
    result->Success(OkResult(true));
    return;
  }
  // Engine still booting: wait up to the budget, then the menu takes over.
  if (pending_result_) pending_result_->Success(OkResult(false));
  pending_result_ = std::move(result);
  pending_content_ = content;
  StartBootTimer();
}

// ─── Engine and shell ───────────────────────────────────────────────────────

bool TrayPanelHost::EnsureEngineAndShell() {
  if (render_controller_ && window_) return true;
  TearDownEngine();

  const RECT rect = ComputeRect(logical_height_);
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;

  auto project = std::make_unique<flutter::DartProject>(L"data");
  project->set_dart_entrypoint("trayPanelMain");
  auto controller =
      std::make_unique<flutter::FlutterViewController>(width, height, *project);
  if (!controller->engine() || !controller->view()) {
    OutputDebugStringW(L"[TrayPanel] Render engine / view creation failed\n");
    return false;
  }

  auto render_ch = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      controller->engine()->messenger(), kRenderChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  render_ch->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<Result> result) {
        HandleRenderCall(call, std::move(result));
      });

  auto shell = std::make_unique<SnippetPickerWindow>();
  if (!shell->Create(owner_, rect.left, rect.top, width, height,
                     controller->view()->GetNativeWindow())) {
    OutputDebugStringW(L"[TrayPanel] Shell window creation failed\n");
    return false;
  }
  // The tray panel is a menu: any focus loss or click outside closes it
  // (unlike the snippet picker, which only closes on a click outside).
  shell->on_focus_lost = [this](bool /*outside_click*/) { Dismiss(); };
  flutter::FlutterViewController* controller_ptr = controller.get();
  shell->forward_to_flutter = [controller_ptr](HWND hwnd, UINT msg, WPARAM wp,
                                               LPARAM lp) {
    return controller_ptr->HandleTopLevelWindowProc(hwnd, msg, wp, lp);
  };
  shell->on_navigate = [this](int delta) {
    EncodableMap m;
    m[EncodableValue("delta")] = EncodableValue(delta);
    SendRender("moveFocus", EncodableValue(m));
  };

  render_project_ = std::move(project);
  render_controller_ = std::move(controller);
  render_channel_ = std::move(render_ch);
  motion_channel_ = std::make_unique<SystemMotionChannel>(
      render_controller_->engine()->messenger());
  window_ = std::move(shell);
  return true;
}

RECT TrayPanelHost::ComputeRect(double logical_height) const {
  HMONITOR mon = MonitorFromPoint(anchor_, MONITOR_DEFAULTTONEAREST);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(mon);
  const double scale = dpi > 0 ? dpi / 96.0 : 1.0;
  const int width = static_cast<int>(std::lround(kLogicalWidth * scale));
  const int height = static_cast<int>(std::ceil(logical_height * scale));
  const int gap = static_cast<int>(std::lround(kLogicalGap * scale));

  RECT work = {anchor_.x - width, anchor_.y - height, anchor_.x + width,
               anchor_.y + height};
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  if (GetMonitorInfoW(mon, &mi)) work = mi.rcWork;

  const bool above = anchor_.y > (work.top + work.bottom) / 2;
  int y = above ? anchor_.y - gap - height : anchor_.y + gap;
  int x = anchor_.x - width / 2;
  x = Clamp(x, static_cast<int>(work.left),
            static_cast<int>(work.right) - width);
  y = Clamp(y, static_cast<int>(work.top),
            static_cast<int>(work.bottom) - height);
  return RECT{x, y, x + width, y + height};
}

void TrayPanelHost::Present(const EncodableValue& content) {
  if (!window_) return;
  const RECT rect = ComputeRect(logical_height_);
  window_->SetPhysicalRect(rect.left, rect.top, rect.right - rect.left,
                           rect.bottom - rect.top);

  EncodableMap payload = std::get<EncodableMap>(content);
  payload[EncodableValue("shown")] = EncodableValue(true);
  SendRender("setContent", EncodableValue(payload));

  is_dismissing_ = false;
  window_->Show();
}

void TrayPanelHost::Dismiss() {
  if (is_dismissing_ || !window_ || !window_->visible()) return;
  is_dismissing_ = true;
  last_dismiss_at_ = GetTickCount64();
  window_->Hide();
  SendRender("panelHidden", EncodableValue());
  SendEvent("onDismissed", EncodableValue());
  is_dismissing_ = false;
}

// ─── Boot budget ────────────────────────────────────────────────────────────

void TrayPanelHost::StartBootTimer() {
  CancelBootTimer();
  boot_timer_ = SetTimer(nullptr, 0, kBootBudgetMs, &TrayPanelHost::OnBootTimer);
}

void TrayPanelHost::CancelBootTimer() {
  if (boot_timer_ != 0) {
    KillTimer(nullptr, boot_timer_);
    boot_timer_ = 0;
  }
}

// static
void CALLBACK TrayPanelHost::OnBootTimer(HWND /*hwnd*/, UINT /*msg*/,
                                         UINT_PTR id, DWORD /*time*/) {
  KillTimer(nullptr, id);
  TrayPanelHost* self = instance_;
  if (!self || self->boot_timer_ != id) return;
  self->boot_timer_ = 0;
  if (self->pending_result_) {
    OutputDebugStringW(
        L"[TrayPanel] Render engine not ready within budget, menu fallback\n");
    self->pending_result_->Success(OkResult(false));
    self->pending_result_.reset();
    self->pending_content_ = EncodableValue();
  }
}

// ─── Render channel ─────────────────────────────────────────────────────────

void TrayPanelHost::HandleRenderCall(const MethodCall<EncodableValue>& call,
                                     std::unique_ptr<Result> result) {
  const auto& method = call.method_name();
  const auto* args = std::get_if<EncodableMap>(call.arguments());

  if (method == "ready") {
    render_ready_ = true;
    if (pending_result_) {
      CancelBootTimer();
      auto pending = std::move(pending_result_);
      const EncodableValue content = pending_content_;
      pending_content_ = EncodableValue();
      Present(content);
      pending->Success(OkResult(true));
    }
    result->Success();
    return;
  }
  if (method == "action") {
    std::string action;
    if (args) {
      auto it = args->find(EncodableValue("action"));
      if (it != args->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) action = *s;
      }
    }
    // Close first: the panel never holds focus while the action runs.
    Dismiss();
    if (!action.empty()) {
      EncodableMap m;
      m[EncodableValue("action")] = EncodableValue(action);
      SendEvent("onAction", EncodableValue(m));
    }
    result->Success();
    return;
  }
  if (method == "cancel") {
    Dismiss();
    result->Success();
    return;
  }
  if (method == "resize") {
    if (args) {
      auto it = args->find(EncodableValue("height"));
      if (it != args->end()) {
        if (const auto* h = std::get_if<double>(&it->second); h && *h > 0) {
          if (std::abs(*h - logical_height_) >= 1) {
            logical_height_ = *h;
            if (window_ && window_->visible()) {
              const RECT rect = ComputeRect(logical_height_);
              window_->SetPhysicalRect(rect.left, rect.top,
                                       rect.right - rect.left,
                                       rect.bottom - rect.top);
            }
          }
        }
      }
    }
    result->Success();
    return;
  }
  if (method == "reportError") {
    if (args) {
      auto it = args->find(EncodableValue("message"));
      if (it != args->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) {
          EncodableMap m;
          m[EncodableValue("message")] = EncodableValue(*s);
          m[EncodableValue("isError")] = EncodableValue(true);
          SendEvent("onRenderEngineDiagnostic", EncodableValue(m));
        }
      }
    }
    result->Success();
    return;
  }
  result->NotImplemented();
}

void TrayPanelHost::SendEvent(const char* method, const EncodableValue& args) {
  if (destroyed_ || !channel_) return;
  channel_->InvokeMethod(method, std::make_unique<EncodableValue>(args));
}

void TrayPanelHost::SendRender(const char* method, const EncodableValue& args) {
  if (!render_channel_ || !render_ready_) return;
  render_channel_->InvokeMethod(method, std::make_unique<EncodableValue>(args));
}
