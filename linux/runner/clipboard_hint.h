#ifndef RUNNER_CLIPBOARD_HINT_H_
#define RUNNER_CLIPBOARD_HINT_H_

#include <gtk/gtk.h>

#include <string>

// Target that tells Klipper to keep the content out of its history. Only
// Klipper honours it: GPaste and other managers record the text anyway.
inline constexpr char kClipboardHintTarget[] = "x-kde-passwordManagerHint";

// Puts [text] on [clipboard] with every GTK text target (UTF8_STRING, STRING,
// text/plain, ...) plus the history-exclusion hint, so pasting works in any
// app and Klipper skips the entry. Returns false when GTK refuses the
// ownership; the caller decides how to react.
bool SetClipboardTextHidden(GtkClipboard* clipboard, const std::string& text);

// Target infos the hidden-text payload registers: [get] callbacks tell a text
// request from a request for the hint by them.
inline constexpr guint kClipboardTextInfo = 0;
inline constexpr guint kClipboardHintInfo = 1;

// Owns [clipboard] with the same targets as SetClipboardTextHidden, but serves
// them through the caller's callbacks (the read receipt counts text requests).
// [get] answers with SetHiddenClipboardSelection. Returns false when GTK
// refuses the ownership; [clear] is then never called for [user_data].
bool SetClipboardHiddenWithData(GtkClipboard* clipboard,
                                GtkClipboardGetFunc get,
                                GtkClipboardClearFunc clear,
                                gpointer user_data);

// Answers one request for a hidden-text payload: "secret" for the hint
// target, [text] for every text target.
void SetHiddenClipboardSelection(GtkSelectionData* data, guint info,
                                 const std::string& text);

#endif  // RUNNER_CLIPBOARD_HINT_H_
