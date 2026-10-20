#ifndef HOTKEY_MANAGER_LINUX_FLUTTER_KEYVAL_H_
#define HOTKEY_MANAGER_LINUX_FLUTTER_KEYVAL_H_

#include <glib.h>

// WhisPaste fork: the key code the Dart side sends is the first GDK keyval
// that Flutter's kGtkToLogicalKey maps to the logical key. For Space, F1-F4
// and the period that is the keypad variant (KP_Space, KP_F1...), which no
// common keyboard has, so the grab fails. The safe-default hotkey
// Ctrl+Shift+Space could therefore never be registered. Returns the main
// keyboard keyval for those keys and every other keyval unchanged.
guint hotkey_keyval_from_flutter(guint keyval);

#endif  // HOTKEY_MANAGER_LINUX_FLUTTER_KEYVAL_H_
