/// Dialog for managing all tags — view, delete individual tags, and
/// batch-remove unused tags.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/toast.dart';

/// Shows the tag management dialog.
///
/// Returns `true` if any tags were modified (so callers can refresh).
Future<bool> showTagManagementDialog({
  required BuildContext context,
  required HistoryDatabase db,
  required bool isDark,
}) async {
  final result = await showWpFormDialog<bool>(
    context: context,
    builder: (ctx, animation) => _TagManagementContent(
      animation: animation,
      db: db,
      isDark: isDark,
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Dialog content
// ---------------------------------------------------------------------------

class _TagManagementContent extends StatefulWidget {
  const _TagManagementContent({
    required this.animation,
    required this.db,
    required this.isDark,
  });

  final Animation<double> animation;
  final HistoryDatabase db;
  final bool isDark;

  @override
  State<_TagManagementContent> createState() => _TagManagementContentState();
}

class _TagManagementContentState extends State<_TagManagementContent> {
  List<(Tag, int)> _tags = [];
  bool _loading = true;
  bool _didModify = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tags = await widget.db.allTagsWithCount();
    if (mounted) {
      setState(() {
        _tags = tags;
        _loading = false;
      });
    }
  }

  Future<void> _deleteTag(Tag tag, int count) async {
    if (count > 0) {
      final confirmed = await showWpConfirmDialog(
        context: context,
        title: L10n.of(context).tagDeleteConfirmTitle,
        message: L10n.of(context).tagDeleteConfirmMessage(tag.name, count),
        destructive: true,
      );
      if (!confirmed) return;
    }

    await widget.db.deleteTag(tag.id);
    _didModify = true;
    await _load();

    if (mounted) {
      WpToast.show(
        context,
        message: L10n.of(context).tagDeleted(tag.name),
        type: WpToastType.info,
      );
    }
  }

  Future<void> _deleteUnused() async {
    final unusedCount = _tags.where((t) => t.$2 == 0).length;
    if (unusedCount == 0) return;

    final confirmed = await showWpConfirmDialog(
      context: context,
      title: L10n.of(context).tagDeleteUnusedTitle,
      message: L10n.of(context).tagDeleteUnusedMessage(unusedCount),
      destructive: true,
    );
    if (!confirmed) return;

    final deleted = await widget.db.deleteUnusedTags();
    _didModify = true;
    await _load();

    if (mounted) {
      WpToast.show(
        context,
        message: L10n.of(context).tagDeletedUnused(deleted),
        type: WpToastType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final borderColor = widget.isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    final unusedCount = _tags.where((t) => t.$2 == 0).length;

    return ScaleTransition(
      scale: CurvedAnimation(
        parent: widget.animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: widget.animation,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
            child: Material(
              color: widget.isDark
                  ? WpColorsDark.surfaceElevated
                  : WpColorsLight.surfaceElevated,
              borderRadius: BorderRadius.circular(WpRadius.lg),
              elevation: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WpSpacing.lg, WpSpacing.lg, WpSpacing.sm, WpSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.tags, size: WpIconSize.md,
                            color: accent),
                        const SizedBox(width: WpSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.tagManageTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(LucideIcons.x, size: WpIconSize.sm,
                              color: textMuted),
                          onPressed: () =>
                              Navigator.of(context).pop(_didModify),
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                        ),
                      ],
                    ),
                  ),

                  // Divider
                  Divider(height: 1, color: borderColor),

                  // Content
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(WpSpacing.xl),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(WpSpacing.xl),
                      child: Center(
                        child: Text(
                          l10n.tagManageEmpty,
                          style: TextStyle(color: textMuted, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: WpSpacing.xs,
                        ),
                        itemCount: _tags.length,
                        itemBuilder: (context, index) {
                          final (tag, count) = _tags[index];
                          return _TagRow(
                            tag: tag,
                            count: count,
                            isDark: widget.isDark,
                            onDelete: () => _deleteTag(tag, count),
                          );
                        },
                      ),
                    ),

                  // Footer with "Delete unused" action
                  if (!_loading && unusedCount > 0) ...[
                    Divider(height: 1, color: borderColor),
                    Padding(
                      padding: const EdgeInsets.all(WpSpacing.sm),
                      child: TextButton.icon(
                        onPressed: _deleteUnused,
                        icon: Icon(LucideIcons.trash2, size: WpIconSize.sm,
                            color: widget.isDark
                                ? WpColorsDark.error
                                : WpColorsLight.error),
                        label: Text(
                          l10n.tagDeleteUnusedAction(unusedCount),
                          style: TextStyle(
                            color: widget.isDark
                                ? WpColorsDark.error
                                : WpColorsLight.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
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
// Individual tag row
// ---------------------------------------------------------------------------

class _TagRow extends StatefulWidget {
  const _TagRow({
    required this.tag,
    required this.count,
    required this.isDark,
    required this.onDelete,
  });

  final Tag tag;
  final int count;
  final bool isDark;
  final VoidCallback onDelete;

  @override
  State<_TagRow> createState() => _TagRowState();
}

class _TagRowState extends State<_TagRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = widget.isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: WpMotion.hoverOut,
        color: _hovered
            ? accent.withValues(alpha: 0.06)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.lg,
          vertical: WpSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(LucideIcons.hash, size: 14, color: accent),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                widget.tag.name,
                style: TextStyle(
                  fontSize: 14,
                  color: textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Text(
              l10n.tagUsageCount(widget.count),
              style: TextStyle(fontSize: 12, color: textMuted),
            ),
            const SizedBox(width: WpSpacing.xs),
            AnimatedOpacity(
              opacity: _hovered ? 1.0 : 0.0,
              duration: WpMotion.hoverOut,
              child: IconButton(
                icon: Icon(LucideIcons.trash2, size: 14,
                    color: widget.isDark
                        ? WpColorsDark.error
                        : WpColorsLight.error),
                onPressed: widget.onDelete,
                tooltip: l10n.actionDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
