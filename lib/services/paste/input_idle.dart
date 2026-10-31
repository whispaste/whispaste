/// Native input-idle state, read at one moment (DEV-185, GS-056).
///
/// All values are seconds since the event, as reported by the OS:
/// [keyIdle] and [mouseIdle] since the last hardware key-down or left/right
/// mouse-down, [syntheticIdle] since WhisPaste's own last synthetic key-down
/// (a large value when none was sent).
class InputIdleSnapshot {
  const InputIdleSnapshot({
    required this.keyIdle,
    required this.mouseIdle,
    required this.syntheticIdle,
  });

  final double keyIdle;
  final double mouseIdle;
  final double syntheticIdle;
}

/// The OS may report a hardware key-down a few milliseconds after our own
/// synthetic one. Keys inside this window are not counted as typing.
const double syntheticKeyTolerance = 0.05;

/// Whether the user typed or clicked since an insert that started [elapsed]
/// ago. A null [snapshot] (the platform cannot answer) counts as typed, so
/// the caller takes the clipboard path.
///
/// Known limit: a keypress between the start of the paste call and our
/// synthetic Cmd+V is missed when no key follows it. Keys that land within
/// [syntheticKeyTolerance] after our own key-down are also hidden.
bool userInputSince(Duration elapsed, InputIdleSnapshot? snapshot) {
  if (snapshot == null) return true;
  final seconds = elapsed.inMicroseconds / 1000000;
  final typed =
      snapshot.keyIdle < seconds &&
      snapshot.keyIdle < snapshot.syntheticIdle - syntheticKeyTolerance;
  final clicked = snapshot.mouseIdle < seconds;
  return typed || clicked;
}
