/// Pure interface for the floating button controller.
///
/// The [FloatingButtonVisualState] enum and the abstract
/// [FloatingButtonController] class live here so that platform
/// implementations can import only this file and avoid a circular
/// dependency with the factory layer.
library;

import 'floating_button_events.dart';

/// Visual state of the floating button (matches C++ FloatingButtonState).
enum FloatingButtonVisualState {
  idle,
  recording,
  transcribing,
  done,
  error,
  disabled,
}

/// Platform-agnostic interface for the native floating button.
///
/// Layer 2 in the three-layer architecture. Only Layer 1 (the native
/// implementation) is platform-specific. Future macOS/Linux implementations
/// provide their own controller behind this same interface.
abstract class FloatingButtonController {
  /// Show the floating button at the given position (logical pixels).
  Future<void> show({double x = 200, double y = 200, int size = 56});

  /// Hide the floating button (keeps the native window for reuse).
  Future<void> hide();

  /// Update the visual state (gradient, icon, animation).
  Future<void> setState(FloatingButtonVisualState state);

  /// Switch between dark/light theme (affects idle/muted gradients).
  Future<void> setTheme({required bool isDark});

  /// Move the button to a new position (logical pixels).
  Future<void> setPosition(double x, double y);

  /// Resize the button (logical pixels: 48, 56, or 72).
  Future<void> setSize(int size);

  /// Set master opacity (0.0–1.0).
  Future<void> setOpacity(double opacity);

  /// Set context menu items shown on right-click.
  ///
  /// Each item is a map with `id` (String) and `label` (String).
  /// Pass an empty list to disable the context menu (falls back to
  /// [FloatingButtonSecondaryClicked] event).
  Future<void> setContextMenuItems(List<Map<String, String>> items);

  /// Get the current position (logical pixels), or null if not created.
  Future<({double x, double y})?> getPosition();

  /// Stream of events from the native window.
  Stream<FloatingButtonEvent> get events;

  /// Destroy the native window and clean up resources.
  Future<void> dispose();
}
