#include "side_panel_host.h"

#include <gdk-pixbuf/gdk-pixbuf.h>
#include <gdk/gdk.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "clipboard_receipt.h"

namespace {

constexpr char kChannelName[] = "com.whispaste.side_panel";
constexpr char kRenderChannelName[] = "com.whispaste.side_panel_render";
constexpr char kClipboardChannelName[] = "com.whispaste.clipboard_history";

// FNV-1a, 64-bit -- bit-for-bit identical to Dart's `_fnv1a64`
// (clipboard_fingerprint.dart) and the macOS/Windows native mirrors.
uint64_t Fnv1a64(const uint8_t* bytes, size_t length) {
  uint64_t hash = 0xcbf29ce484222325ULL;
  constexpr uint64_t kPrime = 0x100000001b3ULL;
  for (size_t i = 0; i < length; ++i) {
    hash ^= bytes[i];
    hash *= kPrime;
  }
  return hash;
}

// Reads a byte list argument. Dart sends `List<int>` (an int list) unless
// the value is a Uint8List; both are accepted.
std::vector<uint8_t> BytesValue(FlValue* value) {
  std::vector<uint8_t> bytes;
  if (!value) return bytes;
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_UINT8_LIST: {
      const uint8_t* data = fl_value_get_uint8_list(value);
      bytes.assign(data, data + fl_value_get_length(value));
      break;
    }
    case FL_VALUE_TYPE_LIST: {
      const size_t length = fl_value_get_length(value);
      bytes.reserve(length);
      for (size_t i = 0; i < length; ++i) {
        FlValue* item = fl_value_get_list_value(value, i);
        if (fl_value_get_type(item) != FL_VALUE_TYPE_INT) return {};
        bytes.push_back(static_cast<uint8_t>(fl_value_get_int(item)));
      }
      break;
    }
    default:
      break;
  }
  return bytes;
}

}  // namespace

// ══════════════════════════════════════════════════════════════════════
// Construction / Destruction
// ══════════════════════════════════════════════════════════════════════

SidePanelHost::SidePanelHost(FlBinaryMessenger* main_messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(main_messenger, kChannelName,
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                             nullptr);

  g_autoptr(FlStandardMethodCodec) clip_codec = fl_standard_method_codec_new();
  clipboard_channel_ = fl_method_channel_new(
      main_messenger, kClipboardChannelName, FL_METHOD_CODEC(clip_codec));
  fl_method_channel_set_method_call_handler(clipboard_channel_,
                                             OnClipboardMethodCall, this,
                                             nullptr);

  GdkDisplay* display = gdk_display_get_default();
  if (display) {
    monitor_added_handler_id_ = g_signal_connect(
        display, "monitor-added", G_CALLBACK(OnMonitorChanged), this);
    monitor_removed_handler_id_ = g_signal_connect(
        display, "monitor-removed", G_CALLBACK(OnMonitorChanged), this);
  }

  // No sensors yet (issue #967): Dart only talks to this host while the
  // panel is enabled and onboarding is done, so the first updateSnapshot
  // arms them and "destroy" (setting off) removes them again.
}

SidePanelHost::~SidePanelHost() { Destroy(); }

void SidePanelHost::Teardown() {
  sensors_armed_ = false;
  CancelNativeClose();
  if (rebuild_idle_id_) {
    g_source_remove(rebuild_idle_id_);
    rebuild_idle_id_ = 0;
  }
  sensors_.clear();
  DisconnectMonitorNotifies();

  if (render_channel_) {
    fl_method_channel_set_method_call_handler(render_channel_, nullptr,
                                               nullptr, nullptr);
    g_object_unref(render_channel_);
    render_channel_ = nullptr;
  }
  content_window_.reset();

  if (latest_snapshot_args_) {
    fl_value_unref(latest_snapshot_args_);
    latest_snapshot_args_ = nullptr;
  }
  render_ready_ = false;
  is_shown_ = false;
  current_work_area_.reset();
  pending_rect_.reset();
  pending_self_writes_.clear();
}

void SidePanelHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;

  Teardown();

  GdkDisplay* display = gdk_display_get_default();
  if (display) {
    if (monitor_added_handler_id_) {
      g_signal_handler_disconnect(display, monitor_added_handler_id_);
      monitor_added_handler_id_ = 0;
    }
    if (monitor_removed_handler_id_) {
      g_signal_handler_disconnect(display, monitor_removed_handler_id_);
      monitor_removed_handler_id_ = 0;
    }
  }

  if (clipboard_channel_) {
    fl_method_channel_set_method_call_handler(clipboard_channel_, nullptr,
                                               nullptr, nullptr);
    g_object_unref(clipboard_channel_);
    clipboard_channel_ = nullptr;
  }
  if (channel_) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                               nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
}

// ══════════════════════════════════════════════════════════════════════
// Sensor strips (one per monitor)
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::RebuildSensors() {
  if (destroyed_ || !sensors_armed_) return;

  sensors_.clear();
  DisconnectMonitorNotifies();

  GdkDisplay* display = gdk_display_get_default();
  if (!display) return;
  int n = gdk_display_get_n_monitors(display);
  work_area_signature_ = WorkAreaSignature();
  for (int i = 0; i < n; ++i) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (!monitor) continue;
    GdkRectangle work_area;
    gdk_monitor_get_workarea(monitor, &work_area);
    // Panel bars, resolution and scale changes surface as workarea /
    // geometry changes on the monitor (issue #967).
    monitor_notify_ids_.emplace_back(
        monitor, g_signal_connect(monitor, "notify::workarea",
                                  G_CALLBACK(OnMonitorGeometryChanged), this));
    monitor_notify_ids_.emplace_back(
        monitor, g_signal_connect(monitor, "notify::geometry",
                                  G_CALLBACK(OnMonitorGeometryChanged), this));

    // Sensor strip hugs whichever edge current_edge_ selects (issue #150) --
    // mirrors the same left/right branch in ComputeTargetRect below.
    const int sensor_x = (current_edge_ == "right")
                              ? work_area.x + work_area.width - kSensorWidth
                              : work_area.x;

    auto sensor = std::make_unique<SidePanelSensorWindow>();
    bool created = sensor->Create(sensor_x, work_area.y, kSensorWidth,
                                   work_area.height, kDwellMs);
    if (!created) {
      g_warning("[side-panel] sensor creation failed for a monitor");
      continue;
    }

    // Captured by value -- this monitor's work area is fixed for the
    // lifetime of this sensor; a real geometry change comes back through
    // monitor-added/-removed -> RebuildSensors(), which replaces the whole
    // vector (and therefore this callback) anyway.
    sensor->on_hover_entered = [this, work_area]() {
      HandleHoverEntered(work_area);
    };
    sensor->on_raw_enter = [this]() { HandleRawEnter(); };
    sensor->on_raw_exit = [this]() { HandleRawExit(); };

    sensors_.push_back(std::move(sensor));
  }
}

void SidePanelHost::DisconnectMonitorNotifies() {
  for (auto& [monitor, id] : monitor_notify_ids_) {
    if (id && G_IS_OBJECT(monitor)) g_signal_handler_disconnect(monitor, id);
  }
  monitor_notify_ids_.clear();
}

std::string SidePanelHost::WorkAreaSignature() const {
  std::string sig;
  GdkDisplay* display = gdk_display_get_default();
  if (!display) return sig;
  int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; ++i) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    if (!monitor) continue;
    GdkRectangle wa;
    gdk_monitor_get_workarea(monitor, &wa);
    sig += std::to_string(wa.x) + "," + std::to_string(wa.y) + "," +
           std::to_string(wa.width) + "," + std::to_string(wa.height) + ";";
  }
  return sig;
}

// static
void SidePanelHost::OnMonitorGeometryChanged(GObject* /*monitor*/,
                                              GParamSpec* /*pspec*/,
                                              gpointer user_data) {
  auto* self = static_cast<SidePanelHost*>(user_data);
  if (self->destroyed_ || !self->sensors_armed_ || self->rebuild_idle_id_) {
    return;
  }
  // Coalesce the burst of notifications one change produces.
  self->rebuild_idle_id_ = g_timeout_add(
      150,
      [](gpointer data) -> gboolean {
        auto* host = static_cast<SidePanelHost*>(data);
        host->rebuild_idle_id_ = 0;
        if (host->WorkAreaSignature() != host->work_area_signature_) {
          host->RebuildSensors();
        }
        return G_SOURCE_REMOVE;
      },
      self);
}

