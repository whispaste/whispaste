/// Wiring test for the live-transcript overlay option (ticket 11):
/// [FloatingOverlayService] must forward the active STT engine's
/// [PartialTranscriptSource] text into
/// [FloatingOverlaySnapshot.liveTranscript] while transcribing — but ONLY
/// when `AppSettings.overlayShowLiveTranscript` is on. With the setting off
/// (the default — see that field's doc comment), the classic
/// waveform/label-only "Transcribing…" composition must be unaffected even
/// though the engine is still emitting partial text underneath.
///
/// The STT seam is [SttServerStateNotifier.partialTranscriptStream]
/// (`localSttBundleProvider`): overridden here with a fake notifier exposing
/// a controllable stream, so this test never touches the real
/// whisper.cpp/FFI/isolate machinery.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

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
/// Mirrors `floating_overlay_service_waveform_wiring_test.dart`'s
/// `_ConstantSettingsNotifier`.
class _ConstantSettingsNotifier extends SettingsNotifier {
  _ConstantSettingsNotifier({required this.liveTranscript});

  final bool liveTranscript;

  @override
  Future<AppSettings> build() async =>
      const AppSettings().copyWith(overlayShowLiveTranscript: liveTranscript);
}

/// Fake [SttServerStateNotifier] exposing a controllable
/// [partialTranscriptStream] instead of a real engine — the whole point is
/// to test [FloatingOverlayService]'s consumption of that stream in
/// isolation from whisper.cpp/FFI/isolate wiring.
class _FakeSttNotifier extends SttServerStateNotifier {
  final _controller = StreamController<String>.broadcast();

  void emitPartial(String text) => _controller.add(text);

  @override
  SttStatus build() => const SttStatus();

  @override
  Stream<String>? get partialTranscriptStream => _controller.stream;
}

// ── Harness ──────────────────────────────────────────────────────────────────

class _Harness {
  _Harness(this.fake, this.stt, this.container);

  final _RecordingController fake;
  final _FakeSttNotifier stt;
  final ProviderContainer container;

  void dispose() => container.dispose();
}

_Harness _buildHarness(FakeAsync async, {required bool liveTranscript}) {
  final fake = _RecordingController();
  final stt = _FakeSttNotifier();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _ConstantSettingsNotifier(liveTranscript: liveTranscript),
      ),
      localSttBundleProvider.overrideWith(() => stt),
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

  return _Harness(fake, stt, container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatingOverlayService — live-transcript setting (ticket 11)', () {
    test(
      'setting ON: partial text reaches the snapshot while transcribing',
      () {
        FakeAsync().run((async) {
          final h = _buildHarness(async, liveTranscript: true);
          try {
            h.container.read(recordingProvider.notifier).startRecording();
            async.elapse(const Duration(milliseconds: 5));
            h.container.read(recordingProvider.notifier).stopRecording();
            async.elapse(const Duration(milliseconds: 5));

            h.stt.emitPartial('Hello wor');
            async.elapse(const Duration(milliseconds: 5));
            h.stt.emitPartial('Hello world');
            async.elapse(const Duration(milliseconds: 5));

            final last = h.fake.snapshots.last;
            expect(last.state, OverlayVisualState.transcribing);
            expect(last.liveTranscript, 'Hello world');
          } finally {
            h.dispose();
          }
        });
      },
    );

    test('setting OFF: partial text never reaches the snapshot (waveform-only '
        'stays unaffected)', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async, liveTranscript: false);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));
          h.container.read(recordingProvider.notifier).stopRecording();
          async.elapse(const Duration(milliseconds: 5));

          h.stt.emitPartial('Hello world');
          async.elapse(const Duration(milliseconds: 5));

          expect(
            h.fake.snapshots.any((s) => s.liveTranscript != null),
            isFalse,
            reason:
                'liveTranscript must stay null on every snapshot while '
                'the setting is off, even though the engine emitted text',
          );
          final last = h.fake.snapshots.last;
          expect(last.state, OverlayVisualState.transcribing);
        } finally {
          h.dispose();
        }
      });
    });
  });
}
