import 'dart:io';

import 'floating_overlay_events.dart';
import 'windows_floating_overlay_controller.dart';

/// Visual state of the overlay (matches C++ OverlayVisualState).
enum OverlayVisualState {
  recording,
  transcribing,
  processing,
  done,
  error,
}

/// Anchor position mode for the overlay window.
enum OverlayAnchorMode {
  topCenter,
  bottomCenter,
  topLeft,
}

/// Immutable snapshot of everything the overlay needs to render.
///
/// Dart owns ALL state — the native window is a dumb renderer.
/// Every field is pre-resolved (localized, formatted, themed) before sending.
class FloatingOverlaySnapshot {
  const FloatingOverlaySnapshot({
    required this.visible,
    required this.state,
    required this.isDark,
    required this.compact,
    required this.label,
    this.elapsed = '',
    this.hint = '',
    this.transcript,
    this.errorMessage,
    this.privacyMode = 'local',
    this.showRetry = false,
    this.doneMessage,
    this.processingLabel,
  });

  final bool visible;
  final OverlayVisualState state;
  final bool isDark;
  final bool compact;
  final String label;
  final String elapsed;
  final String hint;
  final String? transcript;
  final String? errorMessage;
  final String privacyMode;
  final bool showRetry;
  final String? doneMessage;
  final String? processingLabel;

  Map<String, dynamic> toMap() => {
        'visible': visible,
        'state': state.name,
        'isDark': isDark,
        'compact': compact,
        'label': label,
        'elapsed': elapsed,
        'hint': hint,
        'transcript': transcript,
        'errorMessage': errorMessage,
        'privacyMode': privacyMode,
        'showRetry': showRetry,
        'doneMessage': doneMessage,
        'processingLabel': processingLabel,
      };
}

/// Platform-agnostic interface for the native floating overlay window.
///
/// Layer 2 in the three-layer architecture. The overlay shows recording
/// status, waveform, transcription progress, and results in a native
/// always-on-top window. Future macOS/Linux implementations provide their
/// own controller behind this same interface.
abstract class FloatingOverlayController {
  /// Create the platform-specific controller, or null if unsupported.
  static FloatingOverlayController? create() {
    if (Platform.isWindows) return WindowsFloatingOverlayController();
    return null;
  }

  /// Send the complete overlay state for rendering.
  ///
  /// This is the primary interface — one call carries everything. The native
  /// window lazy-creates on the first call with `visible: true`.
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot);

  /// Send a real-time audio level for waveform animation.
  ///
  /// Only meaningful during [OverlayVisualState.recording].
  /// Should be throttled to ~20Hz by the caller.
  Future<void> setAudioLevel(double level);

  /// Move the overlay to a specific position.
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor);

  /// Set the context menu items for compact right-click.
  Future<void> setContextMenuItems(List<({String id, String label})> items);

  /// Stream of events from the native overlay window.
  Stream<FloatingOverlayEvent> get events;

  /// Destroy the native window and clean up resources.
  Future<void> dispose();
}
