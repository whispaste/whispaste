// The multi-select action bar shared by the list pages (Verlauf, Textbausteine, Notizen).
// Lives in widgets/ so a feature page can use it without importing another
// feature's widget file (that created an import cycle).
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/settings_labels.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'page_shell.dart';
import 'wp_button.dart';

/// Horizontal padding inside the selection-count pill.
const double _kCountPadX = WpSpacing.sm;

/// Width of the overflow (…) button, the menu's own minimum tap box.
const double _kMoreButtonWidth = 48;

/// Rounding headroom per measured slot, so a label that measures exactly
/// at the edge is moved into the menu rather than clipped.
const double _kFitSlack = 4;

// ---------------------------------------------------------------------------
// Multi-select action bar
// ---------------------------------------------------------------------------

class WpMultiSelectBar extends StatelessWidget {
  const WpMultiSelectBar({
    super.key,
    required this.selectedCount,
    required this.isTrashView,
    required this.isArchiveView,
    required this.onCancelSelection,
    this.onSelectAll,
    this.totalCount,
    this.onMerge,
    this.onBatchCopy,
    this.onBatchCopyMarkdown,
    this.onExport,
    this.onArchive,
    this.onDelete,
    this.onRestore,
    this.onFavourite,
    this.onTag,
    this.favouriteLabel,
    this.favouriteIcon = LucideIcons.star,
    this.idPrefix = 'history-multiselect',
  });

  final int selectedCount;
  final bool isTrashView;
  final bool isArchiveView;
  final VoidCallback onCancelSelection;
  final VoidCallback? onSelectAll;
  final int? totalCount;
  final VoidCallback? onMerge;
  final VoidCallback? onBatchCopy;
  final VoidCallback? onBatchCopyMarkdown;
  final VoidCallback? onExport;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  /// Star / un-star the selection (Textbausteine). [favouriteLabel] names what
  /// the tap will do for the current selection.
  final VoidCallback? onFavourite;

  /// Add a tag to the selection (Notizen, #655).
  final VoidCallback? onTag;
  final String? favouriteLabel;
  final IconData favouriteIcon;

  /// Prefix of the test keys, so another list can reuse the bar with its own
  /// stable IDs (`<prefix>-delete`, `<prefix>-cancel`, `<prefix>-more`).
  final String idPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent = WpColors.accent;
    // Card material at its elevated rung: this bar is a mode band laid over
    // the list, and the frost keeps the ambient running under it.
    final bg = WpColors.cardFillElevated;

    // Secondary actions sit in the overflow menu, so the destructive action
    // and Cancel stay on the bar at every width and never need a horizontal
    // scroll to be reached (UIA-HIS-18).
    final overflowActions = <_HistoryMultiSelectOverflowAction>[
      if (onMerge != null)
        _HistoryMultiSelectOverflowAction(
          id: 'merge',
          icon: LucideIcons.merge,
          label: l10n.historyMerge,
          shortcutHint: formatHotkeyShortcut('ctrl', 'm', l10n: l10n),
          onTap: onMerge!,
        ),
      if (onBatchCopy != null)
        _HistoryMultiSelectOverflowAction(
          id: 'copy',
          icon: LucideIcons.copy,
          label: l10n.historyCopyText,
          shortcutHint: formatHotkeyShortcut('ctrl', 'c', l10n: l10n),
          onTap: onBatchCopy!,
        ),
      if (onBatchCopyMarkdown != null)
        _HistoryMultiSelectOverflowAction(
          id: 'markdown',
          icon: LucideIcons.fileText,
          label: l10n.historyCopyAsMarkdown,
          onTap: onBatchCopyMarkdown!,
        ),
      if (onExport != null)
        _HistoryMultiSelectOverflowAction(
          id: 'export',
          icon: LucideIcons.download,
          label: l10n.historyExportAction,
          onTap: onExport!,
        ),
      if (onTag != null)
        _HistoryMultiSelectOverflowAction(
          id: 'tag',
          icon: LucideIcons.tag,
          label: l10n.notesAddTag,
          onTap: onTag!,
        ),
      if (onFavourite != null)
        _HistoryMultiSelectOverflowAction(
          id: 'favourite',
          icon: favouriteIcon,
          label: favouriteLabel ?? '',
          onTap: onFavourite!,
        ),
      if (onRestore != null)
        _HistoryMultiSelectOverflowAction(
          id: 'restore',
          icon: LucideIcons.undo2,
          label: l10n.historyRestore,
          onTap: onRestore!,
        ),
      if (onArchive != null)
        _HistoryMultiSelectOverflowAction(
          id: 'archive',
          icon: isArchiveView
              ? LucideIcons.archiveRestore
              : LucideIcons.archive,
          label: isArchiveView ? l10n.historyUnarchive : l10n.historyArchive,
          onTap: onArchive!,
        ),
    ];

