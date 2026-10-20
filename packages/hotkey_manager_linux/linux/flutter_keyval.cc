#include "flutter_keyval.h"

#include <gdk/gdkkeysyms.h>

guint hotkey_keyval_from_flutter(guint keyval) {
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
