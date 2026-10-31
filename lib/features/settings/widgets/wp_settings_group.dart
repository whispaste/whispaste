/// Settings card group and row (WP-23a, spec 06 §5, ticket IA §2).
///
/// A group is a heading outside a card (radius 12, `cardFill`). Rows inside it
/// carry a title, at most one explanation line and a trailing control on the
/// right. No row has a leading icon: icons live in the settings navigation.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_accent_badge.dart';

/// Widest the trailing control may grow before the label gets the rest. Wide
/// enough for a hotkey display with its change button; keeps a long dropdown
/// from crowding the title at the 800 px window.
const double _kTrailingMaxWidth = 420;

/// One [GlobalKey] per row id. The settings page scrolls to a row through it
/// (`Scrollable.ensureVisible`), so a deep link lands on the row itself.
final Map<String, GlobalKey> _settingsRowKeys = <String, GlobalKey>{};

/// The key of the row [rowId], created on first use.
GlobalKey settingsRowKey(String rowId) =>
    _settingsRowKeys.putIfAbsent(rowId, GlobalKey.new);

/// Carries the row a search hit or deep link marks; the row fades in a soft
/// tint behind itself while it is the target (see [_SettingsRowHighlightFill]).
class SettingsRowHighlight extends InheritedWidget {
  const SettingsRowHighlight({
    super.key,
    required this.rowId,
    required super.child,
  });

  /// Row id of the marked row, or null when nothing is marked.
  final String? rowId;

  static String? of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SettingsRowHighlight>();
    return scope?.rowId;
  }

  @override
  bool updateShouldNotify(SettingsRowHighlight oldWidget) =>
      oldWidget.rowId != rowId;
}

/// A titled card that holds settings rows, separated by dividers that start at
/// the text edge.
///
/// The group is the only place that draws a divider between rows. Rows and
/// their controls never draw one of their own, and a spacer ([SizedBox]
/// without a child) is air, not a row: it never adds a rule of its own.
class WpSettingsGroup extends StatelessWidget {
  const WpSettingsGroup({super.key, this.heading, required this.children});

  /// Section heading (16 Semibold) above the card. Null for an untitled card.
  final String? heading;

  /// Usually [WpSettingsRow]s. A divider goes between each pair.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = _withDividers(children);

    // The one card level of an area: a single step of fill plus a hairline
    // rim. Dark grounds get the same structure as light, never a second fill
    // inside it (rows paint nothing of their own).
    final card = DecoratedBox(
      key: const ValueKey('settings-group-card'),
      decoration: BoxDecoration(
        color: WpColors.cardFill,
        borderRadius: BorderRadius.circular(WpRadius.md),
        border: Border.all(color: WpColors.cardEdgeHighlight),
      ),
      // Horizontal 20 puts the text 20 px in. Vertical 8 plus the rows' own
      // 12 px gives the 20 px top and bottom inset of spec §5.2.
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.lg,
          vertical: WpSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );

    final heading = this.heading;
    if (heading == null) return card;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            heading,
            style: const TextStyle(
              fontFamily: kWpUiFont,
              fontFamilyFallback: kWpFontFallback,
              fontSize: WpTypography.heading,
              fontWeight: FontWeight.w600,
            ).copyWith(color: WpColors.textPrimary),
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        card,
      ],
    );
  }
}

/// The group's children with exactly one divider between each pair of rows.
///
/// Spacers (a [SizedBox] without a child, e.g. a sub-group break) never count
/// as rows and never add a rule. Between two rows their height is split around
/// the single divider, so the rule sits in the middle of the gap. Spacers
/// before the first row or after the last one keep their height, and a
/// childless [SizedBox.shrink] next to a row adds neither air nor a rule.
List<Widget> _withDividers(List<Widget> children) {
  final out = <Widget>[];
  var gap = 0.0;
  var hasRow = false;
  for (final child in children) {
    if (child is SizedBox && child.child == null) {
      gap += child.height ?? 0;
      continue;
    }
    if (hasRow) {
      if (gap > 0) out.add(SizedBox(height: gap / 2));
      out.add(Divider(height: 1, thickness: 1, color: WpColors.borderSubtle));
      // The 1 px the removed second rule took stays as air, so the rows below
      // do not move: only the duplicate line goes.
      if (gap > 0) out.add(SizedBox(height: gap / 2 + 1));
    } else if (gap > 0) {
      out.add(SizedBox(height: gap));
    }
    gap = 0;
    hasRow = true;
    out.add(child);
  }
  if (gap > 0) out.add(SizedBox(height: gap));
  return out;
}

