/// Controller/service interaction tests for the unified overlay (issue 05).
///
/// Locks the event back-channels and lifecycle contracts that survive the
/// renderer unification (D7/D8 — `OverlaySettings`/`WindowPositionSettings`
/// semantics unchanged):
///   - AC6: a native `onDragEnded` event persists the new position into
///     settings (`floatingOverlayX/Y`).
///   - AC3: the master opacity is pushed to the shell on settings sync.
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
  double? lastOpacity;
  int opacityCalls = 0;
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
  Future<void> setOpacity(double opacity) async {
    opacityCalls++;
    lastOpacity = opacity;
  }

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

    test('AC3: master opacity is pushed to the shell on sync', () {
      FakeAsync().run((async) {
        final h = _build(async);
        try {
          expect(h.fake.opacityCalls, greaterThanOrEqualTo(1));
          // Default OverlaySettings.floatingOverlayOpacity == 0.9.
          expect(h.fake.lastOpacity, 0.9);
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

          // Default auto-hide is 5 s; walk just past it.
          async.elapse(const Duration(seconds: 5, milliseconds: 100));
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
}
