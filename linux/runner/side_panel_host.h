#ifndef FLUTTER_SIDE_PANEL_HOST_H_
#define FLUTTER_SIDE_PANEL_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "side_panel_window.h"

// Owns the public MethodChannel com.whispaste.side_panel (issue 06, Linux/
// XWayland port) and bridges it to the private render channel on the second
// engine (com.whispaste.side_panel_render). Structural precedent:
// floating_overlay_host.{h,cc} (per-monitor shell, monitor hotplug via
// GdkDisplay signals, lazy render-engine boot). Behavioral precedent:
// macos/Runner/SidePanelHost.swift and windows/runner/side_panel_host
// .{h,cpp} (dwell-to-open, close-grace, slide animation -- same constants,
// see kDwellMs/kCloseGraceMs/kSlideDurationMs below).
//
//   main engine  ←→  SidePanelHost  ←→  SidePanelContentWindow
//        ↕            (relay / translate)        ↕
//  public channel                        render channel (2nd engine)
//
// ── Clipboard: snapshot-on-open, not a rolling buffer (PRD.md, ticket 06)
//
// Unlike macOS's ClipboardMonitorHost.swift and windows/runner/clipboard_
// monitor_host.{h,cpp} -- both of which poll/listen continuously for the
// whole app session -- this host reads the clipboard exactly once, at the
// moment the sensor's dwell timer fires (HandleHoverEntered, i.e. "the panel
// is about to open"), and reports at most one `clipEntryDetected` on the
// SAME `com.whispaste.clipboard_history` channel the continuous monitors
// use. `ClipboardHistoryMonitorService` (Dart) has no idea whether an entry
// arrived from a 0.3s poll or a single on-open read, so this needs no Dart-
// side branching. This is a deliberate PRD decision, not a partial port:
// background clipboard *monitoring* on GNOME/Wayland (no portal API for it,
// polling would have to run indefinitely against a compositor that can
// suspend/throttle background apps) is structurally too fragile to promise a
// live history the way macOS/Windows can -- reading once, synchronously, at
// the one moment the feature is actually about to be used sidesteps that
// entirely.
//
// This host therefore also owns the self-write-suppression registry
// (`markSelfWrite` handler on the clipboard_history channel) that the
// continuous monitors keep on the OTHER platforms -- same FNV-1a 64
// fingerprint + 2s expiry as Swift's SelfWriteSuppressionRegistry / the
// Windows host's Fingerprint map, just consulted once per open instead of
// once per poll tick.
//
// ── Why this panel never takes keyboard focus (unlike SnippetPickerHost)
//
// See side_panel_window.h's file comment for the full reasoning: Linux's
// Auto-Paste bridge (DesktopPasteHost, uinput) has no window-targeting
// concept at all, unlike macOS/Windows, which can force-reactivate their
// captured target before pasting. If this panel took real keyboard focus,
// a row click's paste() would send Ctrl+V into the panel itself. So there is
// no X11 focus save/restore here (contrast SnippetPickerHost, which DOES
// take focus and DOES need it) and no search-field keyboard input on Linux
// yet -- mouse hover/click only.
class SidePanelHost {
 public:
  // |main_messenger| is the main engine's binary messenger.
  explicit SidePanelHost(FlBinaryMessenger* main_messenger);
  ~SidePanelHost();

  SidePanelHost(const SidePanelHost&) = delete;
  SidePanelHost& operator=(const SidePanelHost&) = delete;

  // Rebuilds the per-monitor sensor strips -- call on monitor hotplug
  // (mirrors FloatingOverlayHost::RevalidateOnScreen's monitor-added/-removed
  // wiring, and SidePanelHost.swift's rebuildSensors).
  void RebuildSensors();

