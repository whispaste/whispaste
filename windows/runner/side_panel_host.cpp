#include "side_panel_host.h"

#include <flutter/encodable_value.h>
#include <flutter_windows.h>

#include <algorithm>
#include <cmath>
#include <string>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "com.whispaste.side_panel";
constexpr char kRenderChannelName[] = "com.whispaste.side_panel_render";

// SetTimer's TIMERPROC callback carries no user-data slot (unlike WM_TIMER
// delivered through a window's own WndProc, which recovers `this` via
// GWLP_USERDATA the way SidePanelContentWindow's animation timer does) --
// see NativeCloseTimerProc below. Exactly one SidePanelHost exists at a
// time (owned by FlutterWindow), so a single translation-unit-local pointer
// set in the constructor and cleared in Destroy() is sufficient; this does
// not need to be a class member.
SidePanelHost* g_active_host_for_close_timer = nullptr;

// Collects every connected monitor -- same idiom as
// floating_overlay_window.cpp's NearestMonitorEnumProc, just gathering all
// handles instead of picking the nearest one (mirrors NSScreen.screens).
BOOL CALLBACK CollectMonitorsProc(HMONITOR hmon, HDC /*hdc*/,
                                  LPRECT /*rect*/, LPARAM lparam) {
  auto* monitors = reinterpret_cast<std::vector<HMONITOR>*>(lparam);
  monitors->push_back(hmon);
  return TRUE;
}

// Convert a UTF-8 std::string into a wide string for OutputDebugStringW.
// Mirrors desktop_paste_host.cpp's Utf8ToWide (kept file-local rather than
// shared -- both copies are small and this file otherwise has no dependency
// on desktop_paste_host.h).
std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int needed = ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                                     static_cast<int>(utf8.size()), nullptr,
                                     0);
  if (needed <= 0) return std::wstring();
  std::wstring wide(static_cast<size_t>(needed), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(),
                        static_cast<int>(utf8.size()), wide.data(), needed);
  return wide;
}

}  // namespace

// ══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ══════════════════════════════════════════════════════════════════════

SidePanelHost::SidePanelHost(flutter::FlutterEngine* main_engine, HWND owner)
    : main_engine_(main_engine), owner_(owner) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      main_engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });

  g_active_host_for_close_timer = this;

  // Mirrors SidePanelHost.swift's init calling rebuildSensors() up front --
  // the sensor strips exist for the whole app session, independent of
  // whether the panel itself has ever been opened.
  RebuildSensors();

  OutputDebugStringW(L"[SidePanel] Host created\n");
}

SidePanelHost::~SidePanelHost() { Destroy(); }

void SidePanelHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  CancelNativeClose();
  if (g_active_host_for_close_timer == this) {
    g_active_host_for_close_timer = nullptr;
  }

  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  if (render_channel_) {
    render_channel_->SetMethodCallHandler(nullptr);
    render_channel_.reset();
  }
  if (content_window_) {
    content_window_->Destroy();
    content_window_.reset();
  }
  if (render_controller_) {
    render_controller_.reset();
  }
  render_project_.reset();

  sensors_.clear();

  render_ready_ = false;
  latest_snapshot_args_.reset();
  is_shown_ = false;
  current_work_area_.reset();
  pending_rect_.reset();

  OutputDebugStringW(L"[SidePanel] Host destroyed\n");
}

