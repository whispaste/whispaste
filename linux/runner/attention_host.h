// Owns the public MethodChannel com.whispaste.attention (PAR-046).
//
// Sets the urgency hint on the main window (_NET_WM_STATE_DEMANDS_ATTENTION
// on X11), so the taskbar or dock entry flags up as it does on Windows and
// macOS. The hint is cleared when the window gets focus, or when Dart cancels
// the request. Wayland has no attention protocol for normal clients, so there
// the request is answered with false and nothing is faked.

#ifndef FLUTTER_ATTENTION_HOST_H_
#define FLUTTER_ATTENTION_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

class AttentionHost {
 public:
  AttentionHost(FlBinaryMessenger* messenger, GtkWindow* window);
  ~AttentionHost();

  AttentionHost(const AttentionHost&) = delete;
  AttentionHost& operator=(const AttentionHost&) = delete;

 private:
  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);
  static gboolean OnFocusIn(GtkWidget* widget, GdkEventFocus* event,
                            gpointer user_data);
  static void OnWindowDestroy(GtkWidget* widget, gpointer user_data);

  // True when the window runs on X11 and the hint was set.
  bool RequestAttention();
  void CancelAttention();

  FlMethodChannel* channel_ = nullptr;
  GtkWindow* window_ = nullptr;
  bool urgent_ = false;
};

#endif  // FLUTTER_ATTENTION_HOST_H_
