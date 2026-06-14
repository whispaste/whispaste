// Runner-owned MethodChannel bridge for the floating overlay (ADR 0002 Phase 2).
//
// Migration from GDI+/DirectWrite drawing (Phase 1) to second Flutter engine
// (Phase 2). Mirrors the already-shipped macOS FloatingOverlayHost.swift
// (commit 13fce43f) and structurally mirrors FloatingButtonHost (canonical
// Windows template for this pattern).
//
// Drag approach (identical to FloatingButtonHost):
//   Dart fires "startDrag" when the user pans the pill. We use the classic
//   ReleaseCapture / WM_NCLBUTTONDOWN(HTCAPTION) trick so the OS handles the
//   move loop natively. When the loop ends we read the final shell window
//   top-left, update anchor_mode_ to "topLeft", and fire onDragEnded{x,y,
//   anchorMode:"topLeft"} to the main Dart engine.
//
// setContextMenuItems BUG FIX (vs Phase 1 host):
//   Phase 1 called std::get_if<EncodableList>(call.arguments()), reading args
//   as a bare list. But Dart sends {items:[...]} — an EncodableMap with key
//   "items". This is consistent with how FloatingButtonHost unwraps it. Fixed
//   here: we extract args["items"] first.
//
// Boot-race handshake:
//   The render engine's Dart handler is ready only a few message-loop ticks
//   after FlutterViewController is created. Until the engine signals "ready"
//   we cache the latest snapshot + bars. On "ready" we flush bars then
//   snapshot (mirrors macOS order in handleRenderCall("ready")).

#include "floating_overlay_host.h"

#include <flutter/encodable_value.h>

#include <algorithm>
#include <cmath>
#include <string>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.floating_overlay";
constexpr char kRenderChannelName[] = "com.whispaste.floating_overlay_render";

// ── Window-size spec (mirrors OverlayDesignSpec.windowSize in Dart) ──────
// pill + 8 px shadow padding each side
constexpr int kNormalW = 346;
constexpr int kNormalH = 80;
constexpr int kCompactW = 236;
constexpr int kCompactH = 56;

// Anchor margin from the screen edge (logical pixels, mirrors macOS 16 pt).
constexpr double kAnchorMargin = 16.0;

// ── EncodableMap helpers (mirrors FloatingButtonHost) ────────────────────

double GetDouble(const EncodableMap& map, const std::string& key,
                 double fallback = 0.0) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* d = std::get_if<double>(&it->second)) return *d;
  if (auto* i = std::get_if<int32_t>(&it->second))
    return static_cast<double>(*i);
  if (auto* l = std::get_if<int64_t>(&it->second))
    return static_cast<double>(*l);
  return fallback;
}

bool GetBool(const EncodableMap& map, const std::string& key,
             bool fallback = false) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* b = std::get_if<bool>(&it->second)) return *b;
  return fallback;
}

std::string GetString(const EncodableMap& map, const std::string& key,
                      const std::string& fallback = "") {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* s = std::get_if<std::string>(&it->second)) return *s;
  return fallback;
}

// Normalise the anchor mode string from Dart (accepts both camelCase and
// snake_case; "custom" → "topLeft" for backwards compat).
std::string NormaliseAnchor(const std::string& s) {
  if (s == "topCenter" || s == "top_center") return "topCenter";
  if (s == "bottomCenter" || s == "bottom_center") return "bottomCenter";
  if (s == "topLeft" || s == "custom") return "topLeft";
  return "topCenter";
}

}  // namespace

// ══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ══════════════════════════════════════════════════════════════════════

FloatingOverlayHost::FloatingOverlayHost(flutter::FlutterEngine* main_engine,
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

  OutputDebugStringW(
      L"[FloatingOverlay] Host created (Phase 2 / Flutter engine)\n");
}

FloatingOverlayHost::~FloatingOverlayHost() { Destroy(); }

void FloatingOverlayHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  // Tear down public channel first so no new calls arrive during cleanup.
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }

  // Tear down the render channel before the render controller.
  if (render_channel_) {
    render_channel_->SetMethodCallHandler(nullptr);
    render_channel_.reset();
  }

  // Tear down the shell BEFORE the render engine/controller — the shell
  // un-parents the Flutter child HWND so the controller can destroy it.
  if (window_) {
    window_->Destroy();
    window_.reset();
  }

  // Destroy the render controller (and its engine) last.
  render_controller_.reset();
  render_project_.reset();
  render_ready_ = false;
  latest_snapshot_args_.reset();
  latest_bars_args_.reset();

  OutputDebugStringW(L"[FloatingOverlay] Host destroyed\n");
}