 private:
  // ── Public channel (main engine) ─────────────────────────────────────
  FlMethodChannel* channel_ = nullptr;
  bool destroyed_ = false;

  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                            gpointer user_data);
  void HandleMethodCall(FlMethodCall* method_call);
  void HandleUpdateSnapshot(FlValue* args);
  void Destroy();

  // ── Render engine / content shell (lazy, 2nd engine) ──────────────────
  std::unique_ptr<SidePanelContentWindow> content_window_;
  FlMethodChannel* render_channel_ = nullptr;
  bool render_ready_ = false;
  FlValue* latest_snapshot_args_ = nullptr;  // Retained; unref'd in dtor.

  bool EnsureContentWindow();
  void OpenRenderChannel();
  static void OnRenderMethodCall(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data);
  void HandleRenderMethodCall(FlMethodCall* method_call);

  // ── Sensors (one per monitor) ──────────────────────────────────────────
  std::vector<std::unique_ptr<SidePanelSensorWindow>> sensors_;
  gulong monitor_added_handler_id_ = 0;
  gulong monitor_removed_handler_id_ = 0;
  static void OnMonitorChanged(GdkDisplay* display, GdkMonitor* monitor,
                                gpointer user_data);

  void HandleHoverEntered(const GdkRectangle& work_area);
  void HandleRawEnter();
  void HandleRawExit();

  // ── Content-window hover (native close-grace fallback) ────────────────
  void HandleContentEnter();
  void HandleContentExit();
  void ScheduleNativeClose();
  void CancelNativeClose();
  static gboolean OnNativeCloseTimeout(gpointer user_data);
  guint close_timer_id_ = 0;

  // ── Layout ───────────────────────────────────────────────────────────
  void ComputeTargetRect(const GdkRectangle& work_area, bool shown, int* x,
                          int* y, int* width, int* height) const;
  void PositionPanel(const GdkRectangle& work_area);
  void SlideIn();
  void SlideOut();

  bool is_shown_ = false;
  std::optional<GdkRectangle> current_work_area_;
  std::optional<GdkRectangle> pending_rect_;

  // ── Clipboard snapshot-on-open (see class comment) ────────────────────
  struct Fingerprint {
    size_t length;
    uint64_t hash;
    bool operator==(const Fingerprint& other) const {
      return length == other.length && hash == other.hash;
    }
  };
  struct FingerprintHash {
    size_t operator()(const Fingerprint& f) const {
      return std::hash<size_t>()(f.length) ^
             (std::hash<uint64_t>()(f.hash) << 1);
    }
  };
  static Fingerprint FingerprintOfUtf8(const std::string& utf8);
  void MarkSelfWrite(const Fingerprint& fp);
  bool ShouldSuppress(const Fingerprint& fp);
  static constexpr double kSuppressionExpirySeconds = 2.0;
  std::unordered_map<Fingerprint, gint64, FingerprintHash>
      pending_self_writes_;  // value = absolute expiry (g_get_monotonic_time)

  FlMethodChannel* clipboard_channel_ = nullptr;
  void HandleClipboardMethodCall(FlMethodCall* method_call);
  static void OnClipboardMethodCall(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data);
  // Reads the clipboard once (GTK's synchronous API, already used
  // elsewhere in this runner -- see desktop_paste_host.cc) and reports at
  // most one clipEntryDetected, unless the content is self-write-suppressed.
  void EmitClipboardSnapshot();

  // ── Helpers ───────────────────────────────────────────────────────────
  void InvokeMainChannel(const char* method, FlValue* args);
  void InvokeRenderChannel(const char* method, FlValue* args);
  static void OnInvokeDone(GObject* source, GAsyncResult* result,
                            gpointer user_data);

  // ── Layout constants (GTK logical px -- GDK resolves per-monitor DPI
  // scaling itself, see snippet_picker_window.h's file comment) ──────────
  static constexpr int kSensorWidth = 6;
  static constexpr int kContentWidth = 320;
  static constexpr int kContentHeight = 640;
  static constexpr int kSlideDurationMs = 220;
  static constexpr int kDwellMs = 60;
  static constexpr int kCloseGraceMs = 350;
};

#endif  // FLUTTER_SIDE_PANEL_HOST_H_
