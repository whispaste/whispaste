/// Start-up diagnostics of a capture (#1777): the dead-mic log line must tell
/// "no data", "only zeros" and "sound, then lost" apart.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/mic_warmup_probe.dart';

Uint8List _zeros() => Uint8List(64);

/// One 16-bit little-endian chunk whose loudest sample is [peak].
Uint8List _sound(int peak) {
  final data = ByteData(64);
  data.setInt16(10, peak, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  var now = 0;
  MicWarmupProbe probe() => MicWarmupProbe(elapsedMs: () => now);

  setUp(() => now = 0);

  test('no chunk at all reads as no data', () {
    final p = probe();
    now = 7000;
    expect(p.state, MicWarmupState.noData);
    expect(p.firstSoundMs, isNull);
    expect(p.diagnosis(), contains(MicWarmupState.noData.reason));
    expect(p.diagnosis(), contains('open for: 7000 ms'));
  });

  test('only zero chunks read as digital silence, with their count', () {
    final p = probe();
    now = 40;
    expect(p.observe(_zeros()), isFalse);
    now = 80;
    expect(p.observe(_zeros()), isFalse);
    expect(p.state, MicWarmupState.onlySilence);
    expect(p.diagnosis(), contains('chunks: 2 (2 silent before sound)'));
    expect(p.diagnosis(), contains('first chunk: 40 ms'));
    expect(p.diagnosis(), contains('first sound: none'));
  });

  test('the first real sound is reported once, with time and level', () {
    final p = probe();
    now = 40;
    p.observe(_zeros());
    now = 560;
    expect(p.observe(_sound(16384)), isTrue);
    now = 600;
    expect(p.observe(_sound(16384)), isFalse);
    expect(p.state, MicWarmupState.live);
    expect(p.firstSoundMs, 560);
    expect(p.warmupLine(), contains('first sound after 560 ms'));
    expect(p.warmupLine(), contains('1 silent chunks before'));
    // Half of full scale is -6 dBFS.
    expect(p.warmupLine(), contains('peak -6.0 dBFS'));
  });

  test('only a start at or above the threshold counts as slow', () {
    final fast = probe();
    now = MicWarmupProbe.slowStartMs - 1;
    fast.observe(_sound(100));
    expect(fast.slowStart, isFalse);

    final slow = probe();
    now = MicWarmupProbe.slowStartMs;
    slow.observe(_sound(100));
    expect(slow.slowStart, isTrue);
  });

  test('the statistics get fixed ids and coarse time classes only', () {
    expect(MicWarmupState.values.map((s) => s.id), [
      'no_data',
      'digital_silence',
      'signal_lost',
    ]);
    expect(warmupBucket(300), 'le500');
    expect(warmupBucket(577), 'le1000');
    expect(warmupBucket(3000), 'le3000');
    expect(warmupBucket(6500), 'le7000');
    expect(warmupBucket(9000), 'gt7000');
  });

  group('reopen (#1784)', () {
    test('a dead-mic line tells whether and why the capture reopened', () {
      final p = probe();
      expect(p.diagnosis(), contains('reopened: no'));

      now = 2000;
      p.noteReopen(MicReopenTrigger.stalled);
      p.noteReopenResult(running: true);
      p.observe(_zeros());
      now = 7000;

      expect(p.reopenTrigger, MicReopenTrigger.stalled);
      expect(
        p.diagnosis(),
        contains(
          'reopened: after 2000 ms (${MicReopenTrigger.stalled.reason}), '
          'running, 1 chunks since',
        ),
      );
    });

    test('the reopen statistics get fixed ids only', () {
      expect(MicReopenTrigger.values.map((t) => t.id), ['stalled', 'stopped']);
    });
  });
}
