/// Unit tests for [OnboardingMicProbe].
///
/// The probe is the only thing standing between an honest mic test and the
/// fake "2-second timer" UX it replaces, so the test surface focuses on the
/// outcome decision tree — speech vs. silence vs. permission denial vs. error
/// — plus the threshold gating that filters out transient peaks.
library;

import 'dart:async';
import 'dart:io' show ProcessException;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/features/onboarding/mic_probe.dart';

import '../../fixtures/fake_mic_recorder.dart';

/// Builds a synthetic PCM chunk whose peak sample lands at the requested
/// dBFS level. Used to drive the AmplitudeFromPcm threshold logic
/// deterministically.
Uint8List _pcmAtDbFs(double dbFs, {int samples = 64}) {
  final linear = math.pow(10, dbFs / 20).toDouble();
  final amplitude = (32768.0 * linear).clamp(1.0, 32767.0).toInt();
  final bytes = Uint8List(samples * 2);
  final view = ByteData.view(bytes.buffer);
  // First sample carries the peak so the chunk is guaranteed to register at
  // exactly `dbFs`; remaining samples are zero (a silent tail).
  view.setInt16(0, amplitude, Endian.little);
  return bytes;
}

void main() {
  group('OnboardingMicProbe', () {
    test('returns permissionDenied when the recorder denies', () async {
      final recorder = FakeMicRecorder(hasPermission: false);
      final probe = OnboardingMicProbe(recorder: recorder);
      addTearDown(probe.dispose);

      expect(await probe.start(), MicProbeOutcome.permissionDenied);
      expect(recorder.lastConfig, isNull); // never started streaming
    });

    test('returns error when hasPermission throws', () async {
      final recorder = FakeMicRecorder(
        throwOnPermission: true,
        devices: const [_builtIn],
      );
      final probe = OnboardingMicProbe(recorder: recorder);
      addTearDown(probe.dispose);

      expect(await probe.start(), MicProbeOutcome.error);
    });

    test(
      'returns error when startStream throws with a device present',
      () async {
        final recorder = FakeMicRecorder(
          throwOnStart: true,
          devices: const [_builtIn],
        );
        final probe = OnboardingMicProbe(recorder: recorder);
        addTearDown(probe.dispose);

        expect(await probe.start(), MicProbeOutcome.error);
      },
    );

    test(
      'returns noDevice when startStream throws and no input exists',
      () async {
        final recorder = FakeMicRecorder(throwOnStart: true);
        final probe = OnboardingMicProbe(recorder: recorder);
        addTearDown(probe.dispose);

        expect(await probe.start(), MicProbeOutcome.noDevice);
      },
    );

    test('returns toolMissing when parecord is not installed (#85)', () async {
      final recorder = FakeMicRecorder(
        startError: const ProcessException('parecord', [], 'No such file', 2),
        devices: const [_builtIn],
      );
      final probe = OnboardingMicProbe(recorder: recorder);
      addTearDown(probe.dispose);

      expect(await probe.start(), MicProbeOutcome.toolMissing);
    });

    // The probe's timeout and poll interval are timers: these tests drive
    // them on a fake clock instead of waiting in real time (#1491).
    test('returns silence when no audio crosses the threshold', () async {
      final clock = FakeAsync();
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 20),
      );

      final outcome = _start(clock, probe);
      clock.elapse(const Duration(milliseconds: 200));
      expect(outcome.value, MicProbeOutcome.silence);
      expect(recorder.lastConfig, isNotNull);
      await _settle(clock, probe.dispose);
    });

    test('returns speechDetected for sustained loud PCM', () async {
      final clock = FakeAsync();
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(seconds: 2),
        sustainedAbove: const Duration(milliseconds: 60),
        speechThresholdDbFs: -20.0,
        pollInterval: const Duration(milliseconds: 20),
      );

      final outcome = _start(clock, probe);
      // Let the subscription be wired up before we feed PCM in.
      clock.elapse(const Duration(milliseconds: 10));

      // Pump well-above-threshold chunks across several poll windows. The
      // amplitude calculator flushes peaks at the poll interval, so each
      // burst across a fresh interval registers a single dBFS sample at
      // ~-6 dBFS which clears the threshold and accumulates sustained time.
      for (var i = 0; i < 8; i++) {
        clock.run((_) => recorder.emitPcm(_pcmAtDbFs(-6)));
        clock.elapse(const Duration(milliseconds: 25));
      }

      expect(outcome.value, MicProbeOutcome.speechDetected);
      await _settle(clock, probe.dispose);
    });

    test('a single transient peak does NOT trigger speechDetected', () async {
      final clock = FakeAsync();
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 300),
        sustainedAbove: const Duration(milliseconds: 200),
        speechThresholdDbFs: -20.0,
        pollInterval: const Duration(milliseconds: 20),
      );

      final outcome = _start(clock, probe);
      clock.elapse(const Duration(milliseconds: 10));

      // One loud chunk, then the microphone keeps delivering silence — the
      // sustained window resets at the next poll. (A source that delivers
      // nothing at all holds its last level briefly; see AmplitudeFromPcm.)
      final quiet = clock.run((_) {
        recorder.emitPcm(_pcmAtDbFs(-6));
        return Timer.periodic(
          const Duration(milliseconds: 20),
          (_) => recorder.emitPcm(Uint8List(128)),
        );
      });
      clock.elapse(const Duration(milliseconds: 300));
      quiet.cancel();

      expect(outcome.value, MicProbeOutcome.silence);
      await _settle(clock, probe.dispose);
    });

    test('PCM stream error resolves to MicProbeOutcome.disconnected', () async {
      final clock = FakeAsync();
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 20),
      );

      final outcome = _start(clock, probe);
      clock.elapse(const Duration(milliseconds: 10));
      clock.run((_) => recorder.emitStreamError());
      clock.flushMicrotasks();

      expect(outcome.value, MicProbeOutcome.disconnected);
      await _settle(clock, probe.dispose);
    });

    test('concurrent start() calls share the same future', () async {
      final recorder = FakeMicRecorder(hasPermission: false);
      final probe = OnboardingMicProbe(recorder: recorder);
      addTearDown(probe.dispose);

      final first = probe.start();
      final second = probe.start();
      expect(await first, MicProbeOutcome.permissionDenied);
      expect(await second, MicProbeOutcome.permissionDenied);
    });

    test('start() after stop() can run a fresh probe cycle', () async {
      final clock = FakeAsync();
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 20),
      );

      final first = _start(clock, probe);
      clock.elapse(const Duration(milliseconds: 100));
      expect(first.value, MicProbeOutcome.silence);
      await _settle(clock, probe.stop);
      // After stop() the underlying recorder is paused but the probe object
      // is still alive and ready for another run — the retry / device-switch
      // path in the UI relies on exactly this.
      final second = _start(clock, probe);
      clock.elapse(const Duration(milliseconds: 100));
      expect(second.value, MicProbeOutcome.silence);
      await _settle(clock, probe.stop);
      expect(recorder.stopCalls, greaterThanOrEqualTo(2));
      await _settle(clock, probe.dispose);
    });

    test(
      'start() after dispose() returns error and does not touch the recorder',
      () async {
        final recorder = FakeMicRecorder();
        final probe = OnboardingMicProbe(recorder: recorder);
        await probe.dispose();

        expect(await probe.start(), MicProbeOutcome.error);
        expect(recorder.lastConfig, isNull);
        expect(recorder.disposeCalls, 1);
      },
    );

    test('forwards InputDevice into the RecordConfig', () async {
      final clock = FakeAsync();
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 60),
        pollInterval: const Duration(milliseconds: 20),
      );

      const device = InputDevice(id: 'usb-headset', label: 'USB Headset');
      final outcome = _start(clock, probe, device: device);
      clock.elapse(const Duration(milliseconds: 60));
      expect(outcome.value, isNotNull);
      expect(recorder.lastConfig?.device?.id, 'usb-headset');
      await _settle(clock, probe.dispose);
    });

    test('listInputDevices passes through the recorder', () async {
      final recorder = FakeMicRecorder(
        devices: const [
          InputDevice(id: 'a', label: 'Built-in'),
          InputDevice(id: 'b', label: 'USB Headset'),
        ],
      );
      final probe = OnboardingMicProbe(recorder: recorder);
      addTearDown(probe.dispose);

      final devices = await probe.listInputDevices();
      expect(devices.map((d) => d.id), ['a', 'b']);
    });

    test(
      'listInputDevices returns empty on failure instead of throwing',
      () async {
        final recorder = FakeMicRecorder(throwOnListDevices: true);
        final probe = OnboardingMicProbe(recorder: recorder);
        addTearDown(probe.dispose);

        expect(await probe.listInputDevices(), isEmpty);
      },
    );
  });
}

const _builtIn = InputDevice(id: 'built-in', label: 'Built-in');

/// Holds a probe run's outcome once it completed under the fake clock.
class _Outcome {
  MicProbeOutcome? value;
}

/// Starts [probe] on [clock], so its timeout and poll timers are fake.
_Outcome _start(
  FakeAsync clock,
  OnboardingMicProbe probe, {
  InputDevice? device,
}) {
  final box = _Outcome();
  clock.run((_) {
    unawaited(probe.start(device: device).then((o) => box.value = o));
  });
  clock.flushMicrotasks();
  return box;
}

/// Runs [action] (a stop or dispose) on [clock] and drives it to its end.
/// The teardown also awaits futures of the root zone (an empty `cancel()`),
/// whose continuations only run on the real microtask queue, so real
/// microtask turns alternate with fake flushes. No timer, no real wait.
Future<void> _settle(FakeAsync clock, Future<void> Function() action) async {
  var done = false;
  clock.run((_) {
    unawaited(action().whenComplete(() => done = true));
  });
  for (var i = 0; i < 100 && !done; i++) {
    clock.flushMicrotasks();
    await Future<void>.value();
  }
  expect(done, isTrue, reason: 'the probe did not settle');
}