    final countLabel = l10n.historyItemsSelected(selectedCount);
    final selectAllLabel = totalCount != null && selectedCount >= totalCount!
        ? l10n.historyDeselectAll
        : l10n.historySelectAll;
    final deleteLabel = isTrashView
        ? l10n.historyDeleteForever
        : l10n.actionDelete;
    final deleteShortcut = hotkeyKeyLabel('delete', l10n: l10n);
    final countStyle = TextStyle(
      fontSize: WpTypography.body,
      fontWeight: FontWeight.w600,
      color: accent,
    );
    final selectAllStyle = TextStyle(
      fontSize: WpTypography.small,
      color: accent,
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure every label at the user's text size, so the bar can decide
        // up front what fits whole. A label that is squeezed instead wraps
        // mid-word or ellipsizes at 200 % text (#1388).
        final ambient = DefaultTextStyle.of(context).style;
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double textWidth(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: ambient.merge(style)),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width.ceilToDouble();
        }

        final fit = fitMultiSelectBar(
          available: constraints.maxWidth - 2 * WpPageFrame.inset,
          count:
              textWidth(countLabel, countStyle) + _kCountPadX * 2 + _kFitSlack,
          countShort:
              textWidth('$selectedCount', countStyle) +
              _kCountPadX * 2 +
              _kFitSlack,
          selectAll: onSelectAll == null
              ? null
              : WpSpacing.sm +
                    textWidth(selectAllLabel, selectAllStyle) +
                    WpSpacing.xs * 2 +
                    _kFitSlack,
          delete: onDelete == null
              ? null
              : WpMultiSelectAction.widthFor(
                      textWidth(
                        deleteLabel,
                        const TextStyle(fontSize: WpTypography.small),
                      ),
                    ) +
                    _kFitSlack,
          cancel:
              WpSpacing.sm +
              WpButton.denseGhostWidthFor(
                textWidth(l10n.actionCancel, WpButton.denseTextStyle),
                hasIcon: true,
              ) +
              _kFitSlack,
          more: _kMoreButtonWidth,
          hasSecondary: overflowActions.isNotEmpty,
        );

        final menuActions = <_HistoryMultiSelectOverflowAction>[
          if (!fit.selectAllOnBar && onSelectAll != null)
            _HistoryMultiSelectOverflowAction(
              id: 'select-all',
              key: ValueKey('$idPrefix-select-all'),
              icon: LucideIcons.listChecks,
              label: selectAllLabel,
              onTap: onSelectAll!,
            ),
          ...overflowActions,
          if (!fit.deleteOnBar && onDelete != null)
            _HistoryMultiSelectOverflowAction(
              id: 'delete',
              key: ValueKey('$idPrefix-delete'),
              icon: LucideIcons.trash2,
              label: deleteLabel,
              shortcutHint: deleteShortcut,
              onTap: onDelete!,
              isDestructive: true,
            ),
        ];

