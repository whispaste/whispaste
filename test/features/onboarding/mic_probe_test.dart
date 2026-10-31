/// Unit tests for [OnboardingMicProbe].
///
/// The probe is the only thing standing between an honest mic test and the
/// fake "2-second timer" UX it replaces, so the test surface focuses on the
/// outcome decision tree — speech vs. silence vs. permission denial vs. error
/// — plus the threshold gating that filters out transient peaks.
library;

import 'dart:math' as math;
import 'dart:typed_data';

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
      final recorder = FakeMicRecorder(throwOnPermission: true);
      final probe = OnboardingMicProbe(recorder: recorder);
      addTearDown(probe.dispose);

      expect(await probe.start(), MicProbeOutcome.error);
    });

    test('returns error when startStream throws', () async {
      final recorder = FakeMicRecorder(throwOnStart: true);
      final probe = OnboardingMicProbe(recorder: recorder);
      addTearDown(probe.dispose);

      expect(await probe.start(), MicProbeOutcome.error);
    });

    test('returns silence when no audio crosses the threshold', () async {
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(probe.dispose);

      expect(await probe.start(), MicProbeOutcome.silence);
      expect(recorder.lastConfig, isNotNull);
    });

    test('returns speechDetected for sustained loud PCM', () async {
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(seconds: 2),
        sustainedAbove: const Duration(milliseconds: 60),
        speechThresholdDbFs: -20.0,
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(probe.dispose);

      final future = probe.start();
      // Yield so the subscription is wired up before we feed PCM in.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Pump well-above-threshold chunks across several poll windows. The
      // amplitude calculator flushes peaks at the poll interval, so each
      // burst across a fresh interval registers a single dBFS sample at
      // ~-6 dBFS which clears the threshold and accumulates sustained time.
      for (var i = 0; i < 8; i++) {
        recorder.emitPcm(_pcmAtDbFs(-6));
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(await future, MicProbeOutcome.speechDetected);
    });

    test('a single transient peak does NOT trigger speechDetected', () async {
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 300),
        sustainedAbove: const Duration(milliseconds: 200),
        speechThresholdDbFs: -20.0,
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(probe.dispose);

      final future = probe.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // One loud chunk, then nothing — the sustained window resets the next
      // poll because subsequent samples drop back to silence.
      recorder.emitPcm(_pcmAtDbFs(-6));

      expect(await future, MicProbeOutcome.silence);
    });

    test('PCM stream error resolves to MicProbeOutcome.error', () async {
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(probe.dispose);

      final future = probe.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      recorder.emitStreamError();

      expect(await future, MicProbeOutcome.error);
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
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 100),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(probe.dispose);

      expect(await probe.start(), MicProbeOutcome.silence);
      await probe.stop();
      // After stop() the underlying recorder is paused but the probe object
      // is still alive and ready for another run — the retry / device-switch
      // path in the UI relies on exactly this.
      expect(await probe.start(), MicProbeOutcome.silence);
      await probe.stop();
      expect(recorder.stopCalls, greaterThanOrEqualTo(2));
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
      final recorder = FakeMicRecorder();
      final probe = OnboardingMicProbe(
        recorder: recorder,
        timeout: const Duration(milliseconds: 60),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(probe.dispose);

      const device = InputDevice(id: 'usb-headset', label: 'USB Headset');
      await probe.start(device: device);
      expect(recorder.lastConfig?.device?.id, 'usb-headset');
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