// ══════════════════════════════════════════════════════════════════════
// Sensor strips (one per monitor)
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::RebuildSensors() {
  // Guards against a WM_DISPLAYCHANGE landing between a Dart-driven
  // "destroy" (HandleMethodCall) and FlutterWindow::OnDestroy() resetting
  // the owning unique_ptr -- without this, a destroyed host would silently
  // resurrect a fresh set of native sensor windows whose events all no-op
  // in SendEvent (destroyed_ check), leaking window handles for nothing.
  if (destroyed_) return;

  // Destroying and recreating on every call (rather than diffing) mirrors
  // SidePanelHost.swift's rebuildSensors: `sensors.forEach { $0.orderOut
  // (nil) }` followed by a fresh `NSScreen.screens.map`.
  sensors_.clear();

  std::vector<HMONITOR> monitors;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitorsProc,
                      reinterpret_cast<LPARAM>(&monitors));

  for (HMONITOR hmon : monitors) {
    MONITORINFO mi = {};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(hmon, &mi)) continue;
    const RECT wa = mi.rcWork;

    UINT dpi = FlutterDesktopGetDpiForMonitor(hmon);
    double scale = (dpi > 0) ? dpi / 96.0 : 1.0;
    int width = static_cast<int>(std::round(kSensorWidth * scale));

    auto sensor = std::make_unique<SidePanelSensorWindow>();
    bool created = sensor->Create(wa.left, wa.top, width, wa.bottom - wa.top,
                                  kDwellMs);
    if (!created) {
      OutputDebugStringW(L"[SidePanel] Sensor creation failed for a monitor\n");
      continue;
    }

    // Captured by value -- this monitor's work area is fixed for the
    // lifetime of this sensor; a real geometry change comes back through
    // WM_DISPLAYCHANGE -> RebuildSensors(), which replaces the whole vector
    // (and therefore this callback) anyway.
    sensor->on_hover_entered = [this, wa]() { HandleHoverEntered(wa); };
    sensor->on_raw_enter = [this]() { HandleRawEnter(); };
    sensor->on_raw_exit = [this]() { HandleRawExit(); };

    sensors_.push_back(std::move(sensor));
  }

  OutputDebugStringW(L"[SidePanel] Sensors rebuilt\n");
}

void SidePanelHost::HandleHoverEntered(const RECT& work_area) {
  PositionPanel(work_area);
  SendEvent("hoverEntered");
}

void SidePanelHost::HandleRawEnter() { CancelNativeClose(); }

void SidePanelHost::HandleRawExit() { ScheduleNativeClose(); }

// ══════════════════════════════════════════════════════════════════════
// Content-window hover (native close-grace fallback)
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::HandleContentEnter() { CancelNativeClose(); }

void SidePanelHost::HandleContentExit() { ScheduleNativeClose(); }

void SidePanelHost::ScheduleNativeClose() {
  CancelNativeClose();
  SetTimer(owner_, kCloseTimerId, static_cast<UINT>(kCloseGraceMs),
           NativeCloseTimerProc);
  close_timer_armed_ = true;
}

void SidePanelHost::CancelNativeClose() {
  if (!close_timer_armed_) return;
  KillTimer(owner_, kCloseTimerId);
  close_timer_armed_ = false;
}

void CALLBACK SidePanelHost::NativeCloseTimerProc(HWND hwnd, UINT /*msg*/,
                                                  UINT_PTR id, DWORD /*time*/) {
  KillTimer(hwnd, id);
  if (!g_active_host_for_close_timer) return;
  SidePanelHost* host = g_active_host_for_close_timer;
  host->close_timer_armed_ = false;

  // Fire-point guard: once the content window covers the sensor's screen
  // point, TrackMouseEvent reports the sensor strip as "left" (WindowFromPoint
  // now resolves to the content window) even though the pointer never
  // physically moved, which keeps re-arming this timer via
  // HandleRawExit/HandleContentExit. Rather than chase every message race
  // that can (re-)arm the timer, make the final call here, at the one place
  // the irreversible close decision actually happens.
  if (host->content_window_ && host->content_window_->visible() &&
      host->content_window_->hwnd()) {
    POINT cursor;
    RECT rect;
    if (GetCursorPos(&cursor) &&
        GetWindowRect(host->content_window_->hwnd(), &rect) &&
        PtInRect(&rect, cursor)) {
      return;  // Pointer is still over the panel -- don't close.
    }
  }

  // Relay to the main engine; SidePanelService.close() replies with
  // updateSnapshot(visible:false), which is what actually triggers
  // SlideOut() -- the native side never unilaterally hides the panel
  // itself. Mirrors SidePanelHost.swift's scheduleNativeClose.
  host->SendEvent("hoverLeft");
}