void FloatingOverlayHost::RefreshTopmost() {
  if (!destroyed_ && window_) window_->RefreshTopmost();
}

// ══════════════════════════════════════════════════════════════════════
// Lazy engine + shell creation
// ══════════════════════════════════════════════════════════════════════

bool FloatingOverlayHost::EnsureEngineAndShell(bool compact) {
  if (render_controller_) return true;  // already booted

  render_ready_ = false;
  is_compact_ = compact;

  int logical_w = compact ? kCompactW : kNormalW;
  int logical_h = compact ? kCompactH : kNormalH;

  // ── Boot the render engine ──────────────────────────────────────────
  // DartProject("data") resolves relative to the executable (standard for
  // the Windows embedder).
  auto project = std::make_unique<flutter::DartProject>(L"data");
  project->set_dart_entrypoint("floatingOverlayMain");

  // Create the Flutter view controller at the logical overlay size.
  auto controller = std::make_unique<flutter::FlutterViewController>(
      logical_w, logical_h, *project);

  if (!controller->engine() || !controller->view()) {
    OutputDebugStringW(
        L"[FloatingOverlay] Render engine / view creation failed\n");
    return false;
  }

  // Plugin registration: intentionally skipped for the render engine.
  // See file-level comment in floating_button_host.cpp for rationale.

  // ── Render MethodChannel ────────────────────────────────────────────
  auto render_ch = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      controller->engine()->messenger(), kRenderChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  render_ch->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleRenderCall(call, std::move(result));
      });

  // ── Resolve initial position from anchor mode ───────────────────────
  auto [lx, ly] = ResolveAnchorPosition();

  // ── Create the shell window ─────────────────────────────────────────
  HWND flutter_child = controller->view()->GetNativeWindow();

  auto shell = std::make_unique<FloatingOverlayWindow>();
  if (!shell->Create(owner_, lx, ly, logical_w, logical_h, flutter_child)) {
    OutputDebugStringW(L"[FloatingOverlay] Shell window creation failed\n");
    return false;
  }

  // Wire display-change callback: re-resolve anchor after monitor changes.
  shell->SetDisplayChangeCallback([this]() {
    if (!window_ || !window_->IsVisible()) return;
    auto [new_lx, new_ly] = ResolveAnchorPosition();
    window_->SetPosition(new_lx, new_ly);
    // Inform Dart so it can persist the updated position.
    auto [cur_x, cur_y] = window_->GetPosition();
    EncodableMap m;
    m[EncodableValue("x")] = EncodableValue(cur_x);
    m[EncodableValue("y")] = EncodableValue(cur_y);
    m[EncodableValue("anchorMode")] = EncodableValue(anchor_mode_);
    SendEvent("onDragEnded", EncodableValue(m));
  });

  render_project_ = std::move(project);
  render_controller_ = std::move(controller);
  render_channel_ = std::move(render_ch);
  window_ = std::move(shell);

  OutputDebugStringW(
      L"[FloatingOverlay] Render engine booted, shell created\n");
  return true;
}