// static
void SidePanelHost::OnMonitorChanged(GdkDisplay* /*display*/,
                                      GdkMonitor* /*monitor*/,
                                      gpointer user_data) {
  static_cast<SidePanelHost*>(user_data)->RebuildSensors();
}

void SidePanelHost::HandleHoverEntered(const GdkRectangle& work_area) {
  // Snapshot-on-open (see class comment): read the clipboard exactly once,
  // right before telling the main engine the panel is about to open, so the
  // resulting `updateSnapshot` it pushes back already includes whatever this
  // produces.
  EmitClipboardSnapshot();

  PositionPanel(work_area);
  InvokeMainChannel("hoverEntered", nullptr);
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
  close_timer_id_ =
      g_timeout_add(static_cast<guint>(kCloseGraceMs), OnNativeCloseTimeout,
                    this);
}

void SidePanelHost::CancelNativeClose() {
  if (!close_timer_id_) return;
  g_source_remove(close_timer_id_);
  close_timer_id_ = 0;
}

// static
gboolean SidePanelHost::OnNativeCloseTimeout(gpointer user_data) {
  auto* self = static_cast<SidePanelHost*>(user_data);
  self->close_timer_id_ = 0;

  // Fire-point guard, mirrors the Windows host's NativeCloseTimerProc:
  // the content window covering the sensor's screen point makes GDK report
  // the sensor as "left" even though the pointer never physically moved,
  // which keeps re-arming this timer. Make the final call here instead of
  // chasing every message race that can (re-)arm it.
  if (self->content_window_ && self->content_window_->visible()) {
    GdkDisplay* display = gdk_display_get_default();
    if (display) {
      GdkSeat* seat = gdk_display_get_default_seat(display);
      GdkDevice* pointer = gdk_seat_get_pointer(seat);
      gint cursor_x = 0, cursor_y = 0;
      gdk_device_get_position(pointer, nullptr, &cursor_x, &cursor_y);
      if (self->current_work_area_) {
        int px, py, pw, ph;
        self->ComputeTargetRect(*self->current_work_area_, /*shown=*/true,
                                 &px, &py, &pw, &ph);
        if (cursor_x >= px && cursor_x < px + pw && cursor_y >= py &&
            cursor_y < py + ph) {
          return G_SOURCE_REMOVE;  // Pointer is still over the panel.
        }
      }
    }
  }

  // Relay to the main engine; SidePanelService.close() replies with
  // updateSnapshot(visible:false), which is what actually triggers
  // SlideOut() -- the native side never unilaterally hides the panel.
  self->InvokeMainChannel("hoverLeft", nullptr);
  return G_SOURCE_REMOVE;
}

// ══════════════════════════════════════════════════════════════════════
// Layout
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::ComputeTargetRect(const GdkRectangle& work_area,
                                       bool shown, int* px, int* py,
                                       int* pwidth, int* pheight) const {
  const int height = std::min(kContentHeight, work_area.height);
  // Resting x is flush with the docked edge (left or right per
  // current_edge_, issue #150); the just-off-edge staging x is exactly one
  // panel-width further off-screen on that same side.
  const int x =
      current_edge_ == "right"
          ? (shown ? work_area.x + work_area.width - kContentWidth
                   : work_area.x + work_area.width)
          : (shown ? work_area.x : work_area.x - kContentWidth);
  const int y = work_area.y + (work_area.height - height) / 2;

  *px = x;
  *py = y;
  *pwidth = kContentWidth;
  *pheight = height;
}

void SidePanelHost::PositionPanel(const GdkRectangle& work_area) {
  current_work_area_ = work_area;

  int x, y, width, height;
  ComputeTargetRect(work_area, /*shown=*/false, &x, &y, &width, &height);

  if (content_window_ && !is_shown_) {
    content_window_->SetRect(x, y, width, height);
  } else if (!content_window_) {
    pending_rect_ = GdkRectangle{x, y, width, height};
  }
}

// ══════════════════════════════════════════════════════════════════════
// Lazy content window + render engine creation
// ══════════════════════════════════════════════════════════════════════