/// One row of a [WpSettingsGroup]: title, optional explanation, trailing
/// control.
class WpSettingsRow extends StatelessWidget {
  const WpSettingsRow({
    super.key,
    required this.rowId,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.subtitleKey,
    this.disabledReason,
    this.indent = false,
    this.semanticToggledValue,
    this.badge,
    this.badgeKey,
  });

  /// Short status word after the title (e.g. "Experimental").
  final String? badge;

  /// Key for [badge], so tests and agents can address it by id.
  final Key? badgeKey;

  /// Stable kebab-case id, e.g. `general-hotkey-dictation`. Becomes
  /// `ValueKey('settings-row-<rowId>')` for deep links and search.
  final String rowId;

  final String title;

  /// The control on the right: a switch, a dropdown, a button.
  final Widget trailing;

  /// One explanation line under the title (13, `textMuted`).
  final String? subtitle;

  /// Key for the explanation line (the text of [disabledReason] or
  /// [subtitle]), so tests and agents can address it by id.
  final Key? subtitleKey;

  /// Why the control is disabled. The row stays visible, and this text
  /// replaces [subtitle] as the explanation line. Callers pass a null
  /// `onChanged` to the control at the same time.
  final String? disabledReason;

  /// Dependent row, for example the edge of a side panel under its switch.
  /// Moves the text in by one step (24).
  final bool indent;

  /// When non-null the row announces "on" or "off" with its label.
  final bool? semanticToggledValue;

