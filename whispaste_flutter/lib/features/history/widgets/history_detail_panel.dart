import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../data/database.dart';
import 'history_helpers.dart';
import 'history_notes_section.dart';

// ---------------------------------------------------------------------------
// Detail panel — opens on entry selection (ChatGPT/Notion detail view)
// ---------------------------------------------------------------------------

class HistoryDetailPanel extends StatelessWidget {
  const HistoryDetailPanel({
    super.key,
    required this.entry,
    required this.isDark,
    required this.onClose,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    this.onDuplicate,
    this.onCopyMarkdown,
    this.isTrashView = false,
    this.isArchiveView = false,
  });

  final HistoryEntry entry;
  final bool isDark;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDuplicate;
  final VoidCallback? onCopyMarkdown;
  final bool isTrashView;
  final bool isArchiveView;

  String _fullTimestamp(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final fmt = DateFormat.yMMMd(locale).add_Hm();
    return fmt.format(entry.timestamp);
  }

  String get _durationLabel {
    final secs = entry.durationSec.round();
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
  }

  List<String> get _tags {
    try {
      final decoded = jsonDecode(entry.tags);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final avatarCol = historyAvatarColor(entry, isDark);

    return Container(
      color: isDark
          ? WpColorsDark.surface
          : WpColorsLight.surface,
      child: Column(
        children: [
          // Header bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl, WpSpacing.md, WpSpacing.md, WpSpacing.sm,
            ),
            child: Row(
              children: [
                HistoryEntryAvatar(
                  color: avatarCol,
                  icon: historyAvatarIcon(entry),
                  isPinned: entry.pinned,
                  isDark: isDark,
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title.isNotEmpty ? entry.title : l10n.historyUntitled,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fullTimestamp(context),
                        style: TextStyle(fontSize: 12, color: textMuted),
                      ),
                    ],
                  ),
                ),
                // Action buttons
                if (isTrashView) ...[
                  HistoryDetailAction(
                    icon: LucideIcons.undo2,
                    tooltip: l10n.historyRestore,
                    isDark: isDark,
                    onTap: onRestore,
                  ),
                  HistoryDetailAction(
                    icon: LucideIcons.trash2,
                    tooltip: l10n.historyDeleteForever,
                    isDark: isDark,
                    onTap: onDelete,
                    isDestructive: true,
                  ),
                ] else ...[
                  HistoryDetailAction(
                    icon: LucideIcons.copy,
                    tooltip: l10n.historyCopyText,
                    isDark: isDark,
                    onTap: onCopy,
                  ),
                  HistoryDetailAction(
                    icon: entry.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                    tooltip: entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop,
                    isDark: isDark,
                    onTap: onPin,
                  ),
                  // Overflow menu for secondary actions
                  PopupMenuButton<String>(
                    icon: Icon(
                      LucideIcons.ellipsisVertical,
                      size: 18,
                      color: isDark
                          ? WpColorsDark.textSecondary
                          : WpColorsLight.textSecondary,
                    ),
                    tooltip: '',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    color: isDark
                        ? WpColorsDark.surfaceElevated
                        : WpColorsLight.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(WpRadius.md),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'markdown':
                          onCopyMarkdown?.call();
                        case 'duplicate':
                          onDuplicate?.call();
                        case 'archive':
                          onArchive();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      if (onCopyMarkdown != null)
                        PopupMenuItem(
                          value: 'markdown',
                          child: HistoryPopupMenuRow(
                            icon: LucideIcons.fileText,
                            label: l10n.historyCopyAsMarkdown,
                            isDark: isDark,
                          ),
                        ),
                      if (onDuplicate != null)
                        PopupMenuItem(
                          value: 'duplicate',
                          child: HistoryPopupMenuRow(
                            icon: LucideIcons.files,
                            label: l10n.historyDuplicate,
                            isDark: isDark,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'archive',
                        child: HistoryPopupMenuRow(
                          icon: entry.archived
                              ? LucideIcons.archiveRestore
                              : LucideIcons.archive,
                          label: entry.archived
                              ? l10n.historyUnarchive
                              : l10n.historyArchive,
                          isDark: isDark,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: HistoryPopupMenuRow(
                          icon: LucideIcons.trash2,
                          label: l10n.actionDelete,
                          isDark: isDark,
                          isDestructive: true,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(width: WpSpacing.xxs),
                HistoryDetailAction(
                  icon: LucideIcons.x,
                  tooltip: l10n.historyClose,
                  isDark: isDark,
                  onTap: onClose,
                ),
              ],
            ),
          ),
          // Divider
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
            color: isDark
                ? WpColorsDark.borderSubtle
                : WpColorsLight.borderSubtle,
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WpSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Full text
                  SelectableText(
                    entry.content,
                    style: TextStyle(
                      fontSize: 15.5,
                      color: textPrimary,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xxl),
                  // Metadata section
                  Container(
                    padding: const EdgeInsets.all(WpSpacing.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? WpColorsDark.surfaceElevated
                          : WpColorsLight.surfaceElevated,
                      borderRadius: WpRadius.borderMd,
                      border: Border.all(
                        color: isDark
                            ? WpColorsDark.borderSubtle
                            : WpColorsLight.borderSubtle,
                      ),
                    ),
                    child: Column(
                      children: [
                        HistoryDetailMetaRow(
                          icon: LucideIcons.clock,
                          label: l10n.historyDuration,
                          value: _durationLabel,
                          isDark: isDark,
                        ),
                        if (entry.language.isNotEmpty)
                          HistoryDetailMetaRow(
                            icon: LucideIcons.globe,
                            label: l10n.historyLanguageLabel,
                            value: entry.language.toUpperCase(),
                            isDark: isDark,
                          ),
                        HistoryDetailMetaRow(
                          icon: entry.isLocal
                              ? LucideIcons.hardDrive
                              : LucideIcons.cloud,
                          label: l10n.historyProcessed,
                          value: entry.isLocal ? l10n.historyOnDevice : l10n.statusCloud,
                          isDark: isDark,
                        ),
                        if (entry.model.isNotEmpty)
                          HistoryDetailMetaRow(
                            icon: LucideIcons.cpu,
                            label: l10n.historyModel,
                            value: entry.model,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
                  // Tags
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: WpSpacing.md),
                    Wrap(
                      spacing: WpSpacing.xs,
                      runSpacing: WpSpacing.xs,
                      children: [
                        for (final tag in _tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.sm,
                              vertical: WpSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: WpRadius.borderFull,
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                fontSize: 12,
                                color: accent.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  // Notes section
                  const SizedBox(height: WpSpacing.lg),
                  HistoryNotesSection(entryId: entry.id, isDark: isDark),
                  // FAB clearance so content isn't hidden behind the floating button
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Popup menu row (icon + label)
// ---------------------------------------------------------------------------

class HistoryPopupMenuRow extends StatelessWidget {
  const HistoryPopupMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.isDark,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? (isDark ? WpColorsDark.error : WpColorsLight.error)
        : (isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: WpSpacing.sm),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel action button
// ---------------------------------------------------------------------------

class HistoryDetailAction extends StatefulWidget {
  const HistoryDetailAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  State<HistoryDetailAction> createState() => _HistoryDetailActionState();
}

class _HistoryDetailActionState extends State<HistoryDetailAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    if (widget.isDestructive && _isHovered) {
      iconColor = widget.isDark ? WpColorsDark.error : WpColorsLight.error;
    } else if (_isHovered) {
      iconColor = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      iconColor = widget.isDark
          ? WpColorsDark.textMuted
          : WpColorsLight.textMuted;
    }

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: WpMotion.fast,
            padding: const EdgeInsets.all(WpSpacing.xs),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isDark
                      ? WpColorsDark.hover
                      : WpColorsLight.hover)
                  : (widget.isDark
                      ? WpColorsDark.hoverTransparent
                      : WpColorsLight.hoverTransparent),
              borderRadius: WpRadius.borderSm,
            ),
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail metadata row
// ---------------------------------------------------------------------------

class HistoryDetailMetaRow extends StatelessWidget {
  const HistoryDetailMetaRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: textSecondary),
          const SizedBox(width: WpSpacing.sm),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