// ══════════════════════════════════════════════════════════════════════
// Public MethodChannel handler (Dart main engine → C++)
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "FloatingOverlayHost is destroyed");
    return;
  }

  const auto& method = call.method_name();
  const auto* args = call.arguments();
  const EncodableMap* map =
      args ? std::get_if<EncodableMap>(args) : nullptr;

  // ── updateSnapshot ──────────────────────────────────────────────────
  // Lazy-creates the engine + shell on the first call with visible:true.
  // Mirrors macOS handleUpdateSnapshot.
  if (method == "updateSnapshot") {
    bool visible = map ? GetBool(*map, "visible", false) : false;
    bool compact = map ? GetBool(*map, "compact", false) : false;
    bool size_changed = (compact != is_compact_);

    // Update compact state BEFORE EnsureEngineAndShell so the first creation
    // sizes the shell correctly (mirrors macOS: set isCompact before ensurePanel).
    is_compact_ = compact;

    if (visible && !render_controller_) {
      if (!EnsureEngineAndShell(compact)) {
        result->Error("CREATE_FAILED",
                      "Failed to create render engine / shell window");
        return;
      }
    } else if (size_changed && window_) {
      ResizeShell(compact);
    }

    // Cache for boot-race handshake (flushed in HandleRenderCall("ready")).
    if (args) latest_snapshot_args_ = *args;

    // Relay to render engine (no-op if not ready yet).
    if (render_ready_) RelaySnapshot();

    // Show or hide the shell.
    if (window_) {
      if (visible) window_->Show();
      else          window_->Hide();
    }

    result->Success();
    return;
  }

  // ── setWaveformBars ─────────────────────────────────────────────────
  // Dart pushes a pre-computed bar array from its WaveformPipeline. The
  // render engine is stateless — we relay the whole payload verbatim.
  if (method == "setWaveformBars") {
    if (args) latest_bars_args_ = *args;
    if (render_ready_) RelayBars();
    result->Success();
    return;
  }

  // ── setPosition ─────────────────────────────────────────────────────
  if (method == "setPosition") {
    if (map) {
      anchor_mode_ = NormaliseAnchor(GetString(*map, "anchorMode", "topCenter"));
      // anchor_x_/y_ are the raw logical coords from Dart; used only in
      // "topLeft" mode — for topCenter/bottomCenter they are ignored by
      // ResolveAnchorPosition().
      anchor_x_ = GetDouble(*map, "x", 0.0);
      anchor_y_ = GetDouble(*map, "y", 0.0);

      if (window_) {
        auto [lx, ly] = ResolveAnchorPosition();
        window_->SetPosition(lx, ly);
      }
      // If the window does not exist yet, anchor_mode_/x/y are already stored
      // and will be used by ResolveAnchorPosition() in EnsureEngineAndShell.
    }
    result->Success();
    return;
  }

  // ── setContextMenuItems ─────────────────────────────────────────────
  // BUG FIX vs Phase 1: Dart sends {items:[{id,label},...]} — an EncodableMap
  // with key "items". Phase 1 mistakenly read the bare args as an EncodableList.
  // Fixed here: unwrap args["items"] first (mirrors FloatingButtonHost).
  if (method == "setContextMenuItems") {
    auto* args_map = args ? std::get_if<EncodableMap>(args) : nullptr;
    if (args_map) {
      auto it = args_map->find(EncodableValue("items"));
      if (it != args_map->end()) {
        auto* list = std::get_if<EncodableList>(&it->second);
        if (list) {
          std::vector<std::pair<std::string, std::wstring>> items;
          for (const auto& item_val : *list) {
            auto* item_map = std::get_if<EncodableMap>(&item_val);
            if (!item_map) continue;
            auto id_it    = item_map->find(EncodableValue("id"));
            auto label_it = item_map->find(EncodableValue("label"));
            if (id_it == item_map->end() || label_it == item_map->end())
              continue;
            auto* id_str    = std::get_if<std::string>(&id_it->second);
            auto* label_str = std::get_if<std::string>(&label_it->second);
            if (!id_str || !label_str) continue;
            // Convert UTF-8 label to wstring for TrackPopupMenu.
            int len = MultiByteToWideChar(CP_UTF8, 0, label_str->c_str(),
                                          -1, nullptr, 0);
            std::wstring wlabel(len > 1 ? len - 1 : 0, L'\0');
            MultiByteToWideChar(CP_UTF8, 0, label_str->c_str(), -1,
                                wlabel.data(), len);
            items.emplace_back(*id_str, std::move(wlabel));
          }
          context_menu_items_ = std::move(items);
        }
      }
    }
    result->Success();
    return;
  }

  // ── setOpacity ───────────────────────────────────────────────────────
  // Opacity was removed in issue 11. Accept as a no-op so the Dart controller
  // does not receive a MethodChannel error.
  if (method == "setOpacity") {
    result->Success();
    return;
  }

  // ── destroy ─────────────────────────────────────────────────────────
  // Tear down the render engine and shell. The host itself stays alive so
  // it can handle a future updateSnapshot (lazy-recreate pattern).
  if (method == "destroy") {
    if (render_channel_) {
      render_channel_->SetMethodCallHandler(nullptr);
      render_channel_.reset();
    }
    if (window_) {
      window_->Destroy();
      window_.reset();
    }
    render_controller_.reset();
    render_project_.reset();
    render_ready_ = false;
    latest_snapshot_args_.reset();
    latest_bars_args_.reset();
    result->Success();
    return;
  }

  result->NotImplemented();
}

