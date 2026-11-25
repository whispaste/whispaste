import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// The small count on the corner of a toolbar icon button: active filters on
/// the filter button, pending imports or interrupted recordings on
/// Recordings. One look for every count in the toolbar row. The number is
/// decoration; the button's own label carries it for assistive technology.
class WpCountBadge extends StatelessWidget {
  const WpCountBadge({super.key, required this.count, required this.child});

  final int count;

  /// The button the badge sits on.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          PositionedDirectional(
            top: -WpSpacing.xxs,
            end: -WpSpacing.xxs,
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
                decoration: BoxDecoration(
                  color: WpColors.accentBadgeFill,
                  borderRadius: WpRadius.borderFull,
                  border: Border.all(color: WpColors.accentBorder30),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    fontWeight: FontWeight.w600,
                    color: WpColors.accent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
