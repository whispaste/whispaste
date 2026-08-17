#include "snippet_picker_host.h"

#include <flutter/encodable_value.h>
#include <flutter_windows.h>

#include <algorithm>
#include <cmath>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.snippet_picker";
constexpr char kRenderChannelName[] = "com.whispaste.snippet_picker_render";

// Fixed panel size (logical px) — see snippet_picker_controller_interface
// .dart's cross-platform shell contract. Never content-measured.
constexpr int kLogicalWidth = 360;
constexpr int kLogicalHeight = 420;

}  // namespace

// ══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ══════════════════════════════════════════════════════════════════════

SnippetPickerHost::SnippetPickerHost(flutter::FlutterEngine* main_engine,
                                     HWND owner)
    : main_engine_(main_engine), owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      main_engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  OutputDebugStringW(L"[SnippetPicker] Host created\n");
}

SnippetPickerHost::~SnippetPickerHost() { Destroy(); }

void SnippetPickerHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  if (render_channel_) {
    render_channel_->SetMethodCallHandler(nullptr);
    render_channel_.reset();
  }
  if (window_) {
    window_->Destroy();
    window_.reset();
  }
  if (render_controller_) {
    render_controller_.reset();
  }
  render_project_.reset();
  render_ready_ = false;
  has_pending_items_ = false;
  pending_items_.clear();

  OutputDebugStringW(L"[SnippetPicker] Host destroyed\n");
}

// ══════════════════════════════════════════════════════════════════════
// Lazy engine + shell creation
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerHost::ComputePanelRect(int* px, int* py, int* pwidth,
                                         int* pheight) const {
  POINT cursor = {0, 0};
  GetCursorPos(&cursor);

  // Monitor (and its DPI) picked from the raw cursor point — same
  // rationale as SnippetPickerHost.swift's clampToVisibleScreen: on a
  // multi-monitor setup with differently scaled/sized displays, picking by
  // an already-offset point can select the wrong monitor.
  HMONITOR mon = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(mon);
  double scale = (dpi > 0) ? dpi / 96.0 : 1.0;

  int width = static_cast<int>(std::round(kLogicalWidth * scale));
  int height = static_cast<int>(std::round(kLogicalHeight * scale));

  // Anchor top-left at the cursor — opens downward/rightward, matching
  // typical context-menu placement (same intent as the macOS shell; that
  // one subtracts height because AppKit's origin is bottom-left, top-down
  // Win32 needs no such adjustment).
  int x = cursor.x;
  int y = cursor.y;

  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  if (GetMonitorInfoW(mon, &mi)) {
    const RECT& wa = mi.rcWork;
    // Manual min/max clamp rather than std::clamp: if the panel is wider/
    // taller than the work area, std::clamp's lo<=hi precondition would be
    // violated (asserts in debug builds).
    x = std::max(wa.left, std::min(x, wa.right - width));
    y = std::max(wa.top, std::min(y, wa.bottom - height));
  }

  *px = x;
  *py = y;
  *pwidth = width;
  *pheight = height;
}

bool SnippetPickerHost::EnsureEngineAndShell() {
  if (render_controller_) return true;  // already booted

  render_ready_ = false;

  int px, py, pwidth, pheight;
  ComputePanelRect(&px, &py, &pwidth, &pheight);

  // DartProject("data") resolves relative to the executable, same as every
  // other second-engine shell in this runner.
  auto project = std::make_unique<flutter::DartProject>(L"data");
  project->set_dart_entrypoint("snippetPickerMain");

  auto controller = std::make_unique<flutter::FlutterViewController>(
      pwidth, pheight, *project);

  if (!controller->engine() || !controller->view()) {
    OutputDebugStringW(
        L"[SnippetPicker] Render engine / view creation failed\n");
    return false;
  }

  // Plugin registration intentionally skipped — see floating_button_host
  // .cpp's file-level comment for the shared rationale (this render engine
  // only uses the private render MethodChannel, no plugins).

  auto render_ch = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      controller->engine()->messenger(), kRenderChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  render_ch->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleRenderCall(call, std::move(result));
      });

  HWND flutter_child = controller->view()->GetNativeWindow();

  auto shell = std::make_unique<SnippetPickerWindow>();
  if (!shell->Create(owner_, px, py, pwidth, pheight, flutter_child)) {
    OutputDebugStringW(L"[SnippetPicker] Shell window creation failed\n");
    return false;
  }

  shell->on_deactivate_cancel = [this]() { Dismiss(/*fire_cancelled=*/true); };

  render_project_ = std::move(project);
  render_controller_ = std::move(controller);
  render_channel_ = std::move(render_ch);
  window_ = std::move(shell);

  OutputDebugStringW(L"[SnippetPicker] Render engine booted, shell created\n");
  return true;
}

// ══════════════════════════════════════════════════════════════════════
// Show / Dismiss
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerHost::Show(const std::vector<EncodableMap>& items) {
  int px, py, pwidth, pheight;
  ComputePanelRect(&px, &py, &pwidth, &pheight);
  window_->SetPhysicalRect(px, py, pwidth, pheight);

  if (render_ready_) {
    RelaySetItems(items);
  } else {
    pending_items_ = items;
    has_pending_items_ = true;
  }

  window_->Show();
}

