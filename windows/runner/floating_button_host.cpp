// Runner-owned MethodChannel bridge for the floating button (ADR 0002 Phase 2).
//
// Migration from GDI+ drawing (Phase 1) to second Flutter engine (Phase 2).
// Mirrors the already-shipped macOS FloatingButtonHost.swift (commit da35f51d).
//
// Architecture:
//   Main engine  ──[com.whispaste.floating_button]──▶ FloatingButtonHost
//                ◀─[onClicked / onDragEnded / ...]───
//
//   FloatingButtonHost ──[com.whispaste.floating_button_render]──▶ Dart
//                       ◀─[clicked / startDrag / showContextMenu / ready]───
//
// Plugin registration decision:
//   The render engine (floatingButtonMain) only uses the private render
//   MethodChannel and NO Flutter plugins (no window_manager, no
//   flutter_acrylic calls from this engine, no tray, etc.). Calling
//   RegisterPlugins() on the render engine would attempt to re-register
//   singletons that are already alive on the main engine, which can cause
//   crashes or duplicate state. macOS made the same call and did NOT register
//   plugins on the second engine. We follow that precedent.
//   If a plugin is needed on the render side in the future, register it
//   explicitly with the render engine's messenger only.
//
// Drag approach:
//   Dart fires "startDrag" when the user starts panning the button. We use
//   the classic ReleaseCapture / WM_NCLBUTTONDOWN(HTCAPTION) trick so the OS
//   handles the move loop natively. When the loop ends we read the final shell
//   window position and fire onDragEnded{x,y} to Dart.
//   Alternative (SetCapture + WM_MOUSEMOVE loop) was not chosen because the
//   gesture originates in Dart/Flutter input, not from a raw WM_LBUTTONDOWN
//   that we received — so we cannot reliably reconstruct the capture state.

#include "floating_button_host.h"

#include <flutter/encodable_value.h>

#include <algorithm>
#include <iterator>
#include <string>

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.floating_button";
constexpr char kRenderChannelName[] = "com.whispaste.floating_button_render";

// Preset ids the render engine understands (overlay_design_spec.dart). Any
// other value from the method channel is replaced by the default before it is
// cached or relayed.
constexpr const char* kBackgroundPresets[] = {"marine", "graphit", "gletscher", "amber"};
constexpr const char* kWavePresets[] = {"cyan", "violett", "ink", "amber", "coral", "mint"};

template <size_t N>
std::string KnownPreset(const std::string& value,
                        const char* const (&known)[N], const char* fallback) {
  const bool is_known = std::any_of(
      std::begin(known), std::end(known),
      [&value](const char* id) { return value == id; });
  return is_known ? value : fallback;
}

// ── EncodableMap helpers (unchanged from Phase 1) ────────────────────

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

int GetInt(const EncodableMap& map, const std::string& key, int fallback = 0) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (auto* l = std::get_if<int64_t>(&it->second))
    return static_cast<int>(*l);
  if (auto* d = std::get_if<double>(&it->second))
    return static_cast<int>(*d);
  return fallback;
}

std::string GetString(const EncodableMap& map, const std::string& key,
                      const std::string& fallback = "") {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* s = std::get_if<std::string>(&it->second)) return *s;
  return fallback;
}

bool GetBool(const EncodableMap& map, const std::string& key,
             bool fallback = true) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto* b = std::get_if<bool>(&it->second)) return *b;
  return fallback;
}

}  // namespace

// ══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ══════════════════════════════════════════════════════════════════════

FloatingButtonHost::FloatingButtonHost(flutter::FlutterEngine* main_engine,
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

  OutputDebugStringW(L"[FloatingButton] Host created (Phase 2 / Flutter engine)\n");
}

FloatingButtonHost::~FloatingButtonHost() { Destroy(); }

void FloatingButtonHost::Destroy() {
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
  if (render_controller_) {
    render_controller_.reset();
  }
  render_project_.reset();
  render_ready_ = false;

  OutputDebugStringW(L"[FloatingButton] Host destroyed\n");
}

void FloatingButtonHost::RefreshTopmost() {
  if (!destroyed_ && window_) window_->RefreshTopmost();
}

