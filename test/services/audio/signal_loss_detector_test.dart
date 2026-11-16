// XP-5-08: a microphone that drops out mid-recording turns into exact digital
// silence or no data at all (both arrive as -inf dBFS); a thinking pause in a
// quiet room stays finite.
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/amplitude_from_pcm.dart';
import 'package:whispaste/services/audio/signal_loss_detector.dart';

const _dead = double.negativeInfinity;
const _quietRoom = -78.0;
const _speech = -18.0;

void main() {
  SignalLossDetector detector() =>
      SignalLossDetector(samplesPerSecond: 25); // 40 ms ticks

  List<bool?> feed(SignalLossDetector d, double dbFs, int ticks) => [
    for (var i = 0; i < ticks; i++) d.observe(dbFs),
  ];

  test('stays quiet before the first signal: the dead-mic guard owns that', () {
    final d = detector();
    expect(feed(d, _dead, 200), everyElement(isNull));
  });

  test('reports the loss once, after three seconds of dead input', () {
    final d = detector();
    feed(d, _speech, 10);

    final ticks = feed(d, _dead, 120);

    expect(ticks.indexOf(true), 74, reason: 'tick 75 completes 3 s');
    expect(ticks.where((t) => t != null), [true]);
  });

  test('reports the signal coming back, then can lose it again', () {
    final d = detector();
    feed(d, _speech, 5);
    feed(d, _dead, 75);

    expect(d.observe(_speech), isFalse);
    expect(d.observe(_speech), isNull);
    expect(feed(d, _dead, 75).last, isTrue);
  });

  test('a long pause in a quiet room is not a lost microphone', () {
    final d = detector();
    feed(d, _speech, 10);
    expect(feed(d, _quietRoom, 25 * 30), everyElement(isNull));
  });

  test('a dropout under three seconds does not count', () {
    // A noise gate or a hardware mute button can zero the input for a
    // moment while the microphone is fine; that must not raise an alarm.
    final d = detector();
    feed(d, _speech, 10);
    expect(feed(d, _dead, 74), everyElement(isNull));
    expect(d.observe(_speech), isNull);
    expect(feed(d, _dead, 74), everyElement(isNull));
  });

  group('fed by AmplitudeFromPcm, as in the audio service', () {
    // 40 ms of 16 kHz mono int16 per chunk; the level is the same in every
    // sample, which is all the peak meter looks at.
    Uint8List chunk(int sample) {
      final data = ByteData(640 * 2);
      for (var i = 0; i < 640; i++) {
        data.setInt16(i * 2, sample, Endian.little);
      }
      return data.buffer.asUint8List();
    }

    ({List<bool> changes, void Function(Uint8List) add, AmplitudeFromPcm amp})
    wire() {
      final amp = AmplitudeFromPcm(
        pollInterval: const Duration(milliseconds: 40),
      );
      final d = SignalLossDetector(samplesPerSecond: 25);
      final changes = <bool>[];
      amp.stream.listen((dbFs) {
        final c = d.observe(dbFs);
        if (c != null) changes.add(c);
      });
      return (changes: changes, add: amp.addChunk, amp: amp);
    }

    void run(
      FakeAsync async,
      void Function(Uint8List) add,
      int sample,
      int ms,
    ) {
      for (var t = 0; t < ms; t += 40) {
        add(chunk(sample));
        async.elapse(const Duration(milliseconds: 40));
      }
    }

    test('digital zeros after speech (PipeWire null-sink monitor)', () {
      FakeAsync().run((async) {
        final w = wire();
        run(async, w.add, 6000, 400);
        run(async, w.add, 0, 2800);
        expect(w.changes, isEmpty, reason: 'a noise gate closing briefly');
        run(async, w.add, 0, 400);
        expect(w.changes, [true]);
        run(async, w.add, 6000, 80);
        expect(w.changes, [true, false]);
        w.amp.dispose();
      });
    });

    test('no data at all after speech (stream stopped or stalled)', () {
      FakeAsync().run((async) {
        final w = wire();
        run(async, w.add, 6000, 400);
        async.elapse(const Duration(milliseconds: 3400));
        expect(w.changes, isEmpty, reason: 'held level, then 3 s of silence');
        async.elapse(const Duration(milliseconds: 200));
        expect(w.changes, [true]);
        w.amp.dispose();
      });
    });

    test('room noise of a working microphone never trips it', () {
      FakeAsync().run((async) {
        final w = wire();
        run(async, w.add, 6000, 400);
        run(async, w.add, 3, 10000);
        expect(w.changes, isEmpty);
        w.amp.dispose();
      });
    });
  });
}
