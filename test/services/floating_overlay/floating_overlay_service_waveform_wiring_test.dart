/// Wiring tests for [FloatingOverlayService]'s cut-over to the
/// [WaveformPipeline] (issue 06).
///
/// Locks in the pipeline + animation-timer contract:
///   1. `idle → recording` resets the pipeline and starts the periodic
///      `setWaveformBars` push (~30 Hz, period 33 ms).
///   2. `audioLevelProvider` changes propagate into `pushSample`.
///   3. Over 200 ms of simulated time, 5–7 `setWaveformBars` calls land on
///      the controller.
///   4. `recording → transcribing` stops the timer hard — no further bar
///      pushes for at least 200 ms.
///   5. A second `idle → recording` cycle starts from a clean pipeline
///      state (i.e. the reset() is wired correctly between recordings).
///
/// The seam is [FloatingOverlayController]: a recording controller is
/// injected via the provider override so no platform channels are touched.
/// `package:fake_async` is the wall-clock used by both the timer and the
/// injected `now` parameter on [FloatingOverlayService].
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

// ── Fake controller ───────────────────────────────────────────────────────────

class _RecordingController implements FloatingOverlayController {
  final List<List<double>> waveformPushes = [];
  int snapshotCalls = 0;
  int contextMenuCalls = 0;
  int positionCalls = 0;
  int opacityCalls = 0;
  bool disposed = false;

  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  @override
  Stream<FloatingOverlayEvent> get events => _eventCtrl.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _eventCtrl.close();
  }

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    snapshotCalls++;
  }

  @override
  Future<void> setWaveformBars(List<double> bars) async {
    // Defensive copy — the service may reuse buffers in the future.
    waveformPushes.add(List<double>.from(bars));
  }

  @override
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor) async {
    positionCalls++;
  }

  @override
  Future<void> setContextMenuItems(
    List<({String id, String label})> items,
  ) async {
    contextMenuCalls++;
  }

  @override
  Future<void> setOpacity(double opacity) async {
    opacityCalls++;
  }
}

// ── Testable service subclass ─────────────────────────────────────────────────

class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake, {required super.now});

  final _RecordingController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

/// Minimal stand-in for [SettingsNotifier] — returns a constant
/// [AppSettings] (default values include `overlayMode = 'floating'`), so
/// `_onPhaseChanged` never short-circuits on the overlay-mode check.
class _ConstantSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

// ── Test harness ──────────────────────────────────────────────────────────────

class _Harness {
  _Harness(this.fake, this.container);

  final _RecordingController fake;
  final ProviderContainer container;

  void dispose() {
    container.dispose();
  }
}

/// Builds a service with a deterministic clock backed by [FakeAsync.elapsed]
/// and a controller that records every `setWaveformBars` push.
_Harness _buildHarness(FakeAsync async) {
  final epoch = DateTime.utc(2026, 1, 1);

  final fake = _RecordingController();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_ConstantSettingsNotifier.new),
      floatingOverlayServiceProvider.overrideWith(
        () => _TestableService(
          fake,
          // Wall-clock source — anchors the pipeline's smoothing baseline at
          // a fixed epoch and advances exactly in lockstep with `async.elapse`.
          now: () => epoch.add(async.elapsed),
        ),
      ),
    ],
  );

  // Materialise the service so its `ref.listen` watchers are attached.
  // `container.listen` (rather than `read`) is required: it keeps the
  // provider's internal `ref.listen(recordingPhaseProvider, …)` subscription
  // hot, so phase transitions actually reach `_onPhaseChanged` from outside
  // a Flutter widget tree.
  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});

  // settingsProvider is an AsyncNotifier; the service reads it during build.
  // Without flushing, `effectiveOverlayMode` is still pending and
  // `_onPhaseChanged` short-circuits.
  async.flushMicrotasks();
  // Tiny real-time slice so the AsyncNotifier resolves to its default
  // `AppSettings` (which has `overlayMode = 'floating'`).
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();

  // Sanity: settings must be resolved at this point or the phase listener
  // will short-circuit. Surface a clear assertion early.
  final settings = container.read(settingsProvider);
  assert(
    settings.hasValue,
    'Test harness expected settingsProvider to be resolved by now; '
    'got $settings',
  );

  return _Harness(fake, container);
}