// ══════════════════════════════════════════════════════════════════════
// Lazy engine + shell creation
// ══════════════════════════════════════════════════════════════════════

bool FloatingButtonHost::EnsureEngineAndShell(double lx, double ly,
                                              int disc_size) {
  if (render_controller_) return true;  // already booted

  render_ready_ = false;

  // ── Boot the render engine ─────────────────────────────────────────
  // DartProject("data") is the relative path to the Flutter assets/icudtl.
  // The Windows embedder resolves it relative to the executable.
  auto project = std::make_unique<flutter::DartProject>(L"data");
  project->set_dart_entrypoint("floatingButtonMain");

  // Total shell size = disc + 2 * shadowPadding (8 px each side).
  int total_size = disc_size + 16;

  // Create the Flutter view controller at the total window size.
  // The controller creates both the engine and the view HWND.
  auto controller = std::make_unique<flutter::FlutterViewController>(
      total_size, total_size, *project);

  if (!controller->engine() || !controller->view()) {
    OutputDebugStringW(
        L"[FloatingButton] Render engine / view creation failed\n");
    return false;
  }

  // Plugin registration: intentionally skipped for the render engine.
  // See file-level comment for rationale.

  // ── Render MethodChannel ────────────────────────────────────────────
  auto render_ch =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          controller->engine()->messenger(), kRenderChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  render_ch->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleRenderCall(call, std::move(result));
      });

  // ── Create the shell window ────────────────────────────────────────
  HWND flutter_child = controller->view()->GetNativeWindow();

  auto shell = std::make_unique<FloatingButtonWindow>();
  if (!shell->Create(owner_, lx, ly, total_size, flutter_child)) {
    OutputDebugStringW(L"[FloatingButton] Shell window creation failed\n");
    // render_ch and controller cleaned up by unique_ptr destructors.
    return false;
  }

  // Wire drag-end callback: after the OS move-loop ends, report the final
  // position back to Dart. This is called from BeginDrag() below.
  shell->SetDragEndCallback([this](double fin_x, double fin_y) {
    EncodableMap m;
    m[EncodableValue("x")] = EncodableValue(fin_x);
    m[EncodableValue("y")] = EncodableValue(fin_y);
    SendEvent("onDragEnded", EncodableValue(m));
  });

  render_project_ = std::move(project);
  render_controller_ = std::move(controller);
  render_channel_ = std::move(render_ch);
  window_ = std::move(shell);

  OutputDebugStringW(
      L"[FloatingButton] Render engine booted, shell created\n");
  return true;
}

