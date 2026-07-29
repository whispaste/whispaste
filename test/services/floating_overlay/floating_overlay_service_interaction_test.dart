/// Controller/service interaction tests for the unified overlay (issue 05).
///
/// Locks the event back-channels and lifecycle contracts that survive the
/// renderer unification (D7/D8 — `OverlaySettings`/`WindowPositionSettings`
/// semantics unchanged):
///   - AC6: a native `onDragEnded` event persists the new position into
///     settings (`floatingOverlayX/Y`).
///   - AC3: entering recording sends the start-position anchor from settings.
///   - AC4: `done` schedules the auto-hide timer and hides after it elapses.
///
/// The seam is [FloatingOverlayController] (a fake that records calls and can
/// emit events) and a capturing [SettingsNotifier] (so `updateSettings` never
/// touches SQLite/secure storage). `package:fake_async` is the shared clock.
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

class _FakeController implements FloatingOverlayController {
  _FakeController({this.positionDelay = Duration.zero});

  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  FloatingOverlaySnapshot? lastSnapshot;
  ({double x, double y, OverlayAnchorMode anchor})? lastPosition;
  int positionCalls = 0;
  bool disposed = false;

  /// Simulates the real platform-channel round trip `setPosition` makes
  /// (currentDisplayBounds() + native reply) — zero by default so it doesn't
  /// slow down every other test, but a real delay is needed to reproduce the
  /// "fast second recording" race, where `_sendSnapshot` for the new content
  /// must win even while a genuinely slow `_setStartPosition` is still
  /// in flight. A same-microtask fake (the previous default for every test,
  /// unconditionally) can't tell an `await`-before vs. `unawaited`-before
  /// ordering apart — both resolve before the next `flushMicrotasks()`.
  final Duration positionDelay;

  void emit(FloatingOverlayEvent event) {
    if (!disposed) _eventCtrl.add(event);
  }

  @override
  Stream<FloatingOverlayEvent> get events => _eventCtrl.stream;

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {
    lastSnapshot = snapshot;
  }

  @override
  Future<void> setWaveformBars(List<double> bars) async {}

  @override
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor) async {
    if (positionDelay > Duration.zero) {
      await Future<void>.delayed(positionDelay);
    }
    positionCalls++;
    lastPosition = (x: x, y: y, anchor: anchor);
  }

  @override
  Future<void> setContextMenuItems(
    List<({String id, String label})> items,
  ) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _eventCtrl.close();
  }
}

class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake, {required super.now});
  final _FakeController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

/// In-memory [SettingsNotifier] — `updateSettings` mutates state only, so the
/// service's persistence path is exercised without SQLite/secure storage.
class _CapturingSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    final current = state.value ?? const AppSettings();
    state = AsyncData(updater(current));
  }
}

class _Harness {
  _Harness(this.fake, this.container);
  final _FakeController fake;
  final ProviderContainer container;
  void dispose() => container.dispose();
}

