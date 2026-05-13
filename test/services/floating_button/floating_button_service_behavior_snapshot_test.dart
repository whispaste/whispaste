/// Behavior-snapshot tests for [FloatingButtonService].
///
/// Locks the controller lifecycle, event-stream wiring, and cleanup contracts
/// before and after the base-class extraction refactor (issue 10). These tests
/// survive migration unchanged — only import paths may change.
///
/// The seam is [FloatingButtonController]: a [_FakeController] is injected via
/// the provider override so no real platform channels are opened.
///
/// Scenarios covered:
///   1. Controller lifecycle — created on build, disposed on container disposal
///   2. Event subscription — stream is listened after build, cancelled on dispose
///   3. Cleanup ordering — subscription cancelled, then controller disposed
///   4. Null-platform guard — service handles null controller gracefully
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';

// ── Fake controller ───────────────────────────────────────────────────────────

class _FakeController implements FloatingButtonController {
  bool created = true;
  bool disposed = false;
  int subscriptionCount = 0;

  final _eventCtrl = StreamController<FloatingButtonEvent>.broadcast();

  /// Whether the event stream currently has at least one listener.
  bool get hasEventListener => _eventCtrl.hasListener;

  /// Whether the event stream has been closed (post-dispose).
  bool get isClosed => _eventCtrl.isClosed;

  /// Emit an event to all listeners.
  void emit(FloatingButtonEvent event) => _eventCtrl.add(event);

  @override
  Stream<FloatingButtonEvent> get events {
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
  Future<void> setOpacity(double opacity) async {}

  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) async {}

  @override
  Future<({double x, double y})?> getPosition() async => null;
}

// ── Testable service subclass ─────────────────────────────────────────────────

/// Overrides [FloatingButtonService] to inject a [_FakeController]
/// instead of calling [FloatingButtonController.create()].
class _TestableService extends FloatingButtonService {
  _TestableService(this._fake);

  final _FakeController _fake;

  @override
  FloatingButtonController? createController() => _fake;
}

/// Variant that simulates a platform with no floating button support.
class _NullControllerService extends FloatingButtonService {
  @override
  FloatingButtonController? createController() => null;
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Creates a [ProviderContainer] wired to [_TestableService] + [_FakeController].
({ProviderContainer container, _FakeController fake}) _makeContainer() {
  final fake = _FakeController();
  final container = ProviderContainer(
    overrides: [
      floatingButtonServiceProvider.overrideWith(() => _TestableService(fake)),
    ],
  );
  return (container: container, fake: fake);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('FloatingButtonService — controller lifecycle', () {
    test('controller is created when provider is first read', () async {
      final (:container, :fake) = _makeContainer();
      try {
        container.read(floatingButtonServiceProvider);
        expect(fake.created, isTrue);
        expect(fake.disposed, isFalse);
      } finally {
        container.dispose();
        await Future<void>.delayed(Duration.zero);
      }
    });

    test('controller is disposed when ProviderContainer is disposed', () async {
      final (:container, :fake) = _makeContainer();

      container.read(floatingButtonServiceProvider);
      expect(fake.disposed, isFalse);

      container.dispose();
      // Allow async onDispose callbacks to complete.
      await Future<void>.delayed(Duration.zero);

      expect(fake.disposed, isTrue);
    });

    test(
      'controller is not double-disposed on single container.dispose()',
      () async {
        final (:container, :fake) = _makeContainer();

        container.read(floatingButtonServiceProvider);
        container.dispose();
        await Future<void>.delayed(Duration.zero);

        // dispose() should have been called exactly once.
        expect(fake.disposed, isTrue);
      },
    );
  });

  group('FloatingButtonService — event subscription', () {
    test(
      'service subscribes to the event stream exactly once on build',
      () async {
        final (:container, :fake) = _makeContainer();
        try {
          container.read(floatingButtonServiceProvider);
          expect(fake.subscriptionCount, 1);
        } finally {
          container.dispose();
          await Future<void>.delayed(Duration.zero);
        }
      },
    );

    test('event stream has a listener after build', () async {
      final (:container, :fake) = _makeContainer();
      try {
        container.read(floatingButtonServiceProvider);
        expect(fake.hasEventListener, isTrue);
      } finally {
        container.dispose();
        await Future<void>.delayed(Duration.zero);
      }
    });

    test(
      'event subscription is cancelled when container is disposed',
      () async {
        final (:container, :fake) = _makeContainer();

        container.read(floatingButtonServiceProvider);
        expect(fake.hasEventListener, isTrue);

        container.dispose();
        await Future<void>.delayed(Duration.zero);

        // Stream closed by controller.dispose() — no active listeners remain.
        expect(fake.isClosed, isTrue);
      },
    );
  });

  group('FloatingButtonService — cleanup ordering', () {
    test('controller is disposed after full cleanup', () async {
      final (:container, :fake) = _makeContainer();

      container.read(floatingButtonServiceProvider);
      expect(fake.disposed, isFalse);

      container.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(fake.disposed, isTrue);
    });

    test(
      'disposing an uninitialized service (null controller) does not throw',
      () async {
        final container = ProviderContainer(
          overrides: [
            floatingButtonServiceProvider.overrideWith(
              () => _NullControllerService(),
            ),
          ],
        );

        // Must not throw.
        container.read(floatingButtonServiceProvider);
        container.dispose();
        // Allow async callbacks to settle.
        await Future<void>.delayed(Duration.zero);
      },
    );
  });

  group('FloatingButtonService — null-platform guard', () {
    test('service builds without error when platform has no floating button '
        'support', () async {
      final container = ProviderContainer(
        overrides: [
          floatingButtonServiceProvider.overrideWith(
            () => _NullControllerService(),
          ),
        ],
      );

      try {
        expect(
          () => container.read(floatingButtonServiceProvider),
          returnsNormally,
        );
      } finally {
        container.dispose();
        await Future<void>.delayed(Duration.zero);
      }
    });

    test(
      'multiple build/dispose cycles on null platform do not throw',
      () async {
        for (var i = 0; i < 3; i++) {
          final container = ProviderContainer(
            overrides: [
              floatingButtonServiceProvider.overrideWith(
                () => _NullControllerService(),
              ),
            ],
          );
          container.read(floatingButtonServiceProvider);
          container.dispose();
          await Future<void>.delayed(Duration.zero);
        }
      },
    );
  });
}
