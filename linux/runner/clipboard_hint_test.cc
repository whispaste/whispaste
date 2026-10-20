// Runtime test of SetClipboardTextHidden (clipboard_hint.h) on a real X
// display: the parent owns the clipboard, a forked reader process checks it
// the way a paste target and Klipper do. Run via
// test/scripts/clipboard_hint_test.sh (private Xvfb).
#include "clipboard_hint.h"

#include <sys/wait.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

namespace {

const char kText[] = "Grüße aus dem Diktat — WhisPaste";

int failures = 0;

void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}

bool HasTarget(GdkAtom* targets, gint count, const char* name) {
  const GdkAtom wanted = gdk_atom_intern(name, FALSE);
  for (gint i = 0; i < count; ++i) {
    if (targets[i] == wanted) return true;
  }
  return false;
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

// Runs in a fresh process, like Klipper or the app that receives the paste.
int Reader() {
  gtk_init(nullptr, nullptr);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);

  GdkAtom* targets = nullptr;
  gint count = 0;
  Expect(gtk_clipboard_wait_for_targets(clipboard, &targets, &count),
         "reader gets the target list");
  Expect(HasTarget(targets, count, kClipboardHintTarget),
         "the Klipper hint target is offered");
  // Apps that only ask for one of these must still be able to paste.
  Expect(HasTarget(targets, count, "UTF8_STRING"), "UTF8_STRING is offered");
  Expect(HasTarget(targets, count, "STRING"), "STRING is offered");
  Expect(HasTarget(targets, count, "text/plain;charset=utf-8"),
         "text/plain;charset=utf-8 is offered");
  g_free(targets);

  // Klipper skips the entry when the hint data is exactly "secret".
  Expect(ReadTarget(clipboard, kClipboardHintTarget) == "secret",
         "the hint data is \"secret\"");
  Expect(ReadTarget(clipboard, "UTF8_STRING") == kText,
         "UTF8_STRING returns the text unchanged");

  gchar* text = gtk_clipboard_wait_for_text(clipboard);
  Expect(text && std::strcmp(text, kText) == 0,
         "gtk_clipboard_wait_for_text returns the text");
  g_free(text);
  return failures == 0 ? 0 : 1;
}

struct ParentState {
  GMainLoop* loop;
  int status;
};

void OnReaderExit(GPid /*pid*/, gint status, gpointer user_data) {
  auto* state = static_cast<ParentState*>(user_data);
  state->status = status;
  g_main_loop_quit(state->loop);
}

}  // namespace

int main() {
  int ready[2];
  if (pipe(ready) != 0) return 2;
  const pid_t pid = fork();
  if (pid < 0) return 2;
  if (pid == 0) {
    close(ready[1]);
    char byte = 0;
    if (read(ready[0], &byte, 1) != 1) _exit(2);
    _exit(Reader());
  }
  close(ready[0]);

  gtk_init(nullptr, nullptr);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if (!SetClipboardTextHidden(clipboard, kText)) {
    std::fprintf(stderr, "FAIL: SetClipboardTextHidden refused ownership\n");
    return 1;
  }
  if (write(ready[1], "r", 1) != 1) return 2;
  close(ready[1]);

  // Serve the reader's selection requests until it exits.
  ParentState state{g_main_loop_new(nullptr, FALSE), -1};
  g_child_watch_add(pid, OnReaderExit, &state);
  g_timeout_add_seconds(
      20,
      [](gpointer loop) -> gboolean {
        std::fprintf(stderr, "FAIL: reader timed out\n");
        g_main_loop_quit(static_cast<GMainLoop*>(loop));
        return G_SOURCE_REMOVE;
      },
      state.loop);
  g_main_loop_run(state.loop);
  g_main_loop_unref(state.loop);

  if (state.status < 0 || !WIFEXITED(state.status) ||
      WEXITSTATUS(state.status) != 0) {
    return 1;
  }
  std::printf("clipboard_hint_test: all checks passed\n");
  return 0;
}
