/// Wiring tests for [FloatingOverlayService]'s [WaveformPipeline] integration
/// (issues 06 + 07).
///
/// Locks in the pipeline + animation-timer contract:
///   1. `idle → recording` resets the pipeline and starts the periodic
///      `setWaveformBars` push (~30 Hz, period 33 ms).
///   2. `audioLevelProvider` changes propagate into `pushSample`.
///   3. Over 200 ms of simulated time, 5–7 `setWaveformBars` calls land on
///      the controller.
///   4. `recording → done / error` (no release-out) stops the timer hard —
///      no further bar pushes for at least 200 ms.
///   5. A second `idle → recording` cycle starts from a clean pipeline
///      state (i.e. the reset() is wired correctly between recordings).
///
/// Issue 07 — trailing release-out for `recording → transcribing`:
///   6. After the transition, 6–10 trailing `setWaveformBars` pushes land
///      over ~`releaseOutDurationMs` of simulated time.
///   7. Live-zone bars in consecutive trailing snapshots are non-increasing
///      (pipeline only sees `pushSample(0.0, …)` during release-out).
///   8. After the release-out window, the timer stops itself; no further
///      pushes for ≥ 200 ms.
///   9. An `audioLevelProvider` value > 0 during the release-out does NOT
///      make the live zone climb — the service-side gate holds even when
///      `RecordingNotifier`'s own phase gate is bypassed.
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
import 'package:whispaste/core/theme/overlay_design_spec.dart';
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

/// Permissive [RecordingNotifier] that exposes the protected `state` setter
/// so a test can force an `audioLevel` change during a non-recording phase.
/// Used by the AC4 test to verify the release-out actively ignores
/// `audioLevelProvider` updates instead of relying on the upstream
/// `RecordingNotifier.updateAudioLevel` phase gate.
class _PermissiveRecordingNotifier extends RecordingNotifier {
  void forceAudioLevel(double level) {
    state = state.copyWith(audioLevel: level);
  }
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

