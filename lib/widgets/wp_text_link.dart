import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

/// Inline text action in the accent (Petrol) colour, with an optional leading
/// icon, e.g. "Kontextvorschau" under a form field. A link-weight action: it
/// never fills a surface, so it does not compete with the one primary button.
///
/// Resting: accent text. Hover: underlined. Focus: the shared focus ring.
/// Disabled ([onPressed] null): `textMuted`, no tap target.
class WpTextLink extends StatefulWidget {
  const WpTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.testID,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Stable, language-independent id put on the tappable node (kebab-case,
  /// e.g. `onboarding-appearance-settings-link`). Null leaves it unset.
  final String? testID;

  @override
  State<WpTextLink> createState() => _WpTextLinkState();
}

class _WpTextLinkState extends State<WpTextLink> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpTextLink');
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final color = enabled ? WpColors.accent : WpColors.textMuted;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
      decoration: enabled && _hovered ? TextDecoration.underline : null,
      decorationColor: color,
      fontFamily: kWpUiFont,
      fontFamilyFallback: kWpFontFallback,
    );

    // A link, not a button: it navigates or opens a URL, and assistive tech
    // announces it as such.
    return Semantics(
      link: true,
      enabled: enabled,
      identifier: widget.testID,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // loam-ignore: a11y-interactive-semantics – the wrapped child keeps its own role and label; WpTouchTarget only enlarges the tap area and is excluded from semantics (see wp_touch_target.dart).
        child: WpTouchTarget(
          onTap: widget.onPressed,
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadiusTokens.sm,
            child: InkWell(
              onTap: widget.onPressed,
              focusNode: _focusNode,
              borderRadius: WpRadius.borderSm,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.xxs,
                  vertical: WpSpacing.xxs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: WpIconSize.sm, color: color),
                      const SizedBox(width: WpSpacing.xxs),
                    ],
                    // Flexible so a long label wraps at large text sizes instead
                    // of overflowing the row (inflexible children get unbounded width).
                    Flexible(child: Text(widget.label, style: style)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
