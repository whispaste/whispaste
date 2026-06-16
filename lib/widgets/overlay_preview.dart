/// Real overlay preview widget for the Settings page.
///
/// The schematic screen simulation (OverlayPositionPreview,
/// FloatingButtonPositionPreview, _ScreenPreview, etc.) has been replaced by
/// the real [FloatingOverlayView], rendered with a deterministic static
/// snapshot — no live audio.
///
/// Public widget:
/// - [OverlayRealPreview] — renders the real [FloatingOverlayView] at the
///   currently selected size (Normal/Compact), reactive to settings changes.
library;

import 'package:flutter/material.dart';

import '../core/config/settings_enums.dart';
import '../core/theme/tokens.dart';
import '../services/floating_overlay/floating_overlay_controller_interface.dart';
import 'floating_overlay/floating_overlay_view.dart';

// ---------------------------------------------------------------------------
// Public — Real Floating Overlay preview
// ---------------------------------------------------------------------------

/// Real preview of the Floating Overlay, rendered at [size] (Normal/Compact).
///
/// Feeds [FloatingOverlayView] with a deterministic static snapshot — no live
/// audio. The inner [FloatingOverlayView] carries
/// `ValueKey('overlay-real-preview-<size.value>')` so widget tests can
/// observe size changes without reaching into painter internals.
class OverlayRealPreview extends StatelessWidget {
  const OverlayRealPreview({super.key, required this.size});

  final FloatingOverlaySize size;

  // 22 bars — matches OverlayDesignSpec.waveform.barCount.
  // Non-flat values so the waveform renders visibly in the preview.
  static final List<double> _sampleBars = List.unmodifiable(
    List.generate(22, (i) => 0.2 + 0.6 * ((i * 7) % 11) / 10.0),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = size == FloatingOverlaySize.compact;
    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.recording,
      isDark: isDark,
      compact: compact,
      label: 'Recording',
      elapsed: '0:05',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: FloatingOverlayView(
            key: ValueKey('overlay-real-preview-${size.value}'),
            snapshot: snapshot,
            waveformBars: _sampleBars,
          ),
        ),
      ),
    );
  }
}
