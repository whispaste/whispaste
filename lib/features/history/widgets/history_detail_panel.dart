import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/history_detail_provider.dart';
import 'history_helpers.dart';
import 'history_notes_section.dart';
import '../../../widgets/tag_input.dart';

// ---------------------------------------------------------------------------
// Detail panel — opens on entry selection (ChatGPT/Notion detail view)
// ---------------------------------------------------------------------------

class HistoryDetailPanel extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<HistoryDetailPanel> createState() =>
      _HistoryDetailPanelState();
}

class _HistoryDetailPanelState extends ConsumerState<HistoryDetailPanel> {
  String _tagSearchQuery = '';
  bool _isEditingTranscript = false;
  late TextEditingController _transcriptController;
  final FocusNode _panelFocusNode = FocusNode();
  final GlobalKey<_TagSectionState> _tagSectionKey = GlobalKey<_TagSectionState>();
  final GlobalKey<HistoryNotesSectionState> _notesSectionKey =
      GlobalKey<HistoryNotesSectionState>();

  @override
  void initState() {
    super.initState();
    _transcriptController = TextEditingController(text: widget.entry.content);
  }

  @override
  void didUpdateWidget(covariant HistoryDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id) {
      _transcriptController.text = widget.entry.content;
      _isEditingTranscript = false;
    }
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    _panelFocusNode.dispose();
    super.dispose();
  }

  HistoryEntry get entry => widget.entry;
  bool get isDark => widget.isDark;
  VoidCallback get onClose => widget.onClose;
  VoidCallback get onCopy => widget.onCopy;
  VoidCallback get onPin => widget.onPin;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback get onArchive => widget.onArchive;
  VoidCallback get onRestore => widget.onRestore;
  VoidCallback? get onDuplicate => widget.onDuplicate;
  VoidCallback? get onCopyMarkdown => widget.onCopyMarkdown;
  bool get isTrashView => widget.isTrashView;
  bool get isArchiveView => widget.isArchiveView;

  void _saveTranscript() {
    final newContent = _transcriptController.text.trim();
    if (newContent != entry.content) {
      ref.read(historyDetailProvider(entry.id).notifier).updateContent(newContent);
    }
    setState(() => _isEditingTranscript = false);
  }

  void _toggleEdit() {
    if (_isEditingTranscript) {
      _saveTranscript();
    } else {
      _transcriptController.text = entry.content;
      setState(() => _isEditingTranscript = true);
    }
  }

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

  String _wordCountLabel(L10n l10n) {
    final words = entry.content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final readMinutes = (words / 200).ceil(); // ~200 wpm average
    final wordStr = l10n.historyWordCount(words);
    final timeStr = readMinutes < 1
        ? l10n.historyReadingTimeUnder1
        : l10n.historyReadingTime(readMinutes);
    return '$wordStr · $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final detailAsync = ref.watch(historyDetailProvider(entry.id));
    final tags = detailAsync.asData?.value.tags ?? [];

    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final avatarCol = historyAvatarColor(entry, isDark);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onClose,
        const SingleActivator(LogicalKeyboardKey.keyT): () {
          _tagSectionKey.currentState?.focusTagInput();
        },
        const SingleActivator(LogicalKeyboardKey.keyN): () {
          _notesSectionKey.currentState?.startAddingNote();
        },
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): _toggleEdit,
        const SingleActivator(LogicalKeyboardKey.keyP): onPin,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): onCopy,
      },
      child: Focus(
        focusNode: _panelFocusNode,
        child: Container(
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
                  // Transcript — view or edit mode
                  Row(
                    children: [
                      Expanded(
                        child: _isEditingTranscript
                            ? TextField(
                                controller: _transcriptController,
                                maxLines: null,
                                autofocus: true,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  color: textPrimary,
                                  height: 1.65,
                                ),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: WpRadius.borderSm,
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? WpColorsDark.borderSubtle
                                          : WpColorsLight.borderSubtle,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: WpRadius.borderSm,
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? WpColorsDark.accent
                                          : WpColorsLight.accent,
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(WpSpacing.sm),
                                ),
                                onSubmitted: (_) => _saveTranscript(),
                              )
                            : SelectableText(
                                entry.content,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  color: textPrimary,
                                  height: 1.65,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (!isTrashView) ...[
                    const SizedBox(height: WpSpacing.xs),
                    Row(
                      children: [
                        if (entry.titleEdited || _isEditingTranscript)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _isEditingTranscript
                                  ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                                      .withValues(alpha: 0.15)
                                  : textMuted.withValues(alpha: 0.1),
                              borderRadius: WpRadius.borderFull,
                            ),
                            child: Text(
                              _isEditingTranscript
                                  ? l10n.historyEditing
                                  : l10n.historyEditTranscript,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: _isEditingTranscript
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: _isEditingTranscript
                                    ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                                    : textMuted,
                              ),
                            ),
                          ),
                        const Spacer(),
                        // Word count + reading time
                        if (!_isEditingTranscript && entry.content.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: WpSpacing.sm),
                            child: Text(
                              _wordCountLabel(l10n),
                              style: TextStyle(
                                fontSize: 11,
                                color: textMuted.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        Material(
                          color: Colors.transparent,
                          borderRadius: WpRadius.borderFull,
                          child: InkWell(
                            borderRadius: const BorderRadius.all(Radius.circular(999)),
                            onTap: _toggleEdit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: WpSpacing.xs,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isEditingTranscript
                                        ? LucideIcons.check
                                        : LucideIcons.pencil,
                                    size: 14,
                                    color: textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isEditingTranscript
                                        ? l10n.historyTranscriptSaved
                                        : l10n.historyEditTranscript,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: WpSpacing.md),
                  // Tags — interactive editor
                  Row(
                    children: [
                      Icon(LucideIcons.tags, size: 14, color: textMuted),
                      const SizedBox(width: WpSpacing.xs),
                      Text(
                        l10n.historyTags,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  _TagSection(
                    key: _tagSectionKey,
                    entryId: entry.id,
                    tags: tags,
                    isDark: isDark,
                    searchQuery: _tagSearchQuery,
                    onSearchChanged: (q) =>
                        setState(() => _tagSearchQuery = q),
                  ),
                  const SizedBox(height: WpSpacing.md),
                  // Metadata — compact inline chips
                  Wrap(
                    spacing: WpSpacing.xs,
                    runSpacing: WpSpacing.xs,
                    children: [
                      _MetaChip(
                        icon: LucideIcons.clock,
                        label: _durationLabel,
                        isDark: isDark,
                      ),
                      if (entry.language.isNotEmpty)
                        _MetaChip(
                          icon: LucideIcons.globe,
                          label: entry.language.toUpperCase(),
                          isDark: isDark,
                        ),
                      _MetaChip(
                        icon: entry.isLocal
                            ? LucideIcons.hardDrive
                            : LucideIcons.cloud,
                        label: entry.isLocal
                            ? l10n.historyOnDevice
                            : l10n.statusCloud,
                        isDark: isDark,
                      ),
                      if (entry.model.isNotEmpty)
                        Tooltip(
                          message: '${l10n.historyModel}: ${entry.model}',
                          child: _MetaChip(
                            icon: LucideIcons.cpu,
                            label: entry.model.length > 20
                                ? '${entry.model.substring(0, 20)}…'
                                : entry.model,
                            isDark: isDark,
                          ),
                        ),
                    ],
                  ),
                  // Notes section
                  const SizedBox(height: WpSpacing.lg),
                  HistoryNotesSection(key: _notesSectionKey, entryId: entry.id, isDark: isDark),
                  // FAB clearance so content isn't hidden behind the floating button
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
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

/// Compact inline metadata chip for the detail panel.
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final fg = isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: WpRadius.borderFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tag section — connects WpTagInput to HistoryDetailNotifier
// ---------------------------------------------------------------------------

class _TagSection extends ConsumerStatefulWidget {
  const _TagSection({
    super.key,
    required this.entryId,
    required this.tags,
    required this.isDark,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  final String entryId;
  final List<Tag> tags;
  final bool isDark;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  @override
  ConsumerState<_TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends ConsumerState<_TagSection> {
  List<Tag> _suggestions = [];
  final FocusNode _tagFocusNode = FocusNode();

  /// Called by keyboard shortcut (T) to focus the tag input field.
  void focusTagInput() {
    _tagFocusNode.requestFocus();
  }

  @override
  void didUpdateWidget(covariant _TagSection old) {
    super.didUpdateWidget(old);
    if (old.searchQuery != widget.searchQuery) {
      _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    final db = ref.read(historyDatabaseProvider);
    final results = widget.searchQuery.isEmpty
        ? await db.frequentTags(limit: 8)
        : await db.searchTags(widget.searchQuery);
    if (mounted) setState(() => _suggestions = results);
  }

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _tagFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(historyDetailProvider(widget.entryId).notifier);
    final l10n = L10n.of(context);

    return WpTagInput(
      tags: widget.tags,
      isDark: widget.isDark,
      hintText: l10n.historyAddTag,
      suggestions: _suggestions,
      focusNode: _tagFocusNode,
      onSearchChanged: (q) {
        widget.onSearchChanged(q);
        _loadSuggestions();
      },
      onAdd: (name) => notifier.addTag(name),
      onRemove: (tagId) => notifier.removeTag(tagId),
    );
  }
}
