> **WhisPaste fork of record_macos 2.1.1.** `RecorderStreamDelegate.stop()`
> stops the engine before it touches voice processing, as AVAudioIONode
> requires and as upstream record_darwin does. Guard:
> `test/services/audio/record_macos_fork_test.dart` in the app repo.

