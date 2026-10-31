// Runtime test of ClipboardReceipt (clipboard_receipt.h) on a real X display:
// the parent owns the clipboard, a forked process reads it like a clipboard
// monitor, Klipper or the paste target would, and finally takes it over.
// Run via test/scripts/clipboard_receipt_test.sh (private Xvfb).
#include "clipboard_receipt.h"

#include <sys/wait.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "clipboard_hint.h"

namespace {

const char kText[] = "Grüße aus dem Diktat — WhisPaste";
const char kPrevious[] = "what the user had copied";

int failures = 0;

void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}

std::string ReadTarget(GtkClipboard* clipboard, const char* name) {
  GtkSelectionData* data =
      gtk_clipboard_wait_for_contents(clipboard, gdk_atom_intern(name, FALSE));
  if (!data) return {};
  const gint length = gtk_selection_data_get_length(data);
  std::string result;
  if (length > 0) {
    result.assign(
        reinterpret_cast<const char*>(gtk_selection_data_get_data(data)),
        static_cast<size_t>(length));
  }
  gtk_selection_data_free(data);
  return result;
}

// The reader runs one command per byte from the parent and answers with one
// byte, so every parent check sees the reads before it completed.
int Reader(int commands, int replies) {
  gtk_init(nullptr, nullptr);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  char command = 0;
  while (read(commands, &command, 1) == 1) {
    switch (command) {
      case 'm': {  // A clipboard monitor: target list plus the text.
        GdkAtom* targets = nullptr;
        gint count = 0;
        gtk_clipboard_wait_for_targets(clipboard, &targets, &count);
        g_free(targets);
        Expect(ReadTarget(clipboard, "UTF8_STRING") == kText,
               "a monitor reads the transcript");
        break;
      }
      case 'k':  // Klipper: target list and the history hint, no text.
        Expect(ReadTarget(clipboard, kClipboardHintTarget) == "secret",
               "Klipper reads the hint");
        break;
      case 'p':  // The paste target.
        Expect(ReadTarget(clipboard, "UTF8_STRING") == kText,
               "the paste target reads the transcript");
        break;
      case 'r': {  // After the restore.
        gchar* text = gtk_clipboard_wait_for_text(clipboard);
        Expect(text && std::strcmp(text, kPrevious) == 0,
               "the restore put the previous text back");
        g_free(text);
        break;
      }
      case 't':  // Another app copies something.
        gtk_clipboard_set_text(clipboard, "someone else", -1);
        gdk_display_flush(gdk_display_get_default());
        break;
      case 'q':
        return failures == 0 ? 0 : 1;
      default:
        return 2;
    }
    if (write(replies, "d", 1) != 1) return 2;
  }
  return 2;
}

class Parent {
 public:
  Parent(int commands, int replies) : commands_(commands), replies_(replies) {}

  // Sends [command] and serves selection requests until the reader answered.
  void Run(char command) {
    if (write(commands_, &command, 1) != 1) {
      Expect(false, "command pipe");
      return;
    }
    struct Wait {
      GMainLoop* loop;
      guint watch;
      guint timeout;
    } wait{g_main_loop_new(nullptr, FALSE), 0, 0};
    GIOChannel* channel = g_io_channel_unix_new(replies_);
    wait.watch = g_io_add_watch(
        channel, static_cast<GIOCondition>(G_IO_IN | G_IO_HUP),
        [](GIOChannel* source, GIOCondition, gpointer data) -> gboolean {
          auto* w = static_cast<Wait*>(data);
          char byte = 0;
          if (read(g_io_channel_unix_get_fd(source), &byte, 1) != 1) {
            Expect(false, "reader answered");
          }
          w->watch = 0;
          g_main_loop_quit(w->loop);
          return G_SOURCE_REMOVE;
        },
        &wait);
    wait.timeout = g_timeout_add_seconds(
        20,
        [](gpointer data) -> gboolean {
          auto* w = static_cast<Wait*>(data);
          Expect(false, "reader timed out");
          w->timeout = 0;
          g_main_loop_quit(w->loop);
          return G_SOURCE_REMOVE;
        },
        &wait);
    g_main_loop_run(wait.loop);
    if (wait.timeout != 0) g_source_remove(wait.timeout);
    if (wait.watch != 0) g_source_remove(wait.watch);
    g_io_channel_unref(channel);
    g_main_loop_unref(wait.loop);
    // Lets the SelectionClear of a takeover arrive before the next check.
    for (int i = 0; i < 50 && g_main_context_iteration(nullptr, FALSE); ++i) {
    }
  }

