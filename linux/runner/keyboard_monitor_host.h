#ifndef FLUTTER_KEYBOARD_MONITOR_HOST_H_
#define FLUTTER_KEYBOARD_MONITOR_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

#include "menu_mask.h"

#include <array>
#include <optional>
#include <string>
#include <vector>

// Xlib's own typedef, repeated so this header does not drag the Xlib macros
// (None, Bool, Status, ...) into every includer.
typedef struct _XDisplay Display;

// Owns the public MethodChannel com.whispaste.keyboard_monitor on Linux —
// the push-to-talk key-up source (catchup/09, shipped as experimental).
// Dart side: lib/services/keyboard_up_monitor.dart.
//
// The global hotkey itself stays an X11 grab (hotkey_manager/keybinder, the
// runner forces GDK_BACKEND=x11), which only ever reports key-DOWN. This host
// adds the release, through whichever of two paths the session supports:
//
//  1. X11 session — XInput2 raw key events on a private Display connection.
//     Raw events observe the keyboard globally without grabbing anything, so
//     the existing grab keeps suppressing and delivering the press. Like the
//     Windows RawInput host, the press of a grabbed key is not reliably
//     visible, so `armRelease` (sent by Dart on key-down) snapshots the held
//     non-modifier key via XQueryKeymap. Autorepeat arrives as a
//     release/press pair of the same keycode; a release only counts once no
//     press follows within kAutorepeatFilterMs.
//
//  2. Wayland session — xdg-desktop-portal org.freedesktop.portal.GlobalShortcuts
//     (GNOME >= 48, KDE Plasma >= 6), via GDBus. X11 grabs over XWayland only
//     fire while an X11 window has focus, so here the compositor owns the
//     shortcut: CreateSession + BindShortcuts with the hotkey as preferred
//     trigger, then Activated/Deactivated become onKeyDown/onKeyUp. The
//     portal needs an app ID, which an unsandboxed app only has with an
//     installed `<app-id>.desktop` (desktop_entry_installer.h writes one).
//
// `start` replies {x11, portal, wayland: bool, reason?: string}. Neither path
// → both false and Dart keeps the toggle-only behaviour; nothing here may
// crash or block the hotkey. On Wayland the binding outcome arrives later as
// onCapabilities {x11, portal, wayland, bound, reason?}: bound once the
// compositor owns the hotkey, or portal: false with a reason ("no-app-id",
// "unavailable", "declined") when it never will.
// libXtst entry points, resolved with dlopen (see keyboard_monitor_host.cc).
// Xlib's Bool is int; spelled out here like Display above, without its macros.
using XTestFakeKeyEventFn = int (*)(Display*, unsigned int, int, unsigned long);
using XTestQueryExtensionFn = int (*)(Display*, int*, int*, int*, int*);

class KeyboardMonitorHost {
 public:
  explicit KeyboardMonitorHost(FlBinaryMessenger* main_messenger);
  ~KeyboardMonitorHost();

  KeyboardMonitorHost(const KeyboardMonitorHost&) = delete;
  KeyboardMonitorHost& operator=(const KeyboardMonitorHost&) = delete;

  void Destroy();

