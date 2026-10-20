#include "floating_button_host.h"

#include <gdk/gdk.h>
#include <gdk/gdkx.h>

#include <cstring>
#include <string>

namespace {

// Preset ids the render engine understands (overlay_design_spec.dart). Any
// other value from the method channel is replaced by the default before it is
// cached or relayed.
const char* const kBackgroundPresets[] = {"marine", "graphit", "gletscher", "amber"};
const char* const kWavePresets[] = {"cyan", "violett", "neutral", "ink", "amber", "coral", "mint"};

template <size_t N>
std::string KnownPreset(const std::string& value,
                        const char* const (&known)[N], const char* fallback) {
  for (const char* id : known) {
    if (value == id) return value;
  }
  return fallback;
}

}  // namespace

// ── Construction / destruction ───────────────────────────────────────────────

FloatingButtonHost::FloatingButtonHost(FlBinaryMessenger* main_messenger) {
  // Open the public channel on the MAIN engine messenger.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(main_messenger,
                                    "com.whispaste.floating_button",
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                             nullptr);
}

FloatingButtonHost::~FloatingButtonHost() {
  // Tear down channels before the window so channel callbacks can't fire
  // with a dangling window pointer after the GtkWindow is destroyed.
  if (render_channel_) {
    fl_method_channel_set_method_call_handler(render_channel_, nullptr, nullptr,
                                               nullptr);
    g_object_unref(render_channel_);
    render_channel_ = nullptr;
  }
  if (channel_) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                               nullptr);
    g_object_unref(channel_);
    channel_ = nullptr;
  }
  delete button_window_;
  button_window_ = nullptr;
}

// ── Public channel handler ────────────────────────────────────────────────────

// static
void FloatingButtonHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  static_cast<FloatingButtonHost*>(user_data)->HandleMethodCall(method_call);
}

