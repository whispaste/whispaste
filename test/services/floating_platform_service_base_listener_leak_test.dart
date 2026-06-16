/// Event-listener-leak tests for [FloatingPlatformServiceBase].
///
/// Reproduces the bug where calling [build] on the same notifier instance more
/// than once (Riverpod rebuild / hot-reload) creates additional event
/// subscriptions without cancelling the previous one — causing every native
/// event to fire N times instead of once.
///
/// Fix: cancel the existing subscription at the start of [build] before
/// overwriting [_eventSub].
///
/// Acceptance criteria covered:
///   AC1 — subscription is cancelled before the next one is created
///   AC2 — after N builds, a single native event triggers exactly one callback
///   AC3 — covers both [FloatingButtonService] and [FloatingOverlayService]
///         via the shared [FloatingPlatformServiceBase]
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/floating_platform_service_base.dart';

// ── Minimal base-class test harness ──────────────────────────────────────────

class _StubController {}

/// Minimal [FloatingPlatformServiceBase] subclass for testing the subscription
/// lifecycle in isolation.
///
/// The event [Stream] is provided externally and is NOT closed when
/// [disposeController] is invoked, so events remain emittable across multiple
/// simulated rebuild cycles.
class _BaseLeakService
    extends FloatingPlatformServiceBase<_StubController, int> {
  _BaseLeakService(this._stream, this._onEventCallback);

  final Stream<int> _stream;
  final void Function() _onEventCallback;

  @override
  _StubController createController() => _StubController();

  @override
  Stream<int> eventsFrom(_StubController _) => _stream;

  @override
  Future<void> disposeController(_StubController _) async {
    // Intentional no-op: the shared stream must outlive controller dispose so
    // events can be emitted across rebuild cycles.
  }

  @override
  void onEvent(int _) => _onEventCallback();

  // Declaring a concrete override here lets simulateRebuild() call through
  // this class's own method rather than the @visibleForOverriding abstract in
  // Notifier. The override is intentionally a no-added-behaviour pass-through
  // that enables the hot-reload simulation seam.
  @override
  // ignore: unnecessary_overrides
  void build() => super.build();

  /// Re-invokes [build] on the existing instance without an [onDispose] cycle.
  ///
  /// This reproduces the hot-reload scenario where Riverpod calls [build] on
  /// the same notifier object a second time. Without the fix the old
  /// [StreamSubscription] is left alive, duplicating [onEvent] callbacks.
  void simulateRebuild() => build();
}

// ── FloatingButtonService fake ────────────────────────────────────────────────

/// [FloatingButtonController] fake whose event stream is never closed by
/// [dispose] — so events remain emittable after the controller has been
/// logically disposed between rebuild cycles. The stream is closed via the
/// [ctrl] getter in the test teardown once the scenario is complete.
class _ButtonFake implements FloatingButtonController {
  final _ctrl = StreamController<FloatingButtonEvent>.broadcast();

  StreamController<FloatingButtonEvent> get ctrl => _ctrl;

  @override
  Stream<FloatingButtonEvent> get events => _ctrl.stream;

  @override
  Future<void> dispose() => _ctrl.close();

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) async {}
  @override
  Future<void> hide() async {}
  @override
  Future<void> setState(FloatingButtonVisualState state) async {}
  @override
  Future<void> setTheme({required bool isDark}) async {}
  @override
  Future<void> setPosition(double x, double y) async {}
  @override
  Future<void> setSize(int size) async {}
  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) async {}
  @override
  Future<({double x, double y})?> getPosition() async => null;
}

/// [FloatingButtonService] subclass configured for leak testing:
///   - [createController] always returns the same [_ButtonFake] instance so
///     every subscription targets the same broadcast stream.
///   - [onControllerReady] is a no-op to avoid provider dependencies.
///   - [onEvent] routes to a callback counter.
class _ButtonLeakService extends FloatingButtonService {
  _ButtonLeakService(this._fake, this._onEventCallback);

  final _ButtonFake _fake;
  final void Function() _onEventCallback;

  @override
  FloatingButtonController createController() => _fake;

  @override
  void onControllerReady(FloatingButtonController _) {
    // No-op: skip complex provider wiring for this leak test.
  }

  @override
  void onEvent(FloatingButtonEvent _) => _onEventCallback();

  @override
  // ignore: unnecessary_overrides
  void build() => super.build();