          // Each push is the canonical spec-sized snapshot.
          for (final bars in h.fake.waveformPushes) {
            expect(bars.length, OverlayDesignSpec.waveform.barCount);
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
          // Scrolling-history model: the freshest moments sit at the right
          // edge. After ~200 ms of constant 0.9 input the loudest (recent)
          // bars should be ≥ 0.5 — anything lower means pushSample is not
          // wired into the history.
          final peak = last.reduce((a, b) => a > b ? a : b);
          expect(
            peak,
            greaterThanOrEqualTo(0.5),
            reason:
                'Waveform must reflect a high audio level after the smoothing '
                'window — peak bar was $peak in $last',
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

    test('recording → done (no release-out) stops the timer hard', () {
      // Direct cut-off path: recording → done bypasses the release-out and
      // the timer must stop immediately (no trailing pushes).
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));

          // Run a short recording period so we're sure the timer is alive.
          async.elapse(const Duration(milliseconds: 100));
          expect(h.fake.waveformPushes, isNotEmpty);

          // recording → error (legal direct transition via fail()).
          h.container.read(recordingProvider.notifier).fail('boom');
          async.elapse(const Duration(milliseconds: 5));
          final pushCountAtStop = h.fake.waveformPushes.length;

          async.elapse(const Duration(milliseconds: 400));

          expect(
            h.fake.waveformPushes.length,
            pushCountAtStop,
            reason:
                'No release-out for recording → error: timer must stop '
                'immediately, no further setWaveformBars calls for 400 ms.',
          );
        } finally {
          h.dispose();
        }
      });
    });

    test(
      'recording → transcribing: 6–10 trailing setWaveformBars over 300 ms',
      () {
        // AC1 + AC2: the named `releaseOutDurationMs` constant is exercised
        // here — 300 ms / 33 ms ≈ 9 ticks; allow 6–10 for jitter.
        FakeAsync().run((async) {
          final h = _buildHarness(async);
          try {
            h.container.read(recordingProvider.notifier).startRecording();
            async.elapse(const Duration(milliseconds: 5));

            // Burn a short window so the timer is alive and producing pushes.
            async.elapse(const Duration(milliseconds: 100));

            // Enter the release-out tail.
            h.container.read(recordingProvider.notifier).stopRecording();
            // Let the phase listener fire so _startReleaseOut() runs.
            async.elapse(const Duration(milliseconds: 5));

            // Count only the pushes during the release-out window.
            h.fake.waveformPushes.clear();
            async.elapse(const Duration(milliseconds: releaseOutDurationMs));

            expect(
              h.fake.waveformPushes.length,
              inInclusiveRange(6, 10),
              reason:
                  '${releaseOutDurationMs}ms / 33ms ≈ 9 trailing ticks; '
                  'got ${h.fake.waveformPushes.length}.',
            );
          } finally {
            h.dispose();
          }
        });
      },
    );

    test(
      'release-out: snapshot peak decays monotonically (non-increasing)',
      () {
        // AC3: during release-out the pipeline only sees pushSample(0.0), so no
        // new energy enters. In the scrolling-history model the per-bar index
        // holds different time-moments across frames, but the overall PEAK
        // (the loudest bar) must never climb back up — it only fades and
        // scrolls out.
        FakeAsync().run((async) {
          final h = _buildHarness(async);
          try {
            h.container.read(recordingProvider.notifier).startRecording();
            async.elapse(const Duration(milliseconds: 5));

            // Drive the level high so the waveform has somewhere to fall from.
            h.container.read(recordingProvider.notifier).updateAudioLevel(0.95);
            async.elapse(const Duration(milliseconds: 250));

            // Enter release-out.
            h.container.read(recordingProvider.notifier).stopRecording();
            async.elapse(const Duration(milliseconds: 5));
            h.fake.waveformPushes.clear();

            // Sample a couple of trailing ticks (≈ 33 ms apart).
            async.elapse(const Duration(milliseconds: 100));
            expect(h.fake.waveformPushes.length, greaterThanOrEqualTo(2));

            double peak(List<double> bars) =>
                bars.reduce((a, b) => a > b ? a : b);

            for (var t = 1; t < h.fake.waveformPushes.length; t++) {
              final prev = peak(h.fake.waveformPushes[t - 1]);
              final curr = peak(h.fake.waveformPushes[t]);
              expect(
                curr,
                lessThanOrEqualTo(prev + 1e-9),
                reason:
                    'Snapshot peak climbed from $prev to $curr across trailing '
                    'snapshots $t-1 → $t (must be non-increasing during '
                    'release-out).',
              );
            }
          } finally {
            h.dispose();
          }
        });
      },
    );

    test('release-out: hard-stop after the window — no pushes for 200 ms', () {
      // AC4 (hard-stop): once releaseOutDurationMs elapses the timer stops
      // itself; no further setWaveformBars calls land for 200 ms.
      FakeAsync().run((async) {
        final h = _buildHarness(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));
          async.elapse(const Duration(milliseconds: 100));

          h.container.read(recordingProvider.notifier).stopRecording();
          async.elapse(const Duration(milliseconds: 5));

          // Walk past the release-out window with a comfortable margin so the
          // self-stopping tick definitely fires (tick period is ~33 ms).
          async.elapse(
            const Duration(milliseconds: releaseOutDurationMs + 100),
          );
          final pushCountAfterWindow = h.fake.waveformPushes.length;

          async.elapse(const Duration(milliseconds: 200));

          expect(
            h.fake.waveformPushes.length,
            pushCountAfterWindow,
            reason:
                'After the release-out window the timer must stop; no further '
                'setWaveformBars calls for 200 ms (got '
                '${h.fake.waveformPushes.length - pushCountAfterWindow} extra).',
          );
        } finally {
          h.dispose();
        }
      });
    });

    test('release-out ignores audioLevelProvider — pipeline only sees 0.0', () {
      // AC5: a high audioLevel emitted during the release-out must not
      // make the live zone climb. We use a permissive notifier to bypass
      // RecordingNotifier.updateAudioLevel's own phase gate, isolating the
      // service-side gating contract.
      FakeAsync().run((async) {
        final fake = _RecordingController();
        final epoch = DateTime.utc(2026, 1, 1);
        final container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_ConstantSettingsNotifier.new),
            recordingProvider.overrideWith(_PermissiveRecordingNotifier.new),
            floatingOverlayServiceProvider.overrideWith(
              () => _TestableService(fake, now: () => epoch.add(async.elapsed)),
            ),
          ],
        );
        container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        try {
          final notifier =
              container.read(recordingProvider.notifier)
                  as _PermissiveRecordingNotifier;

          notifier.startRecording();
          async.elapse(const Duration(milliseconds: 5));
          notifier.updateAudioLevel(0.9);
          async.elapse(const Duration(milliseconds: 200));

          // Enter release-out.
          notifier.stopRecording();
          async.elapse(const Duration(milliseconds: 5));
          fake.waveformPushes.clear();

          // Sample a baseline trailing snapshot.
          async.elapse(const Duration(milliseconds: 50));
          expect(fake.waveformPushes, isNotEmpty);
          double peak(List<double> bars) =>
              bars.reduce((a, b) => a > b ? a : b);
          final baselinePeak = peak(fake.waveformPushes.last);

          // Force a fresh high audioLevel during the release-out — this
          // bypasses RecordingNotifier's own phase gate. If the service is
          // gating correctly, the waveform must NOT climb back up.
          notifier.forceAudioLevel(0.9);
          async.elapse(const Duration(milliseconds: 100));

          for (var snap = 0; snap < fake.waveformPushes.length; snap++) {
            final p = peak(fake.waveformPushes[snap]);
            expect(
              p,
              lessThanOrEqualTo(baselinePeak + 1e-9),
              reason:
                  'Snapshot peak climbed to $p > baseline $baselinePeak after '
                  'a high audioLevel during release-out (snapshot index $snap).',
            );
          }
        } finally {
          container.dispose();
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
