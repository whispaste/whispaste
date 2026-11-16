#ifndef RUNNER_CLIPBOARD_SNAPSHOT_H_
#define RUNNER_CLIPBOARD_SNAPSHOT_H_

#include <gtk/gtk.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

// Full clipboard backup around a dictation's paste (P1.1), the GTK
// counterpart of the pasteboard item copy on macOS and the format copy on
// Windows: every selection target the owner offers (image/png, text/html,
// text/uri-list, ...) is fetched and can be served again after the paste.
//
// Fetching is asynchronous, target by target, so a slow or frozen owner
// never blocks the GTK main thread; a time budget and a byte cap end the
// snapshot early with "failed", and Dart then saves plain text only.
class ClipboardSnapshot {
 public:
  struct Target {
    GdkAtom target;
    GdkAtom type;
    gint format;
    std::string data;
  };

  struct Result {
    std::string status;  // "saved", "empty" or "failed"
    std::string text;    // UTF-8 text form, when the content has one
    bool has_text = false;
    int formats = 0;
    int64_t bytes = 0;
  };

  using Done = std::function<void(const Result& result)>;

  explicit ClipboardSnapshot(GtkClipboard* clipboard);
  ~ClipboardSnapshot();

  ClipboardSnapshot(const ClipboardSnapshot&) = delete;
  ClipboardSnapshot& operator=(const ClipboardSnapshot&) = delete;

  // Replaces any earlier snapshot and calls [done] once with the result.
  void Take(Done done);

  // Owns [clipboard_] with the saved targets plus the Klipper history hint.
  // False when nothing is saved or GTK refuses the ownership. The saved data
  // is handed to GTK and the snapshot is empty afterwards.
  bool Restore();

  void Discard();

  bool HasData() const { return !targets_.empty(); }

  // Whether [name] is a meta target that is never copied (TARGETS, ...).
  static bool IsMetaTarget(const char* name);

 // One snapshot in flight; public so the callback holders can name it.
  struct Job;

 private:
  static void OnTargets(GtkClipboard* clipboard, GdkAtom* atoms, gint count,
                        gpointer user_data);
  static void OnContents(GtkClipboard* clipboard, GtkSelectionData* data,
                         gpointer user_data);
  static gboolean OnTimeout(gpointer user_data);

  void RequestNext(const std::shared_ptr<Job>& job);
  void Finish(const std::shared_ptr<Job>& job, const char* status);

  GtkClipboard* clipboard_;
  std::vector<Target> targets_;
  std::shared_ptr<Job> job_;
};

#endif  // RUNNER_CLIPBOARD_SNAPSHOT_H_
