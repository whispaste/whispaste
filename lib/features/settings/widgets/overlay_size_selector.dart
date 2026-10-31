/// Visual card selector for the overlay-size setting (mini/compact/normal).
///
/// Replaces the former text dropdown in [OverlaySection]
/// (`lib/features/settings/sections/overlay_button_section.dart`) with three
/// tappable cards, each carrying a small static illustration of that size's
/// relative pill proportions. Selecting a card writes the exact same
/// [FloatingOverlaySize] value the dropdown used to — no change to the
/// underlying setting/persistence, and no dependency on the real overlay
/// rendering widgets ([WpFloatingOverlayView]/`WpOverlayPainter`): the
/// mockup below only reads the numeric geometry off [OverlaySizeSpec] (the
/// design SSOT), never the painter or widget that render the live overlay.
/// That keeps this control decoupled from the overlay widget's own
/// in-flight work.
library;

import 'package:flutter/material.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/overlay_design_spec.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';

/// Card-based replacement for the overlay-size dropdown.
///
/// Pure presentational widget: [value] is the currently selected size,
/// [onChanged] fires with the newly tapped size — same contract the old
/// `settingsDropdown` callback had.
class WpOverlaySizeSelector extends StatelessWidget {
  const WpOverlaySizeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final FloatingOverlaySize value;
  final ValueChanged<FloatingOverlaySize> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final size in FloatingOverlaySize.values) ...[
          if (size != FloatingOverlaySize.values.first)
            const SizedBox(width: WpSpacing.xs),
          _OverlaySizeCard(
            key: ValueKey('overlay-size-card-${size.value}'),
            size: size,
            label: _labelFor(l10n, size),
            selected: size == value,
            onTap: () => onChanged(size),
          ),
        ],
      ],
    );
  }

  static String _labelFor(L10n l10n, FloatingOverlaySize size) =>
      switch (size) {
        FloatingOverlaySize.normal => l10n.settingsOverlaySizeNormal,
        FloatingOverlaySize.compact => l10n.settingsOverlaySizeCompact,
        FloatingOverlaySize.mini => l10n.settingsOverlaySizeMini,
      };

  static OverlaySizeSpec _specFor(FloatingOverlaySize size) => switch (size) {
    FloatingOverlaySize.normal => OverlaySizeSpec.normal,
    FloatingOverlaySize.compact => OverlaySizeSpec.compact,
    FloatingOverlaySize.mini => OverlaySizeSpec.mini,
  };
}

// ---------------------------------------------------------------------------
// Card — mockup illustration + label + selected/hover chrome
// ---------------------------------------------------------------------------

/// Fixed mockup box every card's illustration scales into, so the three
/// cards line up on one row regardless of how much smaller mini/compact are
/// than normal.
const double _mockupBoxWidth = 64;
const double _mockupBoxHeight = 32;

class _OverlaySizeCard extends StatefulWidget {
  const _OverlaySizeCard({
    super.key,
    required this.size,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final FloatingOverlaySize size;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OverlaySizeCard> createState() => _OverlaySizeCardState();
}

class _OverlaySizeCardState extends State<_OverlaySizeCard> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final borderColor = selected
        ? WpColors.accent
        : _hovered
        ? WpColors.accentBorder30
        : WpColors.borderSubtle;
    final fillColor = selected
        ? WpColors.accentButtonFill
        : _hovered
        ? WpColors.hover
        : WpColors.floatingSurface;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.label,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.md,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                focusNode: _focusNode,
                onTap: widget.onTap,
                borderRadius: WpRadius.borderMd,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: WpMotion.durationFor(context, WpMotion.fast),
                  curve: WpMotion.defaultCurve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.sm,
                    vertical: WpSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: fillColor,
                    border: Border.all(
                      color: borderColor,
                      width: selected ? 1.5 : 1,
                    ),
                    borderRadius: WpRadius.borderMd,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: _mockupBoxWidth,
                        height: _mockupBoxHeight,
                        child: Center(
                          child: _OverlaySizeMockup(size: widget.size),
                        ),
                      ),
                      const SizedBox(height: WpSpacing.xs),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: WpTypography.caption,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected
                              ? WpColors.textPrimary
                              : WpColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Static mockup — a simplified capsule + waveform-bar illustration.
//
// Deliberately NOT [WpFloatingOverlayView]/`WpOverlayPainter`: this card only
// needs to *suggest* each size's relative footprint, and reaching for the
// real overlay renderer here would couple a settings-page control to the
// overlay widget's own rendering internals (owned by a parallel ticket).
// Only the numeric proportions come from [OverlaySizeSpec] — the design
// single source of truth for width/height, not for rendering.
// ---------------------------------------------------------------------------

class _OverlaySizeMockup extends StatelessWidget {
  const _OverlaySizeMockup({required this.size});

  final FloatingOverlaySize size;

  @override
  Widget build(BuildContext context) {
    final spec = WpOverlaySizeSelector._specFor(size);
    // Scale so the largest (normal) mockup fills the shared box height;
    // mini/compact then render visibly smaller, same as the real sizes.
    final scale = _mockupBoxHeight / OverlaySizeSpec.normal.height;
    final width = spec.width * scale;
    final height = spec.height * scale;
    final barCount = spec.minimalContent ? 5 : 3;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: WpColors.surfaceElevated,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: WpColors.accent.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < barCount; i++) ...[
              if (i > 0) const SizedBox(width: 1.5),
              Container(
                width: 1.5,
                height: height * (0.35 + 0.3 * ((i + 1) % 3) / 2),
                decoration: BoxDecoration(
                  color: WpColors.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
