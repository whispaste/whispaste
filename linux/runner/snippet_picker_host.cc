#include "snippet_picker_host.h"

#include <gdk/gdk.h>

#include <algorithm>
#include <cstring>
#include <string>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xlib.h>

#include "x11_window.h"
#endif

namespace {

constexpr char kChannelName[] = "com.whispaste.snippet_picker";
constexpr char kRenderChannelName[] = "com.whispaste.snippet_picker_render";

}  // namespace

SnippetPickerHost::SnippetPickerHost(FlBinaryMessenger* main_messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(main_messenger, kChannelName,
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                             nullptr);
}

SnippetPickerHost::~SnippetPickerHost() {
  if (render_channel_) {
    fl_method_channel_set_method_call_handler(render_channel_, nullptr,
                                               nullptr, nullptr);
    g_object_unref(render_channel_);
    render_channel_ = nullptr;
  }
  if (channel_) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                               nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
  if (pending_items_) {
    fl_value_unref(pending_items_);
    pending_items_ = nullptr;
  }
  delete window_;
  window_ = nullptr;
}

// ── Public channel handler ────────────────────────────────────────────────

// static
void SnippetPickerHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  static_cast<SnippetPickerHost*>(user_data)->HandleMethodCall(method_call);
}

void SnippetPickerHost::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "show") == 0) {
    // args: { items: [ {id, ...}, ... ], query: "..." }
    FlValue* items = nullptr;
    std::string query;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      items = fl_value_lookup_string(args, "items");
      FlValue* q = fl_value_lookup_string(args, "query");
      if (q && fl_value_get_type(q) == FL_VALUE_TYPE_STRING) {
        query = fl_value_get_string(q);
      }
    }
    EnsureWindowAndEngine();
    Show(items, query);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "hide") == 0) {
    bool outside_click = false;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* v = fl_value_lookup_string(args, "outsideClick");
      outside_click = v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL &&
                      fl_value_get_bool(v);
    }
    Dismiss(/*fire_cancelled=*/false, /*restore_focus=*/!outside_click);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "focus") == 0) {
    // The Snippet hotkey pressed while the picker is open but lost focus
    // (#1680): present it again in place, search text kept.
    if (window_ && visible_) window_->Show();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "destroy") == 0) {
    Dismiss(/*fire_cancelled=*/false);
    if (render_channel_) {
      fl_method_channel_set_method_call_handler(render_channel_, nullptr,
                                                 nullptr, nullptr);
      g_object_unref(render_channel_);
      render_channel_ = nullptr;
    }
    delete window_;
    window_ = nullptr;
    render_ready_ = false;
    has_pending_items_ = false;
    if (pending_items_) {
      fl_value_unref(pending_items_);
      pending_items_ = nullptr;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ── Window/engine creation ────────────────────────────────────────────────

void SnippetPickerHost::EnsureWindowAndEngine() {
  if (window_) return;
  render_ready_ = false;
  window_ = new SnippetPickerWindow();
  window_->SetOnFocusLost(OnWindowFocusLost, this);
  click_watcher_.SetOnClick(OnClick, this);
  window_->Create();
  OpenRenderChannel();
}

void SnippetPickerHost::OpenRenderChannel() {
  FlBinaryMessenger* render_messenger = window_->GetRenderMessenger();
  if (!render_messenger) {
    g_warning("[snippet-picker-host] render messenger is null");
    return;
  }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  render_channel_ = fl_method_channel_new(
      render_messenger, kRenderChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(render_channel_,
                                            OnRenderMethodCall, this, nullptr);
}

// ── Positioning ────────────────────────────────────────────────────────────

// static
void SnippetPickerHost::ComputePanelOrigin(int* out_x, int* out_y) {
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  gint cursor_x = 0, cursor_y = 0;
  gdk_device_get_position(pointer, nullptr, &cursor_x, &cursor_y);

  GdkMonitor* monitor = gdk_display_get_monitor_at_point(display, cursor_x,
                                                          cursor_y);
  if (!monitor) monitor = gdk_display_get_monitor(display, 0);
  GdkRectangle work_area;
  gdk_monitor_get_workarea(monitor, &work_area);

  int x = cursor_x;
  int y = cursor_y;
  const int max_x = work_area.x + work_area.width - kSnippetPickerWidth;
  const int max_y = work_area.y + work_area.height - kSnippetPickerHeight;
  x = std::max(work_area.x, std::min(x, max_x));
  y = std::max(work_area.y, std::min(y, max_y));

  *out_x = x;
  *out_y = y;
}

// ── Show / Dismiss ────────────────────────────────────────────────────────

void SnippetPickerHost::Show(FlValue* items, const std::string& query) {
  if (!window_) return;

  if (items) {
    if (pending_items_) fl_value_unref(pending_items_);
    pending_items_ = fl_value_ref(items);
    pending_query_ = query;
    has_pending_items_ = true;
  }

  if (render_ready_) {
    RelayPendingItems();
  }

  int x = 0, y = 0;
  ComputePanelOrigin(&x, &y);
  window_->MoveTo(x, y);

  SaveFocusedWindow();
  window_->Show();
  visible_ = true;
  // False (nothing running) when there is no X11 display; then a focus-out
  // is the only signal and reports "unknown".
  click_watcher_.Start();
}

void SnippetPickerHost::Dismiss(bool fire_cancelled, bool restore_focus) {
  if (is_dismissing_) return;
  is_dismissing_ = true;

  visible_ = false;
  click_watcher_.Stop();
  if (window_) window_->Hide();
  if (restore_focus) {
    RestoreFocusedWindow();
  } else {
    saved_focus_window_ = 0;
  }
  InvokeRenderChannel("panelHidden", nullptr);

  if (fire_cancelled) {
    InvokeMainChannel("onCancelled", nullptr);
  }

  is_dismissing_ = false;
}

// ── X11 focus save/restore (see snippet_picker_host.h class comment) ──────

void SnippetPickerHost::SaveFocusedWindow() {
  saved_focus_window_ = 0;
#ifdef GDK_WINDOWING_X11
  GdkDisplay* gdk_display = gdk_display_get_default();
  if (!GDK_IS_X11_DISPLAY(gdk_display)) return;
  Display* display = gdk_x11_display_get_xdisplay(gdk_display);
  Window focus_window;
  int revert_to;
  XGetInputFocus(display, &focus_window, &revert_to);
  if (focus_window != None && focus_window != PointerRoot) {
    saved_focus_window_ = focus_window;
  }
#endif
}

void SnippetPickerHost::RestoreFocusedWindow() {
#ifdef GDK_WINDOWING_X11
  if (saved_focus_window_ != 0) {
    GdkDisplay* gdk_display = gdk_display_get_default();
    if (GDK_IS_X11_DISPLAY(gdk_display)) {
      Display* display = gdk_x11_display_get_xdisplay(gdk_display);
      // The saved window may be gone; a BadWindow would end the process.
      WithX11ErrorTrap(gdk_display, [&] {
        XSetInputFocus(display, saved_focus_window_, RevertToParent,
                       CurrentTime);
      });
    }
  }
#endif
  saved_focus_window_ = 0;
}

// static
void SnippetPickerHost::OnWindowFocusLost(void* user_data) {
  auto* self = static_cast<SnippetPickerHost*>(user_data);
  // Clicks are seen only on a real X11 session; elsewhere the focus loss is
  // the only sign that the user went to another window.
  const bool clicks_seen =
      self->click_watcher_.running() && !IsWaylandSession();
  self->ReportFocusLost(clicks_seen ? "other" : "unknown");
}

// static
void SnippetPickerHost::OnClick(void* user_data) {
  auto* self = static_cast<SnippetPickerHost*>(user_data);
  if (!self->visible_ || self->window_ == nullptr) return;
  // A click on the picker itself is no click outside. GDK returns a window
  // only when it belongs to this process.
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat =
      display != nullptr ? gdk_display_get_default_seat(display) : nullptr;
  GdkDevice* pointer = seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;
  GdkWindow* under =
      pointer != nullptr
          ? gdk_device_get_window_at_position(pointer, nullptr, nullptr)
          : nullptr;
  GdkWindow* picker = gtk_widget_get_window(self->window_->GetGtkWindow());
  if (under != nullptr && picker != nullptr &&
      gdk_window_get_toplevel(under) == picker) {
    return;
  }
  self->ReportFocusLost("click");
}

void SnippetPickerHost::ReportFocusLost(const char* cause) {
  if (is_dismissing_ || !visible_) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "cause", fl_value_new_string(cause));
  InvokeMainChannel("onFocusLost", args);
}

// static
bool SnippetPickerHost::IsWaylandSession() {
  // main.cc may drop WAYLAND_DISPLAY when it forces GDK_BACKEND=x11, so the
  // session type is checked first.
  const gchar* type = g_getenv("XDG_SESSION_TYPE");
  if (type != nullptr && g_ascii_strcasecmp(type, "wayland") == 0) return true;
  const gchar* display = g_getenv("WAYLAND_DISPLAY");
  return display != nullptr && display[0] != '\0';
}

// ── Render channel handler (2nd engine → host) ─────────────────────────────

// static
void SnippetPickerHost::OnRenderMethodCall(FlMethodChannel* /*channel*/,
                                           FlMethodCall* method_call,
                                           gpointer user_data) {
  static_cast<SnippetPickerHost*>(user_data)->HandleRenderMethodCall(
      method_call);
}

void SnippetPickerHost::HandleRenderMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "ready") == 0) {
    render_ready_ = true;
    RelayPendingItems();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "selectItem") == 0) {
    std::string id;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* id_v = fl_value_lookup_string(args, "id");
      if (id_v && fl_value_get_type(id_v) == FL_VALUE_TYPE_STRING) {
        id = fl_value_get_string(id_v);
      }
    }
    Dismiss(/*fire_cancelled=*/false);
    g_autoptr(FlValue) event_args = fl_value_new_map();
    fl_value_set_string_take(event_args, "id", fl_value_new_string(id.c_str()));
    InvokeMainChannel("onItemSelected", event_args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "cancel") == 0) {
    Dismiss(/*fire_cancelled=*/true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "reportError") == 0) {
    std::string message;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* msg_v = fl_value_lookup_string(args, "message");
      if (msg_v && fl_value_get_type(msg_v) == FL_VALUE_TYPE_STRING) {
        message = fl_value_get_string(msg_v);
      }
    }
    g_autoptr(FlValue) event_args = fl_value_new_map();
    fl_value_set_string_take(event_args, "message",
                             fl_value_new_string(message.c_str()));
    fl_value_set_string_take(event_args, "isError", fl_value_new_bool(TRUE));
    InvokeMainChannel("onRenderEngineDiagnostic", event_args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

void SnippetPickerHost::RelayPendingItems() {
  if (!has_pending_items_ || !pending_items_) return;
  g_autoptr(FlValue) wrapper = fl_value_new_map();
  fl_value_set_string_take(wrapper, "items", fl_value_ref(pending_items_));
  fl_value_set_string_take(wrapper, "query",
                           fl_value_new_string(pending_query_.c_str()));
  InvokeRenderChannel("setItems", wrapper);
  has_pending_items_ = false;
}

// ── Channel invocation helpers ──────────────────────────────────────────────

void SnippetPickerHost::InvokeMainChannel(const char* method, FlValue* args) {
  if (!channel_) return;
  fl_method_channel_invoke_method(channel_, method, args, nullptr,
                                  OnInvokeDone, nullptr);
}

void SnippetPickerHost::InvokeRenderChannel(const char* method,
                                            FlValue* args) {
  if (!render_channel_ || !render_ready_) return;
  fl_method_channel_invoke_method(render_channel_, method, args, nullptr,
                                  OnInvokeDone, nullptr);
}

// static
void SnippetPickerHost::OnInvokeDone(GObject* source, GAsyncResult* result,
                                     gpointer /*user_data*/) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(source), result, &error);
  if (error) {
    g_warning("[snippet-picker-host] channel invoke error: %s", error->message);
  }
}
