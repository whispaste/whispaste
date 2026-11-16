/// Support provider tiles (#395): one tile per external support provider in
/// the provider's own colour, with its official logo. Like the coffee button,
/// a brand surface that [WpButton] does not cover, so it builds its own
/// button here (allowed by wp_button_raw_material_guard_test).
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/generated/wp_tokens.g.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';
import 'wp_focus_ring.dart';

/// The support providers with a tile of their own. Names are brand names and
/// stay untranslated; colours come from `design-tokens/app.tokens.json`
/// (`brand.*`), logos from `assets/social/` (see its NOTICE.md).
enum WpSupportProvider {
  paypal(
    'PayPal',
    'assets/social/paypal-logo.svg',
    WpBrandTokens.brandPaypalFill,
    WpBrandTokens.brandPaypalFillHover,
    WpBrandTokens.brandPaypalOnFill,
  ),
  kofi(
    'Ko-fi',
    'assets/social/kofi-logo.svg',
    WpBrandTokens.brandKofiFill,
    WpBrandTokens.brandKofiFillHover,
    WpBrandTokens.brandKofiOnFill,
  ),
  buyMeACoffee(
    'Buy Me a Coffee',
    'assets/social/buymeacoffee-logo.svg',
    WpBrandTokens.brandBmcFill,
    WpBrandTokens.brandBmcFillHover,
    WpBrandTokens.brandBmcOnFill,
  ),
  githubSponsors(
    'GitHub Sponsors',
    'assets/social/githubsponsors-logo.svg',
    WpBrandTokens.brandSponsorsFill,
    WpBrandTokens.brandSponsorsFillHover,
    WpBrandTokens.brandSponsorsOnFill,
  );

  const WpSupportProvider(
    this.label,
    this.logo,
    this.fill,
    this.fillHover,
    this.ink,
  );

  final String label;
  final String logo;
  final Color fill;
  final Color fillHover;
  final Color ink;
}

/// One support provider as a tile in its own colour: logo, name and a short
/// line on what it is for, as wide as that content (#1070). The whole tile
/// is one button whose accessible name says what it does ("Support with
/// PayPal") plus the line.
class WpProviderTile extends StatefulWidget {
  const WpProviderTile({
    super.key,
    required this.provider,
    required this.description,
    required this.semanticLabel,
    required this.testId,
    required this.onPressed,
  });

  final WpSupportProvider provider;
  final String description;
  final String semanticLabel;
  final String testId;
  final VoidCallback onPressed;

  @override
  State<WpProviderTile> createState() => _WpProviderTileState();
}

class _WpProviderTileState extends State<WpProviderTile> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'SupportProviderTile');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final ts = Theme.of(context).textTheme;
    final button = FilledButton(
      focusNode: _focusNode,
      onPressed: widget.onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)
              ? provider.fillHover
              : provider.fill,
        ),
        foregroundColor: WidgetStatePropertyAll(provider.ink),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        // At least the touch target; the logo, the two text lines and the
        // padding set the real height.
        minimumSize: const WidgetStatePropertyAll(
          Size(WpLayout.minTouchTarget, WpLayout.minTouchTarget),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: WpSpacing.lg,
            vertical: WpSpacing.md,
          ),
        ),
        alignment: AlignmentDirectional.centerStart,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: WpRadius.borderLg),
        ),
      ),
      child: Semantics(
        label: '${widget.semanticLabel}, ${widget.description}',
        excludeSemantics: true,
        // Content width (#1070): the tile is only as wide as logo, name and
        // line need; in a narrower slot the text wraps instead of overflowing.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              provider.logo,
              width: WpIconSize.lg,
              height: WpIconSize.lg,
              excludeFromSemantics: true,
              colorFilter: ColorFilter.mode(provider.ink, BlendMode.srcIn),
            ),
            const SizedBox(width: WpSpacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    provider.label,
                    style: ts.titleSmall?.copyWith(
                      color: provider.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    widget.description,
                    style: ts.bodySmall?.copyWith(color: provider.ink),
                  ),
                ],
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Icon(
              LucideIcons.externalLink,
              size: WpIconSize.sm,
              color: provider.ink,
            ),
          ],
        ),
      ),
    );
    return Semantics(
      identifier: widget.testId,
      child: KeyedSubtree(
        key: ValueKey<String>(widget.testId),
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.lg,
          child: button,
        ),
      ),
    );
  }
}
