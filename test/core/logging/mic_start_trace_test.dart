import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/mic_start_trace.dart';

Uint8List _pcm16(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('FirstSampleDetector', () {
    test('ignores empty and all-zero (digital silence) chunks', () {
      final d = FirstSampleDetector();
      expect(d.observe(Uint8List(0)), isFalse);
      expect(d.observe(_pcm16([0, 0, 0, 0])), isFalse);
      expect(d.seen, isFalse);
    });

    test('fires exactly once, on the first chunk with a non-zero sample', () {
      final d = FirstSampleDetector();
      expect(d.observe(_pcm16([0, 0, -3, 0])), isTrue);
      expect(d.seen, isTrue);
      expect(d.observe(_pcm16([1200, -800])), isFalse);
    });

    test('a lone odd trailing byte does not count as a sample', () {
      final d = FirstSampleDetector();
      expect(d.observe(Uint8List.fromList([0, 0, 7])), isFalse);
    });
  });

  group('MicStartTrace', () {
    test('reports every stage relative to the hotkey key-down', () {
      var now = 1000000;
      final trace = MicStartTrace(
        sessionId: 's1',
        hotkeyMicros: 990000,
        clock: () => now,
      );
      trace.mark(MicStartStage.phaseRecording); // 10 ms after hotkey
      now += 5000;
      trace.mark(MicStartStage.pasterPrimed); // 15 ms
      now += 40000;
      trace.mark(MicStartStage.captureStarted); // 55 ms
      now += 120000;
      trace.mark(MicStartStage.firstSample); // 175 ms

      expect(trace.elapsedMs(MicStartStage.phaseRecording), 10);
      expect(trace.elapsedMs(MicStartStage.pasterPrimed), 15);
      expect(trace.elapsedMs(MicStartStage.captureStarted), 55);
      expect(trace.elapsedMs(MicStartStage.firstSample), 175);
      expect(trace.isComplete, isTrue);
      expect(
        trace.summary(),
        '[PERF] [s1] mic-start from hotkey: phase→recording 10ms, '
        'paster primed 15ms, capture started 55ms, first sample 175ms',
      );
    });

    test('without a hotkey (tray/CLI/API trigger) the trace start is t₀', () {
      var now = 500000;
      final trace = MicStartTrace(sessionId: 's2', clock: () => now);
      now += 2000;
      trace.mark(MicStartStage.phaseRecording);
      now += 98000;
      trace.mark(MicStartStage.firstSample);

      expect(trace.elapsedMs(MicStartStage.phaseRecording), 2);
      expect(trace.elapsedMs(MicStartStage.firstSample), 100);
      expect(
        trace.summary(),
        '[PERF] [s2] mic-start from trigger: phase→recording 2ms, '
        'paster primed –, capture started –, first sample 100ms',
      );
    });

    test('a start request stamp is t₀ when no hotkey is pending', () {
      final trace = MicStartTrace(
        sessionId: 's5',
        triggerMicros: 4000,
        clock: () => 10000,
      );
      trace.mark(MicStartStage.phaseRecording);
      expect(trace.elapsedMs(MicStartStage.phaseRecording), 6);
      expect(trace.summary(), contains('mic-start from trigger'));
    });

    test('keeps the first stamp of a stage', () {
      var now = 0;
      final trace = MicStartTrace(sessionId: 's3', clock: () => now);
      now = 3000;
      trace.mark(MicStartStage.firstSample);
      now = 9000;
      trace.mark(MicStartStage.firstSample);
      expect(trace.elapsedMs(MicStartStage.firstSample), 3);
    });

    test('is incomplete until the first sample arrives', () {
      final trace = MicStartTrace(sessionId: 's4', clock: () => 0);
      trace.mark(MicStartStage.captureStarted);
      expect(trace.isComplete, isFalse);
      expect(trace.elapsedMs(MicStartStage.firstSample), isNull);
    });
  });
}
