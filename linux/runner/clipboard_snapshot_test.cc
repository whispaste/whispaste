// Runtime test of ClipboardSnapshot (clipboard_snapshot.h) on a real X
// display: a forked process owns rich clipboard content (PNG, HTML, text),
// the parent snapshots it, pastes through a receipt and restores it; the
// owner process then checks that every format came back unchanged, and that
// no restore happens over a copy made in between (P1.1).
// Run via test/scripts/clipboard_snapshot_test.sh (private Xvfb).
#include "clipboard_snapshot.h"

#include <sys/wait.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "clipboard_hint.h"
#include "clipboard_receipt.h"

namespace {

const char kText[] = "Grüße aus dem Diktat — WhisPaste";
const char kHtml[] = "<b>copied</b> rich text";
const char kPlain[] = "copied rich text";
// Binary payload with NUL bytes, as an image has.
const std::string kPng("\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\x01\0\x01", 20);

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

// --- Owner process: serves rich content while it waits for commands. ---

void GetRich(GtkClipboard* /*clipboard*/, GtkSelectionData* data, guint info,
             gpointer /*user_data*/) {
  switch (info) {
    case 0:
      gtk_selection_data_set(data, gdk_atom_intern_static_string("image/png"),
                             8, reinterpret_cast<const guchar*>(kPng.data()),
                             static_cast<gint>(kPng.size()));
      break;
    case 1:
      gtk_selection_data_set(data, gdk_atom_intern_static_string("text/html"),
                             8, reinterpret_cast<const guchar*>(kHtml),
                             static_cast<gint>(std::strlen(kHtml)));
      break;
    default:
      gtk_selection_data_set_text(data, kPlain, -1);
  }
}

void ClearRich(GtkClipboard* /*clipboard*/, gpointer /*user_data*/) {}

struct Owner {
  int replies;
  GtkClipboard* clipboard;
  GMainLoop* loop;
};

gboolean OnCommand(GIOChannel* source, GIOCondition /*condition*/,
                   gpointer data) {
  auto* owner = static_cast<Owner*>(data);
  char command = 0;
  if (read(g_io_channel_unix_get_fd(source), &command, 1) != 1) {
    g_main_loop_quit(owner->loop);
    return G_SOURCE_REMOVE;
  }
  switch (command) {
    case 'o': {  // Copy rich content.
      static const GtkTargetEntry kTargets[] = {
          {const_cast<gchar*>("image/png"), 0, 0},
          {const_cast<gchar*>("text/html"), 0, 1},
          {const_cast<gchar*>("UTF8_STRING"), 0, 2},
      };
      Expect(gtk_clipboard_set_with_data(owner->clipboard, kTargets, 3,
                                         GetRich, ClearRich, nullptr),
             "the owner takes the clipboard");
      break;
    }
    case 'r':  // After the restore: every format is back.
      Expect(ReadTarget(owner->clipboard, "image/png") == kPng,
             "the image came back byte for byte");
      Expect(ReadTarget(owner->clipboard, "text/html") == kHtml,
             "the HTML came back");
      Expect(ReadTarget(owner->clipboard, "UTF8_STRING") == kPlain,
             "the text form came back");
      Expect(ReadTarget(owner->clipboard, kClipboardHintTarget) == "secret",
             "the restore carries the history hint");
      break;
    case 'p':  // The paste target reads the transcript.
      Expect(ReadTarget(owner->clipboard, "UTF8_STRING") == kText,
             "the paste target reads the transcript");
      break;
    case 't':  // Another app copies something.
      gtk_clipboard_set_text(owner->clipboard, "someone else", -1);
      gdk_display_flush(gdk_display_get_default());
      break;
    case 'q':
      g_main_loop_quit(owner->loop);
      return G_SOURCE_REMOVE;
    default:
      ++failures;
  }
  if (write(owner->replies, "d", 1) != 1) ++failures;
  return G_SOURCE_CONTINUE;
}

int OwnerProcess(int commands, int replies) {
  gtk_init(nullptr, nullptr);
  Owner owner{replies, gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
              g_main_loop_new(nullptr, FALSE)};
  GIOChannel* channel = g_io_channel_unix_new(commands);
  g_io_add_watch(channel, static_cast<GIOCondition>(G_IO_IN | G_IO_HUP),
                 OnCommand, &owner);
  g_main_loop_run(owner.loop);
  g_io_channel_unref(channel);
  g_main_loop_unref(owner.loop);
  return failures == 0 ? 0 : 1;
}

// --- Parent: WhisPaste. ---

// Runs the main loop until [done] is set or 20 s pass.
void RunUntil(const bool& done) {
  const gint64 deadline = g_get_monotonic_time() + 20 * G_USEC_PER_SEC;
  while (!done && g_get_monotonic_time() < deadline) {
    g_main_context_iteration(nullptr, TRUE);
  }
  Expect(done, "finished in time");
}

// Sends [command] and serves selection requests until the owner answered.
void Run(int commands, int replies, char command) {
  if (write(commands, &command, 1) != 1) {
    Expect(false, "command pipe");
    return;
  }
  bool answered = false;
  GIOChannel* channel = g_io_channel_unix_new(replies);
  struct Wait {
    bool* answered;
  } wait{&answered};
  const guint watch = g_io_add_watch(
      channel, static_cast<GIOCondition>(G_IO_IN | G_IO_HUP),
      [](GIOChannel* source, GIOCondition, gpointer data) -> gboolean {
        char byte = 0;
        if (read(g_io_channel_unix_get_fd(source), &byte, 1) != 1) {
          Expect(false, "owner answered");
        }
        *static_cast<Wait*>(data)->answered = true;
        return G_SOURCE_REMOVE;
      },
      &wait);
  RunUntil(answered);
  if (!answered) g_source_remove(watch);
  g_io_channel_unref(channel);
  // Lets the SelectionClear of a takeover arrive before the next check.
  for (int i = 0; i < 50 && g_main_context_iteration(nullptr, FALSE); ++i) {
  }
}

ClipboardSnapshot::Result Snapshot(ClipboardSnapshot& snapshot) {
  ClipboardSnapshot::Result result;
  bool done = false;
  snapshot.Take([&](const ClipboardSnapshot::Result& r) {
    result = r;
    done = true;
  });
  RunUntil(done);
  return result;
}

}  // namespace

