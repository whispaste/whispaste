> **WhisPaste fork of hotkey_manager_windows 0.2.0.** Reports a failed RegisterHotKey as PlatformException hotkey_unavailable.
> The app shows the hotkey conflict from it, as on Linux.
> Registrations use `MOD_NOREPEAT`: each delivered down is a new physical
> press, including quick successive presses. Dart must not debounce these.
> The runner compares RawInput with each low-level hook's timestamps and
> reinstalls a silent hook on input after a one-second grace period.

# hotkey_manager_windows

[![pub version][pub-image]][pub-url]

[pub-image]: https://img.shields.io/pub/v/hotkey_manager_windows.svg
[pub-url]: https://pub.dev/packages/hotkey_manager_windows

The Windows implementation of [hotkey_manager](https://pub.dev/packages/hotkey_manager).

## License

[MIT](./LICENSE)
