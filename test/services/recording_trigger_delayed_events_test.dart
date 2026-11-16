/// A UI stall delays hotkey events (#1194): the decision still follows the
/// native event times, and a lost release never leaves the trigger stuck.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 11, 10, 14, 2, 6);
  late DateTime now;
  Duration? at;
  late bool recording;
  late int starts;
  late int busy;
  late int cancels;
  late Completer<void> startGate;
  late RecordingTriggerHandler handler;

  /// Hold plus double tap on one key; the capture takes [startGate] to open
  /// (the stalled overlay), and a start while a capture still opens is
  /// refused as "busy".
  void build() {
    now = t0;
    at = null;
    recording = false;
    starts = 0;
    busy = 0;
    cancels = 0;
    var opening = false;
    startGate = Completer<void>()..complete();
    Future<void> start() async {
      if (opening || recording) {
        busy++;
        return;
      }
      starts++;
      opening = true;
      await startGate.future;
      opening = false;
      recording = true;
    }

    handler = RecordingTriggerHandler(
      startRecording: start,
      stopRecording: () async => recording = false,
      cancelRecording: () async {
        cancels++;
        recording = false;
      },
      toggleRecording: start,
      pushToTalkEnabled: () => true,
      registrarSupportsKeyUp: () => true,
      holdOrTapEnabled: () => false,
      doubleTapEnabled: () => true,
      doubleTapLatches: () => true,
      singleKey: () => true,
      onDoubleTap: () async {},
      isRecording: () => recording,
      clock: () => now,
      nativeEventAt: () => at,
    );
  }

  void stamped(int arrivalMs, int nativeMs, void Function() event) {
    now = t0.add(Duration(milliseconds: arrivalMs));
    at = Duration(milliseconds: nativeMs);
    event();
    at = null;
  }

  test('events about 1 s late with double-tap native times give a hands-free '
      'recording and no busy refusal', () async {
    build();
    // Native: tap 70 ms, gap 150 ms, second press. The UI thread stalled for
    // 1 s: the first press arrived on time, the rest arrives bunched.
    stamped(0, 5000, handler.onKeyDown);
    stamped(1000, 5070, handler.onKeyUp);
    stamped(1001, 5220, handler.onKeyDown);
    await Future<void>.delayed(Duration.zero);
    stamped(1002, 5300, handler.onKeyUp);
    await Future<void>.delayed(Duration.zero);

    expect(busy, 0, reason: 'no refused second start');
    expect(recording, isTrue, reason: 'hands-free recording runs');
    expect(starts, 2, reason: 'first tap discarded, double tap starts anew');
    // The first tap is cancelled while its start still runs (#331); this fake
    // start ignores that cancel and opens anyway, so the settled release
    // discards the opened capture a second time.
    expect(cancels, 2);
  });

  test('a release lost while the start still opens does not leave the '
      'trigger stuck; the next tap behaves as specified', () async {
    build();
    startGate = Completer<void>();
    now = t0;
    handler.onKeyDown();
    // The release is lost; the lost-release check ends the press (no stamp)
    // while the capture is still opening.
    now = t0.add(const Duration(milliseconds: 900));
    handler.onKeyUp();
    startGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(recording, isFalse, reason: 'the late release stops the hold');

    // Next press: a plain hold starts a recording again, release stops it.
    now = t0.add(const Duration(seconds: 3));
    handler.onKeyDown();
    await Future<void>.delayed(Duration.zero);
    expect(recording, isTrue);
    now = t0.add(const Duration(seconds: 4));
    handler.onKeyUp();
    await Future<void>.delayed(Duration.zero);
    expect(recording, isFalse);
    expect(busy, 0);
  });
}
