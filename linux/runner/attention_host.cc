#include "attention_host.h"

#include <gdk/gdkx.h>

#include <cstring>

namespace {

constexpr char kChannelName[] = "com.whispaste.attention";

}  // namespace

AttentionHost::AttentionHost(FlBinaryMessenger* messenger, GtkWindow* window)
    : window_(window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                            nullptr);
  if (window_ != nullptr) {
    g_signal_connect(window_, "focus-in-event", G_CALLBACK(OnFocusIn), this);
    g_signal_connect(window_, "destroy", G_CALLBACK(OnWindowDestroy), this);
  }
}

AttentionHost::~AttentionHost() {
  if (window_ != nullptr) {
    g_signal_handlers_disconnect_by_data(window_, this);
  }
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
  }
  g_clear_object(&channel_);
}

void AttentionHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                 FlMethodCall* method_call,
                                 gpointer user_data) {
  auto* self = static_cast<AttentionHost*>(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  if (strcmp(method, "requestUserAttention") == 0) {
    // The level from Dart ("critical") is not distinguished here: an urgency
    // hint has no repeat count, it stays until the window is focused.
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(self->RequestAttention())));
  } else if (strcmp(method, "cancelUserAttentionRequest") == 0) {
    self->CancelAttention();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

gboolean AttentionHost::OnFocusIn(GtkWidget* /*widget*/,
                                  GdkEventFocus* /*event*/,
                                  gpointer user_data) {
  // The user is back in the app: the attention request is answered.
  static_cast<AttentionHost*>(user_data)->CancelAttention();
  return FALSE;
}

void AttentionHost::OnWindowDestroy(GtkWidget* /*widget*/,
                                    gpointer user_data) {
  auto* self = static_cast<AttentionHost*>(user_data);
  self->window_ = nullptr;
  self->urgent_ = false;
}

bool AttentionHost::RequestAttention() {
  if (window_ == nullptr) return false;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window_));
  if (display == nullptr || !GDK_IS_X11_DISPLAY(display)) return false;
  gtk_window_set_urgency_hint(window_, TRUE);
  urgent_ = true;
  return true;
}

void AttentionHost::CancelAttention() {
  if (window_ == nullptr || !urgent_) return;
  gtk_window_set_urgency_hint(window_, FALSE);
  urgent_ = false;
}
