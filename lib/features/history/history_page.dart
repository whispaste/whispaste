import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/dialog.dart';
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

  /// Keyboard-focused entry ID (distinct from selected/detail entry).
  String? _focusedEntryId;
  final FocusNode _listFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  /// Builds a flat list of entry IDs from the grouped data for keyboard
  /// navigation ordering.
  List<HistoryEntry> _flatEntries(List<DateGroup> groups) {
    return [for (final g in groups) ...g.entries];
  }

  void _moveFocus(int delta, List<HistoryEntry> flat) {
    if (flat.isEmpty) return;
    final currentIdx =
        flat.indexWhere((e) => e.id == _focusedEntryId);
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
              totalCount: filteredEntries.length,
              isDark: isDark,
              isTrashView: isTrashView,
              isArchiveView: isArchiveView,
              onMerge: _selectedIds.length >= 2 ? _mergeSelected : null,
              onBatchCopy: _selectedIds.isNotEmpty
                  ? () => _copySelectedEntries(filteredEntries)
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
                _listFocusNode.requestFocus();
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
              onEmptyTrash: isTrashView && filteredEntries.isNotEmpty
                  ? _emptyTrash
                  : null,
            ),
          // Master-detail content
          Expanded(
            child: groupedAsync.when(
              data: (groups) {
                final hasResults = groups.isNotEmpty;
                if (!hasResults) {
                  return _emptyStateForFilter(isDark, activeFilter);
                }
                final flat = _flatEntries(groups);
                return CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _moveFocus(1, flat),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _moveFocus(-1, flat),
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      final entry = _focusedEntry(flat);
                      if (entry != null) {
                        setState(() {
                          _selectedEntryId = entry.id;
                          _lastClickedId = entry.id;
                        });
                      }
                    },
                    const SingleActivator(LogicalKeyboardKey.delete): () {
                      if (_multiSelectMode && _selectedIds.isNotEmpty) {
                        _deleteSelected();
                      } else {
                        final entry = _focusedEntry(flat);
                        if (entry != null) _deleteEntry(entry);
                      }
                    },
                    const SingleActivator(LogicalKeyboardKey.backspace): () {
                      if (_multiSelectMode && _selectedIds.isNotEmpty) {
                        _deleteSelected();
                      } else {
                        final entry = _focusedEntry(flat);
                        if (entry != null) _deleteEntry(entry);
                      }
                    },
                    // Ctrl+A: Select all visible items
                    const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
                      setState(() {
                        _multiSelectMode = true;
                        _selectedIds
                          ..clear()
                          ..addAll(flat.map((e) => e.id));
                      });
                    },
                    // Ctrl+Shift+A or Ctrl+D: Deselect all
                    const SingleActivator(
                      LogicalKeyboardKey.keyA, control: true, shift: true,
                    ): () {
                      setState(() {
                        _selectedIds.clear();
                        _multiSelectMode = false;
                      });
                    },
                    // Ctrl+C: Copy focused/selected entry text
                    const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
                      if (_multiSelectMode && _selectedIds.isNotEmpty) {
                        _copySelectedEntries(flat);
                      } else {
                        final entry = selectedEntry ?? _focusedEntry(flat);
                        if (entry != null) _copyEntry(entry);
                      }
                    },
                    // Ctrl+M: Merge selected entries
                    const SingleActivator(LogicalKeyboardKey.keyM, control: true): () {
                      if (_multiSelectMode && _selectedIds.length >= 2) {
                        _mergeSelected();
                      }
                    },
                    // F: Toggle favorite on focused entry
                    const SingleActivator(LogicalKeyboardKey.keyF): () {
                      final entry = _focusedEntry(flat);
                      if (entry != null) _togglePin(entry);
                    },
                    const SingleActivator(LogicalKeyboardKey.escape): () {
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
                    },
                    const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
                      final entry = selectedEntry ?? _focusedEntry(flat);
                      if (entry != null) _openCommandPalette(entry);
                    },
                  },
                  child: Focus(
                    focusNode: _listFocusNode,
                    autofocus: true,
                    child: GestureDetector(
                      onTap: () => _listFocusNode.requestFocus(),
                      behavior: HitTestBehavior.translucent,
                      child: HistoryMasterDetail(
                        groups: groups,
                        isDark: isDark,
                        viewMode: _viewMode,
                        selectedEntry: selectedEntry,
                        focusedId: _focusedEntryId,
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
                              _focusedEntryId = entry.id;
                              _lastClickedId = entry.id;
                            });
                          }
                          // Ensure list focus node has focus so keyboard
                          // shortcuts work after any click interaction.
                          // If detail panel opens, it will subsequently
                          // claim focus (as a descendant, so list shortcuts
                          // still work via event bubbling).
                          _listFocusNode.requestFocus();
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
                      ),
                    ),
                  ),
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

  // ---------------------------------------------------------------------------
  // Command Palette
  // ---------------------------------------------------------------------------

  void _openCommandPalette(HistoryEntry entry) {
    final l10n = L10n.of(context);
    final isPinned = entry.pinned;
    final isArchived = entry.archived;

    final commands = <WpCommand>[
      WpCommand(
        id: 'copy',
        label: l10n.historyCopyText,
        icon: LucideIcons.copy,
        shortcutHint: 'Ctrl+C',
        onExecute: () => _copyEntry(entry),
      ),
      WpCommand(
        id: 'edit',
        label: l10n.historyEditTranscript,
        icon: LucideIcons.pencil,
        shortcutHint: 'Ctrl+E',
        onExecute: () {
          // Open detail panel and toggle edit mode by selecting the entry
          setState(() => _selectedEntryId = entry.id);
        },
      ),
      WpCommand(
        id: 'add-tag',
        label: l10n.historyAddTag,
        icon: LucideIcons.tag,
        shortcutHint: 'T',
        onExecute: () {
          setState(() => _selectedEntryId = entry.id);
        },
      ),
      WpCommand(
        id: 'add-note',
        label: l10n.historyAddNote,
        icon: LucideIcons.stickyNote,
        shortcutHint: 'N',
        onExecute: () {
          setState(() => _selectedEntryId = entry.id);
        },
      ),
      WpCommand(
        id: 'toggle-pin',
        label: isPinned ? l10n.historyUnpin : l10n.historyPinToTop,
        icon: isPinned ? LucideIcons.starOff : LucideIcons.star,
        shortcutHint: 'F',
        onExecute: () => _togglePin(entry),
      ),
      WpCommand(
        id: 'toggle-archive',
        label: isArchived ? l10n.historyUnarchive : l10n.historyArchive,
        icon: isArchived ? LucideIcons.archiveRestore : LucideIcons.archive,
        onExecute: () => _archiveEntry(entry),
      ),
      WpCommand(
        id: 'duplicate',
        label: l10n.historyDuplicate,
        icon: LucideIcons.copyPlus,
        onExecute: () => _duplicateEntry(entry),
      ),
      WpCommand(
        id: 'export-text',
        label: l10n.commandPaletteExportText,
        icon: LucideIcons.fileDown,
        onExecute: () => _exportAsText(entry),
      ),
      WpCommand(
        id: 'copy-markdown',
        label: l10n.historyCopyAsMarkdown,
        icon: LucideIcons.fileCode,
        onExecute: () => _copyAsMarkdown(entry),
      ),
      WpCommand(
        id: 'delete',
        label: l10n.actionDelete,
        icon: LucideIcons.trash2,
        shortcutHint: 'Del',
        onExecute: () => _deleteEntry(entry),
      ),
    ];

    showWpCommandPalette(context: context, commands: commands);
  }

  Future<void> _exportAsText(HistoryEntry entry) async {
    try {
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final safeName = (entry.title.isNotEmpty ? entry.title : 'transcription')
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .trim();
      final timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(entry.timestamp);
      final file = File('${dir.path}${Platform.pathSeparator}${safeName}_$timestamp.txt');
      await file.writeAsString(entry.content);
      if (!mounted) return;
      WpToast.show(
        context,
        message: L10n.of(context).commandPaletteExported(file.path),
        type: WpToastType.success,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      if (!mounted) return;
      WpToast.show(
        context,
        message: e.toString(),
        type: WpToastType.error,
        duration: const Duration(seconds: 3),
      );
    }
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