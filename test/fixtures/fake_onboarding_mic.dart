/// Shared microphone test seams for onboarding shell tests.
///
/// The Welcome page mounts [MicrophoneStep], whose production defaults touch
/// real platform channels (the `record` plugin and CoreAudio routing). Every
/// test that pumps the whole [OnboardingOverlay] injects these fakes via the
/// overlay's `micProbeFactory` / `micRouting` seams so no platform channel is
/// ever hit. Focused [MicrophoneStep] behaviour tests keep their own scripted
/// fakes in `microphone_step_test.dart` — these here are deliberately inert.
library;

import 'package:record/record.dart';
import 'package:whispaste/features/onboarding/mic_probe.dart';
import 'package:whispaste/services/audio_routing_service.dart';

import 'fake_mic_recorder.dart';

/// Inert probe: no devices, every capture attempt reports silence.
class FakeOnboardingMicProbe extends OnboardingMicProbe {
  FakeOnboardingMicProbe() : super(recorder: FakeMicRecorder());

  @override
  Future<MicProbeOutcome> start({InputDevice? device}) async =>
      MicProbeOutcome.silence;

  @override
  Future<List<InputDevice>> listInputDevices() async => const <InputDevice>[];

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Inert routing service: behaves like a non-macOS host (unsupported).
class FakeAudioRoutingService implements AudioRoutingService {
  @override
  bool get isSupported => false;

  @override
  Future<String?> getDefaultInputDevice() async => null;

  @override
  Future<bool> setDefaultInputDevice(String uid) async => false;

  @override
  Future<List<InputDevice>> listInputDevices() async => const <InputDevice>[];
}
