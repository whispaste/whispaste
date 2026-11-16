#include "flutter_keyval.h"

#include <gdk/gdkkeysyms.h>

guint hotkey_keyval_from_flutter(guint64 keyval) {
  // Accept both GTK keyvals and Flutter logical IDs at the channel boundary.
  // The latter is uni_platform's fallback when GTK has no logical mapping.
  if (keyval >= 0x0010000080d && keyval <= 0x00100000818) {
    return GDK_KEY_F13 + static_cast<guint>(keyval - 0x0010000080d);
  }
  switch (keyval) {
    case GDK_KEY_KP_Space:
      return GDK_KEY_space;
    case GDK_KEY_KP_F1:
      return GDK_KEY_F1;
    case GDK_KEY_KP_F2:
      return GDK_KEY_F2;
    case GDK_KEY_KP_F3:
      return GDK_KEY_F3;
    case GDK_KEY_KP_F4:
      return GDK_KEY_F4;
    case GDK_KEY_KP_Decimal:
      return GDK_KEY_period;
    default:
      return keyval;
  }
}

guint hotkey_function_key_alias(guint keyval, bool mapped) {
  return keyval == GDK_KEY_F13 && !mapped ? GDK_KEY_Tools : keyval;
}