// ══════════════════════════════════════════════════════════════════════
// Render-engine MethodChannel handler (render Dart → C++ → main Dart)
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::HandleRenderCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();

  // ── ready ────────────────────────────────────────────────────────────
  // The render engine's Dart MethodChannel handler is now live — flush the
  // cached state so the first visible frame is never lost to the boot race.
  // Flush order: bars first, then snapshot. Mirrors macOS handleRenderCall.
  if (method == "ready") {
    OutputDebugStringW(
        L"[FloatingOverlay] Render engine ready — flushing cached state\n");
    render_ready_ = true;
    RelayBars();
    RelaySnapshot();
    result->Success();
    return;
  }

  // ── startDrag ────────────────────────────────────────────────────────
  // Dart fires this when the user starts panning the pill. Hand off to the
  // OS via NCLBUTTONDOWN/HTCAPTION; BeginDrag() fires onDragEnded when done.
  if (method == "startDrag") {
    BeginDrag();
    result->Success();
    return;
  }

  // ── bodyClicked ──────────────────────────────────────────────────────
  if (method == "bodyClicked") {
    SendEvent("onBodyClicked");
    result->Success();
    return;
  }

  // ── showContextMenu ──────────────────────────────────────────────────
  if (method == "showContextMenu") {
    ShowNativeContextMenu();
    result->Success();
    return;
  }

  result->NotImplemented();
}

// ══════════════════════════════════════════════════════════════════════
// Drag
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::BeginDrag() {
  if (!window_ || !window_->GetHandle()) return;
  HWND hwnd = window_->GetHandle();

  // Release any existing mouse capture (Flutter may hold it).
  ReleaseCapture();

  // Synthesise an NCLBUTTONDOWN on HTCAPTION so Windows moves the window.
  // The OS enters its internal move loop synchronously; when the user releases
  // the button the SendMessage returns and we can read the final position.
  //
  // This requires the cursor to already be inside the window — guaranteed
  // because Dart's onPanStart fires from a pointer event on the pill.
  SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);

  // Move loop has ended. Read the final top-left position (physical pixels).
  RECT rc;
  GetWindowRect(hwnd, &rc);

  UINT dpi = GetDpiForWindow(hwnd);
  double dpi_scale = (dpi > 0) ? dpi / 96.0 : 1.0;

  // Convert physical top-left to logical DIPs.
  double fin_x = rc.left / dpi_scale;
  double fin_y = rc.top  / dpi_scale;

  // Persist: dragging always becomes a "topLeft" anchor.
  anchor_mode_ = "topLeft";
  anchor_x_    = fin_x;
  anchor_y_    = fin_y;
  window_->SetPosition(fin_x, fin_y);

  EncodableMap m;
  m[EncodableValue("x")]          = EncodableValue(fin_x);
  m[EncodableValue("y")]          = EncodableValue(fin_y);
  m[EncodableValue("anchorMode")] = EncodableValue(std::string("topLeft"));
  SendEvent("onDragEnded", EncodableValue(m));
}

// ══════════════════════════════════════════════════════════════════════
// Native context menu
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::ShowNativeContextMenu() {
  if (context_menu_items_.empty()) return;

  HMENU menu = CreatePopupMenu();
  for (size_t i = 0; i < context_menu_items_.size(); ++i) {
    const auto& [id, wlabel] = context_menu_items_[i];
    if (wlabel == L"---") {
      // "---" is the separator convention (matches macOS / FloatingButtonHost).
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    } else {
      AppendMenuW(menu, MF_STRING, static_cast<UINT_PTR>(1000 + i),
                  wlabel.c_str());
    }
  }

  POINT pt;
  GetCursorPos(&pt);

  // TPM_RETURNCMD returns the selected item ID instead of posting WM_COMMAND.
  int cmd = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN,
      pt.x, pt.y, 0,
      window_ ? window_->GetHandle() : owner_,
      nullptr);
  DestroyMenu(menu);

  if (cmd >= 1000 &&
      cmd < 1000 + static_cast<int>(context_menu_items_.size())) {
    const auto& selected_id = context_menu_items_[cmd - 1000].first;
    EncodableMap m;
    m[EncodableValue("action")] = EncodableValue(selected_id);
    SendEvent("onContextMenu", EncodableValue(m));
  }
}

