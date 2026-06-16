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
  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  FloatingOverlaySnapshot? lastSnapshot;
  ({double x, double y, OverlayAnchorMode anchor})? lastPosition;
  int positionCalls = 0;
  bool disposed = false;

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

_Harness _build(FakeAsync async) {
  final epoch = DateTime.utc(2026, 1, 1);
  final fake = _FakeController();
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
}
