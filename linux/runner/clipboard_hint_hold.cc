// Test tool for test/scripts/klipper_hint_e2e.sh: owns the clipboard for a
// few seconds so a clipboard manager can read it. "hint" writes through
// SetClipboardTextHidden (clipboard_hint.h), "plain" through
// gtk_clipboard_set_text as a control.
#include "clipboard_hint.h"

#include <cstring>

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  if (argc != 3) return 2;
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if (std::strcmp(argv[1], "hint") == 0) {
    if (!SetClipboardTextHidden(clipboard, argv[2])) return 1;
  } else {
    gtk_clipboard_set_text(clipboard, argv[2], -1);
  }
  g_timeout_add_seconds(
      3,
      [](gpointer) -> gboolean {
        gtk_main_quit();
        return G_SOURCE_REMOVE;
      },
      nullptr);
  gtk_main();
  return 0;
}
