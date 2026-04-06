/// Floating button state management for desktop platforms.
///
/// Manages visibility, position, size, opacity, and locking of the
/// floating recording button. Does NOT create windows — the actual
/// multi-window infrastructure will be wired separately.
library;

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable state of the floating recording button.
class FloatingButtonState {
  const FloatingButtonState({
    this.isVisible = false,
    this.isLocked = false,
    this.size = 56,
    this.opacity = 1.0,
    this.autoHide = 'never',
    this.position = const Offset(100, 100),
  });

  /// Whether the floating button window is shown.
  final bool isVisible;

  /// When locked, [position] cannot be changed via [FloatingButtonNotifier.updatePosition].
  final bool isLocked;

  /// Button diameter in logical pixels (48, 56, or 72).
  final int size;

  /// Window opacity (0.0 – 1.0).
  final double opacity;

  /// Auto-hide behaviour: `'never'`, `'after_5s'`, or `'edge'`.
  final String autoHide;

  /// Current screen position (runtime-only, not persisted).
  final Offset position;

  FloatingButtonState copyWith({
    bool? isVisible,
    bool? isLocked,
    int? size,
    double? opacity,
    String? autoHide,
    Offset? position,
  }) {
    return FloatingButtonState(
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
      autoHide: autoHide ?? this.autoHide,
      position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FloatingButtonState &&
          runtimeType == other.runtimeType &&
          isVisible == other.isVisible &&
          isLocked == other.isLocked &&
          size == other.size &&
          opacity == other.opacity &&
          autoHide == other.autoHide &&
          position == other.position;

  @override
  int get hashCode => Object.hash(
        isVisible,
        isLocked,
        size,
        opacity,
        autoHide,
        position,
      );

  @override
  String toString() =>
      'FloatingButtonState(visible: $isVisible, locked: $isLocked, '
      'size: $size, opacity: $opacity, autoHide: $autoHide, '
      'position: $position)';
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the floating button lifecycle and properties.
///
/// Reads initial values from [settingsProvider] and re-builds whenever
/// relevant settings change. Position is runtime-only and not persisted.
class FloatingButtonNotifier extends Notifier<FloatingButtonState> {
  @override
  FloatingButtonState build() {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    return FloatingButtonState(
      isVisible: settings.showFloatingButton,
      isLocked: settings.floatingButtonLocked,
      size: _sizeFromString(settings.floatingButtonSize),
      opacity: settings.floatingButtonOpacity,
      autoHide: settings.floatingButtonAutoHide,
    );
  }

  // -- Visibility -----------------------------------------------------------

  void show() => state = state.copyWith(isVisible: true);

  void hide() => state = state.copyWith(isVisible: false);

  void toggle() => state = state.copyWith(isVisible: !state.isVisible);

  // -- Position -------------------------------------------------------------

  /// Updates the button position. No-op when [FloatingButtonState.isLocked].
  void updatePosition(Offset position) {
    if (state.isLocked) return;
    state = state.copyWith(position: position);
  }

  /// Snaps the button to the nearest screen edge with [edgePadding] inset.
  void snapToEdge(Size screenSize) {
    final pos = state.position;
    final buttonSize = state.size.toDouble();

    final distLeft = pos.dx;
    final distRight = screenSize.width - (pos.dx + buttonSize);
    final distTop = pos.dy;
    final distBottom = screenSize.height - (pos.dy + buttonSize);

    final minDist =
        [distLeft, distRight, distTop, distBottom].reduce((a, b) => a < b ? a : b);

    const edgePadding = 8.0;
    final Offset snapped;
    if (minDist == distLeft) {
      snapped = Offset(edgePadding, pos.dy);
    } else if (minDist == distRight) {
      snapped = Offset(screenSize.width - buttonSize - edgePadding, pos.dy);
    } else if (minDist == distTop) {
      snapped = Offset(pos.dx, edgePadding);
    } else {
      snapped = Offset(pos.dx, screenSize.height - buttonSize - edgePadding);
    }

    state = state.copyWith(position: snapped);
  }

  // -- Properties -----------------------------------------------------------

  void updateSize(int size) => state = state.copyWith(size: size);

  void updateOpacity(double opacity) =>
      state = state.copyWith(opacity: opacity.clamp(0.0, 1.0));

  void setLocked(bool locked) => state = state.copyWith(isLocked: locked);

  void setAutoHide(String mode) => state = state.copyWith(autoHide: mode);

  // -- Helpers --------------------------------------------------------------

  /// Converts the persisted size string to a pixel value.
  static int _sizeFromString(String size) {
    return switch (size.toLowerCase()) {
      'small' => 48,
      'large' => 72,
      _ => 56, // 'normal' / 'medium' / unknown → default
    };
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global provider for the floating button state.
final floatingButtonProvider =
    NotifierProvider<FloatingButtonNotifier, FloatingButtonState>(
  FloatingButtonNotifier.new,
);
