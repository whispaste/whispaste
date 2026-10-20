#include "clipboard_hint.h"

namespace {

// Clipboard payload for SetClipboardTextHidden. Owned by GTK until the
// clipboard is cleared (clear callback frees it).
void GetHiddenClipboardPayload(GtkClipboard* /*clipboard*/,
                               GtkSelectionData* data, guint info,
                               gpointer user_data) {
  SetHiddenClipboardSelection(data, info,
                              *static_cast<const std::string*>(user_data));
}

void ClearHiddenClipboardPayload(GtkClipboard* /*clipboard*/,
                                 gpointer user_data) {
  delete static_cast<std::string*>(user_data);
}

}  // namespace

void SetHiddenClipboardSelection(GtkSelectionData* data, guint info,
                                 const std::string& text) {
  if (info == kClipboardHintInfo) {
    // Klipper compares the hint data with "secret".
    static const char kSecret[] = "secret";
    gtk_selection_data_set(data,
                           gdk_atom_intern_static_string(kClipboardHintTarget),
                           8, reinterpret_cast<const guchar*>(kSecret),
                           sizeof(kSecret) - 1);
  } else {
    gtk_selection_data_set_text(data, text.c_str(),
                                static_cast<gint>(text.size()));
  }
}

bool SetClipboardHiddenWithData(GtkClipboard* clipboard,
                                GtkClipboardGetFunc get,
                                GtkClipboardClearFunc clear,
                                gpointer user_data) {
  // The same text targets gtk_clipboard_set_text offers: apps that only ask
  // for UTF8_STRING or STRING still get the text.
  GtkTargetList* list = gtk_target_list_new(nullptr, 0);
  gtk_target_list_add_text_targets(list, kClipboardTextInfo);
  gtk_target_list_add(list, gdk_atom_intern_static_string(kClipboardHintTarget),
                      0, kClipboardHintInfo);
  gint count = 0;
  GtkTargetEntry* targets = gtk_target_table_new_from_list(list, &count);
  gtk_target_list_unref(list);

  const gboolean owned = gtk_clipboard_set_with_data(
      clipboard, targets, static_cast<guint>(count), get, clear, user_data);
  gtk_target_table_free(targets, count);
  return owned;
}

bool SetClipboardTextHidden(GtkClipboard* clipboard, const std::string& text) {
  auto* payload = new std::string(text);
  if (!SetClipboardHiddenWithData(clipboard, GetHiddenClipboardPayload,
                                  ClearHiddenClipboardPayload, payload)) {
    delete payload;
    return false;
  }
  return true;
}
