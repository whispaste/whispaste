> **WhisPaste fork of hotkey_manager_linux 0.2.0.** Binds with keybinder's raw
> accelerator matching (`linux/keybinder_raw.cc`), so hotkeys made of Shift
> plus a letter, such as Ctrl+Shift+D, fire on X11. Runtime test:
> `test/scripts/keybinder_raw_test.sh` in the app repo.
> A GDK X11 filter tracks physical releases before keybinder runs, suppressing
> held-key repeats (including legacy X11 release/press pairs) while allowing
> immediate second presses. Dart treats these callbacks like Windows
> `MOD_NOREPEAT`; the Wayland monitor keeps its separate repeat protection.
> F13–F24 accept GTK keyvals and Flutter logical IDs. An unmapped F13 uses
> XKB's XF86Tools alias; a missing layout mapping reports `hotkey_unsupported`
> rather than claiming another app owns the key. Real X11/Wayland acceptance
> of these function keys is still pending.

# hotkey_manager_linux

[![pub version][pub-image]][pub-url]

[pub-image]: https://img.shields.io/pub/v/hotkey_manager_linux.svg
[pub-url]: https://pub.dev/packages/hotkey_manager_linux

The Linux implementation of [hotkey_manager](https://pub.dev/packages/hotkey_manager).

## License

[MIT](./LICENSE)
