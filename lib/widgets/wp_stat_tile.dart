import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// Pill-shaped stat block on the app's card material, with a number that counts
/// up once on entry. Shared by the Statistik page's hero row and the
/// Übersicht's key figures, so a figure looks the same wherever it appears. Deliberately not interactive — the doc used to promise a
/// "hover interaction" that the widget no longer has, and a stat card that
/// lights up under the pointer would imply a click target this app does not
/// offer here.
///
/// Every pill used to carry a 2 px `accentWarmGradient` strip along its top
/// edge (ticket 32, finding B4). Two things were wrong with it. It was the
/// brand's loudest gradient, the one the app otherwise spends only where it
/// marks a real selection, sitting on a tile that cannot be selected or even
/// clicked — the same broken promise the removed hover highlight made, in
/// paint instead of motion. And it was on *all* of them, so the row was four
/// (sometimes five) identically weighted tiles: nothing in it answered "what
/// is this dashboard about", which is the job of the first thing a reader
/// meets on a page.
///
/// Rank replaces the strip. The row's [isLead] tile — the count of the thing
/// the whole app exists to do — sits on the elevated rung of the card material
/// and keeps the accent icon; the rest sit on the base rung with a muted icon
/// and read as the supporting detail they are. Geometry, padding and type are
/// untouched: this is a difference in weight, not in size, which is the only kind a row of equally sized cells can
/// carry without one of them jumping out of the grid.
class WpStatTile extends StatefulWidget {
  const WpStatTile({
    super.key,
    required this.icon,
    required this.rawValue,
    required this.formatter,
    required this.label,
    this.isLead = false,
    this.placeholder,
    this.note,
  }) : flat = false;

  /// The same figure as a row inside a card (the Übersicht's figures card):
  /// no own fill, edge or radius; the card around the rows carries those.
  const WpStatTile.row({
    super.key,
    required this.icon,
    required this.rawValue,
    required this.formatter,
    required this.label,
    this.isLead = false,
    this.placeholder,
    this.note,
  }) : flat = true;

  final IconData icon;
  final int rawValue;
  final String Function(int) formatter;
  final String label;

  /// Whether this is the row's lead statistic. Exactly one pill sets it.
  final bool isLead;

  /// Shown in the label style instead of the number when there is not yet
  /// enough data for an honest value ("Noch zu wenig Daten").
  final String? placeholder;

  /// A short line under the label for a figure that rests on an assumption
  /// ("geschätzt, bei 50 Wörtern pro Minute getippt"): the assumption is
  /// read with the number, not hidden in a tooltip.
  final String? note;

  /// Row inside a card, see [WpStatTile.row].
  final bool flat;

  @override
  State<WpStatTile> createState() => _WpStatTileState();
}

class _WpStatTileState extends State<WpStatTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _counter;
  late final CurvedAnimation _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // `dramatic` (500 ms) is the app's ceiling for a one-shot transition, and
    // this count-up used to run 1200 ms — more than twice it. Every other
    // duration above the ceiling in this codebase is either a timer or a
    // *periodic* pulse (waveform, recording bar, overlay dot), where a long
    // period is the point; among one-shot entrance animations these two on
    // this screen were the only ones out of band. It matters more here than
    // it looks: while the count-up runs, the card does not show the number
    // smaller, it shows a *different* number — a total of 347 reads 12, then
    // 98, then 210. That is decoration instead of the information rather than
    // on top of it, so the time spent unreadable is the thing worth cutting.
    _counter = AnimationController(vsync: this, duration: WpMotion.dramatic);
    _curve = CurvedAnimation(parent: _counter, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `forward()` bakes in `duration` at call time, so the reduced-motion
    // duration must be set before the first (only) forward() call, not after.
    _counter.duration = WpMotion.durationFor(context, WpMotion.dramatic);
    if (!_started) {
      _started = true;
      _counter.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _counter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: WpTypography.body,
      height: 18 / WpTypography.body,
      color: WpColors.textSecondary,
    );
    final placeholder = widget.placeholder;
    // The number counts up for the eye only; its node states the final value
    // from the first frame. The figure stage (28/700, tabular) against the
    // 13/18 label makes the number lead. The `FittedBox` scales a long total
    // down in a narrow tile instead of wrapping or clipping it.
    final value = placeholder != null
        ? Text(placeholder, style: labelStyle)
        : Semantics(
            label: widget.formatter(widget.rawValue),
            excludeSemantics: true,
            child: AnimatedBuilder(
              animation: _curve,
              builder: (context, _) {
                final current = (widget.rawValue * _curve.value).round();
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    widget.formatter(current),
                    maxLines: 1,
                    style: WpTextStyles.figure,
                  ),
                );
              },
            ),
          );
    // Icon to the left of the value, label under the value: the figure is as
    // tall as its content. Icon accent on the lead statistic, muted on the
    // rest.
    final content = Row(
      children: [
        Icon(
          widget.icon,
          size: WpIconSize.md,
          color: widget.isLead ? WpColors.accent : WpColors.textMuted,
        ),
        const SizedBox(width: WpSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              value,
              Text(widget.label, style: labelStyle),
              if (widget.note case final note?)
                Text(
                  note,
                  style: labelStyle.copyWith(
                    fontSize: WpTypography.caption,
                    color: WpColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    // One stat, one node. The number and its caption were two unrelated
    // fragments in the semantics tree, so the value arrived without ever
    // saying what it counted ("1.234" … "Wörter").
    //
    // No hover highlight: everywhere else in this app a surface that lights
    // up under the pointer is a surface you can click, and a figure is not.
    if (widget.flat) {
      return MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
          child: content,
        ),
      );
    }
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: widget.isLead ? WpColors.cardFillElevated : WpColors.cardFill,
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: WpColors.cardEdgeHighlight),
        ),
        child: content,
      ),
    );
  }
}
