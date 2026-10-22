/// A different key pressed while a modifier-only hotkey is held is no
/// gesture: the recording that the press started is cancelled, and the
/// release then does nothing.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int stop;
  late int cancel;
  late bool recording;
  late DateTime now;
  late RecordingTriggerHandler handler;

  void build({required bool holdOrTap}) {
    stop = 0;
    cancel = 0;
    recording = false;
    now = DateTime(2026, 10, 22);
    handler = RecordingTriggerHandler(
      startRecording: () async {
        recording = true;
      },
      stopRecording: () async {
        stop++;
        recording = false;
      },
      toggleRecording: () async {
        recording = !recording;
      },
      cancelRecording: () async {
        cancel++;
        recording = false;
      },
      pushToTalkEnabled: () => true,
      registrarSupportsKeyUp: () => true,
      holdOrTapEnabled: () => holdOrTap,
      isRecording: () => recording,
      clock: () => now,
    );
  }

  test('PTT: another key during the press cancels the started recording', () {
    build(holdOrTap: false);
    handler.onKeyDown();
    expect(recording, isTrue);
    now = now.add(const Duration(milliseconds: 40));
    handler.onOtherKey();
    expect(cancel, 1);
    handler.onKeyUp();
    expect(stop, 0, reason: 'the release must not stop a cancelled recording');
  });

  test('hold-or-tap: another key during a short press cancels, no stop', () {
    build(holdOrTap: true);
    handler.onKeyDown();
    expect(recording, isTrue);
    now = now.add(const Duration(milliseconds: 80));
    handler.onOtherKey();
    expect(cancel, 1);
    now = now.add(const Duration(milliseconds: 20));
    handler.onKeyUp();
    expect(stop, 0);
  });

  test('another key with no press in progress cancels nothing', () {
    build(holdOrTap: false);
    handler.onOtherKey();
    expect(cancel, 0);
  });
}
