import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/toast.dart';
import 'data/database.dart';
import 'data/providers.dart';

/// Resolves a [DateGroup.labelKey] to a localized string.
String _resolveDateLabel(String key, L10n l10n) {
  switch (key) {
    case 'today':
      return l10n.historyToday;
    case 'yesterday':
      return l10n.historyYesterday;
    case 'thisWeek':
      return l10n.historyThisWeek;
    case 'older':
      return l10n.historyOlder;
    default:
      return key;
  }
}

/// View mode for the history page.
enum _ViewMode { list, cards, compact }

/// Formats timestamp as HH:MM.
String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Formats recording duration as human-readable string.
String _formatDuration(double durationSec) {
  final secs = durationSec.round();
  if (secs < 60) return '${secs}s';
  final mins = secs ~/ 60;
  final rem = secs % 60;
  return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
}

/// History page — recorded transcriptions with search, filter, and grouping.
///
/// Uses a chat-style layout: flat rows with hover highlight, date group
/// headers, and conversational preview. Inspired by ChatGPT/WhatsApp list
/// views — scannable, warm, and fast to navigate.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _searchController = TextEditingController();
  String? _selectedEntryId;
  _ViewMode _viewMode = _ViewMode.list;
  bool _multiSelectMode = false;
  final Set<String> _selectedIds = {};
  /// Tracks last clicked entry for Shift+click range selection.
  String? _lastClickedId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFilter = ref.watch(historyFilterProvider);
    final groupedAsync = ref.watch(groupedHistoryProvider);
    final filteredAsync = ref.watch(filteredHistoryProvider);
    final isTrashView = activeFilter == HistoryFilter.trash;
    final isArchiveView = activeFilter == HistoryFilter.archived;

    // Resolve the flat filtered list (for selection lookup & shift-click)
    final filteredEntries = filteredAsync.value ?? [];

    // Look up selected entry from current filtered list
    HistoryEntry? selectedEntry;
    if (_selectedEntryId != null) {
      final idx = filteredEntries.indexWhere((e) => e.id == _selectedEntryId);
      selectedEntry = idx >= 0 ? filteredEntries[idx] : null;
    }

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Multi-select action bar (shown when items are selected)
          if (_multiSelectMode && _selectedIds.isNotEmpty)
            _MultiSelectBar(
              selectedCount: _selectedIds.length,
              isDark: isDark,
              isTrashView: isTrashView,
              isArchiveView: isArchiveView,
              onMerge: _selectedIds.length >= 2 ? _mergeSelected : null,
              onArchive: !isTrashView ? _archiveSelected : null,
              onDelete: _deleteSelected,
              onRestore: isTrashView ? _restoreSelected : null,
              onCancelSelection: () => setState(() {
                _multiSelectMode = false;
                _selectedIds.clear();
              }),
            ),
          // Search & filter toolbar
          if (!_multiSelectMode || _selectedIds.isEmpty)
            _SearchToolbar(
              controller: _searchController,
              activeFilter: activeFilter,
              isDark: isDark,
              onFilterChanged: (f) {
                ref.read(historyFilterProvider.notifier).set(f);
                setState(() {
                  _multiSelectMode = false;
                  _selectedIds.clear();
                  _selectedEntryId = null;
                });
              },
              onSearchChanged: () {
                ref.read(historySearchProvider.notifier).set(
                      _searchController.text,
                    );
              },
              resultCount: filteredEntries.length,
              viewMode: _viewMode,
              onViewModeChanged: (m) => setState(() => _viewMode = m),
              multiSelectMode: _multiSelectMode,
              onToggleMultiSelect: () => setState(() {
                _multiSelectMode = !_multiSelectMode;
                if (!_multiSelectMode) _selectedIds.clear();
              }),
            ),
          // Master-detail content
          Expanded(
            child: groupedAsync.when(
              data: (groups) {
                final hasResults = groups.isNotEmpty;
                if (!hasResults) {
                  return _emptyStateForFilter(isDark, activeFilter);
                }
                return _MasterDetail(
                  groups: groups,
                  isDark: isDark,
                  viewMode: _viewMode,
                  selectedEntry: selectedEntry,
                  multiSelectMode: _multiSelectMode,
                  selectedIds: _selectedIds,
                  isTrashView: isTrashView,
                  isArchiveView: isArchiveView,
                  onEntryTap: (entry) {
                    final isCtrl =
                        HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed;
                    final isShift =
                        HardwareKeyboard.instance.isShiftPressed;

                    if (isCtrl) {
                      // Ctrl+click: toggle individual item in multi-select
                      setState(() {
                        if (!_multiSelectMode) _multiSelectMode = true;
                        if (_selectedIds.contains(entry.id)) {
                          _selectedIds.remove(entry.id);
                        } else {
                          _selectedIds.add(entry.id);
                        }
                        _lastClickedId = entry.id;
                      });
                    } else if (isShift && _lastClickedId != null) {
                      // Shift+click: range select from last clicked
                      final flatIds =
                          filteredEntries.map((e) => e.id).toList();
                      final from = flatIds.indexOf(_lastClickedId!);
                      final to = flatIds.indexOf(entry.id);
                      if (from >= 0 && to >= 0) {
                        final start = from < to ? from : to;
                        final end = from < to ? to : from;
                        setState(() {
                          if (!_multiSelectMode) _multiSelectMode = true;
                          for (var i = start; i <= end; i++) {
                            _selectedIds.add(flatIds[i]);
                          }
                        });
                      }
                    } else if (_multiSelectMode) {
                      setState(() {
                        if (_selectedIds.contains(entry.id)) {
                          _selectedIds.remove(entry.id);
                        } else {
                          _selectedIds.add(entry.id);
                        }
                        _lastClickedId = entry.id;
                      });
                    } else {
                      setState(() {
                        _selectedEntryId = entry.id;
                        _lastClickedId = entry.id;
                      });
                    }
                  },
                  onCopy: _copyEntry,
                  onPin: _togglePin,
                  onDelete: _deleteEntry,
                  onArchive: _archiveEntry,
                  onRestore: _restoreEntry,
                  onDuplicate: _duplicateEntry,
                  onCopyMarkdown: _copyAsMarkdown,
                  onCloseDetail: () =>
                      setState(() => _selectedEntryId = null),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => _emptyStateForFilter(isDark, activeFilter),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyStateForFilter(bool isDark, HistoryFilter activeFilter) {
    final l10n = L10n.of(context);
    if (_searchController.text.isNotEmpty) {
      return WpEmptyState(
        icon: LucideIcons.searchX,
        title: l10n.historyNoResults,
        hint: l10n.historyNoResultsHint(_searchController.text),
      );
    }
    if (activeFilter == HistoryFilter.trash) {
      return WpEmptyState(
        icon: LucideIcons.trash2,
        title: l10n.historyTrashEmpty,
        hint: l10n.historyTrashEmptyHint,
      );
    }
    if (activeFilter == HistoryFilter.archived) {
      return WpEmptyState(
        icon: LucideIcons.archive,
        title: l10n.historyNoArchivedItems,
        hint: l10n.historyNoArchivedItemsHint,
      );
    }
    return WpEmptyState(
      icon: LucideIcons.mic,
      title: l10n.historyEmpty,
      hint: l10n.historyNoRecordingsHint,
    );
  }

  void _copyEntry(HistoryEntry entry) {
    Clipboard.setData(ClipboardData(text: entry.content));
    if (!mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).historyCopiedToClipboard,
      type: WpToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  void _togglePin(HistoryEntry entry) {
    ref.read(historyDatabaseProvider).togglePin(entry.id);
  }

  void _deleteEntry(HistoryEntry entry) {
    final isTrash = ref.read(historyFilterProvider) == HistoryFilter.trash;
    if (isTrash) {
      ref.read(historyDatabaseProvider).permanentDeleteEntry(entry.id);
    } else {
      ref.read(historyDatabaseProvider).softDeleteEntry(entry.id);
    }
    if (_selectedEntryId == entry.id) {
      setState(() => _selectedEntryId = null);
    }
    if (!mounted || isTrash) return;
    final l10n = L10n.of(context);
    WpToast.show(
      context,
      message: l10n.historyMovedToTrash,
      type: WpToastType.info,
      duration: const Duration(seconds: 4),
      actionLabel: l10n.historyUndo,
      onAction: () => _restoreEntry(entry),
    );
  }

  void _archiveEntry(HistoryEntry entry) {
    ref.read(historyDatabaseProvider).toggleArchive(entry.id);
    if (_selectedEntryId == entry.id) {
      setState(() => _selectedEntryId = null);
    }
  }

  void _restoreEntry(HistoryEntry entry) {
    ref.read(historyDatabaseProvider).restoreEntry(entry.id);
  }

  void _duplicateEntry(HistoryEntry entry) {
    ref.read(historyDatabaseProvider).duplicateEntry(entry.id).then((dup) {
      if (!mounted || dup == null) return;
      setState(() => _selectedEntryId = dup.id);
      WpToast.show(
        context,
        message: L10n.of(context).historyDuplicated,
        type: WpToastType.success,
        duration: const Duration(seconds: 2),
      );
    });
  }

  void _copyAsMarkdown(HistoryEntry entry) {
    final md = StringBuffer();
    md.writeln('# ${entry.title.isNotEmpty ? entry.title : "Untitled"}');
    md.writeln();
    md.writeln(entry.content);
    md.writeln();
    md.writeln('---');
    md.writeln();
    final tags = _parseTags(entry.tags);
    if (tags.isNotEmpty) {
      md.writeln('**Tags:** ${tags.map((t) => '#$t').join(', ')}');
    }
    md.writeln(
        '**Date:** ${DateFormat.yMMMd().add_Hm().format(entry.timestamp)}');
    if (entry.model.isNotEmpty) {
      md.writeln('**Model:** ${entry.model}');
    }

    Clipboard.setData(ClipboardData(text: md.toString()));
    if (!mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).historyCopiedAsMarkdown,
      type: WpToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  static List<String> _parseTags(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }

  void _mergeSelected() {
    if (_selectedIds.length < 2) return;
    final db = ref.read(historyDatabaseProvider);
    final ids = _selectedIds.toList();
    db.mergeEntries(ids).then((merged) {
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _multiSelectMode = false;
        if (merged != null) _selectedEntryId = merged.id;
      });
      WpToast.show(
        context,
        message: L10n.of(context).historyEntriesMerged,
        type: WpToastType.success,
        duration: const Duration(seconds: 2),
      );
    });
  }

  void _archiveSelected() {
    final db = ref.read(historyDatabaseProvider);
    for (final id in _selectedIds) {
      db.toggleArchive(id);
    }
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
    });
  }

  void _deleteSelected() {
    final db = ref.read(historyDatabaseProvider);
    final isTrash = ref.read(historyFilterProvider) == HistoryFilter.trash;
    if (isTrash) {
      for (final id in _selectedIds) {
        db.permanentDeleteEntry(id);
      }
    } else {
      db.softDeleteEntries(_selectedIds.toList());
    }
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
    });
  }

  void _restoreSelected() {
    final db = ref.read(historyDatabaseProvider);
    for (final id in _selectedIds) {
      db.restoreEntry(id);
    }
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
    });
  }
}

