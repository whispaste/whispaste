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
/// [WpKeycap.dock] is the dock's variant (spec §2): frost on the navy stage
/// with a 30 % frost rim. It reads [WpColorsDark] directly, because the dock
/// stays navy in every theme.
class WpKeycap extends StatelessWidget {
  const WpKeycap({super.key, required this.label, this.emphasized = false})
    : _dock = false;

  const WpKeycap.dock({super.key, required this.label})
    : _dock = true,
      emphasized = false;

  final String label;
  final bool emphasized;
  final bool _dock;

  @override
  Widget build(BuildContext context) {
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
          border: Border.all(
            color: _dock
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
}