int main() {
  int to_owner[2];
  int to_parent[2];
  if (pipe(to_owner) != 0 || pipe(to_parent) != 0) return 2;
  const pid_t pid = fork();
  if (pid < 0) return 2;
  if (pid == 0) {
    close(to_owner[1]);
    close(to_parent[0]);
    _exit(OwnerProcess(to_owner[0], to_parent[1]));
  }
  close(to_owner[0]);
  close(to_parent[1]);
  const int commands = to_owner[1];
  const int replies = to_parent[0];

  gtk_init(nullptr, nullptr);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  ClipboardReceipt receipt(clipboard);
  ClipboardSnapshot snapshot(clipboard);

  Expect(ClipboardSnapshot::IsMetaTarget("TARGETS"), "TARGETS is meta");
  Expect(!ClipboardSnapshot::IsMetaTarget("image/png"), "image/png is data");

  // Restore keeps the type: image, HTML and text all come back.
  Run(commands, replies, 'o');
  ClipboardSnapshot::Result saved = Snapshot(snapshot);
  Expect(saved.status == "saved", "the rich clipboard is saved");
  Expect(saved.formats == 3, "all three formats are saved");
  Expect(saved.has_text && saved.text == kPlain, "the text form is reported");
  Expect(receipt.Write(kText), "the receipt write takes the clipboard");
  receipt.MarkKeystrokePosted();
  Run(commands, replies, 'p');
  Expect(receipt.RestoreIfOwnerWith([&] { return snapshot.Restore(); }) ==
             "restored",
         "the owner restores the snapshot");
  Expect(!snapshot.HasData(), "the snapshot is handed over");
  Run(commands, replies, 'r');

  // No restore after the clipboard changed.
  Run(commands, replies, 'o');
  saved = Snapshot(snapshot);
  Expect(saved.status == "saved", "the second snapshot is saved");
  Expect(receipt.Write(kText), "the second receipt write takes the clipboard");
  receipt.MarkKeystrokePosted();
  Run(commands, replies, 't');
  bool restored = false;
  Expect(receipt.RestoreIfOwnerWith([&] {
           restored = true;
           return snapshot.Restore();
         }) == "not_owner",
         "no restore over someone else's copy");
  Expect(!restored, "the snapshot is not written after a takeover");
  snapshot.Discard();
  Expect(!snapshot.HasData(), "discard drops the snapshot");

  // WhisPaste's own transcript on the clipboard is snapshotted in-process
  // without counting as the paste receipt.
  Expect(receipt.Write(kText), "the third receipt write takes the clipboard");
  receipt.MarkKeystrokePosted();
  std::string status;
  receipt.Wait([&status](const char* s) { status = s; });
  saved = Snapshot(snapshot);
  Expect(saved.status == "saved", "the own transcript is saved");
  Expect(saved.has_text && saved.text == kText, "the own text is reported");
  Expect(status.empty(), "the own snapshot read is no receipt");

  if (write(commands, "q", 1) != 1) return 2;
  int child = 0;
  waitpid(pid, &child, 0);
  if (!WIFEXITED(child) || WEXITSTATUS(child) != 0) {
    std::fprintf(stderr, "FAIL: owner checks\n");
    ++failures;
  }
  if (failures != 0) return 1;
  std::printf("clipboard_snapshot_test: all checks passed\n");
  return 0;
}
