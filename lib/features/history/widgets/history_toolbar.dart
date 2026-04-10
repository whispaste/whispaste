import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../data/providers.dart';
import 'history_filter_chip.dart';
import 'history_helpers.dart';

// ---------------------------------------------------------------------------
// Search & filter toolbar
// ---------------------------------------------------------------------------

class HistorySearchToolbar extends StatelessWidget {
  const HistorySearchToolbar({
    super.key,
    required this.controller,
    required this.activeFilter,
    required this.isDark,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.resultCount,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.multiSelectMode,
    required this.onToggleMultiSelect,
    this.onEmptyTrash,
  });

  final TextEditingController controller;
  final HistoryFilter activeFilter;
  final bool isDark;
  final ValueChanged<HistoryFilter> onFilterChanged;
  final VoidCallback onSearchChanged;
  final int resultCount;
  final HistoryViewMode viewMode;
  final ValueChanged<HistoryViewMode> onViewModeChanged;
  final bool multiSelectMode;
  final VoidCallback onToggleMultiSelect;
  final VoidCallback? onEmptyTrash;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.sm,
        WpSpacing.xl,
        WpSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: l10n.historySearchTranscriptions,
              prefixIcon: Icon(
                LucideIcons.search,
                size: WpIconSize.sm,
                color: isDark
                    ? WpColorsDark.textMuted
                    : WpColorsLight.textMuted,
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        LucideIcons.x,
                        size: WpIconSize.sm,
                        color: isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted,
                      ),
                      onPressed: () {
                        controller.clear();
                        onSearchChanged();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.xs + 2,
              ),
            ),
            onChanged: (_) => onSearchChanged(),
          ),
          const SizedBox(height: WpSpacing.sm),
          // Filter chips + result count + view mode toggle
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      HistoryFilterChip(
                        label: l10n.historyAll,
                        isActive: activeFilter == HistoryFilter.all,
                        onTap: () => onFilterChanged(HistoryFilter.all),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyToday,
                        isActive: activeFilter == HistoryFilter.today,
                        onTap: () => onFilterChanged(HistoryFilter.today),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyThisWeek,
                        isActive: activeFilter == HistoryFilter.week,
                        onTap: () => onFilterChanged(HistoryFilter.week),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyPinned,
                        icon: LucideIcons.star,
                        isActive: activeFilter == HistoryFilter.pinned,
                        onTap: () => onFilterChanged(HistoryFilter.pinned),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyArchived,
                        icon: LucideIcons.archive,
                        isActive: activeFilter == HistoryFilter.archived,
                        onTap: () => onFilterChanged(HistoryFilter.archived),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyTrash,
                        icon: LucideIcons.trash2,
                        isActive: activeFilter == HistoryFilter.trash,
                        onTap: () => onFilterChanged(HistoryFilter.trash),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
              // Result count
              if (controller.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: WpSpacing.sm),
                  child: Text(
                    l10n.historyResultCount(resultCount),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? WpColorsDark.textMuted
                          : WpColorsLight.textMuted,
                    ),
                  ),
                ),
              const SizedBox(width: WpSpacing.xs),
              // Empty Trash button (only in trash view, when items exist)
              if (onEmptyTrash != null)
                Tooltip(
                  message: l10n.historyEmptyTrash,
                  child: InkWell(
                    borderRadius: WpRadius.borderSm,
                    onTap: onEmptyTrash,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WpSpacing.sm,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: WpIconSize.sm,
                            color: isDark
                                ? WpColorsDark.error
                                : WpColorsLight.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.historyEmptyTrash,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? WpColorsDark.error
                                  : WpColorsLight.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Multi-select toggle
              Tooltip(
                message: multiSelectMode
                    ? l10n.historyExitSelection
                    : l10n.historySelectMultiple,
                child: InkWell(
                  borderRadius: WpRadius.borderSm,
                  onTap: onToggleMultiSelect,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      multiSelectMode
                          ? LucideIcons.checkCheck
                          : LucideIcons.listChecks,
                      size: WpIconSize.sm,
                      color: multiSelectMode
                          ? (isDark
                                ? WpColorsDark.accent
                                : WpColorsLight.accent)
                          : (isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xxs),
              // View mode toggle
              HistoryViewModeToggle(
                viewMode: viewMode,
                isDark: isDark,
                onChanged: onViewModeChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-select action bar
// ---------------------------------------------------------------------------

class HistoryMultiSelectBar extends StatelessWidget {
  const HistoryMultiSelectBar({
    super.key,
    required this.selectedCount,
    required this.isDark,
    required this.isTrashView,
    required this.isArchiveView,
    required this.onCancelSelection,
    this.onSelectAll,
    this.totalCount,
    this.onMerge,
    this.onBatchCopy,
    this.onArchive,
    this.onDelete,
    this.onRestore,
  });

  final int selectedCount;
  final bool isDark;
  final bool isTrashView;
  final bool isArchiveView;
  final VoidCallback onCancelSelection;
  final VoidCallback? onSelectAll;
  final int? totalCount;
  final VoidCallback? onMerge;
  final VoidCallback? onBatchCopy;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final bg = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xl,
        vertical: WpSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.2), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Selection count
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: WpRadius.borderFull,
              ),
              child: Text(
                l10n.historyItemsSelected(selectedCount),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          // Select All / Deselect All toggle
          if (onSelectAll != null)
            InkWell(
              borderRadius: WpRadius.borderSm,
              onTap: onSelectAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.xs,
                  vertical: 4,
                ),
                child: Text(
                  totalCount != null && selectedCount >= totalCount!
                      ? l10n.historyDeselectAll
                      : l10n.historySelectAll,
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          const SizedBox(width: WpSpacing.sm),
          // Action buttons — wrap in Flexible to prevent overflow
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onMerge != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.merge,
                      label: l10n.historyMerge,
                      shortcutHint: formatHotkeyShortcut(
                        'ctrl',
                        'm',
                        l10n: l10n,
                      ),
                      isDark: isDark,
                      onTap: onMerge!,
                    ),
                  if (onBatchCopy != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.copy,
                      label: l10n.historyCopyText,
                      shortcutHint: formatHotkeyShortcut(
                        'ctrl',
                        'c',
                        l10n: l10n,
                      ),
                      isDark: isDark,
                      onTap: onBatchCopy!,
                    ),
                  if (onRestore != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.undo2,
                      label: l10n.historyRestore,
                      isDark: isDark,
                      onTap: onRestore!,
                    ),
                  if (onArchive != null)
                    HistoryMultiSelectAction(
                      icon: isArchiveView
                          ? LucideIcons.archiveRestore
                          : LucideIcons.archive,
                      label: isArchiveView
                          ? l10n.historyUnarchive
                          : l10n.historyArchive,
                      isDark: isDark,
                      onTap: onArchive!,
                    ),
                  if (onDelete != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.trash2,
                      label: isTrashView
                          ? l10n.historyDeleteForever
                          : l10n.actionDelete,
                      shortcutHint: hotkeyKeyLabel('delete', l10n: l10n),
                      isDark: isDark,
                      onTap: onDelete!,
                      isDestructive: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          // Cancel
          TextButton.icon(
            onPressed: onCancelSelection,
            icon: Icon(LucideIcons.x, size: 14, color: textPrimary),
            label: Text(
              l10n.actionCancel,
              style: TextStyle(fontSize: 13, color: textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-select action button
// ---------------------------------------------------------------------------

class HistoryMultiSelectAction extends StatefulWidget {
  const HistoryMultiSelectAction({
    super.key,
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.shortcutHint,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final String? shortcutHint;
  final bool isDestructive;

  @override
  State<HistoryMultiSelectAction> createState() =>
      _HistoryMultiSelectActionState();
}

class _HistoryMultiSelectActionState extends State<HistoryMultiSelectAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final hoverColor = widget.isDestructive
        ? (widget.isDark ? WpColorsDark.error : WpColorsLight.error)
        : (widget.isDark
              ? WpColorsDark.textPrimary
              : WpColorsLight.textPrimary);
    final color = _hovered ? hoverColor : textSecondary;

    return Padding(
      padding: const EdgeInsets.only(right: WpSpacing.xs),
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
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xxs + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Text(
                    widget.label,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// View mode toggle — segmented icon button group
// ---------------------------------------------------------------------------

class HistoryViewModeToggle extends StatelessWidget {
  const HistoryViewModeToggle({
    super.key,
    required this.viewMode,
    required this.isDark,
    required this.onChanged,
  });

  final HistoryViewMode viewMode;
  final bool isDark;
  final ValueChanged<HistoryViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: WpRadius.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HistoryViewModeButton(
            icon: LucideIcons.list,
            isActive: viewMode == HistoryViewMode.list,
            isDark: isDark,
            onTap: () => onChanged(HistoryViewMode.list),
          ),
          _HistoryViewModeButton(
            icon: LucideIcons.layoutGrid,
            isActive: viewMode == HistoryViewMode.cards,
            isDark: isDark,
            onTap: () => onChanged(HistoryViewMode.cards),
          ),
          _HistoryViewModeButton(
            icon: LucideIcons.rows3,
            isActive: viewMode == HistoryViewMode.compact,
            isDark: isDark,
            onTap: () => onChanged(HistoryViewMode.compact),
          ),
        ],
      ),
    );
  }
}

class _HistoryViewModeButton extends StatelessWidget {
  const _HistoryViewModeButton({
    required this.icon,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
        : (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted);
    final bg = isActive
        ? (isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle)
        : Colors.transparent;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(WpSpacing.xxs),
          decoration: BoxDecoration(color: bg, borderRadius: WpRadius.borderSm),
          child: Icon(icon, size: WpIconSize.sm, color: color),
        ),
      ),
    );
  }
}