// ══════════════════════════════════════════════════════════════════════
// Shell resize + re-anchor
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::ResizeShell(bool compact) {
  if (!window_) return;
  is_compact_ = compact;
  window_->SetSize(compact ? kCompactW : kNormalW,
                   compact ? kCompactH : kNormalH);
  // Re-anchor: topCenter/bottomCenter overlays must stay centred after the
  // width changes; topLeft overlays keep their raw corner position.
  auto [lx, ly] = ResolveAnchorPosition();
  window_->SetPosition(lx, ly);
}

// ══════════════════════════════════════════════════════════════════════
// Anchor-mode position resolution
// ══════════════════════════════════════════════════════════════════════

std::pair<double, double> FloatingOverlayHost::ResolveAnchorPosition() const {
  // "topLeft" — raw logical coordinates (custom drag position).
  if (anchor_mode_ == "topLeft") {
    return {anchor_x_, anchor_y_};
  }

  // topCenter / bottomCenter — compute from the monitor the main window is on.
  HMONITOR mon = MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(mon, &mi)) {
    // Fallback to stored raw coords if monitor info fails.
    return {anchor_x_, anchor_y_};
  }

  // Use the main window's DPI to convert physical work area → logical DIPs.
  // This is a proxy for the monitor's DPI; GetDpiForMonitor (requires shcore)
  // would be more precise on mixed-DPI setups but is not worth the dependency
  // for this first-draft calculation.
  double dpi_scale = 1.0;
  if (owner_) {
    UINT dpi = GetDpiForWindow(owner_);
    if (dpi > 0) dpi_scale = dpi / 96.0;
  }

  const RECT& wa = mi.rcWork;
  double wa_left   = wa.left   / dpi_scale;
  double wa_right  = wa.right  / dpi_scale;
  double wa_w      = wa_right  - wa_left;

  double overlay_w = is_compact_ ? static_cast<double>(kCompactW)
                                 : static_cast<double>(kNormalW);
  double overlay_h = is_compact_ ? static_cast<double>(kCompactH)
                                 : static_cast<double>(kNormalH);

  // Horizontal: centred within the work area (both topCenter + bottomCenter).
  double lx = wa_left + (wa_w - overlay_w) / 2.0;

  if (anchor_mode_ == "topCenter") {
    // Logical Y: kAnchorMargin from the top of the work area.
    double wa_top = wa.top / dpi_scale;
    return {lx, wa_top + kAnchorMargin};
  } else {
    // bottomCenter: kAnchorMargin above the bottom of the work area.
    double wa_bottom = wa.bottom / dpi_scale;
    return {lx, wa_bottom - overlay_h - kAnchorMargin};
  }
}

// ══════════════════════════════════════════════════════════════════════
// Relay helpers → render engine
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::RelaySnapshot() {
  if (!render_channel_ || !latest_snapshot_args_) return;
  render_channel_->InvokeMethod(
      "updateSnapshot",
      std::make_unique<EncodableValue>(*latest_snapshot_args_));
}

void FloatingOverlayHost::RelayBars() {
  if (!render_channel_ || !latest_bars_args_) return;
  render_channel_->InvokeMethod(
      "setWaveformBars",
      std::make_unique<EncodableValue>(*latest_bars_args_));
}

// ══════════════════════════════════════════════════════════════════════
// Events (C++ → main Dart engine)
// ══════════════════════════════════════════════════════════════════════

void FloatingOverlayHost::SendEvent(const std::string& method,
                                    const EncodableValue& args) {
  if (destroyed_ || !channel_) return;
  channel_->InvokeMethod(method, std::make_unique<EncodableValue>(args));
}

void FloatingOverlayHost::SendEvent(const std::string& method) {
  SendEvent(method, EncodableValue());
}
