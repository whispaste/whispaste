> **WhisPaste fork of hotkey_manager_macos 0.2.0.** Reports a failed Carbon registration (probe before HotKey) as PlatformException hotkey_unavailable.
> The app shows the hotkey conflict from it, as on Linux.
> A missing native key code reports `hotkey_unsupported` without a forced
> cast. macOS exposes F13–F20; F21–F24 have no Carbon key code. Device acceptance
> of the extended function keys is still pending.

# hotkey_manager_macos

[![pub version][pub-image]][pub-url]

[pub-image]: https://img.shields.io/pub/v/hotkey_manager_macos.svg
[pub-url]: https://pub.dev/packages/hotkey_manager_macos

The macOS implementation of [hotkey_manager](https://pub.dev/packages/hotkey_manager).

## License

[MIT](./LICENSE)