bool SidePanelHost::EnsureContentWindow() {
  if (content_window_) return true;

  render_ready_ = false;

  GdkRectangle rect;
  if (pending_rect_) {
    rect = *pending_rect_;
    pending_rect_.reset();
  } else {
    rect = {0, 0, kContentWidth, kContentHeight};
  }

  auto window = std::make_unique<SidePanelContentWindow>();
  if (!window->Create(rect.x, rect.y, rect.width, rect.height)) {
    g_warning("[side-panel] content window creation failed");
    return false;
  }
  window->on_content_enter = [this]() { HandleContentEnter(); };
  window->on_content_exit = [this]() { HandleContentExit(); };

  content_window_ = std::move(window);
  OpenRenderChannel();
  return true;
}

void SidePanelHost::OpenRenderChannel() {
  FlBinaryMessenger* render_messenger = content_window_->GetRenderMessenger();
  if (!render_messenger) {
    g_warning("[side-panel] OpenRenderChannel: render messenger is null");
    return;
  }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  render_channel_ = fl_method_channel_new(render_messenger,
                                           kRenderChannelName,
                                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(render_channel_,
                                             OnRenderMethodCall, this,
                                             nullptr);
}

// ══════════════════════════════════════════════════════════════════════
// Slide animation
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::SlideIn() {
  if (!content_window_ || !current_work_area_) return;

  // Any native close armed by the pointer leaving the sensor strip on its
  // way here is stale -- GTK synthesizes no fresh enter for a stationary
  // pointer the panel appears underneath, so without this the close-grace
  // timer could still fire ~350ms after open even though the pointer never
  // left. Mirrors the Windows port's SlideIn.
  CancelNativeClose();

  int staging_x, staging_y, staging_w, staging_h;
  ComputeTargetRect(*current_work_area_, /*shown=*/false, &staging_x,
                     &staging_y, &staging_w, &staging_h);
  int shown_x, shown_y, shown_w, shown_h;
  ComputeTargetRect(*current_work_area_, /*shown=*/true, &shown_x, &shown_y,
                     &shown_w, &shown_h);

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

// static
void SidePanelHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  static_cast<SidePanelHost*>(user_data)->HandleMethodCall(method_call);
}

void SidePanelHost::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "updateSnapshot") == 0) {
    HandleUpdateSnapshot(args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "destroy") == 0) {
    // Setting turned off (or onboarding reopened): drop sensors and panel
    // but stay reusable for the next toggle-on.
    Teardown();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

void SidePanelHost::HandleUpdateSnapshot(FlValue* args) {
  bool visible = false;
  if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* visible_val = fl_value_lookup_string(args, "visible");
    if (visible_val && fl_value_get_type(visible_val) == FL_VALUE_TYPE_BOOL) {
      visible = fl_value_get_bool(visible_val);
    }

    // Issue #150: relocate the sensor strip immediately if the user's chosen
    // edge changed since the last snapshot. Every updateSnapshot carries
    // this field (SidePanelService always fills it in, see
    // side_panel_snapshot.dart), so a missing/malformed value keeps the
    // previous edge rather than silently resetting to "left".
    FlValue* edge_val = fl_value_lookup_string(args, "edge");
    if (edge_val && fl_value_get_type(edge_val) == FL_VALUE_TYPE_STRING) {
      const char* edge = fl_value_get_string(edge_val);
      if (edge && (strcmp(edge, "left") == 0 || strcmp(edge, "right") == 0) &&
          current_edge_ != edge) {
        current_edge_ = edge;
        RebuildSensors();
      }
    }
  }
  if (!sensors_armed_) {
    sensors_armed_ = true;
    RebuildSensors();
  }

  if (visible && !content_window_) {
    if (!EnsureContentWindow()) {
      g_warning(
          "[side-panel] updateSnapshot(visible:true) could not create "
          "content window");
      return;
    }
  }

  if (latest_snapshot_args_) fl_value_unref(latest_snapshot_args_);
  latest_snapshot_args_ = args ? fl_value_ref(args) : nullptr;
  if (render_ready_) {
    InvokeRenderChannel("updateSnapshot", args);
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

// static
void SidePanelHost::OnRenderMethodCall(FlMethodChannel* /*channel*/,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  static_cast<SidePanelHost*>(user_data)->HandleRenderMethodCall(method_call);
}

void SidePanelHost::HandleRenderMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "ready") == 0) {
    render_ready_ = true;
    if (latest_snapshot_args_) {
      InvokeRenderChannel("updateSnapshot", latest_snapshot_args_);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "rowClicked") == 0) {
    InvokeMainChannel("rowClicked", args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "hoverLeft") == 0) {
    // Relay to the main engine; SidePanelService.close() replies with
    // updateSnapshot(visible:false), which is what actually triggers
    // SlideOut() above -- keeps the single animate-then-hide path.
    InvokeMainChannel("hoverLeft", nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "beginDrag") == 0) {
    // OS drag-out of a row (issue 11), see SidePanelHost.swift's
    // beginNativeDrag. Fire-and-forget from the render engine.
    std::string text;
    std::vector<uint8_t> png;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* kind_v = fl_value_lookup_string(args, "kind");
      const bool image = kind_v &&
                         fl_value_get_type(kind_v) == FL_VALUE_TYPE_STRING &&
                         strcmp(fl_value_get_string(kind_v), "image") == 0;
      FlValue* content_v = fl_value_lookup_string(args, "content");
      if (content_v && fl_value_get_type(content_v) == FL_VALUE_TYPE_STRING) {
        text = fl_value_get_string(content_v);
      }
      if (image) png = BytesValue(fl_value_lookup_string(args, "imageBytes"));
    }
    if (!content_window_ || !content_window_->BeginDrag(text, png)) {
      g_message("[side-panel] beginDrag: no press to start from or nothing "
                "to drag");
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "reportError") == 0) {
    std::string message;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* msg_v = fl_value_lookup_string(args, "message");
      if (msg_v && fl_value_get_type(msg_v) == FL_VALUE_TYPE_STRING) {
        message = fl_value_get_string(msg_v);
      }
    }
    g_warning("[side-panel] render engine reported an error: %s",
              message.c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ══════════════════════════════════════════════════════════════════════
// Clipboard snapshot-on-open (see class comment)
// ══════════════════════════════════════════════════════════════════════

// static
void SidePanelHost::OnClipboardMethodCall(FlMethodChannel* /*channel*/,
                                           FlMethodCall* method_call,
                                           gpointer user_data) {
  static_cast<SidePanelHost*>(user_data)->HandleClipboardMethodCall(
      method_call);
}

void SidePanelHost::HandleClipboardMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "markSelfWrite") == 0) {
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* length_v = fl_value_lookup_string(args, "length");
      FlValue* hash_v = fl_value_lookup_string(args, "hash");
      if (length_v && hash_v &&
          fl_value_get_type(length_v) == FL_VALUE_TYPE_INT &&
          fl_value_get_type(hash_v) == FL_VALUE_TYPE_INT) {
        Fingerprint fp{
            static_cast<size_t>(fl_value_get_int(length_v)),
            static_cast<uint64_t>(fl_value_get_int(hash_v)),
        };
        MarkSelfWrite(fp);
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    // This host only ever RECEIVES markSelfWrite on this channel -- it never
    // sends clipEntryDetected TO Dart via a call it handles (that direction
    // is host -> Dart, an invoke, not a call this handler answers).
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// static
SidePanelHost::Fingerprint SidePanelHost::FingerprintOfUtf8(
    const std::string& utf8) {
  const auto* bytes = reinterpret_cast<const uint8_t*>(utf8.data());
  return Fingerprint{utf8.size(), Fnv1a64(bytes, utf8.size())};
}

void SidePanelHost::MarkSelfWrite(const Fingerprint& fp) {
  const gint64 expiry =
      g_get_monotonic_time() +
      static_cast<gint64>(kSuppressionExpirySeconds * G_USEC_PER_SEC);
  pending_self_writes_[fp] = expiry;
}

bool SidePanelHost::ShouldSuppress(const Fingerprint& fp) {
  auto it = pending_self_writes_.find(fp);
  if (it == pending_self_writes_.end()) return false;
  const gint64 expiry = it->second;
  pending_self_writes_.erase(it);
  return g_get_monotonic_time() < expiry;
}

void SidePanelHost::EmitClipboardSnapshot() {
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  // A hover during a paste must not count as the target's read (GR-015).
  ClipboardReceipt::ScopedSelfRead self_read;

  // Password managers (KeePassXC, Bitwarden, 1Password, ...) mark secrets
  // with the "x-kde-passwordManagerHint" target on both X11 and Wayland.
  // Such content is never read, so nothing reaches the history (issue #593).
  // The source app itself is not detectable on Linux (no per-copy owner
  // identity on Wayland), so only this marker applies there.
  if (gtk_clipboard_wait_is_target_available(
          clipboard, gdk_atom_intern_static_string("x-kde-passwordManagerHint"))) {
    return;
  }

  gchar* text = gtk_clipboard_wait_for_text(clipboard);
  if (text && text[0] != '\0') {
    std::string utf8_text(text);
    g_free(text);

    Fingerprint fp = FingerprintOfUtf8(utf8_text);
    if (ShouldSuppress(fp)) return;

    g_autoptr(FlValue) entry_args = fl_value_new_map();
    fl_value_set_string_take(entry_args, "kind", fl_value_new_string("text"));
    fl_value_set_string_take(
        entry_args, "capturedAtMs",
        fl_value_new_int(static_cast<int64_t>(g_get_real_time() / 1000)));
    // Content carrying the password-manager hint was dropped above, so the
    // flags stay false here (mirrors the Windows host).
    fl_value_set_string_take(entry_args, "transient", fl_value_new_bool(FALSE));
    fl_value_set_string_take(entry_args, "concealed", fl_value_new_bool(FALSE));
    fl_value_set_string_take(entry_args, "autoGenerated",
                              fl_value_new_bool(FALSE));
    // sourceApp: none (deliberately empty) -- X11/Wayland name no copy source (#616).
    fl_value_set_string_take(entry_args, "text",
                              fl_value_new_string(utf8_text.c_str()));
    InvokeMainChannel("clipEntryDetected", entry_args);
    return;
  }
  if (text) g_free(text);

  GdkPixbuf* pixbuf = gtk_clipboard_wait_for_image(clipboard);
  if (!pixbuf) return;

  gchar* png_buffer = nullptr;
  gsize png_size = 0;
  GError* error = nullptr;
  if (!gdk_pixbuf_save_to_buffer(pixbuf, &png_buffer, &png_size, "png",
                                  &error, nullptr)) {
    if (error) {
      g_warning("[side-panel] clipboard image PNG encode failed: %s",
                error->message);
      g_error_free(error);
    }
    g_object_unref(pixbuf);
    return;
  }
  g_object_unref(pixbuf);

  // No self-write fingerprint for images: WhisPaste only puts an image back
  // when a paste restores the user's earlier clipboard, and that image is
  // the user's own copy. An image that is still unchanged on the next open
  // is dropped in Dart (ClipboardHistoryRingBuffer.add), not here.
  g_autoptr(FlValue) entry_args = fl_value_new_map();
  fl_value_set_string_take(entry_args, "kind", fl_value_new_string("image"));
  fl_value_set_string_take(
      entry_args, "capturedAtMs",
      fl_value_new_int(static_cast<int64_t>(g_get_real_time() / 1000)));
  fl_value_set_string_take(entry_args, "transient", fl_value_new_bool(FALSE));
  fl_value_set_string_take(entry_args, "concealed", fl_value_new_bool(FALSE));
  fl_value_set_string_take(entry_args, "autoGenerated",
                            fl_value_new_bool(FALSE));
  fl_value_set_string_take(
      entry_args, "imageBytes",
      fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(png_buffer),
                               png_size));
  g_free(png_buffer);
  // sourceApp: none (deliberately empty) -- see the text entry above (#616).
  InvokeMainChannel("clipEntryDetected", entry_args);
}

// ══════════════════════════════════════════════════════════════════════
// Channel invocation helpers
// ══════════════════════════════════════════════════════════════════════

void SidePanelHost::InvokeMainChannel(const char* method, FlValue* args) {
  if (destroyed_ || !channel_) return;
  fl_method_channel_invoke_method(channel_, method, args, nullptr,
                                   OnInvokeDone, nullptr);
}

void SidePanelHost::InvokeRenderChannel(const char* method, FlValue* args) {
  if (!render_channel_) return;
  fl_method_channel_invoke_method(render_channel_, method, args, nullptr,
                                   OnInvokeDone, nullptr);
}

// static
void SidePanelHost::OnInvokeDone(GObject* source, GAsyncResult* result,
                                  gpointer /*user_data*/) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(source),
                                              result, &error);
  if (error) {
    g_warning("[side-panel] channel invoke error: %s", error->message);
  }
}
