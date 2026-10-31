import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// A keyboard key cap for showing a shortcut in text, e.g. "Ctrl" or "K".
///
/// Outlined on the page surface with a `borderDefault` rim and the control
/// radius. The label is the key name as the user sees it on their platform,
/// so callers pass the already-localized glyph or word.
///
/// [emphasized] marks the key that completes a shortcut (the non-modifier
/// key of a recorded hotkey): accent text and rim on the active fill.
///
/// [WpKeycap.large] is the key drawn as an object: the onboarding key test
/// and the hotkey recorder's field. It sinks in and lights cyan while [lit],
/// and a [sublabel] names the side of a key that exists twice ("rechts").
///
/// [WpKeycap.dock] is the dock's variant (spec §2): frost on the navy stage
/// with a 30 % frost rim. It reads [WpColorsDark] directly, because the dock
/// stays navy in every theme.
class WpKeycap extends StatelessWidget {
  const WpKeycap({super.key, required this.label, this.emphasized = false})
    : _dock = false,
      _large = false,
      lit = false,
      sublabel = null,
      extent = 0;

  const WpKeycap.dock({super.key, required this.label})
    : _dock = true,
      _large = false,
      emphasized = false,
      lit = false,
      sublabel = null,
      extent = 0;

  const WpKeycap.large({
    super.key,
    required this.label,
    this.sublabel,
    this.lit = false,
    this.extent = 88,
  }) : _dock = false,
       _large = true,
       emphasized = false;

  final String label;
  final bool emphasized;
  final bool _dock;
  final bool _large;

  /// [WpKeycap.large] only: the key is held.
  final bool lit;

  /// [WpKeycap.large] only: a small second line, the side of the key.
  final String? sublabel;

  /// [WpKeycap.large] only: the smallest width and height.
  final double extent;

  @override
  Widget build(BuildContext context) {
    if (_large) return _buildLarge(context);
    final ink = _dock
        ? WpColorsDark.textPrimary
        : emphasized
        ? WpColors.accent
        : WpColors.textPrimary;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: ink,
      fontFamily: kWpUiFont,
      fontFamilyFallback: kWpFontFallback,
    );
    // Keys are read left to right in every locale: a neutral symbol such as
    // "⌘" would otherwise take the RTL paragraph direction (UX-024).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        // No alignment: a Container with one expands to the parent's maximum
        // height, which made a key cap in the hotkey recorder's Wrap fill the
        // whole page (onboarding overflow, UIA-CMP-10).
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xs,
          vertical: WpSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: _dock
              ? WpColorsDark.cardFill
              : emphasized
              ? WpColors.active
              : WpColors.surface,
          borderRadius: BorderRadius.circular(WpRadiusTokens.control),
          border: _keyEdge(
            _dock
                ? WpColorsDark.frostBorder30
                : emphasized
                ? WpColors.accent.withValues(alpha: 0.4)
                : WpColors.borderDefault,
          ),
        ),
        child: Text(label, style: style),
      ),
    );
  }

  /// The key's only depth: a 1 px rim with a 2 px lower edge, as on a real
  /// key. No shadow and no glow, in any variant or colour set: the app is
  /// flat, and a floating cap read as a button.
  static Border _keyEdge(Color color, {double width = 1}) => Border(
    top: BorderSide(color: color, width: width),
    left: BorderSide(color: color, width: width),
    right: BorderSide(color: color, width: width),
    bottom: BorderSide(color: color, width: width + 1),
  );

  Widget _buildLarge(BuildContext context) {
    // Surface, rim and glyph come from the active colour set: the stage
    // palette's light glyph vanished on the light set's white surface.
    final ink = lit ? WpColors.action : WpColors.textPrimary;
    final side = sublabel;
    final rim = lit ? WpColors.action : WpColors.borderDefault;
    // A cap set in running text (below the object size) keeps the line's
    // height: its glyph matches body reading text and the side of the key
    // sits beside it instead of on a second line.
    final inline = extent < 88;
    final glyph = Text(
      label,
      style: TextStyle(
        fontSize: inline ? WpTypography.title : extent * 0.36,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    );
    final sideText = side == null
        ? null
        : Text(
            side,
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: lit ? ink : WpColors.textMuted,
            ),
          );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedContainer(
        duration: WpMotion.durationFor(context, WpMotion.fast),
        curve: WpMotion.defaultCurve,
        constraints: BoxConstraints(minWidth: extent, minHeight: extent),
        padding: EdgeInsets.symmetric(
          horizontal: extent >= 88 ? WpSpacing.lg : WpSpacing.sm,
          vertical: WpSpacing.xs,
        ),
        // Held: the key sinks by its lower edge and lights cyan.
        transform: Matrix4.translationValues(0, lit ? 1 : 0, 0),
        decoration: BoxDecoration(
          color: lit
              ? Color.lerp(WpColors.floatingSurface, WpColors.action, 0.18)
              : WpColors.floatingSurface,
          borderRadius: inline ? WpRadius.borderSm : WpRadius.borderLg,
          border: _keyEdge(rim, width: lit ? 2 : 1),
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: inline
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    glyph,
                    if (sideText != null) ...[
                      const SizedBox(width: WpSpacing.xxs),
                      sideText,
                    ],
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [glyph, ?sideText],
                ),
        ),
      ),
    );
  }
}