// ══════════════════════════════════════════════════════════════════════
// Layout
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::ComputeTargetRect(const RECT& work_area, bool shown,
                                      int* px, int* py, int* pwidth,
                                      int* pheight) const {
  HMONITOR mon = MonitorFromRect(&work_area, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(mon);
  double scale = (dpi > 0) ? dpi / 96.0 : 1.0;

  const int wa_height = static_cast<int>(work_area.bottom - work_area.top);
  const int width = static_cast<int>(std::round(kContentWidth * scale));
  // Clamped to the monitor's own work-area height (issue 08) -- mirrors
  // SidePanelHost.swift's targetRect: `min(contentHeight, screenFrame
  // .height)`.
  const int height =
      std::min(static_cast<int>(std::round(kContentHeight * scale)),
               wa_height);

  // Resting x is flush with the work area's left edge; the just-off-edge
  // staging x is exactly one panel-width to the left -- see targetRect's
  // doc comment on SidePanelHost.swift for why no sensor-strip offset is
  // needed here.
  const int x =
      shown ? static_cast<int>(work_area.left)
            : static_cast<int>(work_area.left) - width;
  const int y = static_cast<int>(work_area.top) + (wa_height - height) / 2;

  *px = x;
  *py = y;
  *pwidth = width;
  *pheight = height;
}

void SidePanelHost::PositionPanel(const RECT& work_area) {
  current_work_area_ = work_area;

  int px, py, pwidth, pheight;
  ComputeTargetRect(work_area, /*shown=*/false, &px, &py, &pwidth, &pheight);
  const RECT rect = {px, py, px + pwidth, py + pheight};

  if (content_window_ && !is_shown_) {
    // Not currently shown -- safe to relocate without a visible jump (e.g.
    // the user hovered a different monitor's edge this time). Mirrors
    // SidePanelHost.swift's positionPanel.
    content_window_->SetRect(px, py, pwidth, pheight);
  } else if (!content_window_) {
    pending_rect_ = rect;
  }
}

// ══════════════════════════════════════════════════════════════════════
// Lazy engine + shell creation
// ══════════════════════════════════════════════════════════════════════

bool SidePanelHost::EnsureEngineAndShell() {
  if (render_controller_) return true;  // already booted

  render_ready_ = false;

  RECT rect;
  if (pending_rect_) {
    rect = *pending_rect_;
    pending_rect_.reset();
  } else {
    // No prior hover-enter to size against -- shouldn't normally happen,
    // since updateSnapshot(visible:true) is only ever sent after
    // hoverEntered has primed the main engine, but mirrors
    // SidePanelHost.swift's `pendingFrame ?? NSRect(x:0,y:0,contentWidth,
    // contentHeight)` fallback rather than failing outright.
    rect = {0, 0, kContentWidth, kContentHeight};
  }
  const int pwidth = rect.right - rect.left;
  const int pheight = rect.bottom - rect.top;

  // DartProject("data") resolves relative to the executable, same as every
  // other second-engine shell in this runner.
  auto project = std::make_unique<flutter::DartProject>(L"data");
  // Declared in lib/main.dart (root library, reused verbatim from macOS --
  // see that file's doc comment on why it must live at the root).
  project->set_dart_entrypoint("sidePanelMain");

  auto controller = std::make_unique<flutter::FlutterViewController>(
      pwidth, pheight, *project);

  if (!controller->engine() || !controller->view()) {
    OutputDebugStringW(
        L"[SidePanel] Render engine / view creation failed\n");
    return false;
  }

  // Plugin registration intentionally skipped -- see floating_button_host
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

  auto shell = std::make_unique<SidePanelContentWindow>();
  if (!shell->Create(rect.left, rect.top, pwidth, pheight, flutter_child)) {
    OutputDebugStringW(L"[SidePanel] Content shell creation failed\n");
    return false;
  }

  shell->on_content_enter = [this]() { HandleContentEnter(); };
  shell->on_content_exit = [this]() { HandleContentExit(); };

  // Captures the raw controller pointer, not a shared_ptr: render_controller_
  // outlives content_window_ (destroyed after it in Destroy()), so the
  // callback is never invoked past the controller's lifetime -- same
  // reasoning as SnippetPickerHost::EnsureEngineAndShell.
  flutter::FlutterViewController* render_controller_ptr = controller.get();
  shell->forward_to_flutter = [render_controller_ptr](
                                  HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    return render_controller_ptr->HandleTopLevelWindowProc(hwnd, msg, wp, lp);
  };

  render_project_ = std::move(project);
  render_controller_ = std::move(controller);
  render_channel_ = std::move(render_ch);
  content_window_ = std::move(shell);

  OutputDebugStringW(
      L"[SidePanel] Render engine booted, content shell created\n");
  return true;
}

// ══════════════════════════════════════════════════════════════════════
// Slide animation
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::SlideIn() {
  if (!content_window_ || !current_work_area_) return;

  // The panel is opening in direct response to a genuine hover-dwell, so any
  // native close armed by the pointer leaving the sensor strip on its way
  // here (HandleRawExit -> ScheduleNativeClose) is stale. Win32 synthesizes
  // no enter for a stationary pointer the panel appears underneath -- unlike
  // AppKit, which reconciles tracking areas on order-front -- so without
  // this the close-grace timer can still fire ~350ms after open even though
  // the pointer never left the panel.
  CancelNativeClose();

  int staging_x, staging_y, staging_w, staging_h;
  ComputeTargetRect(*current_work_area_, /*shown=*/false, &staging_x,
                    &staging_y, &staging_w, &staging_h);
  int shown_x, shown_y, shown_w, shown_h;
  ComputeTargetRect(*current_work_area_, /*shown=*/true, &shown_x, &shown_y,
                    &shown_w, &shown_h);

  // width/height are identical between the two calls (only x differs) --
  // same work area, same `shown` flag only changes x above.
  content_window_->SlideIn(staging_x, shown_x, shown_y, shown_w, shown_h,
                           kSlideDurationMs);
}

void SidePanelHost::SlideOut() {
  if (!content_window_ || !current_work_area_) return;

  int staging_x, staging_y, staging_w, staging_h;
  ComputeTargetRect(*current_work_area_, /*shown=*/false, &staging_x,
                    &staging_y, &staging_w, &staging_h);

  content_window_->SlideOut(staging_x, kSlideDurationMs);
}

// ══════════════════════════════════════════════════════════════════════
// Public MethodChannel handler (Dart main engine -> C++)
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (destroyed_) {
    result->Error("DESTROYED", "SidePanelHost is destroyed");
    return;
  }

  const auto& method = call.method_name();

  if (method == "updateSnapshot") {
    const auto* args_map = std::get_if<EncodableMap>(call.arguments());
    if (args_map) {
      HandleUpdateSnapshot(*args_map);
    }
    result->Success();
    return;
  }

  if (method == "destroy") {
    // Full teardown -- mirrors SidePanelHost.swift's `case "destroy":
    // teardown()`. Unlike SnippetPickerHost's "destroy" (which keeps the
    // host/public channel alive for a future re-boot), side_panel_host.h
    // exposes only the one Destroy(), so this method call and the
    // FlutterWindow::OnDestroy() teardown path both end up here -- safe,
    // Destroy() is idempotent.
    Destroy();
    result->Success();
    return;
  }

  result->NotImplemented();
}

