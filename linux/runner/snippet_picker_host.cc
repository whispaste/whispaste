#include "snippet_picker_host.h"

#include <gdk/gdk.h>

#include <algorithm>
#include <cstring>
#include <string>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/Xlib.h>
#endif

namespace {

constexpr char kChannelName[] = "com.whispaste.snippet_picker";
constexpr char kRenderChannelName[] = "com.whispaste.snippet_picker_render";

#ifdef GDK_WINDOWING_X11
// A stale/destroyed window ID passed to XSetInputFocus raises a BadWindow X
// error, which by default terminates the whole process — install this for
// the duration of that one call instead of crashing on a focus-restore race.
int IgnoreXErrorHandler(Display* /*display*/, XErrorEvent* /*event*/) {
  return 0;
}
#endif

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
    // args: { items: [ {id, ...}, ... ] }
    FlValue* items = nullptr;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      items = fl_value_lookup_string(args, "items");
    }
    EnsureWindowAndEngine();
    Show(items);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "hide") == 0) {
    Dismiss(/*fire_cancelled=*/false);
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

void SnippetPickerHost::Show(FlValue* items) {
  if (!window_) return;

  if (items) {
    if (pending_items_) fl_value_unref(pending_items_);
    pending_items_ = fl_value_ref(items);
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
}

void SnippetPickerHost::Dismiss(bool fire_cancelled) {
  if (is_dismissing_) return;
  is_dismissing_ = true;

  if (window_) window_->Hide();
  RestoreFocusedWindow();
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
      auto* previous_handler = XSetErrorHandler(IgnoreXErrorHandler);
      XSetInputFocus(display, saved_focus_window_, RevertToParent,
                     CurrentTime);
      XSync(display, False);
      XSetErrorHandler(previous_handler);
    }
  }
#endif
  saved_focus_window_ = 0;
}

// static
void SnippetPickerHost::OnWindowFocusLost(void* user_data) {
  auto* self = static_cast<SnippetPickerHost*>(user_data);
  self->Dismiss(/*fire_cancelled=*/true);
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
