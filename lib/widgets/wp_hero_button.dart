import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

/// Shared accent-gradient hero CTA button used throughout onboarding and
/// elsewhere.
///
/// Always renders white text on the gradient background for reliable contrast
/// in both light and dark themes. Supports disabled state via nullable
/// [onPressed] and keyboard focus via [Material] + [InkWell].
class WpHeroButton extends StatefulWidget {
  const WpHeroButton({
    super.key,
    required this.label,
    required this.gradient,
    required this.onPressed,
    this.verticalPadding = WpSpacing.md,
  });

  final String label;
  final LinearGradient gradient;
  final VoidCallback? onPressed;

  /// Vertical inner padding.
  ///
  /// Every call site is on the default. The dense-page overrides this once
  /// described (`xs` on the model CTA, `sm` on the test-recording CTA) were
  /// both retired in `fa601b95`, when the merged Model & Hotkey page they
  /// paid for was split into two pages that fit the fixed window without
  /// shortening anything. Keep it that way: a CTA that is shorter than the
  /// rest of the flow's is a symptom of a page that does not fit, and the
  /// fix belongs on the page.
  final double verticalPadding;

  @override
  State<WpHeroButton> createState() => _WpHeroButtonState();
}

class _WpHeroButtonState extends State<WpHeroButton> {
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

    // House idiom for a composed control (`section.dart`): MergeSemantics +
    // a *label-less* Semantics. A `label:` here does not replace the
    // subtree's text, it is prepended to it — the rendered `Text(widget.label)`
    // below still contributes a node, so a screen reader announced the caption
    // twice ("Weiter, Weiter"). Verified against the framework: the merged
    // node keeps `actions: focus, tap`, so the button stays operable.
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: !isDisabled,
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
                      padding: EdgeInsets.symmetric(
                        vertical: widget.verticalPadding,
                      ),
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
      ),
    );
  }
}
