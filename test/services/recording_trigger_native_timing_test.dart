/// Hold, tap and double tap are decided from the host's own event times, so a
/// stalled UI thread (events arrive late and bunched) changes nothing. Without
/// a stamp the arrival time decides, as before.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

void main() {
  late int stop;
  late int doubleTap;
  late bool recording;
  late DateTime now;
  Duration? at;
  Duration? pressed;
  late RecordingTriggerHandler handler;

  void build({bool doubleTapOn = false}) {
    stop = 0;
    doubleTap = 0;
    recording = false;
    now = DateTime(2026, 11, 5);
    at = null;
    pressed = null;
    handler = RecordingTriggerHandler(
      startRecording: () async => recording = true,
      stopRecording: () async {
        stop++;
        recording = false;
      },
      toggleRecording: () async => recording = !recording,
      pushToTalkEnabled: () => !doubleTapOn,
      registrarSupportsKeyUp: () => true,
      holdOrTapEnabled: () => !doubleTapOn,
      doubleTapEnabled: () => doubleTapOn,
      doubleTapLatches: () => false,
      singleKey: () => doubleTapOn,
      onDoubleTap: () async => doubleTap++,
      isRecording: () => recording,
      clock: () => now,
      nativeEventAt: () => at,
      nativePressed: () => pressed,
    );
  }

  /// One stamped event: native time [nativeMs], delivered at [arrivalMs].
  void stamped(int arrivalMs, int nativeMs, void Function() event) {
    now = DateTime(2026, 11, 5).add(Duration(milliseconds: arrivalMs));
    at = Duration(milliseconds: nativeMs);
    event();
    at = null;
  }

  test('a hold whose events arrive bunched is still a hold', () {
    build();
    // Native: 600 ms hold. A stalled UI thread delivers both at once.
    stamped(1500, 5000, handler.onKeyDown);
    stamped(1510, 5600, handler.onKeyUp);
    expect(stop, 1, reason: 'the hold ends the recording');
  });

  test('a real tap delivered late stays a tap', () {
    build();
    // Native: 100 ms tap. The release reaches Dart 900 ms later.
    stamped(1000, 5000, handler.onKeyDown);
    stamped(1900, 5100, handler.onKeyUp);
    expect(stop, 0, reason: 'a 100 ms tap latches, it does not stop');
  });

  test('double tap pairs by native times when the second tap arrives late', () {
    build(doubleTapOn: true);
    // Native: tap 60 ms, 190 ms gap, tap. The second press reaches Dart
    // 700 ms after the first release.
    stamped(3000, 5000, handler.onKeyDown);
    stamped(3300, 5060, handler.onKeyUp);
    expect(handler.lastHeldMs, 60);
    stamped(4000, 5250, handler.onKeyDown);
    stamped(4001, 5350, handler.onKeyUp);
    expect(doubleTap, 1);
  });

  test('taps far apart natively are no double tap', () {
    build(doubleTapOn: true);
    stamped(3000, 5000, handler.onKeyDown);
    stamped(3100, 5100, handler.onKeyUp);
    stamped(3900, 5900, handler.onKeyDown);
    stamped(4000, 6000, handler.onKeyUp);
    expect(doubleTap, 0);
  });

  test('an unstamped key-down uses the press length of the release', () {
    build();
    // Grab path: no stamp on the down; the host timed 700 ms. Both events
    // reach Dart at the same instant after a stall.
    now = DateTime(2026, 11, 5, 0, 0, 1);
    handler.onKeyDown();
    pressed = const Duration(milliseconds: 700);
    handler.onKeyUp();
    pressed = null;
    expect(stop, 1);
  });

  test('without any stamp the arrival time decides', () {
    build();
    now = DateTime(2026, 11, 5, 0, 0, 1);
    handler.onKeyDown();
    now = now.add(const Duration(milliseconds: 600));
    handler.onKeyUp();
    expect(stop, 1);
  });

  test('a twisted stamp pair falls back to the arrival time', () {
    build();
    // Release stamped before the press: not a usable length. Arrival says a
    // 600 ms hold, which is what counts.
    stamped(1000, 5000, handler.onKeyDown);
    stamped(1600, 4000, handler.onKeyUp);
    expect(stop, 1);
  });

  test('a restarted native clock does not skew the next press', () {
    build();
    stamped(1000, 900000, handler.onKeyDown);
    stamped(1600, 900600, handler.onKeyUp);
    expect(stop, 1);
    // The host restarted: its clock starts near zero again. A 100 ms tap must
    // still be a tap.
    stamped(5000, 10, handler.onKeyDown);
    stamped(5100, 110, handler.onKeyUp);
    expect(handler.lastHeldMs, 100);
    expect(stop, 1, reason: 'the tap did not stop anything');
  });
}
