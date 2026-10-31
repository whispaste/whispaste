#ifndef RUNNER_CLIPBOARD_RECEIPT_H_
#define RUNNER_CLIPBOARD_RECEIPT_H_

#include <gtk/gtk.h>

#include <functional>
#include <string>

// Read receipt for the transcript on the Linux clipboard (GR-015), the GTK
// counterpart of delayed rendering on Windows and the pasteboard data
// provider on macOS.
//
// X11 hands clipboard data out only on request: the owner gets a selection
// request per read. A text request after the paste shortcut went out is the
// target's paste, and losing the selection means another writer took the
// clipboard. Under Wayland WhisPaste runs on XWayland (GDK_BACKEND=x11), and
// the compositor turns a Wayland app's read into the same selection request.
// Requests before the shortcut come from clipboard monitors and do not count;
// Klipper only asks for the target list and the history hint, never the text.
class ClipboardReceipt {
 public:
  // Called once with "read", "lost" or "superseded".
  using Resolve = std::function<void(const char* status)>;

  explicit ClipboardReceipt(GtkClipboard* clipboard);
  ~ClipboardReceipt();

  ClipboardReceipt(const ClipboardReceipt&) = delete;
  ClipboardReceipt& operator=(const ClipboardReceipt&) = delete;

  // Puts [text] on the clipboard as hidden text and arms the receipt. False
  // when GTK refuses the ownership; Dart then uses the classic write.
  bool Write(const std::string& text);

  // From here on, a text request for the armed receipt counts as the paste.
  void MarkKeystrokePosted();

  // Resolves at once with "read" or "lost" when that is already known,
  // otherwise on the next read, takeover or newer wait ("superseded"). Never
  // times out; Dart bounds the wait.
  void Wait(Resolve resolve);

  // Writes [text] back (hidden) only while WhisPaste still owns the clipboard
  // since Write: "restored", "not_owner" or "failed".
  std::string RestoreIfOwner(const std::string& text);

  // Same owner check, but [write] puts the content back (the full snapshot,
  // P1.1). [write] returns false when GTK refused the ownership.
  std::string RestoreIfOwnerWith(const std::function<bool()>& write);

  // Resolves a pending wait with "superseded" (host shutdown).
  void Cancel();

  // Marks WhisPaste's own clipboard reads, such as the side panel snapshot.
  // GTK answers a read from the owning process through the same get
  // callback, and such a read is not the target's paste.
  class ScopedSelfRead {
   public:
    ScopedSelfRead() { ++depth_; }
    ~ScopedSelfRead() { --depth_; }
    ScopedSelfRead(const ScopedSelfRead&) = delete;
    ScopedSelfRead& operator=(const ScopedSelfRead&) = delete;

    static bool Active() { return depth_ > 0; }

   private:
    static int depth_;
  };

 private:
  struct Payload {
    ClipboardReceipt* owner;
    std::string text;
  };

  static void OnGet(GtkClipboard* clipboard, GtkSelectionData* data,
                    guint info, gpointer user_data);
  static void OnClear(GtkClipboard* clipboard, gpointer user_data);

  void ResolvePending(const char* status);

  GtkClipboard* clipboard_;
  // Payload of the armed write; GTK owns it until its clear callback.
  Payload* current_ = nullptr;
  bool active_ = false;
  bool keystroke_posted_ = false;
  bool read_ = false;
  Resolve pending_;
};

#endif  // RUNNER_CLIPBOARD_RECEIPT_H_
