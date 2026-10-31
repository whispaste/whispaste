/// Service wiring for WP-84 phase 2:
///   - the render-frame heartbeat drives at most a budgeted re-boot request
///     (plan item 1), and a frame acknowledgement ends the episode;
///   - the start feedback shows the preparing state until the microphone is
///     actually open (briefing criterion 4).
///
/// Uses the same seam as the waveform-wiring tests: a fake controller injected
/// via [FloatingOverlayService] subclassing, a deterministic clock backed by
/// `package:fake_async`, and `RecordingNotifier` driven directly.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/floating_overlay/overlay_render_recovery.dart';

class _RecoveringController
    implements FloatingOverlayController, RenderEngineRecovery {
  final List<FloatingOverlaySnapshot> snapshots = [];
  int rebootCalls = 0;
  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  void emit(FloatingOverlayEvent event) => _eventCtrl.add(event);

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

  @override
  Future<void> rebootRenderEngine() async {
    rebootCalls++;
  }
}

class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake, {required super.now});

  final _RecoveringController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

/// Mic state the test controls. Default is closed (capture idle).
class _FakeAudioNotifier extends AudioServiceNotifier {
  void openMic() =>
      state = const AudioStatus(captureState: AudioCaptureState.recording);

  void firstSample() => state = state.withLiveSamples();
}

class _Harness {
  _Harness(this.fake, this.container, this.audio);

  final _RecoveringController fake;
  final ProviderContainer container;
  final _FakeAudioNotifier audio;

  void dispose() => container.dispose();
}

_Harness _build(FakeAsync async) {
  final epoch = DateTime.utc(2026, 1, 1);
  final fake = _RecoveringController();
  late final _FakeAudioNotifier audio;
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_ConstantSettingsNotifier.new),
      audioServiceProvider.overrideWith(() => audio = _FakeAudioNotifier()),
      floatingOverlayServiceProvider.overrideWith(
        () => _TestableService(fake, now: () => epoch.add(async.elapsed)),
      ),
    ],
  );
  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
  return _Harness(fake, container, audio);
}

class _ConstantSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatingOverlayService — render frame heartbeat', () {
    test(
      'a shown overlay without a frame gets one re-boot request after 500 ms '
      'plus the first-boot grace',
      () {
        FakeAsync().run((async) {
          final h = _build(async);
          try {
            h.container.read(recordingProvider.notifier).startRecording();
            async.elapse(const Duration(milliseconds: 1));
            expect(h.fake.rebootCalls, 0);

            async.elapse(
              const Duration(milliseconds: 498) + kRenderFirstBootGrace,
            );
            expect(h.fake.rebootCalls, 0, reason: 'deadline not yet reached');

            async.elapse(const Duration(milliseconds: 1));
            expect(h.fake.rebootCalls, 1);
          } finally {
            h.dispose();
          }
        });
      },
    );

    test('a frame acknowledgement stops the deadline before it fires', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 100));
          h.fake.emit(const OverlayRenderFrame());
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 5));
          expect(h.fake.rebootCalls, 0);
        } finally {
          h.dispose();
        }
      });
    });

    test('a healthy re-boot ends the episode after exactly one re-boot', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(
            const Duration(milliseconds: 500) + kRenderFirstBootGrace,
          );
          expect(h.fake.rebootCalls, 1);

          h.fake.emit(const OverlayRenderFrame());
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 10));
          expect(h.fake.rebootCalls, 1);
        } finally {
          h.dispose();
        }
      });
    });

    test('the session budget caps re-boots at three', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(seconds: 30));
          expect(h.fake.rebootCalls, 3);
        } finally {
          h.dispose();
        }
      });
    });
  });

  group('FloatingOverlayService — start feedback (briefing criterion 4)', () {
    test('recording before the microphone opens shows the preparing state', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 1));

          final last = h.fake.snapshots.last;
          expect(last.visible, isTrue);
          expect(last.state, OverlayVisualState.transcribing);
          expect(last.elapsed, isEmpty);
        } finally {
          h.dispose();
        }
      });
    });

    test('the preparing state appears within one frame of a held start', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 16));

          final last = h.fake.snapshots.last;
          expect(last.state, OverlayVisualState.transcribing);
          expect(last.label, isNotEmpty);
          expect(last.elapsed, isEmpty);
        } finally {
          h.dispose();
        }
      });
    });

    test('an open microphone without samples keeps the preparing state', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 1));

          h.audio.openMic();
          async.flushMicrotasks();

          expect(h.fake.snapshots.last.state, OverlayVisualState.transcribing);
        } finally {
          h.dispose();
        }
      });
    });

    test(
      'the first sample switches the overlay to the live recording state',
      () {
        FakeAsync().run((async) {
          final h = _build(async);
          try {
            h.container.read(recordingProvider.notifier).startRecording();
            async.elapse(const Duration(milliseconds: 1));

            h.audio.openMic();
            h.audio.firstSample();
            async.flushMicrotasks();

            expect(h.fake.snapshots.last.state, OverlayVisualState.recording);
          } finally {
            h.dispose();
          }
        });
      },
    );
  });
}
