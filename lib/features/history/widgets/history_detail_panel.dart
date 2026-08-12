import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/recording/recording_helpers.dart'
    show displayNameForModel;
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../../../services/history/history_exporter.dart' as history_exporter;
import '../data/history_detail_provider.dart';
import 'highlighted_text.dart';
import 'history_helpers.dart';
import 'history_notes_section.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/find_replace.dart';
import '../../../widgets/tag_input.dart';
import '../../../widgets/markdown_toolbar.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_text_field.dart';
import 'tag_management_dialog.dart';
import '../../../core/utils/focus_helpers.dart';
import '../../../core/utils/word_count.dart';

/// Signature of the export-entries seam used by [HistoryDetailPanel].
///
/// Defaults to the top-level [history_exporter.exportEntries]. Tests inject a
/// fake to assert that the overflow "Export…" menu item invokes the exporter
/// with the expected entry list, without spinning up real platform channels.
typedef HistoryDetailPanelExportFn =
    Future<void> Function(BuildContext context, List<HistoryEntry> entries);

/// Wraps [child] in the panel's standard [Tooltip] — but only when [message]
/// is non-null.
///
/// A tooltip that names an action is a promise. In the trash view neither the
/// title nor the transcript can be edited, so the promise has to disappear
/// rather than be blanked: `Tooltip(message: '')` still builds a tooltip, pops
/// an empty card on hover and leaves an empty `tooltip` on the semantics node.
/// One helper for both call sites so the two read-only affordances behave
/// identically.
Widget _tooltipIf(String? message, {required Widget child}) => message == null
    ? child
    : Tooltip(
        message: message,
        waitDuration: const Duration(milliseconds: 600),
        child: child,
      );

// ---------------------------------------------------------------------------
// Detail panel — opens on entry selection (ChatGPT/Notion detail view)
// ---------------------------------------------------------------------------

class HistoryDetailPanel extends ConsumerStatefulWidget {
  const HistoryDetailPanel({
    super.key,
    required this.entry,
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
    this.exportFn = history_exporter.exportEntries,
  });

  final HistoryEntry entry;
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

  /// Injection seam for the export flow.
  ///
  /// Defaults to the production [history_exporter.exportEntries]. Widget tests
  /// substitute a fake to assert the overflow "Export…" item invokes the
  /// exporter with `[entry]` without touching the filesystem or platform
  /// channels.
  final HistoryDetailPanelExportFn exportFn;

  @override
  ConsumerState<HistoryDetailPanel> createState() => _HistoryDetailPanelState();
}

class _HistoryDetailPanelState extends ConsumerState<HistoryDetailPanel> {
  String _tagSearchQuery = '';
  bool _isEditingTranscript = false;
  late TextEditingController _transcriptController;
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  final FocusNode _panelFocusNode = FocusNode();
  final FocusNode _editorFocusNode = FocusNode();
  final FocusNode _titleFocusNode = FocusNode();
  final GlobalKey<_TagSectionState> _tagSectionKey =
      GlobalKey<_TagSectionState>();
  final GlobalKey<HistoryNotesSectionState> _notesSectionKey =
      GlobalKey<HistoryNotesSectionState>();

