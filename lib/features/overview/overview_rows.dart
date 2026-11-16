import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_row_divider.dart';
import '../../widgets/wp_text_link.dart';

/// The one look of the Übersicht's list sections ("Letzte Aufnahmen",
/// "Notizen", #630): a card with a title, an "all" link to the page behind it,
/// and either rows divided by hairlines or a quiet empty state. Both sections
/// build on this, so they cannot drift apart.
class OverviewRowsCard extends StatelessWidget {
  const OverviewRowsCard({
    super.key,
    required this.title,
    required this.testId,
    required this.allLabel,
    required this.onAll,
    required this.rows,
    this.empty,
    this.allKind = WpLinkKind.page,
  });

  final String title;

  /// Base testID: the title carries it, the link `<testId>-all`.
  final String testId;
  final String allLabel;
  final VoidCallback onAll;

  /// What the trailing link does: opens a page (default) or acts in place,
  /// such as the news block's "Quellen" dialog.
  final WpLinkKind allKind;

  /// The rows, each an [OverviewRow]; ignored while [empty] is set.
  final List<Widget> rows;

  /// The empty state shown instead of the rows, or null when there are rows.
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final empty = this.empty;
    return WpCard(
      title: title,
      titleTestId: testId,
      trailing: WpTextLink(
        testID: '$testId-all',
        label: allLabel,
        kind: allKind,
        onPressed: onAll,
      ),
      // Rows carry a 16 px inset of their own, so their hover surface keeps a
      // margin to the card edge and their text lines up with the title.
      bodyPadding: empty != null ? null : const EdgeInsets.all(WpSpacing.xs),
      child:
          empty ??
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0)
                  const WpRowDivider(
                    inset: EdgeInsets.symmetric(horizontal: WpSpacing.md),
                  ),
                row,
              ],
            ],
          ),
    );
  }
}

/// One row of an [OverviewRowsCard]: a time column that grows with the text
/// size, a leading tile, the text (clicking it opens the item, where people
/// read it) and the actions, which stay visible so they need no precise
/// pointer move. Hover and keyboard focus tint the whole row.
class OverviewRow extends StatefulWidget {
  const OverviewRow({
    super.key,
    required this.time,
    required this.leading,
    required this.text,
    required this.onOpen,
    required this.actions,
    this.subtitle,
    this.timeWidth = 48,
  });

  /// The label of the time column.
  final String time;

  /// Unscaled width of the time column; it grows with the text size so the
  /// label never breaks.
  final double timeWidth;

  /// The tile in front of the text ([WpIconSize.xl]).
  final Widget leading;
  final String text;
  final String? subtitle;
  final VoidCallback onOpen;

  /// The buttons at the end; the row puts the gaps between them.
  final List<Widget> actions;

  @override
  State<OverviewRow> createState() => _OverviewRowState();
}

class _OverviewRowState extends State<OverviewRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final meta = WpTextStyles.rowNote;
    final subtitle = widget.subtitle;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: _hovered || _focused ? WpColors.hover : Colors.transparent,
            borderRadius: WpRadius.borderSm,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xs,
          ),
          child: Row(
            children: [
              // Grows with the text so the time never breaks at its colon.
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(widget.timeWidth),
                child: Text(widget.time, style: meta),
              ),
              const SizedBox(width: WpSpacing.md),
              widget.leading,
              const SizedBox(width: WpSpacing.md),
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WpTextStyles.rowTitle,
                        ),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(subtitle, style: meta),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.md),
              for (final (i, action) in widget.actions.indexed) ...[
                if (i > 0) const SizedBox(width: WpSpacing.xs),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