void FloatingButtonHost::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "show") == 0) {
    // ── show ──────────────────────────────────────────────────────────────
    // args: { x, y, size }
    // Lazy-creates the button window, positions it, and shows it.
    double x = static_cast<double>(current_x_);
    double y = static_cast<double>(current_y_);
    int size = pending_diameter_;

    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* xv = fl_value_lookup_string(args, "x");
      FlValue* yv = fl_value_lookup_string(args, "y");
      FlValue* sv = fl_value_lookup_string(args, "size");
      if (xv) {
        if (fl_value_get_type(xv) == FL_VALUE_TYPE_FLOAT)
          x = fl_value_get_float(xv);
        else if (fl_value_get_type(xv) == FL_VALUE_TYPE_INT)
          x = static_cast<double>(fl_value_get_int(xv));
      }
      if (yv) {
        if (fl_value_get_type(yv) == FL_VALUE_TYPE_FLOAT)
          y = fl_value_get_float(yv);
        else if (fl_value_get_type(yv) == FL_VALUE_TYPE_INT)
          y = static_cast<double>(fl_value_get_int(yv));
      }
      if (sv) {
        if (fl_value_get_type(sv) == FL_VALUE_TYPE_INT)
          size = static_cast<int>(fl_value_get_int(sv));
        else if (fl_value_get_type(sv) == FL_VALUE_TYPE_FLOAT)
          size = static_cast<int>(fl_value_get_float(sv));
      }
    }

    pending_x_ = static_cast<int>(x);
    pending_y_ = static_cast<int>(y);
    pending_diameter_ = size;
    current_x_ = pending_x_;
    current_y_ = pending_y_;

    if (button_window_ == nullptr) {
      EnsureButtonWindow();
    }
    if (button_window_) {
      button_window_->SetDiameter(pending_diameter_);
      suppress_next_configure_ = true;
      button_window_->MoveTo(pending_x_, pending_y_);
      button_window_->Show();
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "hide") == 0) {
    // ── hide ──────────────────────────────────────────────────────────────
    if (button_window_) button_window_->Hide();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setState") == 0) {
    // ── setState ──────────────────────────────────────────────────────────
    // args: { state: string }
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* sv = fl_value_lookup_string(args, "state");
      if (sv && fl_value_get_type(sv) == FL_VALUE_TYPE_STRING) {
        pending_state_ = fl_value_get_string(sv);
      }
    }
    if (render_ready_) InvokeRenderChannel("setState", args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setTheme") == 0) {
    // ── setTheme ──────────────────────────────────────────────────────────
    // args: { background: string, wave: string } (WP-75). Cached so the ready
    // flush can replay them.
    // A missing or non-string id resets to the default, like macOS and
    // Windows; an unknown string is replaced by the default as well.
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* bv = fl_value_lookup_string(args, "background");
      FlValue* wv = fl_value_lookup_string(args, "wave");
      const char* background =
          (bv && fl_value_get_type(bv) == FL_VALUE_TYPE_STRING)
              ? fl_value_get_string(bv)
              : "";
      const char* wave = (wv && fl_value_get_type(wv) == FL_VALUE_TYPE_STRING)
                             ? fl_value_get_string(wv)
                             : "";
      pending_background_ =
          KnownPreset(background, kBackgroundPresets, "marine");
      pending_wave_ = KnownPreset(wave, kWavePresets, "cyan");
      // WP-95 button look: shape, recording ring, resting opacity (40-100 %).
      FlValue* shv = fl_value_lookup_string(args, "shape");
      pending_shape_ = (shv && fl_value_get_type(shv) == FL_VALUE_TYPE_STRING &&
                        strcmp(fl_value_get_string(shv), "square") == 0)
                           ? "square"
                           : "round";
      FlValue* rv = fl_value_lookup_string(args, "ring");
      pending_ring_ = (rv && fl_value_get_type(rv) == FL_VALUE_TYPE_BOOL)
                          ? fl_value_get_bool(rv)
                          : true;
      double idle = 1.0;
      FlValue* ov = fl_value_lookup_string(args, "idleOpacity");
      if (ov && fl_value_get_type(ov) == FL_VALUE_TYPE_FLOAT) {
        idle = fl_value_get_float(ov);
      } else if (ov && fl_value_get_type(ov) == FL_VALUE_TYPE_INT) {
        idle = static_cast<double>(fl_value_get_int(ov));
      }
      pending_idle_opacity_ = idle < 0.4 ? 0.4 : (idle > 1.0 ? 1.0 : idle);
    }
    if (render_ready_) {
      g_autoptr(FlValue) theme_args = fl_value_new_map();
      fl_value_set_string_take(theme_args, "background",
                               fl_value_new_string(pending_background_.c_str()));
      fl_value_set_string_take(theme_args, "wave",
                               fl_value_new_string(pending_wave_.c_str()));
      fl_value_set_string_take(theme_args, "shape",
                               fl_value_new_string(pending_shape_.c_str()));
      fl_value_set_string_take(theme_args, "ring",
                               fl_value_new_bool(pending_ring_));
      fl_value_set_string_take(theme_args, "idleOpacity",
                               fl_value_new_float(pending_idle_opacity_));
      InvokeRenderChannel("setTheme", theme_args);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setPosition") == 0) {
    // ── setPosition ───────────────────────────────────────────────────────
    // args: { x, y }
    double x = static_cast<double>(current_x_);
    double y = static_cast<double>(current_y_);
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* xv = fl_value_lookup_string(args, "x");
      FlValue* yv = fl_value_lookup_string(args, "y");
      if (xv) {
        if (fl_value_get_type(xv) == FL_VALUE_TYPE_FLOAT)
          x = fl_value_get_float(xv);
        else if (fl_value_get_type(xv) == FL_VALUE_TYPE_INT)
          x = static_cast<double>(fl_value_get_int(xv));
      }
      if (yv) {
        if (fl_value_get_type(yv) == FL_VALUE_TYPE_FLOAT)
          y = fl_value_get_float(yv);
        else if (fl_value_get_type(yv) == FL_VALUE_TYPE_INT)
          y = static_cast<double>(fl_value_get_int(yv));
      }
    }
    current_x_ = static_cast<int>(x);
    current_y_ = static_cast<int>(y);
    if (button_window_ && button_window_->IsCreated()) {
      suppress_next_configure_ = true;
      button_window_->MoveTo(current_x_, current_y_);
    } else {
      pending_x_ = current_x_;
      pending_y_ = current_y_;
      has_pending_position_ = true;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setSize") == 0) {
    // ── setSize ───────────────────────────────────────────────────────────
    // args: { size: int }
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* sv = fl_value_lookup_string(args, "size");
      if (sv) {
        if (fl_value_get_type(sv) == FL_VALUE_TYPE_INT)
          pending_diameter_ = static_cast<int>(fl_value_get_int(sv));
        else if (fl_value_get_type(sv) == FL_VALUE_TYPE_FLOAT)
          pending_diameter_ = static_cast<int>(fl_value_get_float(sv));
      }
    }
    if (button_window_ && button_window_->IsCreated()) {
      button_window_->SetDiameter(pending_diameter_);
    }
    // Relay to render engine as setDiameter so it can resize the painter.
    if (render_ready_) {
      g_autoptr(FlValue) diam_args = fl_value_new_map();
      fl_value_set_string_take(diam_args, "diameter",
                                fl_value_new_int(pending_diameter_));
      InvokeRenderChannel("setDiameter", diam_args);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setContextMenuItems") == 0) {
    // ── setContextMenuItems ───────────────────────────────────────────────
    // args: { items: [{id, label}, …] }
    context_menu_items_.clear();
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* items_val = fl_value_lookup_string(args, "items");
      if (items_val && fl_value_get_type(items_val) == FL_VALUE_TYPE_LIST) {
        size_t count = fl_value_get_length(items_val);
        for (size_t i = 0; i < count; ++i) {
          FlValue* item = fl_value_get_list_value(items_val, i);
          if (!item || fl_value_get_type(item) != FL_VALUE_TYPE_MAP) continue;
          FlValue* id_v = fl_value_lookup_string(item, "id");
          FlValue* lb_v = fl_value_lookup_string(item, "label");
          if (!id_v || !lb_v) continue;
          context_menu_items_.push_back(
              {fl_value_get_string(id_v), fl_value_get_string(lb_v)});
        }
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "getPosition") == 0) {
    // ── getPosition ───────────────────────────────────────────────────────
    // Returns the current window position as { x, y }.
    // Prefer the live GTK position if the window exists; fall back to the
    // cached current_x_/current_y_ otherwise.
    int x = current_x_, y = current_y_;
    if (button_window_ && button_window_->IsCreated()) {
      GtkWidget* gtk_win = button_window_->GetGtkWindow();
      if (gtk_win) {
        gint wx = 0, wy = 0;
        gtk_window_get_position(GTK_WINDOW(gtk_win), &wx, &wy);
        x = wx;
        y = wy;
      }
    }
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "x",
                              fl_value_new_float(static_cast<double>(x)));
    fl_value_set_string_take(result, "y",
                              fl_value_new_float(static_cast<double>(y)));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "destroy") == 0) {
    // ── destroy ───────────────────────────────────────────────────────────
    // Called by MethodChannelPlatformHost.dispose() from Dart. Tear down the
    // button window and render channel; the host itself is deleted by the
    // GtkApplication in my_application_dispose().
    if (render_channel_) {
      fl_method_channel_set_method_call_handler(render_channel_, nullptr,
                                                 nullptr, nullptr);
      g_object_unref(render_channel_);
      render_channel_ = nullptr;
    }
    delete button_window_;
    button_window_ = nullptr;
    render_ready_ = false;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "getCapabilities") == 0) {
    // ── getCapabilities ───────────────────────────────────────────────────
    // Reports whether the active GDK backend can host the button at all. Keep-
    // above, absolute positioning and focus-free clicks need X11 (native or
    // XWayland). The Dart side maps the session type (X11 vs. Wayland) to the
    // limits it shows in Settings (PAR-010).
    GdkDisplay* display = gdk_display_get_default();
    g_autoptr(FlValue) caps = fl_value_new_map();
    fl_value_set_string_take(
        caps, "x11",
        fl_value_new_bool(display != nullptr && GDK_IS_X11_DISPLAY(display)));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(caps));

  } else if (strcmp(method, "setOpacity") == 0) {
    // ── setOpacity ────────────────────────────────────────────────────────
    // No-op on Linux — the Flutter painter handles its own alpha compositing.
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ── Button window creation ────────────────────────────────────────────────────

void FloatingButtonHost::EnsureButtonWindow() {
  render_ready_ = false;
  button_window_ = new FloatingButtonWindow();
  button_window_->SetOnMoved(OnWindowMoved, this);
  button_window_->Create();

  // Apply pending position before the window is shown.
  if (has_pending_position_) {
    suppress_next_configure_ = true;
    button_window_->MoveTo(pending_x_, pending_y_);
    has_pending_position_ = false;
  }

  // Open the render channel on the 2nd engine. The engine starts booting
  // when the FlView is realized (inside Create()). The Dart handler fires
  // "ready" when it is live; until then, outgoing calls are cached.
  OpenRenderChannel();
}

void FloatingButtonHost::OpenRenderChannel() {
  FlBinaryMessenger* render_messenger = button_window_->GetRenderMessenger();
  if (!render_messenger) {
    g_warning("[button-host] OpenRenderChannel: render messenger is null");
    return;
  }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  render_channel_ =
      fl_method_channel_new(render_messenger,
                             "com.whispaste.floating_button_render",
                             FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(render_channel_, OnRenderMethodCall,
                                             this, nullptr);
}

// ── Render channel handler (2nd engine → host) ────────────────────────────────

// static
void FloatingButtonHost::OnRenderMethodCall(FlMethodChannel* /*channel*/,
                                             FlMethodCall* method_call,
                                             gpointer user_data) {
  static_cast<FloatingButtonHost*>(user_data)->HandleRenderMethodCall(
      method_call);
}

void FloatingButtonHost::HandleRenderMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "ready") == 0) {
    // ── ready ─────────────────────────────────────────────────────────────
    // The render engine's Dart MethodChannel handler is live. Flush any state
    // that arrived while the engine was still booting (mirrors macOS).
    g_print("[button-host] render engine ready — flushing cached state\n");
    render_ready_ = true;

    // Flush pending visual state.
    g_autoptr(FlValue) state_args = fl_value_new_map();
    fl_value_set_string_take(state_args, "state",
                              fl_value_new_string(pending_state_.c_str()));
    InvokeRenderChannel("setState", state_args);

    // Flush pending diameter.
    g_autoptr(FlValue) diam_args = fl_value_new_map();
    fl_value_set_string_take(diam_args, "diameter",
                              fl_value_new_int(pending_diameter_));
    InvokeRenderChannel("setDiameter", diam_args);

    // Flush pending theme presets.
    g_autoptr(FlValue) theme_args = fl_value_new_map();
    fl_value_set_string_take(theme_args, "background",
                              fl_value_new_string(pending_background_.c_str()));
    fl_value_set_string_take(theme_args, "wave",
                              fl_value_new_string(pending_wave_.c_str()));
    fl_value_set_string_take(theme_args, "shape",
                              fl_value_new_string(pending_shape_.c_str()));
    fl_value_set_string_take(theme_args, "ring",
                              fl_value_new_bool(pending_ring_));
    fl_value_set_string_take(theme_args, "idleOpacity",
                              fl_value_new_float(pending_idle_opacity_));
    InvokeRenderChannel("setTheme", theme_args);

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "clicked") == 0) {
    // ── clicked ───────────────────────────────────────────────────────────
    // Tap on the button disc — relay as onClicked to the main engine.
    InvokeMainChannel("onClicked", nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "startDrag") == 0) {
    // ── startDrag ─────────────────────────────────────────────────────────
    // The user began a pan gesture on the button disc (Dart onPanStart).
    // WindowDragMover follows the pointer until the button is released and
    // reports the final position once via OnDragEnded. Not a WM move:
    // KWin refuses to move NOTIFICATION windows (see window_drag_mover.h).
    //
    // TUNING: X11-only, like every window move here (GDK_BACKEND=x11, see
    // main.cc); without XWayland the pointer cannot be queried.
    if (button_window_ && button_window_->IsCreated()) {
      drag_mover_.Start(GTK_WINDOW(button_window_->GetGtkWindow()));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "showContextMenu") == 0) {
    // ── showContextMenu ───────────────────────────────────────────────────
    // If we have items, show the GTK popup and emit onContextMenu{id} for
    // the selected item. If items list is empty, emit onSecondaryClicked
    // (mirrors macOS/Windows behaviour).
    if (context_menu_items_.empty()) {
      InvokeMainChannel("onSecondaryClicked", nullptr);
    } else {
      ShowContextMenu();
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ── Context menu ──────────────────────────────────────────────────────────────

void FloatingButtonHost::ShowContextMenu() {
  GtkWidget* menu = gtk_menu_new();
  for (const auto& item : context_menu_items_) {
    GtkWidget* menu_item =
        gtk_menu_item_new_with_label(item.label.c_str());

    // Heap-allocate callback data; destroyed by the GClosureNotify below.
    auto* data = new MenuItemCallbackData{this, item.id};
    g_signal_connect_data(
        menu_item, "activate",
        G_CALLBACK(OnMenuItemActivated), data,
        [](gpointer p, GClosure*) {
          delete static_cast<MenuItemCallbackData*>(p);
        },
        static_cast<GConnectFlags>(0));

    gtk_menu_shell_append(GTK_MENU_SHELL(menu), menu_item);
  }
  gtk_widget_show_all(menu);

  // Popup at the current pointer position.
  // gtk_menu_popup_at_pointer requires GTK >= 3.22 (Ubuntu 18.04+).
#if GTK_CHECK_VERSION(3, 22, 0)
  gtk_menu_popup_at_pointer(GTK_MENU(menu), nullptr);
#else
  gtk_menu_popup(GTK_MENU(menu), nullptr, nullptr, nullptr, nullptr, 3,
                  GDK_CURRENT_TIME);
#endif
}

// static
void FloatingButtonHost::OnMenuItemActivated(GtkMenuItem* /*item*/,
                                              gpointer user_data) {
  auto* data = static_cast<MenuItemCallbackData*>(user_data);
  // NOTE: key is "id" (not "action" as in the overlay channel).
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id",
                            fl_value_new_string(data->id.c_str()));
  data->host->InvokeMainChannel("onContextMenu", args);
}

// ── Drag / position tracking ──────────────────────────────────────────────────

// static
void FloatingButtonHost::OnWindowMoved(int x, int y, void* user_data) {
  auto* self = static_cast<FloatingButtonHost*>(user_data);

  // If we triggered this configure-event programmatically (via setPosition or
  // show), skip emitting onDragEnded to avoid a Dart-side feedback loop.
  if (self->suppress_next_configure_) {
    self->suppress_next_configure_ = false;
    return;
  }
  // The drag mover's own steps; it reports the end position itself.
  if (self->drag_mover_.IsActive()) return;
  // The configure-event of the mover's last step, already reported.
  if (x == self->current_x_ && y == self->current_y_) return;

  // Store the new position.
  self->current_x_ = x;
  self->current_y_ = y;

  // Report the final drag position to the main engine.
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "x",
                            fl_value_new_float(static_cast<double>(x)));
  fl_value_set_string_take(args, "y",
                            fl_value_new_float(static_cast<double>(y)));
  self->InvokeMainChannel("onDragEnded", args);
}

