/// Pure interface for the floating overlay controller.
///
/// The shared types, enums, and the abstract [FloatingOverlayController]
/// class live here so that platform implementations can import only this file
/// and avoid a circular dependency with the factory layer.
library;

import '../../core/theme/overlay_design_spec.dart'
    show OverlaySizeVariant, OverlayStyleVariant;
import 'floating_overlay_events.dart';

/// Visual state of the overlay (matches C++ OverlayVisualState).
enum OverlayVisualState { recording, transcribing, done, error }

/// Anchor position mode for the overlay window.
enum OverlayAnchorMode { topCenter, bottomCenter, topLeft }

/// Immutable snapshot of everything the overlay needs to render.
///
/// Dart owns ALL state — the native window is a dumb renderer.
/// Every field is pre-resolved (localized, formatted, themed) before sending.
class FloatingOverlaySnapshot {
  const FloatingOverlaySnapshot({
    required this.visible,
    required this.state,
    required this.label,
    this.size = OverlaySizeVariant.normal,
    this.style = OverlayStyleVariant.glass,
    this.elapsed = '',
    this.hint = '',
    this.transcript,
    this.errorMessage,
    this.privacyMode = 'local',
    this.doneMessage,
    this.progress = 0.0,
    this.secondaryLabel,
  });

  final bool visible;
  final OverlayVisualState state;

  /// The overlay size variant (normal / compact / mini). The native shells
  /// size their window from the serialised `size` name.
  final OverlaySizeVariant size;

  /// The overlay chrome style (glass / solid), independent of [size].
  final OverlayStyleVariant style;

  final String label;
  final String elapsed;
  final String hint;
  final String? transcript;
  final String? errorMessage;
  final String privacyMode;
  final String? doneMessage;

  /// Recording progress (0.0–1.0). 0 = unlimited/no limit set.
  final double progress;

  /// Smaller second text line under [label] in the text-forward
  /// (transcribing-style) composition — the guided-sequence frames use it
  /// for the Enter/Escape mechanics and the "get ready" beat. Null/empty
  /// keeps the classic single-line layout; the minimal (mini) composition
  /// never paints it.
  final String? secondaryLabel;

  Map<String, dynamic> toMap() => {
    'visible': visible,
    'state': state.name,
    'size': size.name,
    'style': style.name,
    // Legacy mirror of the old two-size contract, kept so any consumer that
    // still switches on the boolean (older shell binaries during a staged
    // rollout) degrades to compact instead of breaking. `mini` reports
    // compact=false; such a consumer falls back to the normal window.
    'compact': size == OverlaySizeVariant.compact,
    'label': label,
    'elapsed': elapsed,
    'hint': hint,
    'transcript': transcript,
    'errorMessage': errorMessage,
    'privacyMode': privacyMode,
    'doneMessage': doneMessage,
    'progress': progress,
    'secondaryLabel': secondaryLabel,
  };

  /// Rebuilds a snapshot from its [toMap] form.
  ///
  /// Used by the in-process overlay render engine (ADR 0002 phase 2): the
  /// native shell relays the main engine's [toMap] payload to the dedicated
  /// overlay Flutter engine, which deserialises it here before feeding
  /// [WpFloatingOverlayView]. Unknown/absent `state` falls back to
  /// [OverlayVisualState.recording] so a malformed relay never crashes the
  /// render isolate.
  factory FloatingOverlaySnapshot.fromMap(Map<dynamic, dynamic> map) {
    final stateName = map['state'] as String?;
    final state = OverlayVisualState.values.firstWhere(
      (s) => s.name == stateName,
      orElse: () => OverlayVisualState.recording,
    );
    // `size` is the canonical key; a payload without it (older sender) falls
    // back to the legacy `compact` boolean.
    final sizeName = map['size'] as String?;
    final size = sizeName != null
        ? OverlaySizeVariant.fromName(sizeName)
        : ((map['compact'] as bool? ?? false)
              ? OverlaySizeVariant.compact
              : OverlaySizeVariant.normal);
    final style = OverlayStyleVariant.fromName(map['style'] as String?);
    return FloatingOverlaySnapshot(
      visible: map['visible'] as bool? ?? false,
      state: state,
      size: size,
      style: style,
      label: map['label'] as String? ?? '',
      elapsed: map['elapsed'] as String? ?? '',
      hint: map['hint'] as String? ?? '',
      transcript: map['transcript'] as String?,
      errorMessage: map['errorMessage'] as String?,
      privacyMode: map['privacyMode'] as String? ?? 'local',
      doneMessage: map['doneMessage'] as String?,
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      secondaryLabel: map['secondaryLabel'] as String?,
    );
  }
}

/// Platform-agnostic interface for the native floating overlay window.
///
/// Layer 2 in the three-layer architecture. The overlay shows recording
/// status, waveform, transcription progress, and results in a native
/// always-on-top window. Future macOS/Linux implementations provide their
/// own controller behind this same interface.
abstract class FloatingOverlayController {
  /// Send the complete overlay state for rendering.
  ///
  /// This is the primary interface — one call carries everything. The native
  /// window lazy-creates on the first call with `visible: true`.
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot);

  /// Push a pre-computed waveform bar array (length 30, values 0.0–1.0).
  ///
  /// Stateless render path: the native window draws bar `i` at height
  /// `minH + bars[i] × (maxH − minH)` with active/muted colour decided by
  /// `bars[i] >= 0.30`. This is the sole waveform input — the native side
  /// owns no smoothing or animation state of its own (cut-over: issue 06).
  Future<void> setWaveformBars(List<double> bars);

  /// Move the overlay to a specific position.
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor);

  /// Set the context menu items for compact right-click.
  Future<void> setContextMenuItems(List<({String id, String label})> items);

  /// Stream of events from the native overlay window.
  Stream<FloatingOverlayEvent> get events;

  /// Destroy the native window and clean up resources.
  Future<void> dispose();
}
