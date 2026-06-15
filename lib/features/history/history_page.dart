import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_info.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/toast.dart';
import 'package:whispaste/core/data/database.dart';
import '../../services/history/history_exporter.dart' as history_exporter;
import 'data/history_detail_provider.dart';
import 'data/providers.dart';
import 'widgets/widgets.dart';

/// Signature of the export-entries seam used by [HistoryPage].
///
/// Defaults to the top-level [history_exporter.exportEntries]. Widget tests
/// substitute a fake to assert that the multi-select "Export…" button (and
/// the detail-panel item routed through the same widget) invokes the exporter
/// with the expected entries, without touching the filesystem or platform
/// channels.
typedef HistoryPageExportFn =
    Future<void> Function(BuildContext context, List<HistoryEntry> entries);

/// History page — recorded transcriptions with search, filter, and grouping.
///
/// Uses a chat-style layout: flat rows with hover highlight, date group
/// headers, and conversational preview. Inspired by ChatGPT/WhatsApp list
/// views — scannable, warm, and fast to navigate.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({
    super.key,
    this.exportFn = history_exporter.exportEntries,
  });

  /// Injection seam for the export flow.
  ///
  /// Defaults to the production [history_exporter.exportEntries]. Widget tests
  /// substitute a fake to assert that the multi-select "Export…" button
  /// invokes the exporter with the selected entries without touching the
  /// filesystem or platform channels.
  final HistoryPageExportFn exportFn;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String? _selectedEntryId;
  HistoryViewMode _viewMode = HistoryViewMode.list;
  HistorySortOrder _sortOrder = HistorySortOrder.newest;
  bool _multiSelectMode = false;
  final Set<String> _selectedIds = {};

  /// Tracks last clicked entry for Shift+click range selection.
  String? _lastClickedId;

  /// Keyboard-focused entry ID (distinct from selected/detail entry).
  String? _focusedEntryId;
  final FocusNode _listFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  /// Builds a flat list of entry IDs from the grouped data for keyboard
  /// navigation ordering. Applies the current sort order.
  List<HistoryEntry> _flatEntries(List<DateGroup> groups) {
    final flat = [for (final g in groups) ...g.entries];
    return _applySortOrder(flat);
  }

  /// Applies the current sort order to a list of entries.
  List<HistoryEntry> _applySortOrder(List<HistoryEntry> entries) {
    switch (_sortOrder) {
      case HistorySortOrder.newest:
        return entries; // Default order from DB is newest first
      case HistorySortOrder.oldest:
        return entries.reversed.toList();
      case HistorySortOrder.longest:
        return [...entries]
          ..sort((a, b) => b.content.length.compareTo(a.content.length));
    }
  }

  /// Applies sort order to groups for display.
  List<DateGroup> _sortGroups(List<DateGroup> groups) {
    switch (_sortOrder) {
      case HistorySortOrder.newest:
        return groups;
      case HistorySortOrder.oldest:
        return groups.reversed
            .map(
              (g) => DateGroup(
                labelKey: g.labelKey,
                entries: g.entries.reversed.toList(),
              ),
            )
            .toList();
      case HistorySortOrder.longest:
        final all = [for (final g in groups) ...g.entries];
        all.sort((a, b) => b.content.length.compareTo(a.content.length));
        return [DateGroup(labelKey: 'all', entries: all)];
    }
  }

  /// Returns true when any text input field currently has keyboard focus.
  ///
  /// `EditableText.build()` creates an internal `Focus` widget that overwrites
  /// the FocusNode context, so `context.widget` ends up being `Focus`, not
  /// `EditableText`. We check the widget directly AND walk ancestors as a
  /// fallback to cover both cases.
  bool _isTextFieldFocused() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final context = primary.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _moveFocus(int delta, List<HistoryEntry> flat) {
    if (flat.isEmpty) return;
    final currentIdx = flat.indexWhere((e) => e.id == _focusedEntryId);
    final int nextIdx;
    if (currentIdx < 0) {
      nextIdx = delta > 0 ? 0 : flat.length - 1;
    } else {
      nextIdx = (currentIdx + delta).clamp(0, flat.length - 1);
    }
    setState(() => _focusedEntryId = flat[nextIdx].id);
  }

  HistoryEntry? _focusedEntry(List<HistoryEntry> flat) {
    if (_focusedEntryId == null) return null;
    final idx = flat.indexWhere((e) => e.id == _focusedEntryId);
    return idx >= 0 ? flat[idx] : null;
  }

  /// Handles a tap/click on a list entry, interpreting modifier keys for
  /// Ctrl+click (toggle), Shift+click (range select), and plain click.
  void _handleEntryTap(HistoryEntry entry, List<HistoryEntry> filteredEntries) {
    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

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
      final flatIds = filteredEntries.map((e) => e.id).toList();
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
        _focusedEntryId = entry.id;
        _lastClickedId = entry.id;
      });
    }
    // Ensure list focus node has focus so keyboard shortcuts work after any
    // click interaction. If the detail panel opens, it will subsequently claim
    // focus (as a descendant, so list shortcuts still work via event bubbling).
    _listFocusNode.requestFocus();
  }

  /// Handles bare-key events on the list focus node (arrows, enter, delete,
  /// escape, F). Returns [KeyEventResult.ignored] when a text field has focus
  /// so [DefaultTextEditingShortcuts] can process the keys normally.
  KeyEventResult _handleListKeyEvent(
    FocusNode node,
    KeyEvent event,
    List<HistoryEntry> flat,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isTextFieldFocused()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(1, flat);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1, flat);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final entry = _focusedEntry(flat);
      if (entry != null) _copyEntry(entry);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_multiSelectMode && _selectedIds.isNotEmpty) {
        _deleteSelected();
      } else {
        final entry = _focusedEntry(flat);
        if (entry != null) _deleteEntry(entry);
      }
      return KeyEventResult.handled;
    }
    // F: Toggle favourite on focused entry
    if (key == LogicalKeyboardKey.keyF) {
      final entry = _focusedEntry(flat);
      if (entry != null) _togglePin(entry);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_multiSelectMode) {
        setState(() {
          _selectedIds.clear();
          _multiSelectMode = false;
        });
      } else if (_selectedEntryId != null) {
        setState(() => _selectedEntryId = null);
      } else if (_focusedEntryId != null) {
        setState(() => _focusedEntryId = null);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Builds the content area when [groupedHistoryProvider] has data.
  Widget _buildLoadedView(
    BuildContext context,
    List<DateGroup> groups,
    List<HistoryEntry> filteredEntries,
    HistoryEntry? selectedEntry,
    bool isDark,
    bool isTrashView,
    bool isArchiveView,
  ) {
    final sortedGroups = _sortGroups(groups);
    final flat = _flatEntries(groups);

    return CallbackShortcuts(
      // Only modifier-combo shortcuts remain here.
      // Bare keys (arrows, enter, delete, backspace, escape, F)
      // are handled in Focus.onKeyEvent below so they can return
      // KeyEventResult.ignored when a text field has focus, allowing
      // DefaultTextEditingShortcuts to handle them for text editing.
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+A: Select all visible items
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          if (_isTextFieldFocused()) return;
          setState(() {
            _multiSelectMode = true;
            _selectedIds
              ..clear()
              ..addAll(flat.map((e) => e.id));
          });
        },
        // Ctrl+Shift+A: Deselect all
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
          shift: true,
        ): () {
          if (_isTextFieldFocused()) return;
          setState(() {
            _selectedIds.clear();
            _multiSelectMode = false;
          });
        },
        // Ctrl+C: Copy focused/selected entry text (suppressed when editing)
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (_isTextFieldFocused()) return;
          if (_multiSelectMode && _selectedIds.isNotEmpty) {
            _copySelectedEntries(flat);
          } else {
            final entry = selectedEntry ?? _focusedEntry(flat);
            if (entry != null) _copyEntry(entry);
          }
        },
        // Ctrl+M: Merge selected entries
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () {
          if (_isTextFieldFocused()) return;
          if (_multiSelectMode && _selectedIds.length >= 2) {
            _mergeSelected();
          }
        },
        // Ctrl+Enter: open detail panel for focused entry
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_isTextFieldFocused()) return;
          final entry = _focusedEntry(flat);
          if (entry != null) {
            setState(() {
              _selectedEntryId = entry.id;
              _lastClickedId = entry.id;
            });
          }
        },
      },
      child: Focus(
        focusNode: _listFocusNode,
        autofocus: true,
        // Bare-key shortcuts are handled here via onKeyEvent so that
        // KeyEventResult.ignored can be returned when a text field has
        // focus. CallbackShortcuts always consumes matched events
        // (VoidCallbackAction.consumesKey == true), which would prevent
        // DefaultTextEditingShortcuts from processing Backspace/Enter/etc.
        onKeyEvent: (node, event) => _handleListKeyEvent(node, event, flat),
        child: GestureDetector(
          onTap: () => _listFocusNode.requestFocus(),
          behavior: HitTestBehavior.translucent,
          child: HistorySplitView(
            groups: sortedGroups,
            isDark: isDark,
            viewMode: _viewMode,
            selectedEntry: selectedEntry,
            focusedId: _focusedEntryId,
            multiSelectMode: _multiSelectMode,
            selectedIds: _selectedIds,
            isTrashView: isTrashView,
            isArchiveView: isArchiveView,
            exportFn: widget.exportFn,
            onEntryTap: (entry) => _handleEntryTap(entry, filteredEntries),
            onCopy: _copyEntry,
            onPin: _togglePin,
            onDelete: _deleteEntry,
            onArchive: _archiveEntry,
            onRestore: _restoreEntry,
            onDuplicate: _duplicateEntry,
            onCopyMarkdown: _copyAsMarkdown,
            onCloseDetail: () => setState(() => _selectedEntryId = null),
            onTagTap: (tag) {
              _searchController.text = '#$tag';
              ref.read(historySearchProvider.notifier).set('#$tag');
              _searchFocusNode.unfocus();
              setState(() {
                _selectedEntryId = null;
                _focusedEntryId = null;
              });
            },
          ),
        ),
      ),
    );
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
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // Ctrl+F / Cmd+F: Focus search field
          SingleActivator(
            LogicalKeyboardKey.keyF,
            control: !Platform.isMacOS,
            meta: Platform.isMacOS,
          ): () {
            _searchFocusNode.requestFocus();
          },
        },
        child: Focus(
          autofocus: false,
          child: Column(
            children: [
              // Multi-select action bar (shown when items are selected)
              if (_multiSelectMode && _selectedIds.isNotEmpty)
                HistoryMultiSelectBar(
                  selectedCount: _selectedIds.length,
                  totalCount: filteredEntries.length,
                  isDark: isDark,
                  isTrashView: isTrashView,
                  isArchiveView: isArchiveView,
                  onMerge: _selectedIds.length >= 2 ? _mergeSelected : null,
                  onBatchCopy: _selectedIds.isNotEmpty
                      ? () => _copySelectedEntries(filteredEntries)
                      : null,
                  onExport: _selectedIds.isNotEmpty
                      ? () => _exportSelectedEntries(filteredEntries)
                      : null,
                  onArchive: !isTrashView ? _archiveSelected : null,
                  onDelete: _deleteSelected,
                  onRestore: isTrashView ? _restoreSelected : null,
                  onSelectAll: () => setState(() {
                    if (_selectedIds.length >= filteredEntries.length) {
                      // All selected → deselect all
                      _selectedIds.clear();
                      _multiSelectMode = false;
                    } else {
                      // Select all visible
                      _selectedIds
                        ..clear()
                        ..addAll(filteredEntries.map((e) => e.id));
                    }
                  }),
                  onCancelSelection: () => setState(() {
                    _multiSelectMode = false;
                    _selectedIds.clear();
                  }),
                ),
              // Search & filter bar
              if (!_multiSelectMode || _selectedIds.isEmpty)
                HistorySearchFilterBar(
                  controller: _searchController,
                  searchFocusNode: _searchFocusNode,
                  activeFilter: activeFilter,
                  isDark: isDark,
                  onFilterChanged: (f) {
                    ref.read(historyFilterProvider.notifier).set(f);
                    setState(() {
                      _multiSelectMode = false;
                      _selectedIds.clear();
                      _selectedEntryId = null;
                      _focusedEntryId = null;
                    });
                    _listFocusNode.requestFocus();
                  },
                  onSearchChanged: () {
                    ref
                        .read(historySearchProvider.notifier)
                        .set(_searchController.text);
                    // Clear all selection state when search changes so the detail
                    // panel closes and keyboard navigation resets.
                    setState(() {
                      _selectedIds.clear();
                      _multiSelectMode = false;
                      _selectedEntryId = null;
                      _focusedEntryId = null;
                    });
                  },
                  resultCount: filteredEntries.length,
                  viewMode: _viewMode,
                  onViewModeChanged: (m) => setState(() => _viewMode = m),
                  multiSelectMode: _multiSelectMode,
                  onToggleMultiSelect: () => setState(() {
                    _multiSelectMode = !_multiSelectMode;
                    if (!_multiSelectMode) _selectedIds.clear();
                  }),
                  sortOrder: _sortOrder,
                  onSortOrderChanged: (s) => setState(() => _sortOrder = s),
                  onEmptyTrash: isTrashView && filteredEntries.isNotEmpty
                      ? _emptyTrash
                      : null,
                ),
              // Master-detail content
              Expanded(
                child: groupedAsync.when(
                  data: (groups) {
                    if (groups.isEmpty) {
                      return _emptyStateForFilter(isDark, activeFilter);
                    }
                    return _buildLoadedView(
                      context,
                      groups,
                      filteredEntries,
                      selectedEntry,
                      isDark,
                      isTrashView,
                      isArchiveView,
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _emptyStateForFilter(isDark, activeFilter),
                ),
              ),
            ],
          ),
        ),
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
        actionLabel: l10n.historyClearSearch,
        onAction: () {
          _searchController.clear();
        },
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
    if (activeFilter == HistoryFilter.pinned) {
      return WpEmptyState(
        icon: LucideIcons.star,
        title: l10n.historyNoPinned,
        hint: l10n.historyNoPinnedHint,
      );
    }
    if (activeFilter == HistoryFilter.today) {
      return WpEmptyState(
        icon: LucideIcons.calendar,
        title: l10n.historyNoToday,
        hint: l10n.historyNoTodayHint,
      );
    }
    if (activeFilter == HistoryFilter.week) {
      return WpEmptyState(
        icon: LucideIcons.calendarRange,
        title: l10n.historyNoThisWeek,
        hint: l10n.historyNoThisWeekHint,
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

  void _togglePin(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).togglePin(entry.id);
      // Refresh detail panel if this entry is shown (Finding #3)
      ref.invalidate(historyDetailProvider(entry.id));
    } catch (e) {
      _showHistoryWriteFailedToast();
    }
  }

  void _deleteEntry(HistoryEntry entry) async {
    final isTrash = ref.read(historyFilterProvider) == HistoryFilter.trash;
    try {
      if (isTrash) {
        await ref.read(historyDatabaseProvider).permanentDeleteEntry(entry.id);
      } else {
        await ref.read(historyDatabaseProvider).softDeleteEntry(entry.id);
      }
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
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

  void _archiveEntry(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).toggleArchive(entry.id);
      ref.invalidate(historyDetailProvider(entry.id));
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    if (_selectedEntryId == entry.id) {
      setState(() => _selectedEntryId = null);
    }
  }

  void _restoreEntry(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).restoreEntry(entry.id);
      ref.invalidate(historyDetailProvider(entry.id));
    } catch (e) {
      _showHistoryWriteFailedToast();
    }
  }

  void _duplicateEntry(HistoryEntry entry) async {
    try {
      final dup = await ref
          .read(historyDatabaseProvider)
          .duplicateEntry(entry.id);
      if (!mounted || dup == null) return;
      setState(() => _selectedEntryId = dup.id);
      WpToast.show(
        context,
        message: L10n.of(context).historyDuplicated,
        type: WpToastType.success,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      _showHistoryWriteFailedToast();
    }
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
      '**Date:** ${DateFormat.yMMMd().add_Hm().format(entry.timestamp)}',
    );
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

  void _mergeSelected() async {
    if (_selectedIds.length < 2) return;
    final l10n = L10n.of(context);

    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.historyMergeConfirm(_selectedIds.length),
      message: l10n.historyMergeConfirmMessage,
      confirmLabel: l10n.historyMerge,
      cancelLabel: l10n.actionCancel,
    );
    if (!confirmed || !mounted) return;

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
        message: l10n.historyEntriesMerged,
        type: WpToastType.success,
        duration: const Duration(seconds: 2),
      );
    });
  }

  void _archiveSelected() async {
    final db = ref.read(historyDatabaseProvider);
    try {
      await db.batchArchive(_selectedIds.toList());
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
    });
  }

  void _deleteSelected() async {
    final db = ref.read(historyDatabaseProvider);
    final isTrash = ref.read(historyFilterProvider) == HistoryFilter.trash;
    try {
      if (isTrash) {
        await db.batchPermanentDelete(_selectedIds.toList());
      } else {
        await db.softDeleteEntries(_selectedIds.toList());
      }
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
    });
  }

  void _restoreSelected() async {
    final db = ref.read(historyDatabaseProvider);
    try {
      await db.batchRestore(_selectedIds.toList());
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
    });
  }

  /// Run the export flow for the currently selected entries.
  ///
  /// Delegates to [HistoryPage.exportFn] (default: `exportEntries` from the
  /// `HistoryExporter` service). The exporter manages picker + toast + path
  /// resolution itself; nothing else to do here.
  void _exportSelectedEntries(List<HistoryEntry> flat) {
    final selected = flat.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;
    // Fire-and-forget: the exporter surfaces success/error via WpToast.
    widget.exportFn(context, selected);
  }

  /// Copy all selected entries' text to clipboard (joined by double newline).
  void _copySelectedEntries(List<HistoryEntry> flat) {
    final selected = flat.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;
    final text = selected.map((e) => e.content).join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).historyCopiedToClipboard,
      type: WpToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  /// Shows the PRD-spec actionable toast for a history-write failure
  /// (most often a final `SqliteException(5) database is locked` after
  /// the `SqliteWriteCoordinator` retry budget is exhausted, mapped to
  /// the [historyWriteFailed] Sentry fingerprint).
  ///
  /// The „Diagnose kopieren" action copies a compact one-liner with the
  /// app version, platform and the canonical fingerprint string into the
  /// clipboard so the user can paste it into a bug report. Sentry's own
  /// event-ID is intentionally not surfaced here — the capture happens
  /// inside the write coordinator and that path does not expose the ID
  /// back to the UI; the fingerprint plus a timestamp is enough for the
  /// maintainer to correlate.
  void _showHistoryWriteFailedToast() {
    if (!mounted) return;
    final l10n = L10n.of(context);
    WpToast.show(
      context,
      message: l10n.historyWriteFailedToast,
      type: WpToastType.error,
      duration: const Duration(seconds: 6),
      // loam-ignore: a11y-interactive-semantics – WpToastAction is a data class; the TextButton in _ToastCard.build uses its child Text as the accessible label
      action: WpToastAction(
        label: l10n.historyWriteFailedAction,
        onPressed: _copyHistoryWriteDiagnostics,
      ),
    );
  }

  void _copyHistoryWriteDiagnostics() {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final diag = StringBuffer()
      ..writeln('WhisPaste diagnostics')
      ..writeln('fingerprint: $historyWriteFailed')
      ..writeln('app: $appName $appVersion')
      ..writeln(
        'platform: ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}',
      )
      ..writeln('locale: ${Platform.localeName}')
      ..writeln('timestamp: $timestamp');
    Clipboard.setData(ClipboardData(text: diag.toString()));
  }

  /// Permanently delete all items in trash after confirmation.
  Future<void> _emptyTrash() async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.historyEmptyTrashConfirm,
      message: l10n.historyEmptyTrashConfirmMessage,
      confirmLabel: l10n.historyEmptyTrash,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final count = await ref.read(historyDatabaseProvider).emptyTrash();
    if (!mounted) return;
    WpToast.show(
      context,
      message: '${l10n.historyTrashEmptied} ($count)',
      type: WpToastType.success,
      duration: const Duration(seconds: 2),
    );
    // Reset selection state
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
      _selectedEntryId = null;
    });
  }
}