  @override
  Widget build(BuildContext context) {
    final explanation = disabledReason ?? subtitle;
    return SettingsRowFrame(
      rowId: rowId,
      child: Semantics(
        label: title,
        hint: explanation,
        toggled: semanticToggledValue,
        child: Padding(
          padding: EdgeInsets.only(left: indent ? WpSpacing.xl : 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
            child: _SettingsRowFit(
              titleWidth: _titleWidth(context),
              textDirection: Directionality.of(context),
              children: [
                ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(title, style: _titleStyle())),
                          if (badge != null) ...[
                            const SizedBox(width: WpSpacing.xs),
                            WpAccentBadge(key: badgeKey, label: badge!),
                          ],
                        ],
                      ),
                      if (explanation != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          explanation,
                          key: subtitleKey,
                          style: _explanationStyle(),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Single-line width of the title for the row's fit check. A badge next to
  /// the title is not counted.
  double _titleWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: title, style: _titleStyle()),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  TextStyle _titleStyle() => const TextStyle(
    fontFamily: kWpUiFont,
    fontFamilyFallback: kWpFontFallback,
    fontSize: WpTypography.rowTitle,
    fontWeight: FontWeight.w500,
    height: 1.3,
  ).copyWith(color: WpColors.textPrimary);

  TextStyle _explanationStyle() => const TextStyle(
    fontFamily: kWpUiFont,
    fontFamilyFallback: kWpFontFallback,
    fontSize: WpTypography.body,
    fontWeight: FontWeight.w400,
    height: 1.4,
  ).copyWith(color: WpColors.textMuted);
}

/// Lays out a row's label and trailing control. The control sits beside the
/// label when the title and the control's measured width fit the row and no
/// word of the label would have to break, and under it otherwise. Both are measured in the same layout pass, so the first frame
/// is already final.
class _SettingsRowFit extends MultiChildRenderObjectWidget {
  const _SettingsRowFit({
    required this.titleWidth,
    required this.textDirection,
    required super.children,
  });

  /// Single-line width of the title, measured by the caller.
  final double titleWidth;

  /// Mirrors the row for right-to-left locales: the label starts on the right.
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSettingsRowFit(
        titleWidth: titleWidth,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSettingsRowFit renderObject,
  ) {
    renderObject
      ..titleWidth = titleWidth
      ..textDirection = textDirection;
  }
}

/// Children are the label (first) and the control (last).
class _RenderSettingsRowFit extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData> {
  _RenderSettingsRowFit({
    required this._titleWidth,
    required this._textDirection,
  });

  double _titleWidth;

  set titleWidth(double value) {
    if (_titleWidth == value) return;
    _titleWidth = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// Distance from the left edge of the row to a child of [width] that sits at
  /// the start of the line (left in LTR, right in RTL).
  double _startX(double width, double childWidth) =>
      _textDirection == TextDirection.rtl ? width - childWidth : 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MultiChildLayoutParentData) {
      child.parentData = MultiChildLayoutParentData();
    }
  }

  @override
  void performLayout() {
    final label = firstChild!;
    final control = lastChild!;
    final labelData = label.parentData! as MultiChildLayoutParentData;
    final controlData = control.parentData! as MultiChildLayoutParentData;
    final maxWidth = constraints.maxWidth;

    control.layout(
      BoxConstraints(maxWidth: math.min(maxWidth, _kTrailingMaxWidth)),
      parentUsesSize: true,
    );
    final controlWidth = control.size.width;

    // Beside only when the title fits on one line and no word of the label
    // (title or explanation) has to break inside itself: at large text scales
    // a narrow column otherwise splits words mid-way.
    final labelWidth = maxWidth - WpSpacing.md - controlWidth;
    if (_titleWidth <= labelWidth &&
        label.getMinIntrinsicWidth(double.infinity) <= labelWidth) {
      // Beside the label: the label takes the rest of the row, like Expanded.
      label.layout(
        BoxConstraints.tightFor(width: labelWidth),
        parentUsesSize: true,
      );
      final height = math.max(label.size.height, control.size.height);
      final labelX = _textDirection == TextDirection.rtl
          ? controlWidth + WpSpacing.md
          : 0.0;
      labelData.offset = Offset(labelX, (height - label.size.height) / 2);
      controlData.offset = Offset(
        _textDirection == TextDirection.rtl ? 0 : maxWidth - controlWidth,
        (height - control.size.height) / 2,
      );
      size = constraints.constrain(Size(maxWidth, height));
    } else {
      label.layout(BoxConstraints(maxWidth: maxWidth), parentUsesSize: true);
      labelData.offset = Offset(_startX(maxWidth, label.size.width), 0);
      controlData.offset = Offset(
        _startX(maxWidth, control.size.width),
        label.size.height + WpSpacing.sm,
      );
      size = constraints.constrain(
        Size(maxWidth, label.size.height + WpSpacing.sm + control.size.height),
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Frames any custom settings row (one that does not use [WpSettingsRow]) with
/// the same anchor and highlight behaviour: a `settings-row-<rowId>` key for
/// tests, the scroll anchor from [settingsRowKey], and the tint from
/// [_SettingsRowHighlightFill] while the row is the active search jump target.
class SettingsRowFrame extends StatelessWidget {
  const SettingsRowFrame({super.key, required this.rowId, required this.child});

  final String rowId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final marked = SettingsRowHighlight.of(context) == rowId;
    return KeyedSubtree(
      key: ValueKey('settings-row-$rowId'),
      child: Semantics(
        identifier: 'settings-row-$rowId',
        container: true,
        child: KeyedSubtree(
          key: settingsRowKey(rowId),
          child: _SettingsRowHighlightFill(active: marked, child: child),
        ),
      ),
    );
  }
}

/// Soft tint behind a marked row. It paints behind the row content and
/// extends [WpSpacing.sm] past the row's left and right edges, into the card's
/// own padding, so the label keeps its inner padding inside the tint. No
/// border, no outline, no layout: the tint is a positioned background, so the
/// row keeps its place while it fades in and out.
class _SettingsRowHighlightFill extends StatelessWidget {
  const _SettingsRowHighlightFill({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          left: -WpSpacing.sm,
          right: -WpSpacing.sm,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: WpMotion.durationFor(
                context,
                active ? WpMotion.highlightIn : WpMotion.highlightOut,
              ),
              curve: WpMotion.defaultCurve,
              child: DecoratedBox(
                key: const ValueKey('settings-row-highlight-fill'),
                decoration: BoxDecoration(
                  color: WpColors.accentActiveFill,
                  borderRadius: WpRadius.borderSm,
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
