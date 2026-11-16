/// A key-up that never arrived must not stretch the held
/// time of the next press (the push-to-talk breadcrumb's `held_ms`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/recording_trigger_handler.dart';

void main() {
  // Sentry requires a binding before breadcrumb calls.
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 11, 3, 12);
  late DateTime now;

  RecordingTriggerHandler make() => RecordingTriggerHandler(
    startRecording: () async {},
    stopRecording: () async {},
    toggleRecording: () async {},
    pushToTalkEnabled: () => false,
    registrarSupportsKeyUp: () => true,
    isRecording: () => false,
    clock: () => now,
  );

  test('a press after a lost key-up is timed from its own key-down', () {
    final handler = make();
    now = t0;
    handler.onKeyDown();
    // The key-up of this press is lost; the next press comes 5 s later.
    now = t0.add(const Duration(seconds: 5));
    handler.onKeyDown();
    now = now.add(const Duration(milliseconds: 200));
    handler.onKeyUp();

    expect(handler.lastHeldMs, 200);
  });

  test('a key-down exactly one repeat window later is a new press', () {
    final handler = make();
    now = t0;
    handler.onKeyDown();
    now = t0.add(const Duration(milliseconds: 1200));
    handler.onKeyDown();
    now = now.add(const Duration(milliseconds: 200));
    handler.onKeyUp();

    expect(handler.lastHeldMs, 200);
  });

  test('auto-repeats within the repeat window keep the press start', () {
    final handler = make();
    now = t0;
    handler.onKeyDown();
    for (var i = 1; i <= 3; i++) {
      now = t0.add(Duration(milliseconds: 300 * i));
      handler.onKeyDown();
    }
    now = t0.add(const Duration(milliseconds: 1000));
    handler.onKeyUp();

    expect(handler.lastHeldMs, 1000);
  });
}