// ---------------------------------------------------------------------------
// Search & filter toolbar
// ---------------------------------------------------------------------------

class _SearchToolbar extends StatelessWidget {
  const _SearchToolbar({
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
  });

  final TextEditingController controller;
  final HistoryFilter activeFilter;
  final bool isDark;
  final ValueChanged<HistoryFilter> onFilterChanged;
  final VoidCallback onSearchChanged;
  final int resultCount;
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final bool multiSelectMode;
  final VoidCallback onToggleMultiSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.sm,
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
                color:
                    isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
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
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        label: l10n.historyAll,
                        isActive: activeFilter == HistoryFilter.all,
                        onTap: () => onFilterChanged(HistoryFilter.all),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
                        label: l10n.historyToday,
                        isActive: activeFilter == HistoryFilter.today,
                        onTap: () => onFilterChanged(HistoryFilter.today),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
                        label: l10n.historyThisWeek,
                        isActive: activeFilter == HistoryFilter.week,
                        onTap: () => onFilterChanged(HistoryFilter.week),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
                        label: l10n.historyPinned,
                        icon: LucideIcons.pin,
                        isActive: activeFilter == HistoryFilter.pinned,
                        onTap: () => onFilterChanged(HistoryFilter.pinned),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
                        label: l10n.historyArchived,
                        icon: LucideIcons.archive,
                        isActive: activeFilter == HistoryFilter.archived,
                        onTap: () => onFilterChanged(HistoryFilter.archived),
                        isDark: isDark,
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      _FilterChip(
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
              // Multi-select toggle
              Tooltip(
                message: multiSelectMode ? l10n.historyExitSelection : l10n.historySelectMultiple,
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
                          ? (isDark ? WpColorsDark.accent : WpColorsLight.accent)
                          : (isDark
                              ? WpColorsDark.textMuted
                              : WpColorsLight.textMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xxs),
              // View mode toggle
              _ViewModeToggle(
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

class _MultiSelectBar extends StatelessWidget {
  const _MultiSelectBar({
    required this.selectedCount,
    required this.isDark,
    required this.isTrashView,
    required this.isArchiveView,
    required this.onCancelSelection,
    this.onMerge,
    this.onArchive,
    this.onDelete,
    this.onRestore,
  });

  final int selectedCount;
  final bool isDark;
  final bool isTrashView;
  final bool isArchiveView;
  final VoidCallback onCancelSelection;
  final VoidCallback? onMerge;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
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
          bottom: BorderSide(
            color: accent.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Selection count
          Container(
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.md),
          // Action buttons
          if (onMerge != null)
            _MultiSelectAction(
              icon: LucideIcons.merge,
              label: l10n.historyMerge,
              isDark: isDark,
              onTap: onMerge!,
            ),
          if (onRestore != null)
            _MultiSelectAction(
              icon: LucideIcons.undo2,
              label: l10n.historyRestore,
              isDark: isDark,
              onTap: onRestore!,
            ),
          if (onArchive != null)
            _MultiSelectAction(
              icon: isArchiveView ? LucideIcons.archiveRestore : LucideIcons.archive,
              label: isArchiveView ? l10n.historyUnarchive : l10n.historyArchive,
              isDark: isDark,
              onTap: onArchive!,
            ),
          if (onDelete != null)
            _MultiSelectAction(
              icon: LucideIcons.trash2,
              label: isTrashView ? l10n.historyDeleteForever : l10n.actionDelete,
              isDark: isDark,
              onTap: onDelete!,
              isDestructive: true,
            ),
          const Spacer(),
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

class _MultiSelectAction extends StatefulWidget {
  const _MultiSelectAction({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  State<_MultiSelectAction> createState() => _MultiSelectActionState();
}

class _MultiSelectActionState extends State<_MultiSelectAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final hoverColor = widget.isDestructive
        ? (widget.isDark ? WpColorsDark.error : WpColorsLight.error)
        : (widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary);
    final color = _hovered ? hoverColor : textSecondary;

    return Padding(
      padding: const EdgeInsets.only(right: WpSpacing.xs),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: widget.label,
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
// Master-detail layout
// ---------------------------------------------------------------------------

class _MasterDetail extends StatefulWidget {
  const _MasterDetail({
    required this.groups,
    required this.isDark,
    required this.viewMode,
    required this.selectedEntry,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    required this.onCloseDetail,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
    required this.isArchiveView,
    this.onDuplicate,
    this.onCopyMarkdown,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final _ViewMode viewMode;
  final HistoryEntry? selectedEntry;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final ValueChanged<HistoryEntry> onArchive;
  final ValueChanged<HistoryEntry> onRestore;
  final VoidCallback onCloseDetail;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;
  final bool isArchiveView;
  final ValueChanged<HistoryEntry>? onDuplicate;
  final ValueChanged<HistoryEntry>? onCopyMarkdown;

  @override
  State<_MasterDetail> createState() => _MasterDetailState();
}

class _MasterDetailState extends State<_MasterDetail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _detailWidth;
  HistoryEntry? _displayedEntry;

  double _masterWidth = _defaultMasterWidth;
  bool _isDragging = false;

  static const _defaultMasterWidth = 340.0;
  static const _minMasterWidth = 240.0;
  static const _maxMasterFraction = 0.65;
  static const _dividerHitWidth = 8.0;
  static const _dividerVisualWidth = 1.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _detailWidth = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    if (widget.selectedEntry != null) {
      _displayedEntry = widget.selectedEntry;
      _anim.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _MasterDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedEntry != null && oldWidget.selectedEntry == null) {
      // Opening detail panel
      _displayedEntry = widget.selectedEntry;
      _anim.forward();
    } else if (widget.selectedEntry == null && oldWidget.selectedEntry != null) {
      // Closing detail panel
      _anim.reverse().then((_) {
        if (mounted) setState(() => _displayedEntry = null);
      });
    } else if (widget.selectedEntry != null) {
      // Switching to different entry
      _displayedEntry = widget.selectedEntry;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _buildMasterBody({String? selectedId}) {
    final Widget body;
    switch (widget.viewMode) {
      case _ViewMode.list:
        body = _EntryList(
          key: const ValueKey('view-list'),
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          onEntryTap: widget.onEntryTap,
          onCopy: widget.onCopy,
          onPin: widget.onPin,
          onDelete: widget.onDelete,
          multiSelectMode: widget.multiSelectMode,
          selectedIds: widget.selectedIds,
          isTrashView: widget.isTrashView,
        );
      case _ViewMode.cards:
        body = _CardView(
          key: const ValueKey('view-cards'),
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          onEntryTap: widget.onEntryTap,
          onCopy: widget.onCopy,
          onPin: widget.onPin,
          onDelete: widget.onDelete,
          multiSelectMode: widget.multiSelectMode,
          selectedIds: widget.selectedIds,
        );
      case _ViewMode.compact:
        body = _CompactView(
          key: const ValueKey('view-compact'),
          groups: widget.groups,
          isDark: widget.isDark,
          selectedId: selectedId,
          onEntryTap: widget.onEntryTap,
          multiSelectMode: widget.multiSelectMode,
          selectedIds: widget.selectedIds,
        );
    }
    return AnimatedSwitcher(
      duration: WpMotion.normal,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDetail =
        widget.selectedEntry != null || _displayedEntry != null;

    if (!showDetail) {
      return _buildMasterBody();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final maxMasterW = totalWidth * _maxMasterFraction;
        return AnimatedBuilder(
          animation: _detailWidth,
          builder: (context, _) {
            final detailFraction = _detailWidth.value;
            final effectiveMaster = _masterWidth.clamp(
              _minMasterWidth, maxMasterW,
            );
            final detailW =
                (totalWidth - effectiveMaster - _dividerHitWidth) *
                    detailFraction;
            final masterW = totalWidth - detailW - _dividerHitWidth;

            return Row(
              children: [
                SizedBox(
                  width: masterW.clamp(effectiveMaster, totalWidth),
                  child: _buildMasterBody(
                    selectedId: (widget.selectedEntry ?? _displayedEntry)?.id,
                  ),
                ),
                // Draggable divider
                MouseRegion(
                  cursor: _isDragging
                      ? SystemMouseCursors.resizeColumn
                      : SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    onHorizontalDragStart: (_) =>
                        setState(() => _isDragging = true),
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _masterWidth = (_masterWidth + details.delta.dx)
                            .clamp(_minMasterWidth, maxMasterW);
                      });
                    },
                    onHorizontalDragEnd: (_) =>
                        setState(() => _isDragging = false),
                    child: Container(
                      width: _dividerHitWidth,
                      color: Colors.transparent,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: _isDragging ? 3.0 : _dividerVisualWidth,
                          decoration: BoxDecoration(
                            color: _isDragging
                                ? (widget.isDark
                                    ? WpColorsDark.accent.withValues(alpha: 0.5)
                                    : WpColorsLight.accent.withValues(alpha: 0.5))
                                : (widget.isDark
                                    ? WpColorsDark.borderSubtle
                                    : WpColorsLight.borderSubtle),
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: detailW.clamp(0.0, totalWidth - _minMasterWidth),
                  child: detailFraction > 0.05
                      ? Opacity(
                          opacity: detailFraction.clamp(0.0, 1.0),
                          child: AnimatedSwitcher(
                            duration: WpMotion.fast,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: _DetailPanel(
                              key: ValueKey(
                                (widget.selectedEntry ?? _displayedEntry!)
                                    .id),
                              entry:
                                  widget.selectedEntry ?? _displayedEntry!,
                              isDark: widget.isDark,
                              isTrashView: widget.isTrashView,
                              isArchiveView: widget.isArchiveView,
                              onClose: widget.onCloseDetail,
                              onCopy: () => widget.onCopy(
                                  widget.selectedEntry ?? _displayedEntry!),
                              onPin: () => widget.onPin(
                                  widget.selectedEntry ?? _displayedEntry!),
                              onDelete: () => widget.onDelete(
                                  widget.selectedEntry ?? _displayedEntry!),
                              onArchive: () => widget.onArchive(
                                  widget.selectedEntry ?? _displayedEntry!),
                              onRestore: () => widget.onRestore(
                                  widget.selectedEntry ?? _displayedEntry!),
                              onDuplicate: widget.onDuplicate == null
                                  ? null
                                  : () => widget.onDuplicate!(
                                      widget.selectedEntry ?? _displayedEntry!),
                              onCopyMarkdown: widget.onCopyMarkdown == null
                                  ? null
                                  : () => widget.onCopyMarkdown!(
                                      widget.selectedEntry ?? _displayedEntry!),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Entry list with date groups
// ---------------------------------------------------------------------------

class _EntryList extends StatelessWidget {
  const _EntryList({
    super.key,
    required this.groups,
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final items = <Widget>[];

    for (final group in groups) {
      items.add(_DateHeader(label: _resolveDateLabel(group.labelKey, l10n), isDark: isDark));
      for (final entry in group.entries) {
        items.add(
          _HistoryEntryRow(
            entry: entry,
            isDark: isDark,
            isSelected: multiSelectMode
                ? selectedIds.contains(entry.id)
                : entry.id == selectedId,
            onTap: () => onEntryTap(entry),
            onCopy: () => onCopy(entry),
            onPin: () => onPin(entry),
            onDelete: () => onDelete(entry),
            multiSelectMode: multiSelectMode,
            isChecked: selectedIds.contains(entry.id),
            isTrashView: isTrashView,
          ),
        );
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: WpSpacing.xs,
        bottom: WpSpacing.xxl,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

// ---------------------------------------------------------------------------
// Date group header — ChatGPT-style time divider
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final lineColor =
        isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl, WpSpacing.md, WpSpacing.xl, WpSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: lineColor)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Content type avatar colors — gives each entry visual identity
// ---------------------------------------------------------------------------

/// Derives a warm avatar color from the entry's first tag or title.
Color _avatarColor(HistoryEntry entry, bool isDark) {
  // Palette of warm, distinguishable hues (not harsh, not glow)
  const palette = [
    Color(0xFF22D3EE), // cyan (default)
    Color(0xFF8B5CF6), // violet
    Color(0xFFF59E0B), // amber
    Color(0xFF10B981), // emerald
    Color(0xFFF472B6), // pink
    Color(0xFF3B82F6), // blue
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // teal
  ];
  // Hash from title for consistent color per entry
  final hash = entry.title.isNotEmpty
      ? entry.title.codeUnits.fold<int>(0, (a, b) => a + b)
      : entry.id.codeUnits.fold<int>(0, (a, b) => a + b);
  return palette[hash % palette.length];
}

/// Icon for the entry avatar — based on content/source hints.
IconData _avatarIcon(HistoryEntry entry) {
  final title = entry.title.toLowerCase();
  final tags = entry.tags.toLowerCase();

  if (tags.contains('meeting') || title.contains('meeting') || title.contains('standup')) {
    return LucideIcons.users;
  }
  if (tags.contains('email') || title.contains('email') || title.contains('follow')) {
    return LucideIcons.mail;
  }
  if (tags.contains('blog') || tags.contains('writing') || title.contains('blog') || title.contains('draft')) {
    return LucideIcons.penLine;
  }
  if (tags.contains('personal') || tags.contains('recipe')) {
    return LucideIcons.heart;
  }
  if (tags.contains('feedback') || title.contains('feedback') || title.contains('review')) {
    return LucideIcons.messageSquare;
  }
  if (tags.contains('project') || title.contains('project') || title.contains('brief')) {
    return LucideIcons.folderOpen;
  }
  if (tags.contains('idea') || tags.contains('team')) {
    return LucideIcons.lightbulb;
  }
  if (title.contains('reminder') || title.contains('todo')) {
    return LucideIcons.bellRing;
  }
  return LucideIcons.mic;
}

// ---------------------------------------------------------------------------
// History entry row — WhatsApp/ChatGPT/Discord-inspired
// ---------------------------------------------------------------------------

class _HistoryEntryRow extends StatefulWidget {
  const _HistoryEntryRow({
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.multiSelectMode = false,
    this.isChecked = false,
    this.isTrashView = false,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final bool multiSelectMode;
  final bool isChecked;
  final bool isTrashView;

  @override
  State<_HistoryEntryRow> createState() => _HistoryEntryRowState();
}

class _HistoryEntryRowState extends State<_HistoryEntryRow> {
  bool _isHovered = false;

  String get _timeLabel {
    final t = widget.entry.timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  String get _durationLabel {
    final secs = widget.entry.durationSec.round();
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final avatarCol = _avatarColor(widget.entry, isDark);

    // Row background
    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = isDark ? WpColorsDark.hoverTransparent : WpColorsLight.hoverTransparent;
    }

    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          margin: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xs,
            vertical: 1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.md,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderMd,
            // Left accent stripe for selected entry (Discord-style)
            border: widget.isSelected
                ? Border(
                    left: BorderSide(color: accent, width: 3),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Multi-select checkbox
              if (widget.multiSelectMode)
                Padding(
                  padding: const EdgeInsets.only(right: WpSpacing.xs, top: 10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: widget.isChecked,
                      onChanged: (_) => widget.onTap(),
                      activeColor: accent,
                      side: BorderSide(
                        color: isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              // Avatar — colored circle with content-type icon
              _EntryAvatar(
                color: avatarCol,
                icon: _avatarIcon(widget.entry),
                isPinned: widget.entry.pinned,
                isDark: isDark,
                size: 42,
              ),
              const SizedBox(width: WpSpacing.sm),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Title + time/actions (fixed height — no jiggle)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.entry.title.isNotEmpty
                                ? widget.entry.title
                                : l10n.historyUntitledRecording,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        // Fixed-height container: cross-fade time ↔ actions
                        SizedBox(
                          height: 28,
                          child: Stack(
                            alignment: Alignment.centerRight,
                            children: [
                              // Time label (fades out on hover)
                              AnimatedOpacity(
                                duration: _isHovered
                                    ? WpMotion.fast
                                    : WpMotion.hoverOut,
                                opacity: _isHovered ? 0.0 : 1.0,
                                child: Text(
                                  _timeLabel,
                                  style: TextStyle(
                                      fontSize: 11, color: textMuted),
                                ),
                              ),
                              // Action buttons (fade in on hover)
                              IgnorePointer(
                                ignoring: !_isHovered,
                                child: AnimatedOpacity(
                                  duration: _isHovered
                                      ? WpMotion.fast
                                      : WpMotion.hoverOut,
                                  opacity: _isHovered ? 1.0 : 0.0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _RowAction(
                                        icon: LucideIcons.copy,
                                        tooltip: l10n.historyCopyText,
                                        isDark: isDark,
                                        onTap: widget.onCopy,
                                      ),
                                      _RowAction(
                                        icon: widget.entry.pinned
                                            ? LucideIcons.pinOff
                                            : LucideIcons.pin,
                                        tooltip: widget.entry.pinned
                                            ? l10n.historyUnpin
                                            : l10n.historyPinToTop,
                                        isDark: isDark,
                                        onTap: widget.onPin,
                                      ),
                                      _RowAction(
                                        icon: LucideIcons.trash2,
                                        tooltip: l10n.actionDelete,
                                        isDark: isDark,
                                        onTap: widget.onDelete,
                                        isDestructive: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Row 2: Content preview — two lines for more context
                    Text(
                      widget.entry.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Row 3: Subtle inline metadata (duration + language)
                    Row(
                      children: [
                        Icon(LucideIcons.clock, size: 10, color: textMuted),
                        const SizedBox(width: 3),
                        Text(
                          _durationLabel,
                          style: TextStyle(fontSize: 10, color: textMuted),
                        ),
                        if (widget.entry.language.isNotEmpty) ...[
                          const SizedBox(width: WpSpacing.xs),
                          Text(
                            '·',
                            style: TextStyle(
                                fontSize: 10, color: textMuted),
                          ),
                          const SizedBox(width: WpSpacing.xs),
                          Text(
                            widget.entry.language.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (!widget.entry.isLocal) ...[
                          const SizedBox(width: WpSpacing.xs),
                          Text(
                            '·',
                            style: TextStyle(
                                fontSize: 10, color: textMuted),
                          ),
                          const SizedBox(width: WpSpacing.xs),
                          Icon(LucideIcons.cloud, size: 10, color: textMuted),
                        ],
                      ],
                    ),
                  ],
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
// Entry avatar — colored circle with icon (Discord/WhatsApp identity)
// ---------------------------------------------------------------------------

class _EntryAvatar extends StatelessWidget {
  const _EntryAvatar({
    required this.color,
    required this.icon,
    required this.isPinned,
    required this.isDark,
    this.size = 36,
  });

  final Color color;
  final IconData icon;
  final bool isPinned;
  final bool isDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = (size * 0.44).roundToDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Avatar circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: color.withValues(alpha: isDark ? 0.9 : 0.8),
            ),
          ),
          // Pin badge — small dot in corner
          if (isPinned)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? WpColorsDark.surface : WpColorsLight.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel — opens on entry selection (ChatGPT/Notion detail view)
// ---------------------------------------------------------------------------

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
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
    final avatarCol = _avatarColor(entry, isDark);

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
                _EntryAvatar(
                  color: avatarCol,
                  icon: _avatarIcon(entry),
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
                  _DetailAction(
                    icon: LucideIcons.undo2,
                    tooltip: l10n.historyRestore,
                    isDark: isDark,
                    onTap: onRestore,
                  ),
                  _DetailAction(
                    icon: LucideIcons.trash2,
                    tooltip: l10n.historyDeleteForever,
                    isDark: isDark,
                    onTap: onDelete,
                    isDestructive: true,
                  ),
                ] else ...[
                  _DetailAction(
                    icon: LucideIcons.copy,
                    tooltip: l10n.historyCopyText,
                    isDark: isDark,
                    onTap: onCopy,
                  ),
                  if (onCopyMarkdown != null)
                    _DetailAction(
                      icon: LucideIcons.fileText,
                      tooltip: l10n.historyCopyAsMarkdown,
                      isDark: isDark,
                      onTap: onCopyMarkdown!,
                    ),
                  if (onDuplicate != null)
                    _DetailAction(
                      icon: LucideIcons.files,
                      tooltip: l10n.historyDuplicate,
                      isDark: isDark,
                      onTap: onDuplicate!,
                    ),
                  _DetailAction(
                    icon: entry.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                    tooltip: entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop,
                    isDark: isDark,
                    onTap: onPin,
                  ),
                  _DetailAction(
                    icon: entry.archived
                        ? LucideIcons.archiveRestore
                        : LucideIcons.archive,
                    tooltip: entry.archived ? l10n.historyUnarchive : l10n.historyArchive,
                    isDark: isDark,
                    onTap: onArchive,
                  ),
                  _DetailAction(
                    icon: LucideIcons.trash2,
                    tooltip: l10n.actionDelete,
                    isDark: isDark,
                    onTap: onDelete,
                    isDestructive: true,
                  ),
                ],
                const SizedBox(width: WpSpacing.xxs),
                _DetailAction(
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
                      fontSize: 14,
                      color: textPrimary,
                      height: 1.6,
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
                        _DetailMetaRow(
                          icon: LucideIcons.clock,
                          label: l10n.historyDuration,
                          value: _durationLabel,
                          isDark: isDark,
                        ),
                        if (entry.language.isNotEmpty)
                          _DetailMetaRow(
                            icon: LucideIcons.globe,
                            label: l10n.historyLanguageLabel,
                            value: entry.language.toUpperCase(),
                            isDark: isDark,
                          ),
                        _DetailMetaRow(
                          icon: entry.isLocal
                              ? LucideIcons.hardDrive
                              : LucideIcons.cloud,
                          label: l10n.historyProcessed,
                          value: entry.isLocal ? l10n.historyOnDevice : l10n.statusCloud,
                          isDark: isDark,
                        ),
                        if (entry.model.isNotEmpty)
                          _DetailMetaRow(
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
                  _NotesSection(entryId: entry.id, isDark: isDark),
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
// Inline notes section (progressive disclosure)
// ---------------------------------------------------------------------------

class _NotesSection extends ConsumerStatefulWidget {
  const _NotesSection({required this.entryId, required this.isDark});
  final String entryId;
  final bool isDark;

  @override
  ConsumerState<_NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends ConsumerState<_NotesSection> {
  final _controller = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addNote() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final db = ref.read(historyDatabaseProvider);
    final now = DateTime.now();
    db.upsertNote(EntryNotesCompanion(
      id: Value(now.millisecondsSinceEpoch.toString()),
      entryId: Value(widget.entryId),
      content: Value(text),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    _controller.clear();
    setState(() => _isAdding = false);
  }

  void _deleteNote(String noteId) {
    ref.read(historyDatabaseProvider).deleteNote(noteId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final notes = ref.watch(entryNotesProvider(widget.entryId));
    final textPrimary =
        widget.isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final borderColor = widget.isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final surfaceElevated = widget.isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;

    return notes.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (noteList) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(LucideIcons.stickyNote, size: 14, color: textMuted),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  noteList.isEmpty
                      ? l10n.historyAddNote
                      : '${l10n.historyNotes} (${noteList.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                const Spacer(),
                if (!_isAdding)
                  GestureDetector(
                    onTap: () => setState(() => _isAdding = true),
                    child: Icon(LucideIcons.plus, size: 16, color: accent),
                  ),
              ],
            ),
            // Add note input
            if (_isAdding) ...[
              const SizedBox(height: WpSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: WpRadius.borderSm,
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: TextStyle(fontSize: 13, color: textPrimary),
                        decoration: InputDecoration(
                          hintText: l10n.historyNotePlaceholder,
                          hintStyle: TextStyle(color: textMuted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: WpSpacing.sm,
                            vertical: WpSpacing.xs,
                          ),
                        ),
                        onSubmitted: (_) => _addNote(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.check, size: 16, color: accent),
                      onPressed: _addNote,
                      splashRadius: 16,
                      padding: const EdgeInsets.all(WpSpacing.xs),
                      constraints: const BoxConstraints(),
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.x, size: 16, color: textMuted),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _isAdding = false);
                      },
                      splashRadius: 16,
                      padding: const EdgeInsets.all(WpSpacing.xs),
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: WpSpacing.xxs),
                  ],
                ),
              ),
            ],
            // Existing notes
            for (final note in noteList) ...[
              const SizedBox(height: WpSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: WpSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: WpRadius.borderSm,
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.content,
                            style:
                                TextStyle(fontSize: 13, color: textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat.yMd().add_Hm().format(note.createdAt),
                            style: TextStyle(fontSize: 11, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteNote(note.id),
                      child: Padding(
                        padding: const EdgeInsets.only(left: WpSpacing.xs),
                        child:
                            Icon(LucideIcons.x, size: 14, color: textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Detail panel action button
// ---------------------------------------------------------------------------

class _DetailAction extends StatefulWidget {
  const _DetailAction({
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
  State<_DetailAction> createState() => _DetailActionState();
}

class _DetailActionState extends State<_DetailAction> {
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

class _DetailMetaRow extends StatelessWidget {
  const _DetailMetaRow({
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

// ---------------------------------------------------------------------------
// Row action button (hover-only, used in entry rows)
// ---------------------------------------------------------------------------

class _RowAction extends StatefulWidget {
  const _RowAction({
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
  State<_RowAction> createState() => _RowActionState();
}

class _RowActionState extends State<_RowAction> {
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
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xxs,
              vertical: 2,
            ),
            child: AnimatedContainer(
              duration: WpMotion.fast,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _isHovered
                    ? (widget.isDark
                        ? WpColorsDark.active
                        : WpColorsLight.active)
                    : (widget.isDark
                        ? WpColorsDark.hoverTransparent
                        : WpColorsLight.hoverTransparent),
                borderRadius: WpRadius.borderSm,
              ),
              child: Icon(widget.icon, size: 14, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip
// ---------------------------------------------------------------------------

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.isDark,
    this.icon,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool isDark;
  final IconData? icon;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    if (widget.isActive) {
      bg = widget.isDark
          ? WpColorsDark.accentSubtle
          : WpColorsLight.accentSubtle;
      fg = widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    } else if (_isHovered) {
      bg = widget.isDark ? WpColorsDark.hover : WpColorsLight.hover;
      fg = widget.isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary;
    } else {
      bg = widget.isDark
          ? WpColorsDark.surfaceVariant
          : WpColorsLight.surfaceVariant;
      fg = widget.isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderFull,
            border: widget.isActive
                ? Border.all(
                    color: (widget.isDark
                            ? WpColorsDark.accent
                            : WpColorsLight.accent)
                        .withValues(alpha: 0.3),
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 13, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w500,
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
// View mode toggle — segmented icon button group
// ---------------------------------------------------------------------------

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.viewMode,
    required this.isDark,
    required this.onChanged,
  });

  final _ViewMode viewMode;
  final bool isDark;
  final ValueChanged<_ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: WpRadius.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeButton(
            icon: LucideIcons.list,
            isActive: viewMode == _ViewMode.list,
            isDark: isDark,
            onTap: () => onChanged(_ViewMode.list),
          ),
          _ViewModeButton(
            icon: LucideIcons.layoutGrid,
            isActive: viewMode == _ViewMode.cards,
            isDark: isDark,
            onTap: () => onChanged(_ViewMode.cards),
          ),
          _ViewModeButton(
            icon: LucideIcons.rows3,
            isActive: viewMode == _ViewMode.compact,
            isDark: isDark,
            onTap: () => onChanged(_ViewMode.compact),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
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
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderSm,
          ),
          child: Icon(icon, size: WpIconSize.sm, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card view — responsive grid of entry cards
// ---------------------------------------------------------------------------

class _CardView extends StatelessWidget {
  const _CardView({
    super.key,
    required this.groups,
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.multiSelectMode,
    required this.selectedIds,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final bool multiSelectMode;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 280.0;
        const gap = WpSpacing.md;
        const sidePad = WpSpacing.md;
        final availableWidth = constraints.maxWidth - sidePad * 2;
        final columns =
            (availableWidth / minCardWidth).floor().clamp(1, 4);
        final cardWidth =
            (availableWidth - gap * (columns - 1)) / columns;

        return ListView(
          padding: const EdgeInsets.only(
            top: WpSpacing.xs,
            bottom: WpSpacing.xxl,
          ),
          children: [
            for (final group in groups) ...[
              _DateHeader(label: _resolveDateLabel(group.labelKey, l10n), isDark: isDark),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: sidePad),
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final entry in group.entries)
                      SizedBox(
                        width: cardWidth,
                        child: _EntryCard(
                          entry: entry,
                          isDark: isDark,
                          isSelected: entry.id == selectedId,
                          onTap: () => onEntryTap(entry),
                          onCopy: () => onCopy(entry),
                          onPin: () => onPin(entry),
                          onDelete: () => onDelete(entry),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Entry card — used in card grid view
// ---------------------------------------------------------------------------

class _EntryCard extends StatefulWidget {
  const _EntryCard({
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final avatarCol = _avatarColor(widget.entry, isDark);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surfaceElevated = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final borderColor = widget.isSelected
        ? accent.withValues(alpha: 0.5)
        : (isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          height: 180,
          padding: const EdgeInsets.all(WpSpacing.md),
          decoration: BoxDecoration(
            color: surfaceElevated,
            borderRadius: WpRadius.borderMd,
            border: Border.all(color: borderColor),
            boxShadow: _isHovered ? WpShadows.subtle : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: avatar + title + hover actions
              Row(
                children: [
                  _EntryAvatar(
                    color: avatarCol,
                    icon: _avatarIcon(widget.entry),
                    isPinned: widget.entry.pinned,
                    isDark: isDark,
                    size: 32,
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.entry.title.isNotEmpty
                          ? widget.entry.title
                          : L10n.of(context).historyUntitledRecording,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  // Hover action buttons
                  if (_isHovered) ...[
                    _RowAction(
                      icon: LucideIcons.copy,
                      tooltip: l10n.historyCopyText,
                      isDark: isDark,
                      onTap: widget.onCopy,
                    ),
                    _RowAction(
                      icon: widget.entry.pinned
                          ? LucideIcons.pinOff
                          : LucideIcons.pin,
                      tooltip: widget.entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop,
                      isDark: isDark,
                      onTap: widget.onPin,
                    ),
                    _RowAction(
                      icon: LucideIcons.trash2,
                      tooltip: l10n.actionDelete,
                      isDark: isDark,
                      onTap: widget.onDelete,
                      isDestructive: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: WpSpacing.xs),
              // Content preview (3-4 lines)
              Expanded(
                child: Text(
                  widget.entry.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: WpSpacing.xs),
              // Bottom metadata
              Row(
                children: [
                  Icon(LucideIcons.clock, size: 10, color: textMuted),
                  const SizedBox(width: 3),
                  Text(
                    _formatDuration(widget.entry.durationSec),
                    style: TextStyle(fontSize: 10, color: textMuted),
                  ),
                  if (widget.entry.language.isNotEmpty) ...[
                    const SizedBox(width: WpSpacing.xs),
                    Text(
                      '·',
                      style: TextStyle(fontSize: 10, color: textMuted),
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Text(
                      widget.entry.language.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!widget.entry.isLocal)
                    Icon(LucideIcons.cloud, size: 10, color: textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact view — dense power-user list
// ---------------------------------------------------------------------------

class _CompactView extends StatelessWidget {
  const _CompactView({
    super.key,
    required this.groups,
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
    required this.multiSelectMode,
    required this.selectedIds,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final bool multiSelectMode;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final items = <Widget>[];
    for (final group in groups) {
      items.add(_CompactDateHeader(label: _resolveDateLabel(group.labelKey, l10n), isDark: isDark));
      for (final entry in group.entries) {
        items.add(
          _CompactRow(
            entry: entry,
            isDark: isDark,
            isSelected: multiSelectMode
                ? selectedIds.contains(entry.id)
                : entry.id == selectedId,
            onTap: () => onEntryTap(entry),
            multiSelectMode: multiSelectMode,
            isChecked: selectedIds.contains(entry.id),
          ),
        );
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: WpSpacing.xs,
        bottom: WpSpacing.xxl,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

// ---------------------------------------------------------------------------
// Compact date header — minimal text-only header
// ---------------------------------------------------------------------------

class _CompactDateHeader extends StatelessWidget {
  const _CompactDateHeader({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl, WpSpacing.sm, WpSpacing.xl, WpSpacing.xxs,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact row — single-line dense entry
// ---------------------------------------------------------------------------

class _CompactRow extends StatefulWidget {
  const _CompactRow({
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    this.multiSelectMode = false,
    this.isChecked = false,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final bool multiSelectMode;
  final bool isChecked;

  @override
  State<_CompactRow> createState() => _CompactRowState();
}

class _CompactRowState extends State<_CompactRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = isDark ? WpColorsDark.hoverTransparent : WpColorsLight.hoverTransparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              // Multi-select checkbox
              if (widget.multiSelectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: widget.isChecked,
                      onChanged: (_) => widget.onTap(),
                      activeColor: accent,
                      side: BorderSide(
                        color: isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              // Pin indicator
              if (widget.entry.pinned)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              // Title
              Expanded(
                child: Text(
                  widget.entry.title.isNotEmpty
                      ? widget.entry.title
                      : L10n.of(context).historyUntitledRecording,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              // Duration
              Text(
                _formatDuration(widget.entry.durationSec),
                style: TextStyle(fontSize: 11, color: textMuted),
              ),
              // Language
              if (widget.entry.language.isNotEmpty) ...[
                const SizedBox(width: WpSpacing.sm),
                Text(
                  widget.entry.language.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(width: WpSpacing.sm),
              // Time
              Text(
                _formatTime(widget.entry.timestamp),
                style: TextStyle(fontSize: 11, color: textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
