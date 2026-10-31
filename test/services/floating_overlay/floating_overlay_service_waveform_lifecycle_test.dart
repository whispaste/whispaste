/// Lifecycle test for the overlay waveform animation timer (CORE-IDLE-CPU).
///
/// The 33 ms `Timer.periodic` that drives the waveform is started on
/// `idle → recording` and must be stopped on `recording → done / error`.
/// `_onPhaseChanged` used to return early when the overlay mode was not
/// `floating` at the moment of the transition, which skipped
/// `_updateWaveformLifecycle` entirely. A recording that ends after the user
/// switched the overlay off then left a 30 Hz timer running for the rest of
/// the session. Every tick is a Dart wake-up on the engine's task runner, so
/// the cost shows up as idle wake-ups, not as visible output.
///
/// Locks in: the waveform timer stops on the phase transition even when the
/// overlay mode is no longer `floating`, because the timer belongs to the
/// recording lifecycle, not to the overlay's visibility.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';

class _CountingController implements FloatingOverlayController {
  int waveformPushes = 0;
  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  @override
  Stream<FloatingOverlayEvent> get events => _eventCtrl.stream;

  @override
  Future<void> dispose() async {
    await _eventCtrl.close();
  }

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {}

  @override
  Future<void> setWaveformBars(List<double> bars) async {
    waveformPushes++;
  }

  @override
  Future<void> setPosition(
    double x,
    double y,
    OverlayAnchorMode anchor,
  ) async {}

  @override
  Future<void> setContextMenuItems(
    List<({String id, String label})> items,
  ) async {}
}

class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake, {required super.now});

  final _CountingController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

/// Settings notifier whose overlay mode can be switched while a recording
/// is running, which is the situation that skipped the lifecycle update.
class _SwitchableSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();

  void setOverlayMode(String mode) {
    state = AsyncData(state.requireValue.copyWith(overlayMode: mode));
  }
}

class _MicOpenAudioNotifier extends AudioServiceNotifier {
  @override
  AudioStatus build() => const AudioStatus(
    captureState: AudioCaptureState.recording,
    hasLiveSamples: true,
  );
}

({ProviderContainer container, _CountingController fake}) _buildHarness(
  FakeAsync async,
) {
  final epoch = DateTime.utc(2026, 1, 1);
  final fake = _CountingController();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_SwitchableSettingsNotifier.new),
      audioServiceProvider.overrideWith(_MicOpenAudioNotifier.new),
      floatingOverlayServiceProvider.overrideWith(
        () => _TestableService(fake, now: () => epoch.add(async.elapsed)),
      ),
    ],
  );
  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
  return (container: container, fake: fake);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatingOverlayService — waveform timer lifecycle', () {
    test('recording that fails after the overlay was switched off stops the '
        'waveform timer', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));
          async.elapse(const Duration(milliseconds: 100));
          expect(
            h.fake.waveformPushes,
            greaterThan(0),
            reason: 'precondition: the timer runs during the recording',
          );

          // The user switches the overlay off mid-recording, then the
          // recording fails. The phase listener sees mode != floating.
          (h.container.read(settingsProvider.notifier)
                  as _SwitchableSettingsNotifier)
              .setOverlayMode(OverlayMode.off.value);
          async.elapse(const Duration(milliseconds: 5));
          h.container.read(recordingProvider.notifier).fail('boom');
          async.elapse(const Duration(milliseconds: 5));

          final pushesAfterStop = h.fake.waveformPushes;
          async.elapse(const Duration(seconds: 1));
          expect(
            h.fake.waveformPushes,
            pushesAfterStop,
            reason:
                'the 33 ms waveform timer must not keep ticking after the '
                'recording ended, even though the overlay is off',
          );
        } finally {
          h.container.dispose();
        }
      });
    });

    test('a floating overlay still stops the timer on error (unchanged)', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 100));
          h.container.read(recordingProvider.notifier).fail('boom');
          async.elapse(const Duration(milliseconds: 5));
          final pushesAfterStop = h.fake.waveformPushes;
          async.elapse(const Duration(seconds: 1));
          expect(h.fake.waveformPushes, pushesAfterStop);
        } finally {
          h.container.dispose();
        }
      });
    });
  });
}