  @override
  void initState() {
    super.initState();
    // Highlight-capable so the toolbar's find bar can tint its hits: a
    // TextField only paints a *selection* while focused, and while the user is
    // typing a query the focus is in the find field, not here.
    _transcriptController = WpFindHighlightController(
      text: widget.entry.content,
    );
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

  void _exportEntry() {
    // Fire-and-forget: the exporter manages its own progress + toast feedback.
    widget.exportFn(context, [entry]);
  }

  void _saveTranscript() {
    final newContent = _transcriptController.text.trim();
    if (newContent != entry.content) {
      ref
          .read(historyDetailProvider(entry.id).notifier)
          .updateContent(newContent);
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _titleFocusNode.requestFocus(),
    );
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

  /// Bold/italic/bullet come from [WpMarkdownFormatting] — the same object the
  /// toolbar's buttons call, so the key and the button it advertises can no
  /// longer drift apart. This panel used to keep its own second copy.
  WpMarkdownFormatting get _markdownFormatting => WpMarkdownFormatting(
    controller: _transcriptController,
    focusNode: _editorFocusNode,
  );

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
    final words = computeWordCountFast(source);
    final readMinutes = (words / 200).ceil(); // ~200 wpm average
    final wordStr = l10n.historyWordCount(words);
    final timeStr = readMinutes < 1
        ? l10n.historyReadingTimeUnder1
        : l10n.historyReadingTime(readMinutes);
    return '$wordStr · $timeStr';
  }

  void _showShortcutHelp() {
    final l10n = L10n.of(context);
    showWpDialog<void>(
      context: context,
      title: l10n.historyShortcutHelp,
      content: const _ShortcutHelpContent(),
      actions: [
        Builder(
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          builder: (dialogContext) => WpButton(
            label: l10n.historyClose,
            variant: WpButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final detailAsync = ref.watch(historyDetailProvider(entry.id));
    final tags = detailAsync.asData?.value.tags ?? [];

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
          if (!isTextFieldFocused()) _startTitleEdit();
        },
        SingleActivator(
          LogicalKeyboardKey.keyE,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          if (isTextFieldFocused()) return;
          _toggleEdit();
        },
        SingleActivator(
          LogicalKeyboardKey.keyS,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          if (_isEditingTitle) {
            _saveTitle();
          } else if (_isEditingTranscript) {
            _saveTranscript();
          }
        },
        SingleActivator(
          LogicalKeyboardKey.enter,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          if (_isEditingTitle) {
            _saveTitle();
          } else if (_isEditingTranscript) {
            _saveTranscript();
          }
        },
        // Suppress full-entry copy when a text field is focused so native
        // text selection copy (Ctrl+C / Cmd+C) works normally inside the editor.
        SingleActivator(
          LogicalKeyboardKey.keyC,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          if (_isEditingTranscript || _isEditingTitle) return;
          onCopy();
        },
        // Markdown formatting shortcuts (active only in edit mode). Owned by
        // WpMarkdownFormatting, shared with the Notes editor — the activators
        // and the operations behind them are defined once, next to the toolbar
        // buttons whose tooltips advertise them.
        ..._markdownFormatting.shortcutBindings(
          when: () => _isEditingTranscript,
        ),
        // Shortcut help overlay
        const SingleActivator(LogicalKeyboardKey.slash, shift: true): () {
          if (!isTextFieldFocused()) _showShortcutHelp();
        },
      },
      child: Focus(
        focusNode: _panelFocusNode,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: WpColors.surfaceGradient),
          child: Column(
            children: [
              // Header bar
              _DetailPanelHeader(
                entry: entry,
                isTrashView: isTrashView,
                isEditingTitle: _isEditingTitle,
                titleController: _titleController,
                titleFocusNode: _titleFocusNode,
                timestamp: _fullTimestamp(context),
                onStartTitleEdit: _startTitleEdit,
                onSaveTitle: _saveTitle,
                onCopy: onCopy,
                onPin: onPin,
                onDelete: onDelete,
                onArchive: onArchive,
                onRestore: onRestore,
                onDuplicate: onDuplicate,
                onCopyMarkdown: onCopyMarkdown,
                onExport: _exportEntry,
                onClose: onClose,
              ),
              // Divider
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
                color: WpColors.borderSubtle,
              ),
              // Content
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact =
                        constraints.maxWidth < WpLayout.breakpointMobile;
                    final contentPad = isCompact ? WpSpacing.md : WpSpacing.xl;
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(contentPad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Context zone: metadata + tags ──
                          _DetailMetaChips(
                            entry: entry,
                            durationLabel: _durationLabel,
                          ),
                          const SizedBox(height: WpSpacing.sm),
                          // Tags — label + chips in a single inline flow
                          _TagSection(
                            key: _tagSectionKey,
                            entryId: entry.id,
                            tags: tags,
                            content: entry.content,
                            searchQuery: _tagSearchQuery,
                            onSearchChanged: (q) =>
                                setState(() => _tagSearchQuery = q),
                          ),
                          // ── Divider between context and content ──
                          const SizedBox(height: WpSpacing.md),
                          Container(height: 1, color: WpColors.borderSubtle),
                          const SizedBox(height: WpSpacing.md),
                          // ── Content zone: transcript + edit controls ──
                          _DetailTranscriptZone(
                            entry: entry,
                            isTrashView: isTrashView,
                            isEditing: _isEditingTranscript,
                            transcriptController: _transcriptController,
                            editorFocusNode: _editorFocusNode,
                            wordCountLabel: _wordCountLabel(l10n),
                            onToggleEdit: _toggleEdit,
                            onSaveTranscript: _saveTranscript,
                          ),
                          // ── Notes section ──
                          const SizedBox(height: WpSpacing.lg),
                          HistoryNotesSection(
                            key: _notesSectionKey,
                            entryId: entry.id,
                          ),
                          const SizedBox(height: WpSpacing.xl),
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
// Shortcut help — body of the keyboard cheat sheet dialog
// ---------------------------------------------------------------------------

/// Content of the shortcut help [showWpDialog]: two labelled groups of
/// key-cap rows. Colors come from the theme (surface, border, radius and
/// title typography are the dialog's) — this body only owns the key caps.
class _ShortcutHelpContent extends StatelessWidget {
  const _ShortcutHelpContent();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final groupStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.historyShortcutGeneral, style: groupStyle),
        const SizedBox(height: WpSpacing.xs),
        _ShortcutRow(keyLabel: 'Esc', description: l10n.historyShortcutClose),
        const SizedBox(height: WpSpacing.sm),
        Text(l10n.historyShortcutEditing, style: groupStyle),
        const SizedBox(height: WpSpacing.xs),
        _ShortcutRow(
          keyLabel: 'F2',
          description: l10n.historyShortcutEditTitle,
        ),
        _ShortcutRow(
          keyLabel: 'Ctrl+E',
          description: l10n.historyShortcutToggleEdit,
        ),
        _ShortcutRow(keyLabel: 'Ctrl+S', description: l10n.historyShortcutSave),
        _ShortcutRow(keyLabel: 'Ctrl+↵', description: l10n.historyShortcutSave),
        _ShortcutRow(keyLabel: 'Ctrl+B', description: l10n.historyShortcutBold),
        _ShortcutRow(
          keyLabel: 'Ctrl+I',
          description: l10n.historyShortcutItalic,
        ),
        _ShortcutRow(keyLabel: 'Ctrl+C', description: l10n.historyShortcutCopy),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keyLabel, required this.description});

  final String keyLabel;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            // Off-scale on purpose: key-cap chip hugs its caption text;
            // xxs would double the height of this deliberately tight cap.
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xs,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: WpRadius.borderSm,
            ),
            child: Text(
              keyLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                letterSpacing: 0,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(child: Text(description, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel header (avatar + title/edit + timestamp + action buttons)
// ---------------------------------------------------------------------------

class _DetailPanelHeader extends StatelessWidget {
  const _DetailPanelHeader({
    required this.entry,
    required this.isTrashView,
    required this.isEditingTitle,
    required this.titleController,
    required this.titleFocusNode,
    required this.timestamp,
    required this.onStartTitleEdit,
    required this.onSaveTitle,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    required this.onDuplicate,
    required this.onCopyMarkdown,
    required this.onExport,
    required this.onClose,
  });

  final HistoryEntry entry;
  final bool isTrashView;
  final bool isEditingTitle;
  final TextEditingController titleController;
  final FocusNode titleFocusNode;
  final String timestamp;
  final VoidCallback onStartTitleEdit;
  final VoidCallback onSaveTitle;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback? onDuplicate;
  final VoidCallback? onCopyMarkdown;
  final VoidCallback onExport;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const textPrimary = WpColors.textPrimary;
    const textSecondary = WpColors.textSecondary;
    const textMuted = WpColors.textMuted;
    final avatarCol = historyAvatarSlot(entry).color();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.md,
        WpSpacing.md,
        WpSpacing.sm,
      ),
      child: ClipRect(
        child: Row(
          children: [
            HistoryEntryAvatar(
              color: avatarCol,
              icon: historyAvatarIcon,
              isPinned: entry
                  .pinned, // Off-scale on purpose (explicit default): mid-sized between
              // the card (32) and the list row (42) — the header shares the
              // row with title/metadata/actions, unlike the list row.
              size: 36,
            ),
            const SizedBox(width: WpSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEditingTitle)
                    WpTextField(
                      controller: titleController,
                      focusNode: titleFocusNode,
                      variant: WpTextFieldVariant.heading,
                      hintText: l10n.historyTitlePlaceholder,
                      onSubmitted: (_) => onSaveTitle(),
                      onEditingComplete: onSaveTitle,
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            button: !isTrashView,
                            onTapHint: isTrashView
                                ? null
                                : l10n.historyEditTitle,
                            onTap: isTrashView ? null : onStartTitleEdit,
                            child: _tooltipIf(
                              isTrashView ? null : l10n.historyEditTitle,
                              child: GestureDetector(
                                onDoubleTap: isTrashView
                                    ? null
                                    : onStartTitleEdit,
                                child: MouseRegion(
                                  cursor: isTrashView
                                      ? SystemMouseCursors.basic
                                      : SystemMouseCursors.click,
                                  child: HighlightedText(
                                    text: entry.title.isNotEmpty
                                        ? entry.title
                                        : l10n.historyUntitled,
                                    // Read view and edit view of the same
                                    // title: one style, so opening edit mode
                                    // never resizes the text.
                                    style: WpTextField.styleFor(
                                      WpTextFieldVariant.heading,
                                      color: textPrimary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 2),
                  Text(
                    timestamp,
                    style: const TextStyle(
                      fontSize: WpTypography.small,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Action buttons
            if (isTrashView) ...[
              // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryDetailActionState.build
              HistoryDetailAction(
                icon: LucideIcons.undo2,
                tooltip: l10n.historyRestore,
                onTap: onRestore,
              ),
              // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryDetailActionState.build
              HistoryDetailAction(
                icon: LucideIcons.trash2,
                tooltip: l10n.historyDeleteForever,
                onTap: onDelete,
                isDestructive: true,
              ),
            ] else ...[
              // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryDetailActionState.build
              HistoryDetailAction(
                icon: LucideIcons.copy,
                tooltip: '${l10n.historyCopyText} (Ctrl+C)',
                onTap: onCopy,
              ),
              // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryDetailActionState.build
              HistoryDetailAction(
                faIcon: entry.pinned ? FontAwesomeIcons.solidStar : null,
                icon: entry.pinned ? null : LucideIcons.star,
                activeColor: entry.pinned ? WpSharedColors.pinnedAccent : null,
                tooltip:
                    '${entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop} (F)',
                onTap: onPin,
              ),
              // Overflow menu for secondary actions
              _DetailOverflowMenu(
                entry: entry,
                textSecondary: textSecondary,
                onCopyMarkdown: onCopyMarkdown,
                onDuplicate: onDuplicate,
                onExport: onExport,
                onArchive: onArchive,
                onDelete: onDelete,
              ),
            ],
            const SizedBox(width: WpSpacing.xxs),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryDetailActionState.build
            HistoryDetailAction(
              icon: LucideIcons.x,
              tooltip: '${l10n.historyClose} (Esc)',
              onTap: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overflow popup menu (secondary header actions)
// ---------------------------------------------------------------------------

class _DetailOverflowMenu extends StatelessWidget {
  const _DetailOverflowMenu({
    required this.entry,
    required this.textSecondary,
    required this.onCopyMarkdown,
    required this.onDuplicate,
    required this.onExport,
    required this.onArchive,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final Color textSecondary;
  final VoidCallback? onCopyMarkdown;
  final VoidCallback? onDuplicate;
  final VoidCallback onExport;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return PopupMenuButton<String>(
      icon: Icon(
        LucideIcons.ellipsisVertical,
        size: WpIconSize.md,
        color: textSecondary,
      ),
      tooltip: '',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: WpColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WpRadius.md),
      ),
      onSelected: (value) {
        switch (value) {
          case 'markdown':
            onCopyMarkdown?.call();
          case 'duplicate':
            onDuplicate?.call();
          case 'export':
            onExport();
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
            ),
          ),
        if (onDuplicate != null)
          PopupMenuItem(
            value: 'duplicate',
            child: HistoryPopupMenuRow(
              icon: LucideIcons.files,
              label: l10n.historyDuplicate,
            ),
          ),
        PopupMenuItem(
          value: 'export',
          child: HistoryPopupMenuRow(
            icon: LucideIcons.download,
            label: l10n.historyExportAction,
          ),
        ),
        PopupMenuItem(
          value: 'archive',
          child: HistoryPopupMenuRow(
            icon: entry.archived
                ? LucideIcons.archiveRestore
                : LucideIcons.archive,
            label: entry.archived ? l10n.historyUnarchive : l10n.historyArchive,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: HistoryPopupMenuRow(
            icon: LucideIcons.trash2,
            label: l10n.actionDelete,
            isDestructive: true,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Meta chips row (duration, language, storage, model)
// ---------------------------------------------------------------------------

class _DetailMetaChips extends StatelessWidget {
  const _DetailMetaChips({required this.entry, required this.durationLabel});

  final HistoryEntry entry;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Wrap(
      spacing: WpSpacing.sm,
      runSpacing: WpSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _MetaChip(icon: LucideIcons.clock, label: durationLabel),
        if (entry.language.isNotEmpty)
          _MetaChip(
            icon: LucideIcons.globe,
            label: entry.language.toUpperCase(),
          ),
        _MetaChip(
          icon: entry.isLocal ? LucideIcons.hardDrive : LucideIcons.cloud,
          label: entry.isLocal ? l10n.historyOnDevice : l10n.statusCloud,
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
              ),
            );
          }(),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transcript zone (view/edit mode + edit status bar)
// ---------------------------------------------------------------------------

class _DetailTranscriptZone extends StatelessWidget {
  const _DetailTranscriptZone({
    required this.entry,
    required this.isTrashView,
    required this.isEditing,
    required this.transcriptController,
    required this.editorFocusNode,
    required this.wordCountLabel,
    required this.onToggleEdit,
    required this.onSaveTranscript,
  });

  final HistoryEntry entry;
  final bool isTrashView;
  final bool isEditing;
  final TextEditingController transcriptController;
  final FocusNode editorFocusNode;
  final String wordCountLabel;
  final VoidCallback onToggleEdit;
  final VoidCallback onSaveTranscript;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const textPrimary = WpColors.textPrimary;

    // Cap prose measure at ~85 chars/line for the 16px body (Fill-By-Default
    // Rule: only the transcript degrades on ultrawide, so only it gets capped).
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEditing) ...[
            WpMarkdownToolbar(
              controller: transcriptController,
              focusNode: editorFocusNode,
            ),
            const SizedBox(height: WpSpacing.xs),
          ],
          Row(
            children: [
              Expanded(
                child: isEditing
                    ? WpTextField(
                        controller: transcriptController,
                        focusNode: editorFocusNode,
                        variant: WpTextFieldVariant.passage,
                        semanticsLabel: l10n.historyEditTranscript,
                        autofocus: true,
                        onSubmitted: (_) => onSaveTranscript(),
                      )
                    : Semantics(
                        button: !isTrashView,
                        // Same trash-view rule as the title above: the
                        // transcript is read-only here, so it must not offer
                        // "Edit transcript" on hover next to a tap that does
                        // nothing.
                        child: _tooltipIf(
                          isTrashView ? null : l10n.historyEditTranscript,
                          child: GestureDetector(
                            onTap: isTrashView ? null : onToggleEdit,
                            behavior: HitTestBehavior.translucent,
                            child: MouseRegion(
                              cursor: isTrashView
                                  ? SystemMouseCursors.basic
                                  : SystemMouseCursors.click,
                              child: HighlightedText(
                                text: entry.content.isEmpty
                                    ? '\u200B'
                                    : entry.content,
                                // Same metrics as the edit view above, so
                                // toggling edit mode doesn't reflow the
                                // paragraph the user is looking at.
                                style: WpTextField.styleFor(
                                  WpTextFieldVariant.passage,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (!isTrashView) ...[
            const SizedBox(height: WpSpacing.xs),
            _TranscriptEditBar(
              entry: entry,
              isEditing: isEditing,
              wordCountLabel: wordCountLabel,
              onToggleEdit: onToggleEdit,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit status bar below transcript (status badge + word count + edit button)
// ---------------------------------------------------------------------------

class _TranscriptEditBar extends StatelessWidget {
  const _TranscriptEditBar({
    required this.entry,
    required this.isEditing,
    required this.wordCountLabel,
    required this.onToggleEdit,
  });

  final HistoryEntry entry;
  final bool isEditing;
  final String wordCountLabel;
  final VoidCallback onToggleEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const textMuted = WpColors.textMuted;
    const accent = WpColors.accent;
    final showBadge = entry.titleEdited || isEditing;
    final showWordCount = entry.content.isNotEmpty || isEditing;

    return Row(
      children: [
        // Left: metadata fills available space
        Expanded(
          child: Row(
            children: [
              if (showBadge)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: WpSpacing.sm,
                      vertical: WpSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: isEditing
                          ? accent.withValues(alpha: 0.15)
                          : textMuted.withValues(alpha: 0.1),
                      borderRadius: WpRadius.borderFull,
                    ),
                    // Resting state is a *status*, not an offer: the badge
                    // marks a transcript that was hand-corrected. It used to
                    // read "Edit transcript" — an action verb, word for word
                    // the same as the button 8 px to its right, so the row
                    // showed the same command twice and said nothing about the
                    // entry. `historyNoteEdited` is the generic past
                    // participle ("edited"/"bearbeitet"); its key name is the
                    // only thing note-specific about it. A dedicated
                    // transcript key would mean touching the ARB files, which
                    // are outside this change — bewusst nicht umgesetzt,
                    // künftiges Ticket.
                    child: Text(
                      isEditing ? l10n.historyEditing : l10n.historyNoteEdited,
                      style: TextStyle(
                        fontSize: WpTypography.micro,
                        fontWeight: isEditing
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isEditing ? accent : textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              if (showBadge && showWordCount)
                const SizedBox(width: WpSpacing.xs),
              if (showWordCount)
                // Flexible (not a hard ConstrainedBox) so the word-count yields
                // space when the badge + count would otherwise overrun the row
                // by a couple of pixels (FLUTTER_WHISPASTE-64).
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      wordCountLabel,
                      style: const TextStyle(
                        fontSize: WpTypography.caption,
                        color: textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: WpSpacing.xs),
        // Right: edit/save button — always right-aligned
        Tooltip(
          message: isEditing
              ? '${l10n.historySaveTranscript} (Ctrl+S / Ctrl+↵)'
              : '${l10n.historyEditTranscript} (Ctrl+E)',
          child: Material(
            color: Colors.transparent,
            borderRadius: WpRadius.borderFull,
            child: InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              onTap: onToggleEdit,
              child: AnimatedContainer(
                duration: WpMotion.durationFor(context, WpMotion.fast),
                // Off-scale on purpose: 12x6 pill proportion shared with the
                // history filter chips; xs would visibly inflate the control.
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isEditing
                      ? accent.withValues(alpha: 0.15)
                      : (WpColors.surfaceMutedFill),
                  borderRadius: WpRadius.borderFull,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isEditing ? LucideIcons.check : LucideIcons.pencil,
                      size: 14,
                      color: isEditing ? accent : textMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isEditing
                            ? l10n.historySaveTranscript
                            : l10n.historyEditTranscript,
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          fontWeight: FontWeight.w500,
                          color: isEditing ? accent : textMuted,
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
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? (WpColors.error) : (WpColors.textPrimary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: WpSpacing.sm),
        Text(
          label,
          style: TextStyle(fontSize: WpTypography.body, color: color),
        ),
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
    required this.onTap,
    this.isDestructive = false,
    this.activeColor,
  }) : assert(icon != null || faIcon != null, 'Provide icon or faIcon');

  final IconData? icon;
  final FaIconData? faIcon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDestructive;

  /// When set, overrides the icon color regardless of hover/active state.
  final Color? activeColor;

  @override
  State<HistoryDetailAction> createState() => _HistoryDetailActionState();
}

class _HistoryDetailActionState extends State<HistoryDetailAction> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'HistoryDetailAction');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    if (widget.activeColor != null) {
      iconColor = widget.activeColor!;
    } else if (widget.isDestructive && _isHovered) {
      iconColor = WpColors.error;
    } else if (_isHovered) {
      iconColor = WpColors.textPrimary;
    } else {
      iconColor = WpColors.textMuted;
    }

    return Semantics(
      label: widget.tooltip,
      button: true,
      child: Tooltip(
        message: widget.tooltip,
        preferBelow: false,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          // InkWell + WpFocusRing instead of a bare GestureDetector: this is the
          // house shape for an icon-only action (WpRowAction:151-200), and the
          // detail panel's own actions were the one set of them Tab could not
          // reach. Copy/Restore/Delete of the open entry were mouse-only, which
          // is precisely the round trip this audience cannot make.
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.sm,
            child: InkWell(
              onTap: widget.onTap,
              focusNode: _focusNode,
              borderRadius: WpRadius.borderSm,
              // WpFocusRing owns all focus visuals — suppress InkWell's own.
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: AnimatedContainer(
                duration: WpMotion.durationFor(
                  context,
                  _isHovered ? Duration.zero : WpMotion.hoverOut,
                ),
                padding: const EdgeInsets.all(WpSpacing.sm),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? (WpColors.hover)
                      : (WpColors.hoverTransparent),
                  borderRadius: WpRadius.borderSm,
                ),
                child: widget.faIcon != null
                    ? FaIcon(
                        widget.faIcon!,
                        size: WpIconSize.md,
                        color: iconColor,
                      )
                    : Icon(widget.icon!, size: WpIconSize.md, color: iconColor),
              ),
            ),
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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    const textSecondary = WpColors.textSecondary;
    const textPrimary = WpColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
      child: Row(
        children: [
          Icon(icon, size: 14, color: textSecondary),
          const SizedBox(width: WpSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontSize: WpTypography.small,
              color: textSecondary,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: WpTypography.small,
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
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    const fg = WpColors.textMuted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: WpSpacing.xxs),
        Text(
          label,
          style: const TextStyle(fontSize: WpTypography.caption, color: fg),
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
    required this.content,
    required this.searchQuery,
    required this.onSearchChanged,
  });

  final String entryId;
  final List<Tag> tags;
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
          _suggestionCounts = {for (final r in results) r.$1.id: r.$2};
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
    const accent = WpColors.accent;
    const textSecondary = WpColors.textSecondary;
    const textMuted = WpColors.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WpTagInput(
          key: _tagInputKey,
          tags: widget.tags,
          hintText: l10n.historyAddTag,
          searchHintText: l10n.historySearchTags,
          suggestions: _suggestions,
          suggestionCounts: _suggestionCounts,
          inlineLabel: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.tags, size: WpIconSize.sm, color: accent),
              const SizedBox(width: WpSpacing.xxs),
              Text(
                l10n.historyTags,
                style: const TextStyle(
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: WpSpacing.xxs),
              IconButton(
                icon: const Icon(
                  LucideIcons.settings,
                  size: 12,
                  color: textMuted,
                ),
                onPressed: () async {
                  final db = ref.read(historyDatabaseProvider);
                  final modified = await showTagManagementDialog(
                    context: context,
                    db: db,
                  );
                  if (modified) _loadSuggestions();
                },
                tooltip: l10n.historyManageTags,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: WpLayout.minTouchTarget,
                  minHeight: WpLayout.minTouchTarget,
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
      ],
    );
  }
}