void SnippetPickerHost::Dismiss(bool fire_cancelled) {
  if (is_dismissing_ || !window_ || !window_->visible()) return;
  is_dismissing_ = true;

  window_->Hide();
  // Tell the render engine the panel left the screen — same "stop glass
  // animations while hidden" signal as SnippetPickerHost.swift's
  // panelHidden (its doc explains why: the render engine's frames are
  // never lifecycle-gated).
  if (render_channel_) {
    render_channel_->InvokeMethod("panelHidden",
                                  std::make_unique<EncodableValue>());
  }
  if (fire_cancelled) {
    SendEvent("onCancelled");
  }

  is_dismissing_ = false;
}

// ══════════════════════════════════════════════════════════════════════
// Public MethodChannel handler (Dart main engine → C++)
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "SnippetPickerHost is destroyed");
    return;
  }

  const auto& method = call.method_name();

  // ── show ────────────────────────────────────────────────────────────
  if (method == "show") {
    const auto* args_map = std::get_if<EncodableMap>(call.arguments());
    std::vector<EncodableMap> items;
    if (args_map) {
      auto it = args_map->find(EncodableValue("items"));
      if (it != args_map->end()) {
        if (const auto* list = std::get_if<EncodableList>(&it->second)) {
          for (const auto& entry : *list) {
            if (const auto* m = std::get_if<EncodableMap>(&entry)) {
              items.push_back(*m);
            }
          }
        }
      }
    }

    if (!EnsureEngineAndShell()) {
      result->Error("CREATE_FAILED",
                    "Failed to create render engine / shell window");
      return;
    }

    Show(items);
    result->Success();
    return;
  }

  // ── hide ────────────────────────────────────────────────────────────
  if (method == "hide") {
    Dismiss(/*fire_cancelled=*/false);
    result->Success();
    return;
  }

  // ── destroy ─────────────────────────────────────────────────────────
  // Tears down the render engine and shell but keeps the host (and its
  // public channel) alive — a future show() re-boots them. Mirrors
  // FloatingButtonHost's "destroy" case.
  if (method == "destroy") {
    if (render_channel_) {
      render_channel_->SetMethodCallHandler(nullptr);
      render_channel_.reset();
    }
    if (window_) {
      window_->Destroy();
      window_.reset();
    }
    if (render_controller_) {
      render_controller_.reset();
    }
    render_project_.reset();
    render_ready_ = false;
    has_pending_items_ = false;
    pending_items_.clear();
    result->Success();
    return;
  }

  result->NotImplemented();
}

// ══════════════════════════════════════════════════════════════════════
// Render-engine MethodChannel handler (render Dart → C++ → main Dart)
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerHost::HandleRenderCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();

  // ── ready ────────────────────────────────────────────────────────────
  if (method == "ready") {
    OutputDebugStringW(
        L"[SnippetPicker] Render engine ready — flushing pending items\n");
    render_ready_ = true;
    if (has_pending_items_) {
      RelaySetItems(pending_items_);
      has_pending_items_ = false;
      pending_items_.clear();
    }
    result->Success();
    return;
  }

  // ── selectItem ───────────────────────────────────────────────────────
  if (method == "selectItem") {
    const auto* args_map = std::get_if<EncodableMap>(call.arguments());
    std::string id;
    if (args_map) {
      auto it = args_map->find(EncodableValue("id"));
      if (it != args_map->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) id = *s;
      }
    }
    // Already reported via onItemSelected below — not a cancellation.
    Dismiss(/*fire_cancelled=*/false);
    EncodableMap m;
    m[EncodableValue("id")] = EncodableValue(id);
    SendEvent("onItemSelected", EncodableValue(m));
    result->Success();
    return;
  }

  // ── cancel ───────────────────────────────────────────────────────────
  if (method == "cancel") {
    Dismiss(/*fire_cancelled=*/true);
    result->Success();
    return;
  }

  // ── reportError ──────────────────────────────────────────────────────
  if (method == "reportError") {
    const auto* args_map = std::get_if<EncodableMap>(call.arguments());
    if (args_map) {
      auto it = args_map->find(EncodableValue("message"));
      if (it != args_map->end()) {
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

// ══════════════════════════════════════════════════════════════════════
// Relay helpers → render engine
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerHost::RelaySetItems(
    const std::vector<EncodableMap>& items) {
  if (!render_channel_) return;
  EncodableList list(items.size());
  std::transform(items.begin(), items.end(), list.begin(),
                 [](const EncodableMap& item) { return EncodableValue(item); });
  EncodableMap wrapper;
  wrapper[EncodableValue("items")] = EncodableValue(list);
  render_channel_->InvokeMethod("setItems",
                                std::make_unique<EncodableValue>(wrapper));
}

// ══════════════════════════════════════════════════════════════════════
// Events (C++ → main Dart engine)
// ══════════════════════════════════════════════════════════════════════

void SnippetPickerHost::SendEvent(const std::string& method,
                                  const EncodableValue& args) {
  if (destroyed_ || !channel_) return;
  channel_->InvokeMethod(method, std::make_unique<EncodableValue>(args));
}

void SnippetPickerHost::SendEvent(const std::string& method) {
  SendEvent(method, EncodableValue());
}
