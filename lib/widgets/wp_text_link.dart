import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_touch_target.dart';

/// Where a link leads. The only thing that varies between the app's links:
/// the words, colour, size and states are the same everywhere.
enum WpLinkKind {
  /// Does something in place ("Hide", "Show full text"): no mark.
  action,

  /// Opens another place in the app ("Statistics →"): an arrow after the
  /// words, pointing with the reading direction.
  page,

  /// Opens a web page in the browser: the external-link mark after the words.
  web,
}

/// The one text link of the app, in the accent (Petrol) colour, 14/600. A
/// link-weight action: it never fills a surface, so it does not compete with
/// the one primary button.
///
/// Resting: accent text. Hover: underlined, hand cursor. Pressed: a light
/// accent wash behind the words. Focus: the shared focus ring. Disabled
/// ([onPressed] null): `textMuted`, no tap target. The colour never changes
/// with the state, so the AA contrast of the accent holds in every one.
class WpTextLink extends StatefulWidget {
  const WpTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = WpLinkKind.action,
    this.semanticsLabel,
    this.testID,
  });

  final String label;
  final VoidCallback? onPressed;
  final WpLinkKind kind;

  /// What a screen reader says instead of [label], when the visible words
  /// need their row to make sense ("Open" → "Open privacy policy").
  final String? semanticsLabel;

  /// Stable, language-independent id put on the tappable node (kebab-case,
  /// e.g. `onboarding-appearance-settings-link`). Null leaves it unset.
  final String? testID;

  @override
  State<WpTextLink> createState() => _WpTextLinkState();
}

class _WpTextLinkState extends State<WpTextLink> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpTextLink');
  bool _hovered = false;
  bool _pressed = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    // A link, not a button: it navigates or opens a URL, and assistive tech
    // announces it as such.
    // One node carries the link role, the label, the tap action and the
    // identifier; excludeSemantics drops the carrier's duplicate tap node.
    return Semantics(
      link: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? widget.label,
      onTap: widget.onPressed,
      identifier: widget.testID,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: WpTouchTarget(
          onTap: widget.onPressed,
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadiusTokens.sm,
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: (down) => setState(() => _pressed = down),
              focusNode: _focusNode,
              borderRadius: WpRadius.borderSm,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: WpLinkLabel(
                label: widget.label,
                kind: widget.kind,
                enabled: enabled,
                hovered: _hovered,
                pressed: _pressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How a link looks, without being one: words, mark and state. [WpTextLink]
/// draws it; a whole surface that is a link (a card that opens a page) puts it
/// inside and passes its own hover and press, so the card's call to action
/// looks and reacts like every other link.
class WpLinkLabel extends StatelessWidget {
  const WpLinkLabel({
    super.key,
    required this.label,
    this.kind = WpLinkKind.action,
    this.enabled = true,
    this.hovered = false,
    this.pressed = false,
  });

  final String label;
  final WpLinkKind kind;
  final bool enabled;
  final bool hovered;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? WpColors.accent : WpColors.textMuted;
    final active = enabled && (hovered || pressed);
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: color,
      fontSize: WpTypography.subheading,
      fontWeight: FontWeight.w600,
      decoration: active ? TextDecoration.underline : null,
      decorationColor: color,
      fontFamily: kWpUiFont,
      fontFamilyFallback: kWpFontFallback,
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final mark = switch (kind) {
      WpLinkKind.action => null,
      WpLinkKind.page => rtl ? LucideIcons.arrowLeft : LucideIcons.arrowRight,
      WpLinkKind.web => LucideIcons.externalLink,
    };
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final wash = enabled && pressed
        ? WpColors.accentActiveFill
        : WpColors.accentActiveFill.withValues(alpha: 0);

    // The words sit flush with the text edge of their column: no horizontal
    // padding. The press wash still reaches a little past the words, painted
    // outside the layout box like the focus ring, so it never shifts them.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: wash),
      duration: reduceMotion || pressed ? Duration.zero : WpMotion.hoverOut,
      builder: (context, fill, child) =>
          CustomPaint(painter: _LinkWashPainter(fill ?? wash), child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible so a long label wraps at large text sizes instead
            // of overflowing the row (inflexible children get unbounded width).
            Flexible(child: Text(label, style: style)),
            if (mark != null) ...[
              const SizedBox(width: WpSpacing.xxs),
              Icon(mark, size: WpIconSize.sm, color: color),
            ],
          ],
        ),
      ),
    );
  }
}

/// Paints the press wash behind a link's words, [WpSpacing.xxs] wider on
/// each side than the layout box.
class _LinkWashPainter extends CustomPainter {
  const _LinkWashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final rect = Rect.fromLTRB(
      -WpSpacing.xxs,
      0,
      size.width + WpSpacing.xxs,
      size.height,
    );
    canvas.drawRRect(WpRadius.borderSm.toRRect(rect), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LinkWashPainter old) => old.color != color;
}
