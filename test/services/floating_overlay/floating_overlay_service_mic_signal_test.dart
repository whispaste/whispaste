/// XP-5-08: when the microphone stops delivering mid-recording, the overlay
/// says so in its recording line while it lasts, and goes back to the timer
/// once the signal returns. The recording itself keeps running.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio/signal_loss_detector.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class _RecordingController implements FloatingOverlayController {
  final List<FloatingOverlaySnapshot> snapshots = [];

  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  @override
  Stream<FloatingOverlayEvent> get events => _eventCtrl.stream;

  @override
  Future<void> dispose() async => _eventCtrl.close();

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    snapshots.add(snapshot);
  }

  @override
  Future<void> setWaveformBars(List<double> bars) async {}

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
  _TestableService(this._fake);

  final _RecordingController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

/// Constant [AppSettings] with a caller-chosen `overlayShowLiveTranscript`.
class _ConstantSettingsNotifier extends SettingsNotifier {
  _ConstantSettingsNotifier({required this.liveTranscript});

  final bool liveTranscript;

  @override
  Future<AppSettings> build() async =>
      const AppSettings().copyWith(overlayShowLiveTranscript: liveTranscript);
}

// ── Harness ──────────────────────────────────────────────────────────────────

class _Harness {
  _Harness(this.fake, this.container);

  final _RecordingController fake;
  final ProviderContainer container;

  void dispose() => container.dispose();
}

_Harness _buildHarness(FakeAsync async, {bool liveTranscript = false}) {
  final fake = _RecordingController();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _ConstantSettingsNotifier(liveTranscript: liveTranscript),
      ),
      audioServiceProvider.overrideWith(_MicOpenAudioNotifier.new),
      floatingOverlayServiceProvider.overrideWith(() => _TestableService(fake)),
    ],
  );

  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});

  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();

  final settings = container.read(settingsProvider);
  assert(
    settings.hasValue,
    'Test harness expected settingsProvider to be resolved by now; '
    'got $settings',
  );

  return _Harness(fake, container);
}

/// Mic-open precondition for snapshot-content tests (briefing criterion 4):
/// the recording content is only shown once the capture runs, so these tests
/// model an opened microphone. The start-feedback rule itself is covered in
/// `floating_overlay_service_recovery_test.dart`.
class _MicOpenAudioNotifier extends AudioServiceNotifier {
  @override
  AudioStatus build() => const AudioStatus(
    captureState: AudioCaptureState.recording,
    hasLiveSamples: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void lose(_Harness h, FakeAsync async, {required bool lost}) {
    h.container.read(micSignalLostProvider.notifier).set(lost);
    async.elapse(const Duration(milliseconds: 5));
  }

  test('a lost signal replaces the timer, which returns with the signal', () {
    FakeAsync().run((async) {
      final h = _buildHarness(async);
      try {
        h.container.read(recordingProvider.notifier).startRecording();
        async.elapse(const Duration(milliseconds: 5));
        final before = h.fake.snapshots.last.elapsed;

        lose(h, async, lost: true);
        final during = h.fake.snapshots.last;
        expect(during.state, OverlayVisualState.recording);
        expect(during.elapsed, 'No microphone signal');

        lose(h, async, lost: false);
        expect(h.fake.snapshots.last.elapsed, before);
      } finally {
        h.dispose();
      }
    });
  });
}