        Widget countPill = Container(
          padding: const EdgeInsets.symmetric(
            horizontal: _kCountPadX,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: WpColors.accentBadgeFill,
            borderRadius: WpRadius.borderFull,
          ),
          child: Text(
            fit.countFull ? countLabel : '$selectedCount',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            softWrap: false,
            style: countStyle,
          ),
        );
        if (!fit.countFull) {
          // Only the number fits: the full phrase stays in reach for the
          // screen reader and on hover.
          countPill = Tooltip(
            message: countLabel,
            child: Semantics(
              label: countLabel,
              child: ExcludeSemantics(child: countPill),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpPageFrame.inset,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: bg,
            // The band's lower edge is `cardEdgeHighlight`, not `accentBorder20`
            // (Ticket 13): the line is load-bearing — it is what separates the
            // mode band from the list underneath it — but the *accent* on it was
            // not. Accent means "you can act on this", and nothing happens when
            // you touch a boundary. Structurally the same finding as Ticket 32's
            // B3 (the section-head accent bar, removed by Ticket 08). The accent
            // that stays on this bar is the selection-count pill, which reports
            // what the operable controls beside it will act on.
            border: Border(
              bottom: BorderSide(color: WpColors.cardEdgeHighlight, width: 1),
            ),
          ),
          child: Row(
            children: [
              // [fitMultiSelectBar] already moved what does not fit whole into
              // the overflow menu; the Flexible/ellipsis below is only a guard
              // against measuring a pixel short, never the layout plan.
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: countPill),
                    if (fit.selectAllOnBar) ...[
                      const SizedBox(width: WpSpacing.sm),
                      // Select All / Deselect All toggle
                      Flexible(
                        child: InkWell(
                          key: ValueKey('$idPrefix-select-all'),
                          borderRadius: WpRadius.borderSm,
                          onTap: onSelectAll,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.xs,
                              vertical: WpSpacing.xxs,
                            ),
                            child: Text(
                              selectAllLabel,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              softWrap: false,
                              style: selectAllStyle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (menuActions.isNotEmpty)
                    _HistoryMultiSelectMoreButton(
                      actions: menuActions,
                      idPrefix: idPrefix,
                    ),
                  if (fit.deleteOnBar)
                    WpMultiSelectAction(
                      key: ValueKey('$idPrefix-delete'),
                      icon: LucideIcons.trash2,
                      label: deleteLabel,
                      shortcutHint: deleteShortcut,
                      onTap: onDelete!,
                      isDestructive: true,
                    ),
                  WpButton(
                    label: l10n.actionCancel,
                    variant: WpButtonVariant.ghost,
                    tone: WpButtonTone.neutral,
                    icon: LucideIcons.x,
                    size: WpButtonSize.dense,
                    onPressed: onCancelSelection,
                    testId: '$idPrefix-cancel',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// What [WpMultiSelectBar] shows on the bar itself; everything else sits in
/// its overflow menu.
@immutable
class WpMultiSelectBarFit {
  const WpMultiSelectBarFit({
    required this.countFull,
    required this.selectAllOnBar,
    required this.deleteOnBar,
  });

  /// False: the count pill shows only the number (full phrase as tooltip and
  /// screen-reader label).
  final bool countFull;
  final bool selectAllOnBar;
  final bool deleteOnBar;

  @override
  bool operator ==(Object other) =>
      other is WpMultiSelectBarFit &&
      other.countFull == countFull &&
      other.selectAllOnBar == selectAllOnBar &&
      other.deleteOnBar == deleteOnBar;

  @override
  int get hashCode => Object.hash(countFull, selectAllOnBar, deleteOnBar);

  @override
  String toString() =>
      'WpMultiSelectBarFit(countFull: $countFull, '
      'selectAllOnBar: $selectAllOnBar, deleteOnBar: $deleteOnBar)';
}

/// Decides which parts of the multi-select bar fit whole into [available]
/// pixels. Widths are the full slot widths including their own gaps; a null
/// [selectAll] or [delete] means the page offers no such action.
///
/// Cancel and the count always stay on the bar. Delete is the bar's primary
/// action and keeps its place longest; Select All moves into the menu first.
/// Only when even the count phrase does not fit beside Cancel and the menu
/// button does the pill fall back to the bare number.
WpMultiSelectBarFit fitMultiSelectBar({
  required double available,
  required double count,
  required double countShort,
  required double? selectAll,
  required double? delete,
  required double cancel,
  required double more,
  required bool hasSecondary,
}) {
  final hasSelectAll = selectAll != null;
  final hasDelete = delete != null;
  bool fits(bool countFull, bool selectAllOnBar, bool deleteOnBar) {
    final needsMenu =
        hasSecondary ||
        (hasSelectAll && !selectAllOnBar) ||
        (hasDelete && !deleteOnBar);
    final total =
        (countFull ? count : countShort) +
        (selectAllOnBar ? selectAll ?? 0 : 0) +
        (deleteOnBar ? delete ?? 0 : 0) +
        (needsMenu ? more : 0) +
        cancel;
    return total <= available;
  }

  for (final countFull in const [true, false]) {
    for (final (selectAllOnBar, deleteOnBar) in [
      (hasSelectAll, hasDelete),
      (false, hasDelete),
      (false, false),
    ]) {
      if (fits(countFull, selectAllOnBar, deleteOnBar)) {
        return WpMultiSelectBarFit(
          countFull: countFull,
          selectAllOnBar: selectAllOnBar,
          deleteOnBar: deleteOnBar,
        );
      }
    }
  }
  return const WpMultiSelectBarFit(
    countFull: false,
    selectAllOnBar: false,
    deleteOnBar: false,
  );
}

/// One secondary action of [WpMultiSelectBar], shown in its overflow menu.
class _HistoryMultiSelectOverflowAction {
  const _HistoryMultiSelectOverflowAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcutHint,
    this.key,
    this.isDestructive = false,
  });

  /// Test key when the action keeps the ID it has on the bar (Delete,
  /// Select All moved into the menu); otherwise `<prefix>-more-<id>`.
  final Key? key;
  final bool isDestructive;

  /// Stable suffix for the menu item's test key (`history-multiselect-more-<id>`).
  final String id;
  final IconData icon;
  final String label;
  final String? shortcutHint;
  final VoidCallback onTap;
}

/// The overflow menu of [WpMultiSelectBar]: every secondary batch action,
/// each with its keyboard shortcut where one exists.
class _HistoryMultiSelectMoreButton extends StatelessWidget {
  const _HistoryMultiSelectMoreButton({
    required this.actions,
    required this.idPrefix,
  });

  final String idPrefix;
  final List<_HistoryMultiSelectOverflowAction> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final textSecondary = WpColors.textSecondary;

    return PopupMenuButton<VoidCallback>(
      key: ValueKey('$idPrefix-more'),
      icon: Icon(LucideIcons.ellipsis, size: WpIconSize.sm, color: textMuted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: l10n.historyMoreActions,
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
      onSelected: (onTap) => onTap(),
      itemBuilder: (_) => [
        for (final action in actions)
          PopupMenuItem<VoidCallback>(
            key: action.key ?? ValueKey('$idPrefix-more-${action.id}'),
            value: action.onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  action.icon,
                  size: WpIconSize.sm,
                  color: action.isDestructive ? WpColors.error : textSecondary,
                ),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    color: action.isDestructive ? WpColors.error : null,
                  ),
                ),
                if (action.shortcutHint != null) ...[
                  const SizedBox(width: WpSpacing.lg),
                  Text(
                    action.shortcutHint!,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-select action button
// ---------------------------------------------------------------------------

class WpMultiSelectAction extends StatefulWidget {
  const WpMultiSelectAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcutHint,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? shortcutHint;
  final bool isDestructive;

  /// Full slot width of the action for a label [labelWidth] wide, matching
  /// the paddings in [build] — what the bar reserves before it places it.
  static double widthFor(double labelWidth) =>
      _kRightGap + _kPadX * 2 + WpIconSize.sm + _kIconGap + labelWidth;

  static const double _kRightGap = WpSpacing.xs;
  static const double _kPadX = WpSpacing.sm;
  static const double _kIconGap = WpSpacing.xxs;

  @override
  State<WpMultiSelectAction> createState() => _WpMultiSelectActionState();
}

class _WpMultiSelectActionState extends State<WpMultiSelectAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textSecondary = WpColors.textSecondary;
    final hoverColor = widget.isDestructive
        ? (WpColors.error)
        : (WpColors.textPrimary);
    final color = _hovered ? hoverColor : textSecondary;

    // House idiom (`no_double_announcement_test.dart`, `wp_hero_button.dart`):
    // one tap target whose label is its own visible text → MergeSemantics plus
    // a *label-less* Semantics. An explicit `label: widget.label` here is not a
    // replacement for the subtree's text, it is prepended to it, so the
    // `Text(widget.label)` below made every batch action announce itself twice
    // ("Zusammenführen, Zusammenführen"). Merging folds the name in from the
    // rendered text while the button role and the tap action survive, and the
    // Tooltip's shortcut hint folds in with it — which is exactly what the
    // keyboard-first audience needs to hear.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            end: WpMultiSelectAction._kRightGap,
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Tooltip(
              message: widget.shortcutHint != null
                  ? '${widget.label} (${widget.shortcutHint})'
                  : widget.label,
              child: InkWell(
                borderRadius: WpRadius.borderSm,
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpMultiSelectAction._kPadX,
                    vertical: WpSpacing.xxs + 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // WpIconSize.sm (not .md): matches WpRowAction and
                      // WpMenuRow's fixed 16 for the same action set —
                      // .md would overwhelm this pill's 12px label.
                      Icon(widget.icon, size: WpIconSize.sm, color: color),
                      const SizedBox(width: WpMultiSelectAction._kIconGap),
                      // One line: the bar moves this action into its menu
                      // rather than let the label wrap mid-word (#1388).
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: WpTypography.small,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
