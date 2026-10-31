import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// The one content card of a page: elevated fill, a 1 px subtle edge, `md`
/// radius, 24 px inside and no shadow. A page that groups content in cards
/// (the Übersicht's hints, figures and recordings) uses this, so every card
/// has the same material, the same inner edge and the same title line.
///
/// The title sits inside the card in the section stage (Bricolage), with an
/// optional [subtitle] under it and a [trailing] action at its end — a link
/// ("Statistik →") or a quiet close. The body follows 16 px below.
class WpCard extends StatelessWidget {
  const WpCard({
    super.key,
    required this.child,
    this.title,
    this.titleTestId,
    this.subtitle,
    this.trailing,
    this.bodyPadding,
  });

  final Widget child;

  /// Section title inside the card; null for a card without a title line.
  final String? title;

  /// Accessibility identifier of the title's header node.
  final String? titleTestId;

  /// Meta line under the title (13/18, secondary text).
  final String? subtitle;

  /// Action at the end of the title line.
  final Widget? trailing;

  /// Inside spacing of the body; null is the standard 24 px. A list whose
  /// rows carry their own inset passes a smaller one, so the row text still
  /// lines up with the title.
  final EdgeInsetsGeometry? bodyPadding;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final subtitle = this.subtitle;
    final textTheme = Theme.of(context).textTheme;
    Widget content;
    if (title == null) {
      content = Padding(
        padding: bodyPadding ?? const EdgeInsets.all(WpSpacing.xl),
        child: child,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl,
              WpSpacing.xl,
              WpSpacing.xl,
              0,
            ),
            child: Row(
              crossAxisAlignment: subtitle == null
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        identifier: titleTestId,
                        child: Text(title, style: textTheme.headlineMedium),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: WpSpacing.xxs),
                        Text(
                          subtitle,
                          style: textTheme.bodyMedium?.copyWith(
                            height: 18 / WpTypography.body,
                            color: WpColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Padding(
            padding:
                bodyPadding ??
                const EdgeInsets.fromLTRB(
                  WpSpacing.xl,
                  WpSpacing.md,
                  WpSpacing.xl,
                  WpSpacing.xl,
                ),
            child: child,
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WpColors.cardFillElevated,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: WpColors.borderSubtle),
      ),
      child: content,
    );
  }
}
