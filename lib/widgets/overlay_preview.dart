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
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/overlay_customization.dart';
import '../core/theme/overlay_design_spec.dart';
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
  const WpOverlayRealPreview({
    super.key,
    required this.size,
    this.background = OverlayBackground.marine,
    this.wave = OverlayWave.cyan,
    this.compact = false,
    this.shrinkWrap = false,
    this.appearance = OverlayAppearance.defaults,
  });

  final FloatingOverlaySize size;

  /// ticket appearance options the preview renders (form, wave style, timer,
  /// cancel glyph, opacity), so the preview matches the live overlay.
  final OverlayAppearance appearance;

  /// Background preset the preview renders (ticket, ADR 0024), reactive to
  /// the Settings swatches, independent of [size].
  final OverlayBackground background;

  /// Wave colour preset the preview renders (ticket, ADR 0024).
  final OverlayWave wave;

  /// Pill only: no surrounding padding, so a short box shows the pill itself.
  /// Used where the page has no room for the framed preview.
  final bool compact;

  /// Sizes the preview to the pill instead of the available width, so it can
  /// share a row with other previews (settings preview stage).
  final bool shrinkWrap;

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
      background: background,
      wave: wave,
      label: L10n.of(context).overlayRecording,
      elapsed: formatOverlayElapsed(const Duration(seconds: 5)),
      appearance: appearance,
    );

    final pill = Center(
      widthFactor: shrinkWrap ? 1 : null,
      heightFactor: shrinkWrap ? 1 : null,
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
    );

    return Semantics(
      label: L10n.of(context).settingsOverlayPreview,
      container: true,
      child: compact
          ? pill
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.sm,
              ),
              child: pill,
            ),
    );
  }
}
