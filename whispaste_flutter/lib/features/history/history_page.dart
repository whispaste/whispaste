import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/toast.dart';
import 'package:whispaste/core/data/database.dart';
import 'data/providers.dart';
import 'widgets/widgets.dart';

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
  HistoryViewMode _viewMode = HistoryViewMode.list;
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
            HistoryMultiSelectBar(
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
            HistorySearchToolbar(
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
                return HistoryMasterDetail(
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

  void _mergeSelected() async {
    if (_selectedIds.length < 2) return;
    final l10n = L10n.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.historyMergeConfirm(_selectedIds.length)),
        content: Text(l10n.historyMergeConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.historyMerge),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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