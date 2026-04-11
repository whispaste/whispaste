import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/recording/recording_helpers.dart' show displayNameForModel;
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../../../services/post_processing_service.dart';
import '../data/history_detail_provider.dart';
import 'highlighted_text.dart';
import 'history_helpers.dart';
import 'history_notes_section.dart';
import '../../../widgets/tag_input.dart';
import '../../../widgets/markdown_toolbar.dart';
import '../../../widgets/toast.dart';
import 'tag_management_dialog.dart';

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
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  bool _isSuggestingTitle = false;
  final FocusNode _panelFocusNode = FocusNode();
  final FocusNode _editorFocusNode = FocusNode();
  final FocusNode _titleFocusNode = FocusNode();
  final GlobalKey<_TagSectionState> _tagSectionKey = GlobalKey<_TagSectionState>();
  final GlobalKey<HistoryNotesSectionState> _notesSectionKey =
      GlobalKey<HistoryNotesSectionState>();

  @override
  void initState() {
    super.initState();
    _transcriptController = TextEditingController(text: widget.entry.content);
    _titleController = TextEditingController(text: widget.entry.title);
    // Auto-focus panel so its shortcuts AND ancestor list shortcuts both work.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panelFocusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant HistoryDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id) {
      _transcriptController.text = widget.entry.content;
      _isEditingTranscript = false;
      _titleController.text = widget.entry.title;
      _isEditingTitle = false;
    } else {
      // Sync fields that changed externally (Finding #3 — dual mutation path)
      if (!_isEditingTitle) {
        _titleController.text = widget.entry.title;
      }
      if (!_isEditingTranscript) {
        _transcriptController.text = widget.entry.content;
      }
    }
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    _titleController.dispose();
    _panelFocusNode.dispose();
    _editorFocusNode.dispose();
    _titleFocusNode.dispose();
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

  /// Returns true if any text input field currently has focus.
  /// Used to prevent single-key shortcuts from intercepting typed characters.
  bool _isTextFieldFocused() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    return primary.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
  }

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

  void _startTitleEdit() {
    if (isTrashView) return;
    _titleController.text = entry.title;
    setState(() => _isEditingTitle = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _titleFocusNode.requestFocus());
  }

  void _saveTitle() {
    final newTitle = _titleController.text.trim();
    if (newTitle != entry.title) {
      ref.read(historyDetailProvider(entry.id).notifier).updateTitle(newTitle);
      final l10n = L10n.of(context);
      WpToast.show(context, message: l10n.historyTitleSaved);
    }
    setState(() => _isEditingTitle = false);
    _panelFocusNode.requestFocus();
  }

  Future<void> _suggestTitle(HistoryEntry entry) async {
    if (_isSuggestingTitle) return;
    final pp = ref.read(postProcessingProvider.notifier);
    if (ref.read(postProcessingProvider).isBusy) {
      WpToast.show(context, message: L10n.of(context).historyAiBusy);
      return;
    }
    setState(() => _isSuggestingTitle = true);
    try {
      final title = await pp.suggestTitle(entry.content);
      if (!mounted) return;
      _titleController.text = title;
      setState(() => _isEditingTitle = true);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _titleFocusNode.requestFocus());
      WpToast.show(context, message: L10n.of(context).historyAiTitleSuggested);
    } on Exception catch (e) {
      if (!mounted) return;
      WpToast.show(
        context,
        message: '${L10n.of(context).historyAiError}: $e',
        type: WpToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isSuggestingTitle = false);
    }
  }

  void _wrapBold() => _wrapEditorSelection('**');
  void _wrapItalic() => _wrapEditorSelection('_');
  void _toggleBullet() => _toggleEditorLinePrefix('- ');

  void _wrapEditorSelection(String marker) {
    final sel = _transcriptController.selection;
    if (!sel.isValid) return;
    final text = _transcriptController.text;
    final selected = text.substring(sel.start, sel.end);
    final wrapped = '$marker$selected$marker';
    _transcriptController.value = TextEditingValue(
      text: '${text.substring(0, sel.start)}$wrapped${text.substring(sel.end)}',
      selection: TextSelection(
        baseOffset: sel.start,
        extentOffset: sel.start + wrapped.length,
      ),
    );
    _editorFocusNode.requestFocus();
  }

  void _toggleEditorLinePrefix(String prefix) {
    final sel = _transcriptController.selection;
    if (!sel.isValid) return;
    final text = _transcriptController.text;
    final lineStart = text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0);
    final start = lineStart == -1 ? 0 : lineStart + 1;
    final lineEnd = text.indexOf('\n', sel.end);
    final end = lineEnd == -1 ? text.length : lineEnd;
    final line = text.substring(start, end);
    final toggled = line.startsWith(prefix)
        ? line.substring(prefix.length)
        : '$prefix$line';
    _transcriptController.value = TextEditingValue(
      text: '${text.substring(0, start)}$toggled${text.substring(end)}',
      selection: TextSelection.collapsed(offset: start + toggled.length),
    );
    _editorFocusNode.requestFocus();
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
    final source = _isEditingTranscript
        ? _transcriptController.text
        : entry.content;
    final words = source.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final readMinutes = (words / 200).ceil(); // ~200 wpm average
    final wordStr = l10n.historyWordCount(words);
    final timeStr = readMinutes < 1
        ? l10n.historyReadingTimeUnder1
        : l10n.historyReadingTime(readMinutes);
    return '$wordStr · $timeStr';
  }

  void _showShortcutHelp() {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        final isDarkTheme = isDark;
        final bg = isDarkTheme
            ? WpColorsDark.surfaceElevated
            : WpColorsLight.surfaceElevated;
        final textCol = isDarkTheme
            ? WpColorsDark.textPrimary
            : WpColorsLight.textPrimary;
        final mutedCol = isDarkTheme
            ? WpColorsDark.textMuted
            : WpColorsLight.textMuted;
        final accentCol =
            isDarkTheme ? WpColorsDark.accent : WpColorsLight.accent;

        Widget shortcutRow(String key, String description) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accentCol.withValues(alpha: 0.12),
                    borderRadius: WpRadius.borderSm,
                  ),
                  child: Text(
                    key,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: accentCol,
                    ),
                  ),
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Text(
                    description,
                    style: TextStyle(fontSize: 13, color: textCol),
                  ),
                ),
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(WpSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.keyboard, size: 18, color: accentCol),
                      const SizedBox(width: WpSpacing.sm),
                      Text(
                        l10n.historyShortcutHelp,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textCol,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: WpSpacing.md),
                  Text(
                    l10n.historyShortcutGeneral,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: mutedCol,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  shortcutRow('Esc', l10n.historyShortcutClose),
                  const SizedBox(height: WpSpacing.sm),
                  Text(
                    l10n.historyShortcutEditing,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: mutedCol,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  shortcutRow('F2', l10n.historyShortcutEditTitle),
                  shortcutRow('Ctrl+E', l10n.historyShortcutToggleEdit),
                  shortcutRow('Ctrl+S', l10n.historyShortcutSave),
                  shortcutRow('Ctrl+↵', l10n.historyShortcutSave),
                  shortcutRow('Ctrl+B', l10n.historyShortcutBold),
                  shortcutRow('Ctrl+I', l10n.historyShortcutItalic),
                  shortcutRow('Ctrl+C', l10n.historyShortcutCopy),
                  const SizedBox(height: WpSpacing.md),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l10n.historyClose),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final detailAsync = ref.watch(historyDetailProvider(entry.id));
    final tags = detailAsync.asData?.value.tags ?? [];

    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final avatarCol = historyAvatarColor(entry, isDark);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isEditingTitle) {
            setState(() => _isEditingTitle = false);
            _panelFocusNode.requestFocus();
          } else if (_isEditingTranscript) {
            _saveTranscript();
          } else {
            onClose();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (!_isTextFieldFocused()) _startTitleEdit();
        },
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): _toggleEdit,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_isEditingTitle) {
            _saveTitle();
          } else if (_isEditingTranscript) {
            _saveTranscript();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_isEditingTitle) {
            _saveTitle();
          } else if (_isEditingTranscript) {
            _saveTranscript();
          }
        },
        // Suppress full-entry copy when a text field is focused so native
        // text selection copy (Ctrl+C) works normally inside the editor.
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (_isEditingTranscript || _isEditingTitle) return;
          onCopy();
        },
        // Markdown formatting shortcuts (active only in edit mode)
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          if (_isEditingTranscript) _wrapBold();
        },
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          if (_isEditingTranscript) _wrapItalic();
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true): () {
          if (_isEditingTranscript) _toggleBullet();
        },
        // Shortcut help overlay
        const SingleActivator(LogicalKeyboardKey.slash, shift: true): () {
          if (!_isTextFieldFocused()) _showShortcutHelp();
        },
      },
      child: Focus(
        focusNode: _panelFocusNode,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? WpColorsDark.surfaceGradient
                : WpColorsLight.surfaceGradient,
          ),
          child: Column(
            children: [
          // Header bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl, WpSpacing.md, WpSpacing.md, WpSpacing.sm,
            ),
            child: ClipRect(
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
                      if (_isEditingTitle)
                        TextField(
                          controller: _titleController,
                          focusNode: _titleFocusNode,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.historyTitlePlaceholder,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.xs,
                              vertical: 4,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: WpRadius.borderSm,
                              borderSide: BorderSide(color: accent, width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: WpRadius.borderSm,
                              borderSide: BorderSide(
                                color: isDark
                                    ? WpColorsDark.borderSubtle
                                    : WpColorsLight.borderSubtle,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _saveTitle(),
                          onEditingComplete: _saveTitle,
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: Tooltip(
                                message: isTrashView ? '' : l10n.historyEditTitle,
                                waitDuration: const Duration(milliseconds: 600),
                                child: GestureDetector(
                                  onDoubleTap: isTrashView ? null : _startTitleEdit,
                                  child: MouseRegion(
                                    cursor: isTrashView
                                        ? SystemMouseCursors.basic
                                        : SystemMouseCursors.click,
                                    child: HighlightedText(
                                      text: entry.title.isNotEmpty
                                          ? entry.title
                                          : l10n.historyUntitled,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                      isDark: isDark,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (!isTrashView && !isArchiveView)
                              _SuggestTitleButton(
                                isLoading: _isSuggestingTitle,
                                isDark: isDark,
                                onTap: () => _suggestTitle(entry),
                              ),
                          ],
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
                    tooltip: '${l10n.historyCopyText} (Ctrl+C)',
                    isDark: isDark,
                    onTap: onCopy,
                  ),
                  HistoryDetailAction(
                    faIcon: entry.pinned ? FontAwesomeIcons.solidStar : null,
                    icon: entry.pinned ? null : LucideIcons.star,
                    activeColor: entry.pinned ? Colors.amber.shade600 : null,
                    tooltip: '${entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop} (F)',
                    isDark: isDark,
                    onTap: onPin,
                  ),
                  // Overflow menu for secondary actions
                  PopupMenuButton<String>(
                    icon: Icon(
                      LucideIcons.ellipsisVertical,
                      size: 18,
                      color: textSecondary,
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
                  tooltip: '${l10n.historyClose} (Esc)',
                  isDark: isDark,
                  onTap: onClose,
                ),
              ],
            ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < WpLayout.breakpointMobile;
                final contentPad = isCompact ? WpSpacing.md : WpSpacing.xl;
                return SingleChildScrollView(
                  padding: EdgeInsets.all(contentPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // ── Context zone: metadata + tags ──
                  Wrap(
                    spacing: WpSpacing.sm,
                    runSpacing: WpSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                      if (entry.model.isNotEmpty) ...[
                        () {
                          final modelName = displayNameForModel(entry.model, l10n);
                          return Tooltip(
                            message: '${l10n.historyModel}: $modelName',
                            child: _MetaChip(
                              icon: LucideIcons.cpu,
                              label: modelName.length > 25
                                  ? '${modelName.substring(0, 25)}…'
                                  : modelName,
                              isDark: isDark,
                            ),
                          );
                        }(),
                      ],
                    ],
                  ),
                  const SizedBox(height: WpSpacing.sm),
                  // Tags — label + chips in a single inline flow
                  _TagSection(
                    key: _tagSectionKey,
                    entryId: entry.id,
                    tags: tags,
                    isDark: isDark,
                    content: entry.content,
                    searchQuery: _tagSearchQuery,
                    onSearchChanged: (q) =>
                        setState(() => _tagSearchQuery = q),
                  ),
                  // ── Divider between context and content ──
                  const SizedBox(height: WpSpacing.md),
                  Container(
                    height: 1,
                    color: isDark
                        ? WpColorsDark.borderSubtle
                        : WpColorsLight.borderSubtle,
                  ),
                  const SizedBox(height: WpSpacing.md),
                  // ── Content zone: transcript + edit controls ──
                  if (_isEditingTranscript) ...[
                    WpMarkdownToolbar(
                      controller: _transcriptController,
                      isDark: isDark,
                      focusNode: _editorFocusNode,
                    ),
                    const SizedBox(height: WpSpacing.xs),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _isEditingTranscript
                            ? TextField(
                                controller: _transcriptController,
                                focusNode: _editorFocusNode,
                                maxLines: null,
                                autofocus: true,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontFamily: 'monospace',
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
                                      color: accent,
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(WpSpacing.sm),
                                ),
                                onSubmitted: (_) => _saveTranscript(),
                              )
                            : Tooltip(
                                message: l10n.historyEditTranscript,
                                waitDuration: const Duration(milliseconds: 600),
                                child: GestureDetector(
                                  onTap: isTrashView ? null : _toggleEdit,
                                  behavior: HitTestBehavior.translucent,
                                  child: MouseRegion(
                                    cursor: isTrashView
                                        ? SystemMouseCursors.basic
                                        : SystemMouseCursors.click,
                                    child: HighlightedText(
                                      text: entry.content,
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        color: textPrimary,
                                        height: 1.65,
                                      ),
                                      isDark: isDark,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (!isTrashView) ...[
                    const SizedBox(height: WpSpacing.xs),
                    Row(
                      children: [
                        // Left: metadata fills available space
                        Expanded(
                          child: Row(
                            children: [
                              if (entry.titleEdited || _isEditingTranscript)
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: WpSpacing.sm,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isEditingTranscript
                                          ? accent.withValues(alpha: 0.15)
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
                                            ? accent
                                            : textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              if ((entry.titleEdited || _isEditingTranscript) &&
                                  (entry.content.isNotEmpty || _isEditingTranscript))
                                const SizedBox(width: WpSpacing.xs),
                              if (entry.content.isNotEmpty || _isEditingTranscript)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  child: Text(
                                    _wordCountLabel(l10n),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: WpSpacing.xs),
                        // Right: edit/save button — always right-aligned
                        Tooltip(
                          message: _isEditingTranscript
                              ? '${l10n.historySaveTranscript} (Ctrl+S / Ctrl+↵)'
                              : '${l10n.historyEditTranscript} (Ctrl+E)',
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: WpRadius.borderFull,
                            child: InkWell(
                              borderRadius: const BorderRadius.all(Radius.circular(999)),
                              onTap: _toggleEdit,
                              child: AnimatedContainer(
                                duration: WpMotion.fast,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: WpSpacing.sm,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _isEditingTranscript
                                      ? accent.withValues(alpha: 0.15)
                                      : textMuted.withValues(alpha: 0.08),
                                  borderRadius: WpRadius.borderFull,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isEditingTranscript
                                          ? LucideIcons.check
                                          : LucideIcons.pencil,
                                      size: 14,
                                      color: _isEditingTranscript
                                          ? accent
                                          : textMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _isEditingTranscript
                                            ? l10n.historySaveTranscript
                                            : l10n.historyEditTranscript,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: _isEditingTranscript
                                              ? accent
                                              : textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // ── AI Actions (post-processing) ──
                  const SizedBox(height: WpSpacing.md),
                  _AiActionsRow(
                    isDark: isDark,
                    entryId: entry.id,
                    content: entry.content,
                  ),
                  // ── Notes section ──
                  const SizedBox(height: WpSpacing.lg),
                  HistoryNotesSection(key: _notesSectionKey, entryId: entry.id, isDark: isDark),
                  // FAB clearance so content isn't hidden behind the floating button
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
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
// AI Actions row — post-processing buttons (live LLM)
// ---------------------------------------------------------------------------

class _AiActionsRow extends ConsumerStatefulWidget {
  const _AiActionsRow({
    required this.isDark,
    required this.entryId,
    required this.content,
  });

  final bool isDark;
  final String entryId;
  final String content;

  @override
  ConsumerState<_AiActionsRow> createState() => _AiActionsRowState();
}

class _AiActionsRowState extends ConsumerState<_AiActionsRow> {
  PostProcessPreset? _activePreset;

  Future<void> _process(PostProcessPreset preset, {String? targetLang}) async {
    if (_activePreset != null) return;
    final pp = ref.read(postProcessingProvider.notifier);
    if (ref.read(postProcessingProvider).isBusy) {
      WpToast.show(context, message: L10n.of(context).historyAiBusy);
      return;
    }
    final originalText = widget.content;
    setState(() => _activePreset = preset);
    try {
      final result = await pp.process(
        originalText,
        preset,
        targetLang: targetLang,
      );
      if (!mounted) return;
      await ref
          .read(historyDetailProvider(widget.entryId).notifier)
          .updateContent(result);
      if (!mounted) return;
      WpToast.show(
        context,
        message: L10n.of(context).historyAiProcessed,
        actionLabel: L10n.of(context).undo,
        onAction: () {
          ref
              .read(historyDetailProvider(widget.entryId).notifier)
              .updateContent(originalText);
        },
      );
    } on Exception catch (e) {
      if (!mounted) return;
      WpToast.show(
        context,
        message: '${L10n.of(context).historyAiError}: $e',
        type: WpToastType.error,
      );
    } finally {
      if (mounted) setState(() => _activePreset = null);
    }
  }

  Future<void> _onTranslate() async {
    final lang = await _showLanguagePicker(context, widget.isDark);
    if (lang == null || !mounted) return;
    await _process(PostProcessPreset.translate, targetLang: lang);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.historyAiActions,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textMuted,
                letterSpacing: 0.5,
              ),
            ),
            if (_activePreset != null) ...[
              const SizedBox(width: WpSpacing.xs),
              Text(
                l10n.historyAiProcessing,
                style: TextStyle(fontSize: 11, color: textMuted),
              ),
            ],
          ],
        ),
        const SizedBox(height: WpSpacing.xs),
        Wrap(
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xs,
          children: [
            _AiActionChip(
              icon: LucideIcons.sparkles,
              label: l10n.historyAiCleanUp,
              isDark: widget.isDark,
              isLoading: _activePreset == PostProcessPreset.cleanup,
              isDisabled: _activePreset != null &&
                  _activePreset != PostProcessPreset.cleanup,
              onTap: () => _process(PostProcessPreset.cleanup),
            ),
            _AiActionChip(
              icon: LucideIcons.arrowDownUp,
              label: l10n.historyAiShorten,
              isDark: widget.isDark,
              isLoading: _activePreset == PostProcessPreset.concise,
              isDisabled: _activePreset != null &&
                  _activePreset != PostProcessPreset.concise,
              onTap: () => _process(PostProcessPreset.concise),
            ),
            _AiActionChip(
              icon: LucideIcons.languages,
              label: l10n.historyAiTranslate,
              isDark: widget.isDark,
              isLoading: _activePreset == PostProcessPreset.translate,
              isDisabled: _activePreset != null &&
                  _activePreset != PostProcessPreset.translate,
              onTap: _onTranslate,
            ),
          ],
        ),
      ],
    );
  }
}

class _AiActionChip extends StatelessWidget {
  const _AiActionChip({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.isLoading = false,
    this.isDisabled = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final bool isLoading;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final chipColor = isLoading ? accent : textMuted;
    final opacity = isDisabled ? 0.35 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        borderRadius: WpRadius.borderFull,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          onTap: (isLoading || isDisabled) ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: isLoading
                    ? accent.withValues(alpha: 0.4)
                    : textMuted.withValues(alpha: 0.2),
              ),
              borderRadius: WpRadius.borderFull,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: accent,
                    ),
                  )
                else
                  Icon(icon, size: 13, color: chipColor),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: chipColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language picker dialog for translate preset
// ---------------------------------------------------------------------------

Future<String?> _showLanguagePicker(BuildContext context, bool isDark) {
  final l10n = L10n.of(context);
  final languages = <String, String>{
    'English': 'English',
    'German': 'Deutsch',
    'Spanish': 'Español',
    'French': 'Français',
    'Italian': 'Italiano',
    'Portuguese': 'Português',
    'Japanese': '日本語',
    'Chinese': '中文',
    'Korean': '한국어',
    'Russian': 'Русский',
  };

  final surface =
      isDark ? WpColorsDark.surfaceElevated : WpColorsLight.surfaceElevated;
  final textPrimary =
      isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: surface,
      title: Text(
        l10n.historyAiTranslateTo,
        style: TextStyle(color: textPrimary, fontSize: 16),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
      content: SizedBox(
        width: 260,
        child: ListView(
          shrinkWrap: true,
          children: languages.entries
              .map(
                (e) => ListTile(
                  dense: true,
                  title: Text(
                    '${e.key}  ${e.value}',
                    style: TextStyle(color: textPrimary, fontSize: 14),
                  ),
                  onTap: () => Navigator.of(ctx).pop(e.key),
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Suggest-title sparkle button
// ---------------------------------------------------------------------------

class _SuggestTitleButton extends StatelessWidget {
  const _SuggestTitleButton({
    required this.isLoading,
    required this.isDark,
    required this.onTap,
  });

  final bool isLoading;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final muted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    return Tooltip(
      message: L10n.of(context).historyAiSuggestTitle,
      child: InkWell(
        borderRadius: WpRadius.borderFull,
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: accent,
                  ),
                )
              : Icon(LucideIcons.sparkles, size: 16, color: muted),
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
    this.icon,
    this.faIcon,
    required this.tooltip,
    required this.isDark,
    required this.onTap,
    this.isDestructive = false,
    this.activeColor,
  }) : assert(icon != null || faIcon != null, 'Provide icon or faIcon');

  final IconData? icon;
  final FaIconData? faIcon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDestructive;
  /// When set, overrides the icon color regardless of hover/active state.
  final Color? activeColor;

  @override
  State<HistoryDetailAction> createState() => _HistoryDetailActionState();
}

class _HistoryDetailActionState extends State<HistoryDetailAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    if (widget.activeColor != null) {
      iconColor = widget.activeColor!;
    } else if (widget.isDestructive && _isHovered) {
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
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: _isHovered ? Duration.zero : WpMotion.hoverOut,
            padding: const EdgeInsets.all(WpSpacing.sm),
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
            child: widget.faIcon != null
                ? FaIcon(widget.faIcon!, size: WpIconSize.md, color: iconColor)
                : Icon(widget.icon!, size: WpIconSize.md, color: iconColor),
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
    final fg = isDark
        ? WpColorsDark.textMuted
        : WpColorsLight.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: WpSpacing.xxs),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: fg),
        ),
      ],
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
    required this.content,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  final String entryId;
  final List<Tag> tags;
  final bool isDark;
  final String content;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  @override
  ConsumerState<_TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends ConsumerState<_TagSection> {
  List<Tag> _suggestions = [];
  Map<String, int> _suggestionCounts = {};
  final GlobalKey<WpTagInputState> _tagInputKey = GlobalKey<WpTagInputState>();
  bool _isSuggestingTags = false;
  List<String> _aiSuggestedTags = [];

  /// Called by keyboard shortcut (T) to enter tag add mode.
  void focusTagInput() {
    _tagInputKey.currentState?.enterAddMode();
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
    if (widget.searchQuery.isEmpty) {
      final results = await db.frequentTagsWithCount(limit: 8);
      if (mounted) {
        setState(() {
          _suggestions = results.map((r) => r.$1).toList();
          _suggestionCounts = {
            for (final r in results) r.$1.id: r.$2,
          };
        });
      }
    } else {
      final results = await db.searchTags(widget.searchQuery);
      if (mounted) {
        setState(() {
          _suggestions = results;
          _suggestionCounts = {};
        });
      }
    }
  }

  Future<void> _suggestTags() async {
    if (_isSuggestingTags) return;
    final pp = ref.read(postProcessingProvider.notifier);
    if (ref.read(postProcessingProvider).isBusy) {
      WpToast.show(context, message: L10n.of(context).historyAiBusy);
      return;
    }
    setState(() {
      _isSuggestingTags = true;
      _aiSuggestedTags = [];
    });
    try {
      final tags = await pp.suggestTags(widget.content);
      if (!mounted) return;
      // Filter out tags already assigned
      final existingNames =
          widget.tags.map((t) => t.name.toLowerCase()).toSet();
      final filtered =
          tags.where((t) => !existingNames.contains(t.toLowerCase())).toList();
      setState(() => _aiSuggestedTags = filtered);
      if (filtered.isNotEmpty) {
        WpToast.show(
          context,
          message: L10n.of(context).historyAiTagsSuggested(filtered.length),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      WpToast.show(
        context,
        message: '${L10n.of(context).historyAiError}: $e',
        type: WpToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isSuggestingTags = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(historyDetailProvider(widget.entryId).notifier);
    final l10n = L10n.of(context);
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WpTagInput(
      key: _tagInputKey,
      tags: widget.tags,
      isDark: widget.isDark,
      hintText: l10n.historyAddTag,
      searchHintText: l10n.historySearchTags,
      suggestions: _suggestions,
      suggestionCounts: _suggestionCounts,
      inlineLabel: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.tags, size: WpIconSize.sm, color: accent),
          const SizedBox(width: WpSpacing.xxs),
          Text(
            l10n.historyTags,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: WpSpacing.xxs),
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              icon: Icon(LucideIcons.settings, size: 12, color: textMuted),
              onPressed: () async {
                final db = ref.read(historyDatabaseProvider);
                final modified = await showTagManagementDialog(
                  context: context,
                  db: db,
                  isDark: widget.isDark,
                );
                if (modified) _loadSuggestions();
              },
              tooltip: l10n.historyManageTags,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: WpSpacing.xxs),
          _isSuggestingTags
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: accent,
                  ),
                )
              : SizedBox(
                  width: 22,
                  height: 22,
                  child: IconButton(
                    icon: Icon(LucideIcons.sparkles, size: 12, color: textMuted),
                    onPressed: _suggestTags,
                    tooltip: l10n.historyAiSuggestTags,
                    padding: EdgeInsets.zero,
                  ),
                ),
        ],
      ),
      onSearchChanged: (q) {
        widget.onSearchChanged(q);
        _loadSuggestions();
      },
      onAdd: (name) => notifier.addTag(name),
      onRemove: (tagId) {
        final tag = widget.tags.where((t) => t.id == tagId).firstOrNull;
        final tagName = tag?.name ?? '';
        notifier.removeTag(tagId);
        if (tag != null) {
          WpToast.show(
            context,
            message: l10n.historyTagRemoved,
            type: WpToastType.info,
            duration: const Duration(seconds: 4),
            actionLabel: l10n.undo,
            onAction: () => notifier.addTag(tagName),
          );
        }
        },
      ),
      if (_aiSuggestedTags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: WpSpacing.xs, left: WpSpacing.xxs),
          child: Wrap(
            spacing: WpSpacing.xxs,
            runSpacing: WpSpacing.xxs,
            children: _aiSuggestedTags.map((tagName) {
              return ActionChip(
                avatar: Icon(LucideIcons.plus, size: 12, color: accent),
                label: Text(
                  tagName,
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                backgroundColor: accent.withValues(alpha: 0.1),
                side: BorderSide(color: accent.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                  borderRadius: WpRadius.borderSm,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () {
                  notifier.addTag(tagName);
                  setState(() {
                    _aiSuggestedTags =
                        _aiSuggestedTags.where((t) => t != tagName).toList();
                  });
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
