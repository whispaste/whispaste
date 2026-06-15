import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

/// Executes [save] and logs any exception via [log].
///
/// Both floating-surface services share this try/catch pattern around
/// settings writes that are fire-and-forget but should not swallow errors.
Future<void> saveSettingsSafely(
  AppLogger log,
  String label,
  Future<void> Function() save,
) async {
  try {
    await save();
  } catch (e, st) {
    log.error(label, e, st);
  }
}

/// Abstract base for platform floating-window services (Layer 3).
///
/// Eliminates the boilerplate that [FloatingButtonService] and
/// [FloatingOverlayService] share:
///   - controller creation via [createController]
///   - event-stream subscription in [build]
///   - cleanup (subscription cancel + controller dispose) in [ref.onDispose]
///
/// Type parameters:
///   [C] — the platform controller type (e.g. [FloatingButtonController])
///   [E] — the event type emitted by the controller's stream
///
/// Subclasses must implement:
///   - [createController] — return the platform controller, or null if
///     the current platform is unsupported
///   - [eventsFrom] — extract the event [Stream] from the controller
///   - [disposeController] — destroy the controller and release resources
///   - [onEvent] — handle each event [E]
///   - [onControllerReady] — called after the controller is wired up so the
///     subclass can set up additional [ref.listen] watchers (optional,
///     defaults to no-op)
///
/// Usage:
/// ```dart
/// class MyService extends FloatingPlatformServiceBase<MyController, MyEvent> {
///   @override
///   MyController? createController() => MyController.create();
///
///   @override
///   Stream<MyEvent> eventsFrom(MyController c) => c.events;
///
///   @override
///   Future<void> disposeController(MyController c) => c.dispose();
///
///   @override
///   void onEvent(MyEvent event) { /* handle */ }
///
///   @override
///   void onControllerReady(MyController controller) {
///     ref.listen(someProvider, ...);
///   }
/// }
/// ```
abstract class FloatingPlatformServiceBase<C extends Object, E>
    extends Notifier<void> {
  C? _controller;
  StreamSubscription<E>? _eventSub;

  final AppLogger _baseLog = AppLogger('FloatingPlatformServiceBase');

  // ── Contract ──────────────────────────────────────────────────────────────

  /// Return the platform-specific controller, or null if unsupported.
  C? createController();

  /// Extract the event [Stream] from the given [controller].
  Stream<E> eventsFrom(C controller);

  /// Destroy [controller] and release its platform resources.
  Future<void> disposeController(C controller);

  /// Handle an event emitted by the controller's event stream.
  void onEvent(E event);

  /// Called once after the controller is created and the event subscription
  /// is set up. Override to attach [ref.listen] watchers and apply initial
  /// state from providers.
  ///
  /// The [controller] argument is guaranteed non-null.
  void onControllerReady(C controller) {}

  // ── Notifier.build ────────────────────────────────────────────────────────

  @override
  void build() {
    _controller = createController();

    if (_controller == null) {
      _baseLog.debug(
        '$runtimeType: platform does not support this floating window',
      );
      return;
    }

    _eventSub = eventsFrom(_controller!).listen(onEvent);

    ref.onDispose(() async {
      await _eventSub?.cancel();
      _eventSub = null;
      final c = _controller;
      _controller = null;
      if (c != null) await disposeController(c);
    });

    onControllerReady(_controller!);
  }

  // ── Protected accessor ────────────────────────────────────────────────────

  /// The active controller, or null if the platform is unsupported or disposed.
  C? get controller => _controller;
}