void main() {
  // `_sendSnapshot` reaches into `WidgetsBinding.instance` for locale and
  // brightness, so the test binding has to be live before any phase
  // transition is observed.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatingOverlayService — pipeline wiring (cut-over)', () {
    test('idle → recording starts a periodic setWaveformBars push', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          expect(
            h.fake.waveformPushes,
            isEmpty,
            reason: 'No bars before recording starts',
          );

          h.container.read(recordingProvider.notifier).startRecording();
          // `ref.listen` callbacks land at the next event-loop tick rather
          // than as a synchronous microtask — elapse a bit so the phase
          // listener and its waveform-loop side-effect actually run.
          async.elapse(const Duration(milliseconds: 5));

          // The very first periodic tick fires 33 ms after the timer was
          // armed. 50 ms is enough to guarantee at least one tick.
          async.elapse(const Duration(milliseconds: 50));
          expect(
            h.fake.waveformPushes,
            isNotEmpty,
            reason: 'Timer must fire within one period of entering recording',
          );

          // Each push is the canonical 30-bar snapshot.
          for (final bars in h.fake.waveformPushes) {
            expect(bars.length, 30);
            for (final v in bars) {
              expect(v, inInclusiveRange(0.0, 1.0));
            }
          }
        } finally {
          h.dispose();
        }
      });
    });

    test('audioLevelProvider → pushSample feeds the pipeline', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));

          // Drive a strong audio level. After enough ticks for the attack
          // smoothing to settle (~5 × tau = 100 ms), the live-zone bars
          // should be well above the noise floor.
          h.container.read(recordingProvider.notifier).updateAudioLevel(0.9);
          async.elapse(const Duration(milliseconds: 200));

          expect(h.fake.waveformPushes, isNotEmpty);
          final last = h.fake.waveformPushes.last;
          // Live zone is the middle 20% of 30 bars → bars 12..18 (indices).
          // After ~200 ms of constant 0.9 input the displayed level should
          // be ≥ 0.5 — anything lower means pushSample is not wired.
          final liveStart = ((30 - (0.20 * 30).round()) / 2).floor();
          final liveEnd = liveStart + (0.20 * 30).round();
          var anyAboveHalf = false;
          for (var i = liveStart; i < liveEnd; i++) {
            if (last[i] >= 0.5) {
              anyAboveHalf = true;
              break;
            }
          }
          expect(
            anyAboveHalf,
            isTrue,
            reason:
                'Live zone must reflect a high audio level after smoothing '
                'window — got bars[$liveStart..$liveEnd] = '
                '${last.sublist(liveStart, liveEnd)}',
          );
        } finally {
          h.dispose();
        }
      });
    });

    test('snapshot frequency: 5–7 pushes per 200 ms of recording', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));

          // Reset the counter so we only measure the 200 ms window.
          h.fake.waveformPushes.clear();

          async.elapse(const Duration(milliseconds: 200));

          // Period = 33 ms → 200 / 33 ≈ 6.06 ticks. Allow 5–7 for jitter
          // tolerance per the acceptance criteria.
          expect(
            h.fake.waveformPushes.length,
            inInclusiveRange(5, 7),
            reason:
                '200 ms / 33 ms ≈ 6 ticks; '
                'got ${h.fake.waveformPushes.length}',
          );
        } finally {
          h.dispose();
        }
      });
    });

    test('recording → transcribing stops the waveform timer hard', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));

          // Run a short recording period so we're sure the timer is alive.
          async.elapse(const Duration(milliseconds: 100));
          expect(h.fake.waveformPushes, isNotEmpty);

          h.container.read(recordingProvider.notifier).stopRecording();
          // Let the listener fire so _stopWaveformLoop() executes.
          async.elapse(const Duration(milliseconds: 5));
          // Snapshot the count immediately after the transition.
          final pushCountAtStop = h.fake.waveformPushes.length;

          async.elapse(const Duration(milliseconds: 200));

          expect(
            h.fake.waveformPushes.length,
            pushCountAtStop,
            reason:
                'No further setWaveformBars calls must land for 200 ms '
                'after transitioning to transcribing.',
          );
        } finally {
          h.dispose();
        }
      });
    });

    test('two consecutive recordings: pipeline is reset between them', () {
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          // First cycle: drive level high, let attack saturate.
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));
          h.container.read(recordingProvider.notifier).updateAudioLevel(0.95);
          async.elapse(const Duration(milliseconds: 250));

          // Exit recording (the audioLevel is forced to 0.0 by the notifier).
          h.container.read(recordingProvider.notifier).stopRecording();
          async.elapse(const Duration(milliseconds: 5));

          // Walk through transcribing → done → idle to land back at the
          // starting point. Each transition needs a small elapse so the
          // ref.listen callback can run.
          h.container
              .read(recordingProvider.notifier)
              .completeTranscription('hello');
          async.elapse(const Duration(milliseconds: 5));
          h.container.read(recordingProvider.notifier).reset();
          async.elapse(const Duration(milliseconds: 5));

          // Second cycle: start a new recording with no level pushed yet.
          h.fake.waveformPushes.clear();
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));

          // Push exactly one frame — pipeline.reset() should have cleared the
          // history flanks. The very first snapshot must therefore reflect
          // the rest-state (every bar at the min floor).
          async.elapse(const Duration(milliseconds: 35));
          expect(h.fake.waveformPushes, isNotEmpty);
          final first = h.fake.waveformPushes.first;
          const minBarLevel = 3.0 / 24.0;
          // Allow numerical wiggle for the micromodulation, but every bar
          // must sit near the floor after one tick at audioLevel == 0.
          for (var i = 0; i < first.length; i++) {
            expect(
              first[i],
              lessThan(minBarLevel + 0.05),
              reason:
                  'bar[$i] = ${first[i]} should be at the rest floor after '
                  'reset(), got history leftover instead.',
            );
          }
        } finally {
          h.dispose();
        }
      });
    });
  });
}