// ══════════════════════════════════════════════════════════════════════
// Public MethodChannel handler (Dart main engine → C++)
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "FloatingButtonHost is destroyed");
    return;
  }

  const auto& method = call.method_name();
  const auto* args = call.arguments();
  const EncodableMap* map =
      args ? std::get_if<EncodableMap>(args) : nullptr;

  // ── show ────────────────────────────────────────────────────────────
  if (method == "show") {
    double x = map ? GetDouble(*map, "x", 200.0) : 200.0;
    double y = map ? GetDouble(*map, "y", 200.0) : 200.0;
    int size = map ? GetInt(*map, "size", 56) : 56;

    latest_disc_size_ = size;

    if (!EnsureEngineAndShell(x, y, size)) {
      result->Error("CREATE_FAILED",
                    "Failed to create render engine / shell window");
      return;
    }

    // On re-show: update position + size if args changed.
    if (map) {
      if (x >= 0 && y >= 0) window_->SetPosition(x, y);
      int total = size + 16;
      window_->SetTotalSize(total);
      // Relay diameter to render engine if it is already ready.
      if (render_ready_) {
        RelaySetDiameter(size);
      }
    }

    window_->Show();
    result->Success();
    return;
  }

  // ── hide ────────────────────────────────────────────────────────────
  if (method == "hide") {
    if (window_) window_->Hide();
    result->Success();
    return;
  }

  // ── setState ────────────────────────────────────────────────────────
  if (method == "setState") {
    if (map) {
      latest_state_ = GetString(*map, "state", "idle");
      if (render_ready_) RelaySetState(latest_state_);
    }
    result->Success();
    return;
  }

  // ── setTheme ────────────────────────────────────────────────────────
  // WP-75: background and wave presets, cached so the ready flush can
  // replay them.
  if (method == "setTheme") {
    if (map) {
      latest_background_ =
          KnownPreset(GetString(*map, "background", "marine"),
                      kBackgroundPresets, "marine");
      latest_wave_ =
          KnownPreset(GetString(*map, "wave", "cyan"), kWavePresets, "cyan");
      // WP-95 button look. Opacity is clamped to the 40-100 % presets.
      latest_shape_ =
          GetString(*map, "shape", "round") == "square" ? "square" : "round";
      latest_ring_ = GetBool(*map, "ring", true);
      double idle = GetDouble(*map, "idleOpacity", 1.0);
      latest_idle_opacity_ = idle < 0.4 ? 0.4 : (idle > 1.0 ? 1.0 : idle);
      if (render_ready_) RelaySetTheme(latest_background_, latest_wave_);
    }
    result->Success();
    return;
  }

  // ── setPosition ─────────────────────────────────────────────────────
  if (method == "setPosition") {
    if (window_ && map) {
      window_->SetPosition(GetDouble(*map, "x"), GetDouble(*map, "y"));
    }
    result->Success();
    return;
  }

  // ── setSize ─────────────────────────────────────────────────────────
  if (method == "setSize") {
    if (map) {
      int size = GetInt(*map, "size", 56);
      latest_disc_size_ = size;
      if (window_) window_->SetTotalSize(size + 16);
      if (render_ready_) RelaySetDiameter(size);
    }
    result->Success();
    return;
  }

  // ── setOpacity ──────────────────────────────────────────────────────
  // Opacity was removed in issue 11. Accept the call as a no-op so old
  // Dart code that still sends it does not produce an error.
  if (method == "setOpacity") {
    result->Success();
    return;
  }

  // ── setContextMenuItems ─────────────────────────────────────────────
  // Preserve the exact "items" key unwrapping from Phase 1.
  if (method == "setContextMenuItems") {
    auto* args_map = std::get_if<EncodableMap>(call.arguments());
    if (args_map) {
      auto it = args_map->find(EncodableValue("items"));
      if (it != args_map->end()) {
        auto* list = std::get_if<EncodableList>(&it->second);
        if (list) {
          std::vector<std::pair<std::string, std::wstring>> items;
          for (auto& item_val : *list) {
            auto* item_map = std::get_if<EncodableMap>(&item_val);
            if (!item_map) continue;
            auto id_it = item_map->find(EncodableValue("id"));
            auto label_it = item_map->find(EncodableValue("label"));
            if (id_it == item_map->end() || label_it == item_map->end())
              continue;
            auto* id_str = std::get_if<std::string>(&id_it->second);
            auto* label_str = std::get_if<std::string>(&label_it->second);
            if (!id_str || !label_str) continue;
            // Convert UTF-8 label to wstring for TrackPopupMenu.
            int len = MultiByteToWideChar(CP_UTF8, 0, label_str->c_str(),
                                          -1, nullptr, 0);
            // 0 means the UTF-8 is invalid; skip the entry rather than size
            // the wstring from a failed conversion.
            if (len <= 0) continue;
            std::wstring wlabel(len - 1, 0);
            MultiByteToWideChar(CP_UTF8, 0, label_str->c_str(), -1,
                                wlabel.data(), len);
            items.emplace_back(*id_str, std::move(wlabel));
          }
          context_menu_items_ = std::move(items);
          // Keep the shell's copy in sync (used if the host needs it later).
          if (window_) window_->SetContextMenuItems(context_menu_items_);
        }
      }
    }
    result->Success();
    return;
  }

  // ── getPosition ─────────────────────────────────────────────────────
  if (method == "getPosition") {
    if (window_) {
      auto [x, y] = window_->GetPosition();
      EncodableMap m;
      m[EncodableValue("x")] = EncodableValue(x);
      m[EncodableValue("y")] = EncodableValue(y);
      result->Success(EncodableValue(m));
    } else {
      result->Success();
    }
    return;
  }

  // ── rebootRenderEngine ──────────────────────────────────────────────
  // Dart's frame heartbeat found no painted frame after its re-push (see
  // FloatingButtonService). Re-boots only the render engine, like
  // FloatingButtonHost.swift: a fresh shell takes the old position and
  // visibility, and the new engine's `ready` flushes the cached state.
  if (method == "rebootRenderEngine") {
    if (!render_controller_ || !window_) {
      result->Success();
      return;
    }
    OutputDebugStringW(
        L"[FloatingButton] rebootRenderEngine: re-booting on request\n");
    const bool was_visible = window_->IsVisible();
    const auto [x, y] = window_->GetPosition();
    render_channel_->SetMethodCallHandler(nullptr);
    render_channel_.reset();
    window_->Destroy();
    window_.reset();
    render_controller_.reset();
    render_project_.reset();
    render_ready_ = false;
    // EnsureEngineAndShell can report success without a shell (its
    // already-booted shortcut), so the shell is checked, not assumed.
    if (EnsureEngineAndShell(x, y, latest_disc_size_) && window_ &&
        was_visible) {
      window_->Show();
    }
    result->Success();
    return;
  }

  // ── destroy ─────────────────────────────────────────────────────────
  if (method == "destroy") {
    // Tear down the render engine and shell but keep the host alive
    // (it still needs to handle future show() calls if Dart re-creates).
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
    result->Success();
    return;
  }

  result->NotImplemented();
}

