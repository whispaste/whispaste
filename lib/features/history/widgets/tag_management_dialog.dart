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
import '../../../widgets/wp_button.dart';

/// Shows the tag management dialog.
///
/// Returns `true` if any tags were modified (so callers can refresh). Esc and
/// Close both leave; the modification flag is kept by the content, not by the
/// footer, so both return the same answer.
Future<bool> showTagManagementDialog({
  required BuildContext context,
  required HistoryDatabase db,
}) async {
  final l10n = L10n.of(context);
  var modified = false;
  await showWpDialog<void>(
    context: context,
    title: l10n.tagManageTitle,
    content: _TagManagementContent(
      db: db,
      onModified: () {
        modified = true;
      },
    ),
    actions: [
      WpDialogAction(
        label: l10n.actionClose,
        testId: 'tag-management-close',
        role: WpDialogActionRole.primary,
      ),
    ],
  );
  return modified;
}

// ---------------------------------------------------------------------------
// Dialog content
// ---------------------------------------------------------------------------

class _TagManagementContent extends StatefulWidget {
  const _TagManagementContent({required this.db, required this.onModified});

  final HistoryDatabase db;

  /// Called after every delete, so the caller knows to refresh.
  final VoidCallback onModified;

  @override
  State<_TagManagementContent> createState() => _TagManagementContentState();
}

class _TagManagementContentState extends State<_TagManagementContent> {
  List<(Tag, int)> _tags = [];
  bool _loading = true;

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
        confirmLabel: L10n.of(context).actionDelete,
        cancelLabel: L10n.of(context).actionCancel,
        destructive: true,
      );
      if (!confirmed) return;
    }

    await widget.db.deleteTag(tag.id);
    widget.onModified();
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
      confirmLabel: L10n.of(context).actionDelete,
      cancelLabel: L10n.of(context).actionCancel,
      destructive: true,
    );
    if (!confirmed) return;

    final deleted = await widget.db.deleteUnusedTags();
    widget.onModified();
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
    final textMuted = WpColors.textMuted;
    final unusedCount = _tags.where((t) => t.$2 == 0).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textMuted,
                  fontSize: WpTypography.subheading,
                ),
              ),
            ),
          ),
        for (final (tag, count) in _tags)
          _TagRow(
            tag: tag,
            count: count,
            onDelete: () => _deleteTag(tag, count),
          ),

        // Bulk action at the foot of the list. It is list content, not a
        // dialog answer, so it stays out of the footer.
        if (!_loading && unusedCount > 0) ...[
          const SizedBox(height: WpSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: WpButton(
              label: l10n.tagDeleteUnusedAction(unusedCount),
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.danger,
              icon: LucideIcons.trash2,
              onPressed: _deleteUnused,
            ),
          ),
        ],
      ],
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
    required this.onDelete,
  });

  final Tag tag;
  final int count;
  final VoidCallback onDelete;

  @override
  State<_TagRow> createState() => _TagRowState();
}

class _TagRowState extends State<_TagRow> {
  bool _hovered = false;

  /// The delete button stays focusable while it is invisible, so keyboard focus
  /// used to land on an `opacity: 0` control: Tab through the tag list and the
  /// caret vanished for one stop per row, on a button that deletes. Revealing
  /// on focus as well as hover keeps the row quiet for the mouse and honest for
  /// the keyboard, instead of buying quiet by dropping the button out of the
  /// Tab order.
  final FocusNode _deleteFocus = FocusNode(debugLabel: 'TagRowDelete');

  @override
  void initState() {
    super.initState();
    _deleteFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _deleteFocus.removeListener(_onFocusChange);
    _deleteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent = WpColors.accent;
    final textPrimary = WpColors.textPrimary;
    final textMuted = WpColors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: WpMotion.durationFor(context, WpMotion.hoverOut),
        color: _hovered ? (WpColors.accentRowHover) : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.lg,
          vertical: WpSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(LucideIcons.hash, size: WpIconSize.xs, color: accent),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                widget.tag.name,
                style: TextStyle(
                  fontSize: WpTypography.subheading,
                  color: textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Text(
              l10n.tagUsageCount(widget.count),
              style: TextStyle(fontSize: WpTypography.small, color: textMuted),
            ),
            const SizedBox(width: WpSpacing.xs),
            AnimatedOpacity(
              opacity: (_hovered || _deleteFocus.hasFocus) ? 1.0 : 0.0,
              duration: WpMotion.durationFor(context, WpMotion.hoverOut),
              child: IconButton(
                focusNode: _deleteFocus,
                icon: Icon(
                  LucideIcons.trash2,
                  size: WpIconSize.xs,
                  color: WpColors.error,
                ),
                onPressed: widget.onDelete,
                tooltip: l10n.actionDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: WpLayout.minTouchTarget,
                  minHeight: WpLayout.minTouchTarget,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
