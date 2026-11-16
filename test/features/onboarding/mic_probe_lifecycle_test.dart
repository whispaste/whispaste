/// Lifecycle guards for [OnboardingMicProbe]: start, stop and dispose, including
/// a page change while a start is still in flight. Plain unit tests: the level
/// meter is injected, so no periodic timer exists and every leak shows up as a
/// count in [_Meters].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/features/onboarding/mic_probe.dart';
import 'package:whispaste/services/audio/amplitude_from_pcm.dart';

/// Counts the meters a probe creates and the ones still alive.
class _Meters {
  int created = 0;
  int live = 0;
  _FakeMeter? last;

  PcmLevelMeter create({required Duration pollInterval}) {
    created++;
    live++;
    return last = _FakeMeter(this);
  }
}

class _FakeMeter implements PcmLevelMeter {
  _FakeMeter(this._meters);

  final _Meters _meters;
  final StreamController<double> _levels = StreamController<double>.broadcast();
  bool _disposed = false;

  void emit(double dbFs) => _levels.add(dbFs);

  @override
  Stream<double> get stream => _levels.stream;

  @override
  void addChunk(Uint8List bytes) {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _meters.live--;
    unawaited(_levels.close());
  }
}

/// A recorder whose stream starts are held back one by one, so a test can stop,
/// dispose or supersede the probe while a start is still pending.
class _GatedRecorder implements MicProbeRecorder {
  final List<Completer<void>> gates = <Completer<void>>[];
  StreamController<Uint8List> pcm = StreamController<Uint8List>();
  bool recording = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    if (gates.isNotEmpty) await gates.removeAt(0).future;
    recording = true;
    // A fresh stream per start: a single-subscription stream cannot be listened
    // to again after the previous run cancelled it.
    pcm = StreamController<Uint8List>();
    return pcm.stream;
  }

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<String?> stop() async {
    recording = false;
    return null;
  }

  @override
  Future<void> dispose() async {
    recording = false;
    unawaited(pcm.close());
  }

  @override
  Future<List<InputDevice>> listInputDevices() async => const [];
}

/// Lets queued microtasks and stream events run.
Future<void> _settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

OnboardingMicProbe _probe(_GatedRecorder recorder, _Meters meters) =>
    OnboardingMicProbe(
      recorder: recorder,
      timeout: null,
      meterFactory: meters.create,
    );

void main() {
  test('start then stop releases the meter', () async {
    final recorder = _GatedRecorder();
    final meters = _Meters();
    final probe = _probe(recorder, meters);

    unawaited(probe.start());
    await _settle();
    expect(meters.created, 1);
    expect(meters.live, 1);

    await probe.stop();
    await _settle();
    expect(recorder.recording, isFalse);
    expect(meters.live, 0);
    expect(probe.level.value, 0.0);

    await probe.dispose();
    expect(meters.live, 0);
  });

  test('stop while the stream start is still pending', () async {
    final gate = Completer<void>();
    final recorder = _GatedRecorder()..gates.add(gate);
    final meters = _Meters();
    final probe = _probe(recorder, meters);

    final outcome = probe.start();
    await _settle();

    await probe.stop();
    // The held start completes after the stop and must not revive the run.
    gate.complete();
    await _settle();

    expect(await outcome, MicProbeOutcome.error);
    expect(recorder.recording, isFalse);
    expect(meters.live, 0);

    await probe.dispose();
  });

  test(
    'dispose while the stream start is pending leaves nothing alive',
    () async {
      final gate = Completer<void>();
      final recorder = _GatedRecorder()..gates.add(gate);
      final meters = _Meters();
      final probe = _probe(recorder, meters);

      unawaited(probe.start());
      await _settle();

      // The page is left during the start: the owner stops, then disposes.
      unawaited(probe.stop());
      await probe.dispose();
      gate.complete();
      await _settle();

      expect(recorder.recording, isFalse);
      expect(meters.live, 0);
    },
  );

  test(
    'a page change during a pending start keeps only the newer run',
    () async {
      final gate = Completer<void>();
      final recorder = _GatedRecorder()..gates.add(gate);
      final meters = _Meters();
      final probe = _probe(recorder, meters);

      final stale = probe.start();
      await _settle();
      await probe.stop();

      // The new page starts while the old start is still held back.
      final fresh = probe.start();
      await _settle();
      expect(meters.live, 1);
      final freshMeter = meters.last!;

      // The old start completes late. It must not dispose or cancel the new run.
      gate.complete();
      await _settle();
      expect(await stale, MicProbeOutcome.error);
      expect(meters.live, 1);

      for (var i = 0; i < 4; i++) {
        freshMeter.emit(-20);
      }
      await _settle();
      expect(await fresh, MicProbeOutcome.speechDetected);

      await probe.stop();
      expect(meters.live, 0);
      await probe.dispose();
    },
  );

  test('a restart after stop reaches speech and releases on stop', () async {
    final recorder = _GatedRecorder();
    final meters = _Meters();
    final probe = _probe(recorder, meters);

    unawaited(probe.start());
    await _settle();
    await probe.stop();

    final outcome = probe.start();
    await _settle();
    final meter = meters.last!;
    for (var i = 0; i < 4; i++) {
      meter.emit(-20);
    }
    await _settle();
    expect(await outcome, MicProbeOutcome.speechDetected);
    expect(meters.created, 2);

    await probe.stop();
    expect(meters.live, 0);
    await probe.dispose();
  });
}