// ══════════════════════════════════════════════════════════════════════
// Render-engine MethodChannel handler (render Dart → C++ → main Dart)
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::HandleRenderCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();

  // ── ready ────────────────────────────────────────────────────────────
  // The render engine's Dart MethodChannel handler is now live — flush
  // the cached state so the first visible frame is never lost to the boot
  // race. Mirrors macOS handleRenderCall("ready").
  if (method == "ready") {
    OutputDebugStringW(
        L"[FloatingButton] Render engine ready — flushing cached state\n");
    render_ready_ = true;
    RelaySetState(latest_state_);
    RelaySetDiameter(latest_disc_size_);
    RelaySetTheme(latest_background_, latest_wave_);
    result->Success();
    return;
  }

  // ── clicked ──────────────────────────────────────────────────────────
  if (method == "clicked") {
    SendEvent("onClicked");
    result->Success();
    return;
  }

  // ── startDrag ────────────────────────────────────────────────────────
  // Dart fires this when the user starts a pan gesture on the disc.
  // We use the NCLBUTTONDOWN/HTCAPTION trick: the OS takes over the move
  // loop, and when it ends we read the final position from the shell window.
  if (method == "startDrag") {
    BeginDrag();
    result->Success();
    return;
  }

  // ── showContextMenu ──────────────────────────────────────────────────
  if (method == "showContextMenu") {
    ShowNativeContextMenu();
    result->Success();
    return;
  }

  // ── frameRendered ────────────────────────────────────────────────────
  if (method == "frameRendered") {
    // Frame heartbeat, relayed like the macOS host. The Dart service runs
    // its stall recovery only for controllers that can re-boot the engine
    // (macOS so far); elsewhere the event only ends a pending deadline.
    SendEvent("onRenderFrame");
    result->Success();
    return;
  }

  // ── reportError ──────────────────────────────────────────────────────
  if (method == "reportError") {
    // Uncaught Dart error inside the render engine: relay it to the main
    // engine's log, as the macOS host and the snippet picker do.
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
    OutputDebugStringW(L"[FloatingButton] Render engine reported an error\n");
    result->Success();
    return;
  }

  result->NotImplemented();
}

