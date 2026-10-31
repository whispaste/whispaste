#include "keybinder_raw.h"

#include <keybinder.h>

void keybinder_init_raw() {
  keybinder_init();
  keybinder_set_use_cooked_accelerators(FALSE);
}
