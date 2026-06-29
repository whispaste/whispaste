import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// Shared accent-gradient CTA button used throughout onboarding and elsewhere.
///
/// Always renders white text on the gradient background for reliable contrast
/// in both light and dark themes. Supports disabled state via nullable
/// [onPressed] and keyboard focus via [Material] + [InkWell].
class WpAccentButton extends StatefulWidget {
  const WpAccentButton({
    super.key,
    required this.label,
    required this.gradient,
    required this.onPressed,
  });

  final String label;
  final LinearGradient gradient;
  final VoidCallback? onPressed;

  @override
  State<WpAccentButton> createState() => _WpAccentButtonState();
}

class _WpAccentButtonState extends State<WpAccentButton> {
  bool _hovered = false;
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: widget.label,
      child: AnimatedScale(
        scale: !isDisabled && _hovered ? 1.02 : 1.0,
        duration: WpMotion.durationFor(context, WpMotion.fast),
        curve: WpMotion.defaultCurve,
        child: AnimatedOpacity(
          duration: WpMotion.durationFor(context, WpMotion.fast),
          opacity: isDisabled ? 0.5 : 1.0,
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.md,
            child: Material(
              color: Colors.transparent,
              borderRadius: WpRadius.borderMd,
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(gradient: widget.gradient),
                child: InkWell(
                  onTap: widget.onPressed,
                  focusNode: _focusNode,
                  borderRadius: WpRadius.borderMd,
                  // WpFocusRing owns focus visuals — suppress InkWell's own.
                  focusColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onHover: (hovering) => setState(() => _hovered = hovering),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
                    alignment: Alignment.center,
                    child: Text(
                      widget.label,
                      // labelLarge = Type/button role (16 / 700 / ls -0.3).
                      // Always white: button sits on an accent-gradient background.
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white),
                    ),
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