 private:
  int commands_;
  int replies_;
};

}  // namespace

int main() {
  int to_reader[2];
  int to_parent[2];
  if (pipe(to_reader) != 0 || pipe(to_parent) != 0) return 2;
  const pid_t pid = fork();
  if (pid < 0) return 2;
  if (pid == 0) {
    close(to_reader[1]);
    close(to_parent[0]);
    _exit(Reader(to_reader[0], to_parent[1]));
  }
  close(to_reader[0]);
  close(to_parent[1]);

  gtk_init(nullptr, nullptr);
  ClipboardReceipt receipt(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  Parent parent(to_reader[1], to_parent[0]);
  std::string status;
  auto record = [&status](const char* s) { status = s; };

  Expect(receipt.Write(kText), "the receipt write takes the clipboard");

  // Reads before the shortcut are monitors, not the paste.
  status.clear();
  receipt.Wait(record);
  parent.Run('m');
  Expect(status.empty(), "a monitor read before the shortcut is no receipt");

  receipt.MarkKeystrokePosted();
  parent.Run('k');
  Expect(status.empty(), "the Klipper hint request is no receipt");

  // WhisPaste's own read (the side panel snapshot) is answered in-process.
  {
    ClipboardReceipt::ScopedSelfRead self_read;
    gchar* own = gtk_clipboard_wait_for_text(
        gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
    Expect(own && std::strcmp(own, kText) == 0, "the own read gets the text");
    g_free(own);
  }
  Expect(status.empty(), "WhisPaste's own read is no receipt");

  parent.Run('p');
  Expect(status == "read", "the target's read after the shortcut is read");
  status.clear();
  receipt.Wait(record);
  Expect(status == "read", "a later wait still answers read");

  Expect(receipt.RestoreIfOwner(kPrevious) == "restored",
         "the owner restores the previous text");
  parent.Run('r');

  // A takeover before any read answers lost and blocks the restore.
  Expect(receipt.Write(kText), "the second receipt write takes the clipboard");
  receipt.MarkKeystrokePosted();
  status.clear();
  receipt.Wait(record);
  parent.Run('t');
  Expect(status == "lost", "another writer's copy answers lost");
  status.clear();
  receipt.Wait(record);
  Expect(status == "lost", "a wait after the takeover answers lost");
  Expect(receipt.RestoreIfOwner(kPrevious) == "not_owner",
         "no restore over someone else's copy");

  // A newer wait or write supersedes a pending one.
  Expect(receipt.Write(kText), "the third receipt write takes the clipboard");
  status.clear();
  receipt.Wait(record);
  Expect(receipt.Write(kText), "a rewrite takes the clipboard again");
  Expect(status == "superseded", "a rewrite supersedes the pending wait");

  // Without the guard GTK answers an in-process read through the same
  // callback, which is why the side panel marks its reads.
  Expect(receipt.Write(kText), "the fourth receipt write takes the clipboard");
  receipt.MarkKeystrokePosted();
  status.clear();
  receipt.Wait(record);
  gchar* unmarked = gtk_clipboard_wait_for_text(
      gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  g_free(unmarked);
  Expect(status == "read", "an unmarked in-process read reaches the receipt");

  if (write(to_reader[1], "q", 1) != 1) return 2;
  int child = 0;
  waitpid(pid, &child, 0);
  if (!WIFEXITED(child) || WEXITSTATUS(child) != 0) {
    std::fprintf(stderr, "FAIL: reader checks\n");
    ++failures;
  }
  if (failures != 0) return 1;
  std::printf("clipboard_receipt_test: all checks passed\n");
  return 0;
}