// static
void FloatingButtonHost::OnDragEnded(int x, int y, void* user_data) {
  auto* self = static_cast<FloatingButtonHost*>(user_data);
  self->current_x_ = x;
  self->current_y_ = y;

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "x",
                            fl_value_new_float(static_cast<double>(x)));
  fl_value_set_string_take(args, "y",
                            fl_value_new_float(static_cast<double>(y)));
  self->InvokeMainChannel("onDragEnded", args);
}

// ── Channel invocation helpers ────────────────────────────────────────────────

void FloatingButtonHost::InvokeMainChannel(const char* method, FlValue* args) {
  if (!channel_) return;
  fl_method_channel_invoke_method(channel_, method, args, nullptr, OnInvokeDone,
                                   nullptr);
}

void FloatingButtonHost::InvokeRenderChannel(const char* method,
                                              FlValue* args) {
  if (!render_channel_ || !render_ready_) return;
  fl_method_channel_invoke_method(render_channel_, method, args, nullptr,
                                   OnInvokeDone, nullptr);
}

// static
void FloatingButtonHost::OnInvokeDone(GObject* source, GAsyncResult* result,
                                       gpointer /*user_data*/) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(source), result, &error);
  if (error) {
    g_warning("[button-host] channel invoke error: %s", error->message);
  }
}
