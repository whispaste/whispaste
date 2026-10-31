/// Double-tap hands-free latch in plain push-to-talk mode (WP-39, matrix 9.1).
///
/// In push-to-talk a press shorter than 100 ms is a tap: its release does not
/// stop the recording. Two such taps within 400 ms latch the recording, so
/// the release no longer stops it; the next press stops it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/recording_trigger_handler.dart';

/// Push-to-talk harness with a fake clock and a fake recording state.
class _Harness {
  _Harness({bool doubleTap = true}) {
    handler = RecordingTriggerHandler(
      startRecording: () async {
        start++;
        recording = true;
      },
      stopRecording: () async {
        stop++;
        recording = false;
      },
      toggleRecording: () async {},
      cancelRecording: () async {
        recording = false; // a discard really ends the recording
      },
      pushToTalkEnabled: () => true,
      registrarSupportsKeyUp: () => true,
      doubleTapEnabled: () => doubleTap,
      // Hands-free is the double tap action under test.
      doubleTapLatches: () => true,
      isRecording: () => recording,
      clock: () => _now,
    );
  }

  late final RecordingTriggerHandler handler;
  DateTime _now = DateTime(2026);
  bool recording = false;
  int start = 0;
  int stop = 0;

  void press(Duration held) {
    handler.onKeyDown();
    advance(held);
    handler.onKeyUp();
  }

  void quickTap() => press(const Duration(milliseconds: 60));

  void gap(Duration d) => advance(d);

  void advance(Duration d) => _now = _now.add(d);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('double tap latches hands-free in push-to-talk mode', () {
    test('two quick taps latch: the second release keeps recording', () async {
      final h = _Harness();
      h.quickTap(); // starts, then the short first tap is discarded
      h.gap(const Duration(milliseconds: 200));
      h.quickTap(); // second tap within the window: latched start
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(h.start, 2);
      expect(h.stop, 0);
      expect(h.recording, isTrue);
    });

    test('the press after a latch stops the recording', () {
      final h = _Harness();
      h.quickTap();
      h.gap(const Duration(milliseconds: 200));
      h.quickTap();
      h.gap(const Duration(seconds: 2));
      h.press(const Duration(milliseconds: 500));

      expect(h.stop, 1);
      expect(h.recording, isFalse);
    });

    test('a second tap later than the window does not latch', () {
      final h = _Harness();
      h.quickTap();
      h.gap(const Duration(milliseconds: 900));
      h.quickTap();

      expect(h.start, 2, reason: 'not latched, so it is a fresh start');
    });

    test('a long press does not arm the latch for a following tap', () {
      final h = _Harness();
      h.press(const Duration(milliseconds: 900)); // ordinary hold: start+stop
      expect(h.stop, 1);
      h.gap(const Duration(milliseconds: 200));
      h.quickTap();

      expect(h.start, 2);
      expect(h.stop, 1, reason: 'the single quick tap must not latch');
    });

    test('off by default: two quick taps are two starts, each released', () {
      final h = _Harness(doubleTap: false);
      h.quickTap();
      h.gap(const Duration(milliseconds: 200));
      h.quickTap();

      expect(h.start, 2);
      expect(h.stop, 2, reason: 'every release ends its own press (Befund 2)');
    });
  });
}
