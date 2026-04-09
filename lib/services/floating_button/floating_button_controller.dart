import 'dart:io';

import 'floating_button_events.dart';
import 'windows_floating_button_controller.dart';

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
  /// Create the platform-specific controller, or null if unsupported.
  static FloatingButtonController? create() {
    if (Platform.isWindows) return WindowsFloatingButtonController();
    return null;
  }

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

  /// Get the current position (logical pixels), or null if not created.
  Future<({double x, double y})?> getPosition();

  /// Stream of events from the native window.
  Stream<FloatingButtonEvent> get events;

  /// Destroy the native window and clean up resources.
  Future<void> dispose();
}
