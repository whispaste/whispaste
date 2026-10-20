#ifndef HOTKEY_MANAGER_LINUX_KEYBINDER_RAW_H_
#define HOTKEY_MANAGER_LINUX_KEYBINDER_RAW_H_

// WhisPaste fork: keybinder_init() with raw accelerator matching.
//
// By default keybinder matches "cooked" accelerators: it first translates the
// pressed key with the active modifiers, so Ctrl+Shift+D arrives as "D" with
// Shift consumed and never equals the binding <Control><Shift>d. Every hotkey
// made of Shift plus a letter, the default Ctrl+Shift+D included, then never
// fires. Raw matching compares keycode and modifiers instead.
//
// keybinder_init() resets the matching mode on every call, so the raw mode
// has to be set again after each one. Use this instead of keybinder_init().
void keybinder_init_raw();

#endif  // HOTKEY_MANAGER_LINUX_KEYBINDER_RAW_H_
