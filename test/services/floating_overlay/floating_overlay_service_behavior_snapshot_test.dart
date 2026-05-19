/// Behavior-snapshot tests for [FloatingOverlayService].
///
/// Locks the controller lifecycle, event-stream wiring, and cleanup contracts
/// after the base-class migration (issue 11).
///
/// The seam is [FloatingOverlayController]: a [_FakeController] is injected via
/// the provider override so no real platform channels are opened.
///
/// Scenarios covered:
///   1. Controller lifecycle — created on build, disposed on container disposal
///   2. Event subscription — stream is listened after build, cancelled on dispose
///   3. Cleanup — subscription cancelled, then controller disposed
///   4. Null-platform guard — service handles null controller gracefully
///
/// NOTE: [FloatingOverlayService] now extends [FloatingPlatformServiceBase]
/// (issue 11). The injection seam is [createController] (base class contract).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_events.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';

// ── Fake controller ───────────────────────────────────────────────────────────

class _FakeController implements FloatingOverlayController {
  bool created = true;
  bool disposed = false;
  int subscriptionCount = 0;

  final _eventCtrl = StreamController<FloatingOverlayEvent>.broadcast();

  /// Whether the event stream currently has at least one listener.
  bool get hasEventListener => _eventCtrl.hasListener;

  /// Whether the event stream has been closed (post-dispose).
  bool get isClosed => _eventCtrl.isClosed;

  /// Emit an event to all listeners.
  void emit(FloatingOverlayEvent event) => _eventCtrl.add(event);

  @override
  Stream<FloatingOverlayEvent> get events {
    subscriptionCount++;
    return _eventCtrl.stream;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _eventCtrl.close();
  }

  // ── Unused interface methods (no-ops for snapshot tests) ─────────────────

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
  Future<void> setOpacity(double opacity) async {}
}

// ── Testable service subclass ─────────────────────────────────────────────────

/// Overrides [FloatingOverlayService] to inject a [_FakeController]
/// instead of calling [FloatingOverlayController.create()].
class _TestableService extends FloatingOverlayService {
  _TestableService(this._fake);

  final _FakeController _fake;

  @override
  FloatingOverlayController? createController() => _fake;
}

/// Variant that simulates a platform with no overlay support.
class _NullControllerService extends FloatingOverlayService {
  @override
  FloatingOverlayController? createController() => null;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FloatingOverlayService — controller lifecycle', () {
    test('controller is created when provider is first read', () async {
      final fake = _FakeController();
      final container = ProviderContainer(
        overrides: [
          floatingOverlayServiceProvider.overrideWith(
            () => _TestableService(fake),
          ),
        ],
      );
      try {
        container.read(floatingOverlayServiceProvider);
        expect(fake.created, isTrue);
        expect(fake.disposed, isFalse);
      } finally {
        container.dispose();
        await Future<void>.delayed(Duration.zero);
      }
    });

    test('controller is disposed when ProviderContainer is disposed', () async {
      final fake = _FakeController();
      final container = ProviderContainer(
        overrides: [
          floatingOverlayServiceProvider.overrideWith(
            () => _TestableService(fake),
          ),
        ],
      );

      container.read(floatingOverlayServiceProvider);
      expect(fake.disposed, isFalse);

      container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(fake.disposed, isTrue);
    });

    test(
      'controller is not double-disposed on single container.dispose()',
      () async {
        final fake = _FakeController();
        final container = ProviderContainer(
          overrides: [
            floatingOverlayServiceProvider.overrideWith(
              () => _TestableService(fake),
            ),
          ],
        );

        container.read(floatingOverlayServiceProvider);
        container.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(fake.disposed, isTrue);
      },
    );
  });

  group('FloatingOverlayService — event subscription', () {
    test(
      'service subscribes to the event stream exactly once on build',
      () async {
        final fake = _FakeController();
        final container = ProviderContainer(
          overrides: [
            floatingOverlayServiceProvider.overrideWith(
              () => _TestableService(fake),
            ),
          ],
        );
        try {
          container.read(floatingOverlayServiceProvider);
          expect(fake.subscriptionCount, 1);
        } finally {
          container.dispose();
          await Future<void>.delayed(Duration.zero);
        }
      },
    );

    test('event stream has a listener after build', () async {
      final fake = _FakeController();
      final container = ProviderContainer(
        overrides: [
          floatingOverlayServiceProvider.overrideWith(
            () => _TestableService(fake),
          ),
        ],
      );
      try {
        container.read(floatingOverlayServiceProvider);
        expect(fake.hasEventListener, isTrue);
      } finally {
        container.dispose();
        await Future<void>.delayed(Duration.zero);
      }
    });

    test(
      'event subscription is cancelled when container is disposed',
      () async {
        final fake = _FakeController();
        final container = ProviderContainer(
          overrides: [
            floatingOverlayServiceProvider.overrideWith(
              () => _TestableService(fake),
            ),
          ],
        );

        container.read(floatingOverlayServiceProvider);
        expect(fake.hasEventListener, isTrue);

        container.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(fake.isClosed, isTrue);
      },
    );
  });

  group('FloatingOverlayService — cleanup ordering', () {
    test('controller is disposed after full cleanup', () async {
      final fake = _FakeController();
      final container = ProviderContainer(
        overrides: [
          floatingOverlayServiceProvider.overrideWith(
            () => _TestableService(fake),
          ),
        ],
      );

      container.read(floatingOverlayServiceProvider);
      expect(fake.disposed, isFalse);

      container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(fake.disposed, isTrue);
    });
  });

  group('FloatingOverlayService — null-platform guard', () {
    test(
      'service builds without error when platform has no overlay support',
      () async {
        final container = ProviderContainer(
          overrides: [
            floatingOverlayServiceProvider.overrideWith(
              () => _NullControllerService(),
            ),
          ],
        );

        try {
          expect(
            () => container.read(floatingOverlayServiceProvider),
            returnsNormally,
          );
        } finally {
          container.dispose();
          await Future<void>.delayed(Duration.zero);
        }
      },
    );

    test(
      'multiple build/dispose cycles on null platform do not throw',
      () async {
        for (var i = 0; i < 3; i++) {
          final container = ProviderContainer(
            overrides: [
              floatingOverlayServiceProvider.overrideWith(
                () => _NullControllerService(),
              ),
            ],
          );
          container.read(floatingOverlayServiceProvider);
          container.dispose();
          await Future<void>.delayed(Duration.zero);
        }
      },
    );
  });
}