_Harness _build(FakeAsync async, {Duration positionDelay = Duration.zero}) {
  final epoch = DateTime.utc(2026, 1, 1);
  final fake = _FakeController(positionDelay: positionDelay);
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(_CapturingSettingsNotifier.new),
      floatingOverlayServiceProvider.overrideWith(
        () => _TestableService(fake, now: () => epoch.add(async.elapsed)),
      ),
    ],
  );
  container.listen<void>(floatingOverlayServiceProvider, (_, _) {});
  async.flushMicrotasks();
  async.elapse(const Duration(milliseconds: 1));
  async.flushMicrotasks();
  return _Harness(fake, container);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FloatingOverlayService — interaction back-channels', () {
    test('AC6: onDragEnded persists the new overlay position', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.fake.emit(const OverlayDragEnded(412.0, 268.0, 'topLeft'));
          async.elapse(const Duration(milliseconds: 5));
          async.flushMicrotasks();

          final settings = h.container.read(settingsProvider).value!;
          expect(settings.windowPosition.floatingOverlayX, 412.0);
          expect(settings.windowPosition.floatingOverlayY, 268.0);
        } finally {
          h.dispose();
        }
      });
    });

    test('AC3: entering recording sends the start-position anchor', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));
          async.flushMicrotasks();

          expect(h.fake.positionCalls, greaterThanOrEqualTo(1));
          // Default OverlaySettings.overlayStartPosition == 'top-center'.
          expect(h.fake.lastPosition?.anchor, OverlayAnchorMode.topCenter);
        } finally {
          h.dispose();
        }
      });
    });

    test('AC4: done schedules auto-hide and hides after the timer', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          final rec = h.container.read(recordingProvider.notifier);
          rec.startRecording();
          async.elapse(const Duration(milliseconds: 5));
          rec.stopRecording(); // → transcribing
          async.elapse(const Duration(milliseconds: 5));
          rec.completeTranscription('hello world'); // → done
          async.elapse(const Duration(milliseconds: 5));

          expect(
            h.fake.lastSnapshot?.state,
            OverlayVisualState.done,
            reason: 'done snapshot must reach the shell',
          );
          expect(h.fake.lastSnapshot?.visible, isTrue);

          // Auto-hide is fixed at 2 s; walk just past it.
          async.elapse(const Duration(seconds: 2, milliseconds: 100));
          async.flushMicrotasks();

          expect(
            h.fake.lastSnapshot?.visible,
            isFalse,
            reason: 'overlay must hide after the auto-hide timer elapses',
          );
        } finally {
          h.dispose();
        }
      });
    });
  });

  group('FloatingOverlayService — hide = click-inert (issue-06)', () {
    // AC5: FloatingOverlayService seam test — the idle transition pushes a
    //      visible:false snapshot, which orders the native shell off-screen so
    //      it no longer intercepts mouse events.
    test('AC5: idle transition hides the overlay via visible:false', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          // Start recording so the overlay becomes active.
          h.container.read(recordingProvider.notifier).startRecording();
          async.elapse(const Duration(milliseconds: 5));
          async.flushMicrotasks();

          // Transition to idle — triggers _hideOverlay().
          h.container.read(recordingProvider.notifier).reset();
          async.elapse(const Duration(milliseconds: 5));
          async.flushMicrotasks();

          expect(
            h.fake.lastSnapshot?.visible,
            isFalse,
            reason: 'snapshot must carry visible:false on hide',
          );
        } finally {
          h.dispose();
        }
      });
    });

    // AC2: Done auto-hide path also pushes visible:false so the window is
    //      click-inert after the linger timer expires.
    test('AC2: Done auto-hide path hides the overlay via visible:false', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          final rec = h.container.read(recordingProvider.notifier);
          rec.startRecording();
          async.elapse(const Duration(milliseconds: 5));
          rec.stopRecording(); // → transcribing
          async.elapse(const Duration(milliseconds: 5));
          rec.completeTranscription('hello world'); // → done
          async.elapse(const Duration(milliseconds: 5));

          expect(h.fake.lastSnapshot?.visible, isTrue);

          // Walk past the 2 s auto-hide delay.
          async.elapse(const Duration(seconds: 2, milliseconds: 100));
          async.flushMicrotasks();

          expect(
            h.fake.lastSnapshot?.visible,
            isFalse,
            reason: 'overlay must be hidden after auto-hide timer',
          );
        } finally {
          h.dispose();
        }
      });
    });
  });

  group('FloatingOverlayService — fast second recording (stuck-status bug)', () {
    // Regression test for a reported bug: a fast second recording left the
    // overlay frozen on the previous cycle's "done" content instead of
    // updating to show the new recording. RecordingOrchestrator.startRecording()
    // preempts a still-lingering done/error state with reset() (done -> idle)
    // and only starts the new recording after an async gap (preflight checks
    // run in between) — this test drives RecordingNotifier through that exact
    // sequence rather than the notifier's own synchronous reset()+startRecording()
    // back-to-back, which doesn't reproduce the race.
    //
    // `positionDelay` on the fake controller stands in for
    // _setStartPosition's real platform-channel round trip (currentDisplayBounds()
    // + native setPosition reply) — without an artificial delay, a same-microtask
    // fake resolves before the next flushMicrotasks() regardless of whether the
    // real code awaits it first or fires it unawaited, so it can't actually
    // distinguish the two orderings. This reproduces the bug against the
    // pre-fix code (verified by reverting the service fix locally: this
    // exact test failed, asserting `done` instead of `recording`).
    test(
      'recording content is not blocked behind an in-flight position call',
      () {
        FakeAsync().run((async) {
          final h = _build(async, positionDelay: const Duration(seconds: 1));
          try {
            final rec = h.container.read(recordingProvider.notifier);

            // First cycle: reach "done", still within the auto-hide window.
            rec.startRecording();
            async.elapse(
              const Duration(milliseconds: 1050),
            ); // clears 1s positionDelay
            rec.stopRecording();
            async.elapse(const Duration(milliseconds: 5));
            rec.completeTranscription('first recording');
            async.elapse(const Duration(milliseconds: 5));
            expect(h.fake.lastSnapshot?.state, OverlayVisualState.done);

            // Second cycle preempts the lingering done state, mirroring
            // RecordingOrchestrator.startRecording(): reset() first, then a
            // real async gap (preflight), then startRecording().
            rec.reset();
            async.elapse(const Duration(milliseconds: 50)); // preflight gap
            async.flushMicrotasks();
            rec.startRecording();
            // Deliberately short — well inside the 1s positionDelay still in
            // flight, so this only passes if content isn't gated behind it.
            async.elapse(const Duration(milliseconds: 5));
            async.flushMicrotasks();

            expect(
              h.fake.lastSnapshot?.state,
              OverlayVisualState.recording,
              reason:
                  'overlay content must show the new recording immediately, '
                  'not stay stuck on the previous cycle\'s done content while '
                  'the position call is still in flight',
            );
            expect(h.fake.lastSnapshot?.visible, isTrue);
          } finally {
            h.dispose();
          }
        });
      },
    );
  });
}