void SidePanelHost::HandleUpdateSnapshot(const EncodableMap& args) {
  bool visible = false;
  auto it = args.find(EncodableValue("visible"));
  if (it != args.end()) {
    if (const auto* b = std::get_if<bool>(&it->second)) visible = *b;
  }
  if (visible && !content_window_) {
    // Mirrors SidePanelHost.swift's `if visible && contentPanel == nil {
    // ensurePanel() }`.
    if (!EnsureEngineAndShell()) {
      OutputDebugStringW(
          L"[SidePanel] updateSnapshot(visible:true) could not boot render "
          L"engine/shell\n");
      return;
    }
  }

  latest_snapshot_args_ = args;
  if (render_ready_) {
    RelayUpdateSnapshot(args);
  }

  if (visible && !is_shown_) {
    is_shown_ = true;
    SlideIn();
  } else if (!visible && is_shown_) {
    is_shown_ = false;
    SlideOut();
  }
}

// ══════════════════════════════════════════════════════════════════════
// Render-engine MethodChannel handler (render Dart -> C++ -> main Dart)
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::HandleRenderCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();

  // ── ready ────────────────────────────────────────────────────────────
  if (method == "ready") {
    OutputDebugStringW(
        L"[SidePanel] Render engine ready -- flushing cached snapshot\n");
    render_ready_ = true;
    if (latest_snapshot_args_) {
      RelayUpdateSnapshot(*latest_snapshot_args_);
    }
    result->Success();
    return;
  }

  // ── rowClicked ───────────────────────────────────────────────────────
  if (method == "rowClicked") {
    const auto* args = call.arguments();
    if (args) {
      SendEvent("rowClicked", *args);
    } else {
      SendEvent("rowClicked");
    }
    result->Success();
    return;
  }

  // ── hoverLeft ────────────────────────────────────────────────────────
  if (method == "hoverLeft") {
    // Relay to the main engine; SidePanelService.close() replies with
    // updateSnapshot(visible:false), which is what actually triggers
    // SlideOut() above -- keeps the single animate-then-hide path instead
    // of a second, uncoordinated immediate hide here. Mirrors
    // SidePanelHost.swift's handleRenderCall("hoverLeft").
    SendEvent("hoverLeft");
    result->Success();
    return;
  }

  // ── reportError ──────────────────────────────────────────────────────
  if (method == "reportError") {
    // Logged only -- unlike SnippetPickerHost, the public channel contract
    // (see this file's header comment) has no onRenderEngineDiagnostic
    // equivalent to forward to. Mirrors SidePanelHost.swift's `case
    // "reportError": os_log(...)`.
    const auto* args_map = std::get_if<EncodableMap>(call.arguments());
    std::wstring detail;
    if (args_map) {
      auto it = args_map->find(EncodableValue("message"));
      if (it != args_map->end()) {
        if (const auto* s = std::get_if<std::string>(&it->second)) {
          detail = Utf8ToWide(*s);
        }
      }
    }
    OutputDebugStringW((L"[SidePanel] Render engine reported an error: " +
                        (detail.empty() ? L"(no message)" : detail) + L"\n")
                           .c_str());
    result->Success();
    return;
  }

  result->NotImplemented();
}

// ══════════════════════════════════════════════════════════════════════
// Relay helpers -> render engine
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::RelayUpdateSnapshot(const EncodableMap& args) {
  if (!render_channel_) return;
  render_channel_->InvokeMethod(
      "updateSnapshot", std::make_unique<EncodableValue>(EncodableValue(args)));
}

// ══════════════════════════════════════════════════════════════════════
// Events (C++ -> main Dart engine)
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::SendEvent(const std::string& method,
                              const EncodableValue& args) {
  if (destroyed_ || !channel_) return;
  channel_->InvokeMethod(method, std::make_unique<EncodableValue>(args));
}

void SidePanelHost::SendEvent(const std::string& method) {
  SendEvent(method, EncodableValue());
}
