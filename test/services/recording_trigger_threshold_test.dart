/// Configurable hold-or-tap threshold (Automatisch): the duration that
/// separates a latching tap from a push-to-talk hold comes from settings.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int stop;
  late int toggle;
  late bool recording;
  late DateTime now;
  late RecordingTriggerHandler handler;

  void build({int? thresholdMs}) {
    stop = 0;
    toggle = 0;
    recording = false;
    now = DateTime(2026, 10, 21);
    handler = RecordingTriggerHandler(
      startRecording: () async {
        recording = true;
      },
      stopRecording: () async {
        stop++;
        recording = false;
      },
      toggleRecording: () async {
        toggle++;
        recording = !recording;
      },
      pushToTalkEnabled: () => true,
      registrarSupportsKeyUp: () => true,
      holdOrTapEnabled: () => true,
      holdOrTapThresholdMs: thresholdMs == null ? null : () => thresholdMs,
      isRecording: () => recording,
      clock: () => now,
    );
  }

  void hold(int ms) {
    handler.onKeyDown();
    now = now.add(Duration(milliseconds: ms));
    handler.onKeyUp();
  }

  test('default threshold is 250 ms when no setting is given', () {
    expect(RecordingTriggerHandler.defaultHoldOrTapThresholdMs, 250);
    build();
    hold(300);
    expect(
      stop,
      1,
      reason: 'a 300 ms hold is push-to-talk at the 250 ms default',
    );
  });

  test('a press below the configured threshold latches (no stop)', () {
    build(thresholdMs: 250);
    hold(240);
    expect(stop, 0);
    expect(recording, isTrue);
  });

  test('a press at the configured threshold is push-to-talk', () {
    build(thresholdMs: 250);
    hold(250);
    expect(stop, 1);
  });

  test('a larger configured threshold keeps slower presses latched', () {
    build(thresholdMs: 800);
    hold(600);
    expect(stop, 0);
    expect(recording, isTrue);
  });

  test(
    'keydown starts the recording synchronously regardless of threshold',
    () {
      build(thresholdMs: 800);
      handler.onKeyDown();
      expect(toggle, 1, reason: 'start must not wait for the threshold');
      expect(recording, isTrue);
    },
  );
}
