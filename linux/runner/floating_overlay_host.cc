#include "floating_overlay_host.h"

#include <gdk/gdk.h>

#include <cstring>

// ── Construction / destruction ───────────────────────────────────────────────

FloatingOverlayHost::FloatingOverlayHost(FlBinaryMessenger* main_messenger) {
  // Open the public channel on the MAIN engine messenger.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ = fl_method_channel_new(main_messenger,
                                    "com.whispaste.floating_overlay",
                                    FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                             nullptr);
}

FloatingOverlayHost::~FloatingOverlayHost() {
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
  if (latest_snapshot_args_) {
    fl_value_unref(latest_snapshot_args_);
    latest_snapshot_args_ = nullptr;
  }
  if (latest_bars_args_) {
    fl_value_unref(latest_bars_args_);
    latest_bars_args_ = nullptr;
  }
  delete overlay_window_;
  overlay_window_ = nullptr;
}

// ── Public channel handler ────────────────────────────────────────────────────

// static
void FloatingOverlayHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  static_cast<FloatingOverlayHost*>(user_data)->HandleMethodCall(method_call);
}

void FloatingOverlayHost::HandleMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "updateSnapshot") == 0) {
    // ── updateSnapshot ────────────────────────────────────────────────────
    // args: { visible, compact, state, isDark, label, … }
    bool visible = false;
    bool compact = false;
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* visible_val = fl_value_lookup_string(args, "visible");
      if (visible_val && fl_value_get_type(visible_val) == FL_VALUE_TYPE_BOOL) {
        visible = fl_value_get_bool(visible_val);
      }
      FlValue* compact_val = fl_value_lookup_string(args, "compact");
      if (compact_val && fl_value_get_type(compact_val) == FL_VALUE_TYPE_BOOL) {
        compact = fl_value_get_bool(compact_val);
      }
    }

    bool size_changed = (compact != is_compact_);
    is_compact_ = compact;

    if (visible && overlay_window_ == nullptr) {
      // Lazy-create the overlay shell on first visible updateSnapshot.
      EnsureOverlayWindow();
    } else if (size_changed && overlay_window_ != nullptr) {
      // Resize the existing shell when the compact flag flips.
      overlay_window_->SetCompact(is_compact_);
      // Re-anchor after resize (matching macOS resizePanelToContent).
      if (overlay_window_->IsCreated()) {
        auto [rx, ry] =
            ResolvePosition(pending_x_, pending_y_, pending_anchor_mode_);
        suppress_next_configure_ = true;
        overlay_window_->MoveTo(rx, ry);
      }
    }

    // Cache and relay to the render engine.
    if (latest_snapshot_args_) fl_value_unref(latest_snapshot_args_);
    latest_snapshot_args_ = args ? fl_value_ref(args) : nullptr;
    if (render_ready_) {
      InvokeRenderChannel("updateSnapshot", args);
    }

    // Show or hide the native shell.
    if (overlay_window_) {
      if (visible) {
        overlay_window_->Show();
      } else {
        overlay_window_->Hide();
      }
    }

    response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setWaveformBars") == 0) {
    // ── setWaveformBars ───────────────────────────────────────────────────
    // args: { bars: [double, …] }
    // Relay pre-computed bar array straight to the render engine; the shell
    // keeps no waveform state of its own (mirrors macOS behaviour).
    if (latest_bars_args_) fl_value_unref(latest_bars_args_);
    latest_bars_args_ = args ? fl_value_ref(args) : nullptr;
    if (render_ready_) {
      InvokeRenderChannel("setWaveformBars", args);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setPosition") == 0) {
    // ── setPosition ───────────────────────────────────────────────────────
    // args: { x, y, anchorMode }
    double x = 0.0, y = 0.0;
    std::string anchor_mode = "topLeft";
    if (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* xv = fl_value_lookup_string(args, "x");
      FlValue* yv = fl_value_lookup_string(args, "y");
      FlValue* av = fl_value_lookup_string(args, "anchorMode");
      if (xv) x = fl_value_get_float(xv);
      if (yv) y = fl_value_get_float(yv);
      if (av && fl_value_get_type(av) == FL_VALUE_TYPE_STRING) {
        anchor_mode = fl_value_get_string(av);
      }
    }
    pending_anchor_mode_ = anchor_mode;
    auto [rx, ry] = ResolvePosition(x, y, anchor_mode);
    pending_x_ = rx;
    pending_y_ = ry;
    if (overlay_window_ && overlay_window_->IsCreated()) {
      suppress_next_configure_ = true;
      overlay_window_->MoveTo(rx, ry);
    } else {
      has_pending_position_ = true;
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

  } else if (strcmp(method, "destroy") == 0) {
    // ── destroy ───────────────────────────────────────────────────────────
    // Called by MethodChannelPlatformHost.dispose() from Dart. Tear down the
    // overlay window and render channel; the host itself is deleted by the
    // GtkApplication in my_application_dispose().
    if (render_channel_) {
      fl_method_channel_set_method_call_handler(render_channel_, nullptr,
                                                 nullptr, nullptr);
      g_object_unref(render_channel_);
      render_channel_ = nullptr;
    }
    if (latest_snapshot_args_) {
      fl_value_unref(latest_snapshot_args_);
      latest_snapshot_args_ = nullptr;
    }
    if (latest_bars_args_) {
      fl_value_unref(latest_bars_args_);
      latest_bars_args_ = nullptr;
    }
    delete overlay_window_;
    overlay_window_ = nullptr;
    render_ready_ = false;
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ── Overlay window creation ───────────────────────────────────────────────────

void FloatingOverlayHost::EnsureOverlayWindow() {
  render_ready_ = false;
  overlay_window_ = new FloatingOverlayWindow();
  overlay_window_->SetOnMoved(OnWindowMoved, this);
  overlay_window_->SetCompact(is_compact_);
  overlay_window_->Create();

  // Apply pending position before the window is shown.
  if (has_pending_position_) {
    suppress_next_configure_ = true;
    overlay_window_->MoveTo(pending_x_, pending_y_);
    has_pending_position_ = false;
  }

  // Open the render channel on the 2nd engine. The engine starts booting
  // when the FlView is realized (inside Create()). The Dart handler fires
  // "ready" when it is live; until then, outgoing calls are cached.
  OpenRenderChannel();
}

void FloatingOverlayHost::OpenRenderChannel() {
  FlBinaryMessenger* render_messenger = overlay_window_->GetRenderMessenger();
  if (!render_messenger) {
    g_warning("[overlay-host] OpenRenderChannel: render messenger is null");
    return;
  }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  render_channel_ =
      fl_method_channel_new(render_messenger,
                             "com.whispaste.floating_overlay_render",
                             FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(render_channel_, OnRenderMethodCall,
                                             this, nullptr);
}

// ── Render channel handler (2nd engine → host) ────────────────────────────────

// static
void FloatingOverlayHost::OnRenderMethodCall(FlMethodChannel* /*channel*/,
                                              FlMethodCall* method_call,
                                              gpointer user_data) {
  static_cast<FloatingOverlayHost*>(user_data)->HandleRenderMethodCall(
      method_call);
}

void FloatingOverlayHost::HandleRenderMethodCall(FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "ready") == 0) {
    // ── ready ─────────────────────────────────────────────────────────────
    // The render engine's Dart MethodChannel handler is live. Flush any state
    // that arrived while the engine was still booting (mirrors macOS).
    g_print("[overlay-host] render engine ready — flushing cached state\n");
    render_ready_ = true;
    if (latest_bars_args_) {
      InvokeRenderChannel("setWaveformBars", latest_bars_args_);
    }
    if (latest_snapshot_args_) {
      InvokeRenderChannel("updateSnapshot", latest_snapshot_args_);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "startDrag") == 0) {
    // ── startDrag ─────────────────────────────────────────────────────────
    // The user began a pan gesture on the overlay pill (Dart onPanStart).
    // We initiate a WM-level window move via gdk_window_begin_move_drag,
    // which sends _NET_WM_MOVERESIZE to the X11 WM (GNOME Shell via XWayland).
    // The WM then handles the interactive drag; configure-event fires on
    // position changes and OnWindowMoved reports them as onDragEnded events.
    //
    // TUNING: gdk_window_begin_move_drag is X11-only and only reliable when
    // GDK_BACKEND=x11 is set (see main.cc). On a bare Wayland session without
    // XWayland it will be a no-op — ensure XWayland is running.
    //
    // TUNING: There is a latency of ~1 MethodChannel round-trip between the
    // Dart gesture and this call, so root_x/root_y is the pointer position at
    // handler time, not at the exact pan-start instant. This is accurate enough
    // for WM interactive-move initiation in practice.
    if (overlay_window_ && overlay_window_->IsCreated()) {
      GtkWidget* gtk_win = overlay_window_->GetGtkWindow();
      GdkWindow* gdk_win = gtk_win ? gtk_widget_get_window(gtk_win) : nullptr;
      if (gdk_win) {
        GdkDisplay* display = gdk_display_get_default();
        GdkSeat* seat = gdk_display_get_default_seat(display);
        GdkDevice* pointer = gdk_seat_get_pointer(seat);
        gint root_x = 0, root_y = 0;
        gdk_device_get_position(pointer, nullptr, &root_x, &root_y);
        // Button 1 = left mouse button. GDK_CURRENT_TIME lets the X server
        // use the most recent event timestamp (avoids focus-theft rejection).
        gdk_window_begin_move_drag(gdk_win, 1, root_x, root_y,
                                    GDK_CURRENT_TIME);
      }
      pending_anchor_mode_ = "topLeft";
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "bodyClicked") == 0) {
    // ── bodyClicked ───────────────────────────────────────────────────────
    // Tap on the pill body — relay to the main engine (toggles recording).
    InvokeMainChannel("onBodyClicked", nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "showContextMenu") == 0) {
    // ── showContextMenu ───────────────────────────────────────────────────
    ShowContextMenu();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// ── Context menu ──────────────────────────────────────────────────────────────

void FloatingOverlayHost::ShowContextMenu() {
  if (context_menu_items_.empty()) return;

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
void FloatingOverlayHost::OnMenuItemActivated(GtkMenuItem* /*item*/,
                                               gpointer user_data) {
  auto* data = static_cast<MenuItemCallbackData*>(user_data);
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "action",
                            fl_value_new_string(data->id.c_str()));
  data->host->InvokeMainChannel("onContextMenu", args);
}

// ── Drag / position tracking ──────────────────────────────────────────────────

// static
void FloatingOverlayHost::OnWindowMoved(int x, int y, void* user_data) {
  auto* self = static_cast<FloatingOverlayHost*>(user_data);

  // If we triggered this configure-event programmatically (via setPosition),
  // skip emitting onDragEnded to avoid a Dart-side feedback loop.
  if (self->suppress_next_configure_) {
    self->suppress_next_configure_ = false;
    return;
  }

  // Store the new raw position (drag mode = "topLeft").
  self->pending_x_ = x;
  self->pending_y_ = y;
  self->pending_anchor_mode_ = "topLeft";

  // Report the final drag position to the main engine.
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "x", fl_value_new_float(static_cast<double>(x)));
  fl_value_set_string_take(args, "y", fl_value_new_float(static_cast<double>(y)));
  fl_value_set_string_take(args, "anchorMode", fl_value_new_string("topLeft"));
  self->InvokeMainChannel("onDragEnded", args);
}

// ── Position resolution ───────────────────────────────────────────────────────

std::pair<int, int> FloatingOverlayHost::ResolvePosition(
    double x, double y, const std::string& anchor_mode) {
  constexpr int kMargin = 16;

  if (anchor_mode == "topCenter" || anchor_mode == "bottomCenter") {
    // Use the primary monitor's work area (excludes taskbar / panels).
    GdkDisplay* display = gdk_display_get_default();
    if (!display) return {static_cast<int>(x), static_cast<int>(y)};

    GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
    if (!monitor) return {static_cast<int>(x), static_cast<int>(y)};

    GdkRectangle work_area;
    gdk_monitor_get_workarea(monitor, &work_area);

    int w = is_compact_ ? kOverlayCompactW : kOverlayNormalW;
    int h = is_compact_ ? kOverlayCompactH : kOverlayNormalH;

    if (anchor_mode == "topCenter") {
      int px = work_area.x + (work_area.width - w) / 2;
      int py = work_area.y + kMargin;
      return {px, py};
    } else {  // bottomCenter
      int px = work_area.x + (work_area.width - w) / 2;
      int py = work_area.y + work_area.height - h - kMargin;
      return {px, py};
    }
  }

  // "topLeft" (and any unknown mode) — use raw coordinates.
  return {static_cast<int>(x), static_cast<int>(y)};
}

// ── Channel invocation helpers ────────────────────────────────────────────────

void FloatingOverlayHost::InvokeMainChannel(const char* method, FlValue* args) {
  if (!channel_) return;
  fl_method_channel_invoke_method(channel_, method, args, nullptr, OnInvokeDone,
                                   nullptr);
}

void FloatingOverlayHost::InvokeRenderChannel(const char* method,
                                               FlValue* args) {
  if (!render_channel_ || !render_ready_) return;
  fl_method_channel_invoke_method(render_channel_, method, args, nullptr,
                                   OnInvokeDone, nullptr);
}

// static
void FloatingOverlayHost::OnInvokeDone(GObject* source, GAsyncResult* result,
                                        gpointer /*user_data*/) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(source), result, &error);
  if (error) {
    g_warning("[overlay-host] channel invoke error: %s", error->message);
  }
}