// ══════════════════════════════════════════════════════════════════════
// Drag
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::BeginDrag() {
  if (!window_ || !window_->GetHandle()) return;
  HWND hwnd = window_->GetHandle();

  // Release any existing mouse capture (Flutter may hold it).
  ReleaseCapture();

  // Synthesise an NCLBUTTONDOWN on HTCAPTION so Windows moves the window.
  // The OS enters its internal move loop synchronously; when the user releases
  // the button the SendMessage returns and we can read the final position.
  //
  // This approach requires the cursor to already be inside the window —
  // which is guaranteed because Dart's onPanStart fires from a pointer event
  // that was on the disc. PostMessage could also be used if we need to
  // return from this function before the drag ends (non-blocking), but the
  // synchronous SendMessage gives us the final position immediately on return.
  SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);

  // Move loop has ended. Read the final position.
  RECT rc;
  GetWindowRect(hwnd, &rc);
  // The position is the window's top-left in logical pixels, the same origin
  // as macOS and Linux, Dart's WindowPositionClamp and the `show` / `setPosition`
  // calls. Reporting the centre here shifted the button by half its diameter
  // every time it was re-shown after a drag.
  UINT dpi = GetDpiForWindow(hwnd);
  double dpi_scale = (dpi > 0) ? dpi / 96.0 : 1.0;
  double fin_x = rc.left / dpi_scale;
  double fin_y = rc.top / dpi_scale;

  // Update the shell's logical position so getPosition() is consistent.
  window_->SetPosition(fin_x, fin_y);

  EncodableMap m;
  m[EncodableValue("x")] = EncodableValue(fin_x);
  m[EncodableValue("y")] = EncodableValue(fin_y);
  SendEvent("onDragEnded", EncodableValue(m));
}

// ══════════════════════════════════════════════════════════════════════
// Native context menu
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::ShowNativeContextMenu() {
  if (context_menu_items_.empty()) {
    // No items configured — fall back to secondary-click event, mirroring
    // macOS behaviour.
    SendEvent("onSecondaryClicked");
    return;
  }

  HMENU menu = CreatePopupMenu();
  for (size_t i = 0; i < context_menu_items_.size(); ++i) {
    const auto& wlabel = context_menu_items_[i].second;
    if (wlabel == L"---") {
      // "---" is the separator convention (matches macOS).
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    } else {
      AppendMenuW(menu, MF_STRING, static_cast<UINT_PTR>(1000 + i),
                  wlabel.c_str());
    }
  }

  POINT pt;
  GetCursorPos(&pt);

  // TPM_RETURNCMD returns the selected item ID instead of posting WM_COMMAND.
  int cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN,
                           pt.x, pt.y, 0,
                           window_ ? window_->GetHandle() : owner_,
                           nullptr);
  DestroyMenu(menu);

  if (cmd >= 1000 && cmd < 1000 + static_cast<int>(context_menu_items_.size())) {
    const auto& selected_id = context_menu_items_[cmd - 1000].first;
    EncodableMap m;
    m[EncodableValue("id")] = EncodableValue(selected_id);
    SendEvent("onContextMenu", EncodableValue(m));
  }
}

// ══════════════════════════════════════════════════════════════════════
// Relay helpers → render engine
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::RelaySetState(const std::string& state) {
  if (!render_channel_) return;
  EncodableMap m;
  m[EncodableValue("state")] = EncodableValue(state);
  render_channel_->InvokeMethod("setState",
                                std::make_unique<EncodableValue>(m));
}

void FloatingButtonHost::RelaySetDiameter(int disc_size) {
  if (!render_channel_) return;
  EncodableMap m;
  m[EncodableValue("diameter")] = EncodableValue(static_cast<double>(disc_size));
  render_channel_->InvokeMethod("setDiameter",
                                std::make_unique<EncodableValue>(m));
}

void FloatingButtonHost::RelaySetTheme(const std::string& background,
                                       const std::string& wave) {
  if (!render_channel_) return;
  EncodableMap m;
  m[EncodableValue("background")] = EncodableValue(background);
  m[EncodableValue("wave")] = EncodableValue(wave);
  m[EncodableValue("shape")] = EncodableValue(latest_shape_);
  m[EncodableValue("ring")] = EncodableValue(latest_ring_);
  m[EncodableValue("idleOpacity")] = EncodableValue(latest_idle_opacity_);
  render_channel_->InvokeMethod("setTheme",
                                std::make_unique<EncodableValue>(m));
}

// ══════════════════════════════════════════════════════════════════════
// Events (C++ → main Dart engine)
// ══════════════════════════════════════════════════════════════════════

void FloatingButtonHost::SendEvent(const std::string& method,
                                   const EncodableValue& args) {
  if (destroyed_ || !channel_) return;
  channel_->InvokeMethod(method, std::make_unique<EncodableValue>(args));
}

void FloatingButtonHost::SendEvent(const std::string& method) {
  SendEvent(method, EncodableValue());
}
