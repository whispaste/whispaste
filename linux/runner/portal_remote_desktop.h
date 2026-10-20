#ifndef FLUTTER_PORTAL_REMOTE_DESKTOP_H_
#define FLUTTER_PORTAL_REMOTE_DESKTOP_H_

#include <gio/gio.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

class EisKeyboardSender;

// Keyboard input through xdg-desktop-portal RemoteDesktop (version 2): the
// second input path next to uinput, for GNOME, KDE and Flatpak without
// /dev/uinput. The portal shows a consent dialog once; the restore token
// returned with it lets later sessions skip the dialog.
//
// Flow: CreateSession -> SelectDevices(KEYBOARD, persist_mode=2, restore_token)
// -> Start (the dialog) -> ConnectToEIS (an EIS socket) -> libei keyboard.
//
// Every portal request is asynchronous, so Connect() returns at once and the
// callback runs later on the GLib main loop. The portal call uses the session
// bus, so it also works under GDK_BACKEND=x11 (XWayland).
//
// Main thread only.
class PortalRemoteDesktop {
 public:
  enum class ConnectOutcome { kConnected, kCancelled, kUnavailable, kFailed };

  struct ConnectResult {
    ConnectOutcome status = ConnectOutcome::kFailed;
    // Set when connected; the caller stores it for the next Connect().
    std::string restore_token;
    // Diagnostic text for the log only, never sent over the channel.
    std::string detail;
  };
  using ConnectCallback = std::function<void(const ConnectResult&)>;

  PortalRemoteDesktop();
  ~PortalRemoteDesktop();

  PortalRemoteDesktop(const PortalRemoteDesktop&) = delete;
  PortalRemoteDesktop& operator=(const PortalRemoteDesktop&) = delete;

  // True when this build has libei, libei.so.1 loads, and the RemoteDesktop
  // portal on the session bus provides version 2 or later. Blocks briefly
  // (sync bus call with a short timeout).
  static bool IsAvailable();

  // Starts a session. [restore_token] may be empty. [done] runs exactly once:
  // with the outcome, or with kCancelled when Disconnect() ends the attempt.
  // A second Connect() while one is pending is answered with kFailed.
  void Connect(const std::string& restore_token, ConnectCallback done);

  // Closes the portal session and drops the EIS sender. A pending Connect()
  // is answered with kCancelled.
  void Disconnect();

  bool connected() const;

  // Ctrl(+Shift)+[keycode] (evdev code) through the EIS sender. False when no
  // session is connected or the keyboard device is not ready.
  bool SendCtrlShortcut(uint32_t keycode, bool shift);

 private:
  struct Flow;

  GDBusConnection* Bus();
  void FinishFlow(Flow* flow, ConnectResult result);

  GDBusConnection* bus_ = nullptr;
  std::unique_ptr<EisKeyboardSender> sender_;
  std::string session_handle_;
  Flow* flow_ = nullptr;
};

#endif  // FLUTTER_PORTAL_REMOTE_DESKTOP_H_
