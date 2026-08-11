/// Real overlay preview widget for the Settings page.
///
/// The schematic screen simulation (OverlayPositionPreview,
/// FloatingButtonPositionPreview, _ScreenPreview, etc.) has been replaced by
/// the real [WpFloatingOverlayView], rendered with a deterministic static
/// snapshot — no live audio.
///
/// Public widget:
/// - [WpOverlayRealPreview] — renders the real [WpFloatingOverlayView] at the
///   currently selected size (Normal/Compact/Mini), reactive to settings
///   changes.
library;

import 'package:flutter/material.dart';

import '../core/config/settings_enums.dart';
import '../core/theme/tokens.dart';
import '../services/floating_overlay/floating_overlay_controller_interface.dart';
import 'floating_overlay/floating_overlay_view.dart';

// ---------------------------------------------------------------------------
// Public — Real Floating Overlay preview
// ---------------------------------------------------------------------------

/// Real preview of the Floating Overlay, rendered at [size]
/// (Normal/Compact/Mini).
///
/// Feeds [WpFloatingOverlayView] with a deterministic static snapshot — no live
/// audio. The inner [WpFloatingOverlayView] carries
/// `ValueKey('overlay-real-preview-<size.value>')` so widget tests can
/// observe size changes without reaching into painter internals.
class WpOverlayRealPreview extends StatelessWidget {
  const WpOverlayRealPreview({super.key, required this.size});

  final FloatingOverlaySize size;

  // 22 bars — matches OverlayDesignSpec.waveform.barCount.
  // Non-flat values so the waveform renders visibly in the preview.
  static final List<double> _sampleBars = List.unmodifiable(
    List.generate(22, (i) => 0.2 + 0.6 * ((i * 7) % 11) / 10.0),
  );

  @override
  Widget build(BuildContext context) {
    final snapshot = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.recording,
      size: size.variant,
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
          child: WpFloatingOverlayView(
            key: ValueKey('overlay-real-preview-${size.value}'),
            snapshot: snapshot,
            waveformBars: _sampleBars,
            // Static preview — no perpetual pulse, so pumpAndSettle settles.
            animate: false,
          ),
        ),
      ),
    );
  }
}