 private:
  // Context of an in-flight async D-Bus call: the generation it belongs to
  // and, for the start probe, the Dart call still waiting for its reply.
  struct AsyncCall {
    KeyboardMonitorHost* host;
    guint generation;
    FlMethodCall* method_call;  // owned ref or nullptr
  };
  using ResponseHandler = void (KeyboardMonitorHost::*)(guint32 response,
                                                        GVariant* results);

  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);
  void HandleMethodCall(FlMethodCall* method_call);

  void Start(FlMethodCall* method_call, const std::string& trigger,
             const std::string& description);
  // Returns whether the armed main key is still held. False means it was
  // already up at the snapshot, so no release will come.
  bool ArmRelease();

  // Menu mask after a Super-only hold (PAR-036, see menu_mask.h). The
  // mask key is an unmapped X keycode pressed and released through XTest.
  bool LoadXTest();
  unsigned int FindUnusedKeycode();
  void SendMenuMask();
  void Stop();

  // Modifier-only pass-through for `watchModifier` (replies itself).
  void WatchModifier(FlMethodCall* method_call, const std::string& key);
  void SendToDart(const char* method, FlValue* args = nullptr);
  // onKeyUp with the press length ({pressMs}), or without it when unknown.
  void SendKeyUp(std::optional<long> press_ms);
  void SendCapabilities();

  // ── X11 / XInput2 ────────────────────────────────────────────────────────
  bool EnsureXi2();
  void CloseX11();
  void DrainX11Events();
  void ScheduleRelease();
  void CancelPendingRelease();
  static gboolean OnX11Readable(gint fd, GIOCondition condition,
                                gpointer user_data);
  static gboolean OnReleaseConfirmed(gpointer user_data);

  // ── GlobalShortcuts portal ───────────────────────────────────────────────
  void ProbePortal(FlMethodCall* method_call);
  void CallRegister(AsyncCall* ctx);
  void ProbeVersion(AsyncCall* ctx);
  void CancelRegisterRetry();
  static gboolean OnRegisterRetry(gpointer user_data);
  void FinishProbe(AsyncCall* ctx, bool portal_available,
                   const char* reason);
  void CreatePortalSession();
  void OnSessionCreated(guint32 response, GVariant* results);
  void OnShortcutsBound(guint32 response, GVariant* results);
  void ClosePortalSession();
  void PortalFailed(const char* why, const char* reason);
  // Calls a GlobalShortcuts method that answers through an
  // org.freedesktop.portal.Request::Response signal; `handler` receives it.
  // Only one request is ever in flight (CreateSession, then BindShortcuts).
  void CallPortalRequest(const char* method, GVariant* params,
                         const std::string& token, ResponseHandler handler);
  void ClearPendingRequest();
  std::string RequestPath(const std::string& token) const;
  std::string NextToken();
  static void OnPortalCallDone(GObject* source, GAsyncResult* result,
                               gpointer user_data);
  static void OnRegisterDone(GObject* source, GAsyncResult* result,
                             gpointer user_data);
  static void OnVersionDone(GObject* source, GAsyncResult* result,
                            gpointer user_data);
  static void OnPortalSignal(GDBusConnection* connection, const gchar* sender,
                             const gchar* object_path,
                             const gchar* interface_name,
                             const gchar* signal_name, GVariant* parameters,
                             gpointer user_data);
  static void OnRequestResponse(GDBusConnection* connection,
                                const gchar* sender, const gchar* object_path,
                                const gchar* interface_name,
                                const gchar* signal_name, GVariant* parameters,
                                gpointer user_data);

  FlMethodChannel* channel_ = nullptr;
  bool destroyed_ = false;

  // Bumped on every start/stop so async replies of a superseded session are
  // dropped instead of binding a stale shortcut.
  guint generation_ = 0;
  GCancellable* cancellable_ = nullptr;

  // X11 path.
  Display* x_display_ = nullptr;
  int xi_opcode_ = -1;
  guint x_watch_id_ = 0;
  bool x11_active_ = false;
  unsigned int watched_keycode_ = 0;

  // Press timing (X server time, ms). press_down_ms_[k] is when keycode k last
  // went down; press_known_[k] is false until an XI press was seen for it
  // (e.g. it went down before Start). release_ms_ is the time of the watched
  // key's release that is waiting for confirmation.
  std::array<unsigned int, 256> press_down_ms_{};
  std::array<bool, 256> press_known_{};
  unsigned int release_ms_ = 0;

  // Modifier-only pass-through (see `watchModifier`): the X keycode of the
  // watched modifier (0 = none) and the modifier keycodes of the current
  // keymap, looked up once when the watch starts.
  unsigned int watched_modifier_keycode_ = 0;
  std::vector<unsigned int> modifier_keycodes_;

  // Menu mask state: tracker, whether the watched key is a Super key, the
  // unmapped keycode used as mask (0 = none) and XTestFakeKeyEvent (nullptr
  // when libXtst or the XTEST extension is missing).
  MenuMaskTracker menu_mask_;
  bool menu_mask_for_watched_ = false;
  unsigned int menu_mask_keycode_ = 0;
  XTestFakeKeyEventFn menu_mask_fake_key_ = nullptr;
  guint release_timer_id_ = 0;

  // Portal path.
  GDBusConnection* bus_ = nullptr;
  std::string trigger_;
  std::string description_;
  std::string session_handle_;
  std::string portal_reason_;
  bool portal_active_ = false;
  bool portal_bound_ = false;
  // trigger_description the compositor reported for the bound shortcut.
  std::string bound_trigger_;
  // Timestamp of the last Activated (portal units), for the press length.
  guint64 portal_down_units_ = 0;
  bool portal_press_known_ = false;
  guint activated_sub_id_ = 0;
  guint deactivated_sub_id_ = 0;
  guint request_sub_id_ = 0;
  ResponseHandler request_handler_ = nullptr;
  guint token_counter_ = 0;
  bool app_id_registered_ = false;
  int register_attempt_ = 0;
  guint register_retry_id_ = 0;
  AsyncCall* register_retry_ctx_ = nullptr;
};

#endif  // FLUTTER_KEYBOARD_MONITOR_HOST_H_