  /// Simulates hot-reload: re-runs [build] on the same instance.
  void simulateRebuild() => build();
}

// ── FloatingOverlayService fake ───────────────────────────────────────────────

/// [FloatingOverlayController] fake whose event stream is never closed by
/// [dispose] across rebuild cycles. The stream is closed in teardown.
class _OverlayFake implements FloatingOverlayController {
  final _ctrl = StreamController<FloatingOverlayEvent>.broadcast();

  StreamController<FloatingOverlayEvent> get ctrl => _ctrl;

  @override
  Stream<FloatingOverlayEvent> get events => _ctrl.stream;

  @override
  Future<void> dispose() => _ctrl.close();

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) async {}
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
  Future<void> orderOut() async {}
}

/// [FloatingOverlayService] subclass configured for leak testing.
///
/// [onControllerReady] is a no-op to avoid:
///   1. The `late final WaveformPipeline _pipeline` re-initialisation error
///      when [build] is invoked more than once on the same instance.
///   2. Complex provider dependencies not relevant to the leak test.
class _OverlayLeakService extends FloatingOverlayService {
  _OverlayLeakService(this._fake, this._onEventCallback);

  final _OverlayFake _fake;
  final void Function() _onEventCallback;

  @override
  FloatingOverlayController createController() => _fake;

  @override
  void onControllerReady(FloatingOverlayController _) {
    // No-op: see class-level doc.
  }

  @override
  void onEvent(FloatingOverlayEvent _) => _onEventCallback();

  @override
  // ignore: unnecessary_overrides
  void build() => super.build();

  /// Simulates hot-reload: re-runs [build] on the same instance.
  void simulateRebuild() => build();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group(
    'FloatingPlatformServiceBase — event-listener leak (AC1 + AC2, base class)',
    () {
      test(
        'after 3 build() calls a single native event fires onEvent exactly once',
        () async {
          final eventCtrl = StreamController<int>.broadcast();
          var callCount = 0;

          final provider = NotifierProvider<_BaseLeakService, void>(
            () => _BaseLeakService(eventCtrl.stream, () => callCount++),
          );

          final container = ProviderContainer();
          addTearDown(() async {
            container.dispose();
            await Future<void>.delayed(Duration.zero);
            await eventCtrl.close();
          });

          // Build #1 — normal Riverpod initialisation.
          container.read(provider);
          final notifier = container.read(provider.notifier);

          // Builds #2 and #3 — simulate hot-reload: build() re-invoked on the
          // same instance without an onDispose cycle.
          notifier.simulateRebuild();
          notifier.simulateRebuild();

          // Emit exactly ONE event.
          eventCtrl.add(0);
          await Future<void>.delayed(Duration.zero);

          // Without fix: callCount == 3 (each leaked sub fires the callback).
          // After fix:  callCount == 1.
          expect(callCount, 1);
        },
      );
    },
  );

  group('FloatingButtonService — event-listener leak (AC3)', () {
    test(
      'after 3 build() calls a single button event fires onEvent exactly once',
      () async {
        final fake = _ButtonFake();
        var callCount = 0;

        final provider = NotifierProvider<_ButtonLeakService, void>(
          () => _ButtonLeakService(fake, () => callCount++),
        );

        final container = ProviderContainer();
        addTearDown(() async {
          container.dispose();
          await Future<void>.delayed(Duration.zero);
        });

        container.read(provider);
        final notifier = container.read(provider.notifier);

        notifier.simulateRebuild();
        notifier.simulateRebuild();

        fake.ctrl.add(const FloatingButtonClicked());
        await Future<void>.delayed(Duration.zero);

        expect(callCount, 1);
      },
    );
  });

  group('FloatingOverlayService — event-listener leak (AC3)', () {
    test(
      'after 3 build() calls a single overlay event fires onEvent exactly once',
      () async {
        final fake = _OverlayFake();
        var callCount = 0;

        final provider = NotifierProvider<_OverlayLeakService, void>(
          () => _OverlayLeakService(fake, () => callCount++),
        );

        final container = ProviderContainer();
        addTearDown(() async {
          container.dispose();
          await Future<void>.delayed(Duration.zero);
        });

        container.read(provider);
        final notifier = container.read(provider.notifier);

        notifier.simulateRebuild();
        notifier.simulateRebuild();

        fake.ctrl.add(const OverlayBodyClicked());
        await Future<void>.delayed(Duration.zero);

        expect(callCount, 1);
      },
    );
  });
}
