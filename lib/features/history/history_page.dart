import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/first_steps/first_steps_notifier.dart';
import '../../core/app_info.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/crash_fingerprints.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/focus_helpers.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_list_skeleton.dart';

import 'package:whispaste/core/data/database.dart';

import '../../services/audio/import/audio_import_providers.dart';
import '../../services/pending_audio/pending_audio_providers.dart';
import '../../services/clipboard_history/app_clipboard.dart';
import '../../services/history/history_exporter.dart' as history_exporter;
import 'data/history_detail_provider.dart';
import 'data/history_lock.dart';
import 'data/providers.dart';
import 'widgets/audio_import_drop_zone.dart';
import 'widgets/audio_import_panel.dart';
import 'widgets/recovery_banner.dart';
import 'widgets/history_status_row.dart';
import 'widgets/history_pin_dialogs.dart';
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

/// Placeholder-bar height of the loading skeleton, matched to the real
/// [HistoryEntryRow]. Measured at a 340 dp list column: 123 dp with the
/// two-line preview, 48 dp action targets and the whole metadata line.
/// 120 tracks the populated case — the one a skeleton has to reserve for —
/// on the repo's 8 dp rhythm. The former 52 reserved less than half a row.
const _historySkeletonRowHeight = 120.0;

/// Key of the privacy gate the page shows instead of entries while
/// `HistorySettings.historyHideOnOpen` is on and the user has not revealed
/// the history yet.
@visibleForTesting
const kHistoryPrivacyGateKey = Key('historyPrivacyGate');
const kHistoryImportRequestHintKey = Key('historyImportRequestHint');

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
  static final _log = AppLogger('HistoryPage');
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpenEntry());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  /// Consumes a pending deep link to one recording ([historyOpenEntryProvider])
  /// and shows it in the detail.
  void _applyOpenEntry() {
    if (!mounted) return;
    final id = ref.read(historyOpenEntryProvider);
    if (id == null) return;
    ref.read(historyOpenEntryProvider.notifier).set(null);
    setState(() {
      _selectedEntryId = id;
      _focusedEntryId = id;
      _lastClickedId = id;
    });
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

  // loam-ignore: code-duplicates – twin of `_moveFocus` in notes_page.dart; the list cursor logic is intentionally kept per page
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
  ///
  /// [orderedEntries] must be in *display* order (sort applied), because the
  /// Shift+click range is defined by what sits between the two clicks on
  /// screen.
  void _handleEntryTap(HistoryEntry entry, List<HistoryEntry> orderedEntries) {
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
      final flatIds = orderedEntries.map((e) => e.id).toList();
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
    if (isTextFieldFocused()) return KeyEventResult.ignored;

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
        if (entry != null) {
          _deleteEntry(entry, focusAfter: _neighbourEntryId(flat, entry.id));
        }
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
        _leaveSelection();
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
    List<DateGroup> groups,
    List<HistoryEntry> filteredEntries,
    HistoryEntry? selectedEntry,
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
        // Ctrl+A / Cmd+A: Select all visible items
        SingleActivator(
          LogicalKeyboardKey.keyA,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          if (isTextFieldFocused()) return;
          setState(() {
            _multiSelectMode = true;
            _selectedIds
              ..clear()
              ..addAll(flat.map((e) => e.id));
          });
        },
        // Ctrl+Shift+A / Cmd+Shift+A: Deselect all
        SingleActivator(
          LogicalKeyboardKey.keyA,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
          shift: true,
        ): () {
          if (isTextFieldFocused()) return;
          setState(() {
            _selectedIds.clear();
            _multiSelectMode = false;
          });
        },
        // Ctrl+C / Cmd+C: Copy focused/selected entry text (suppressed when editing)
        SingleActivator(
          LogicalKeyboardKey.keyC,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          if (isTextFieldFocused()) return;
          if (_multiSelectMode && _selectedIds.isNotEmpty) {
            _copySelectedEntries(flat);
          } else {
            final entry = selectedEntry ?? _focusedEntry(flat);
            if (entry != null) _copyEntry(entry);
          }
        },
        // Ctrl+M on every platform, including macOS: Merge selected entries.
        // Deliberately NOT meta-on-macOS like the siblings above — Cmd+M is
        // the system "Minimize Window" shortcut (see MainMenu.xib), so
        // binding it here would either never fire or fight the OS. The
        // literal Control key has no such conflict on macOS.
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () {
          if (isTextFieldFocused()) return;
          if (_multiSelectMode && _selectedIds.length >= 2) {
            _mergeSelected();
          }
        },
        // Ctrl+Enter / Cmd+Enter: open detail panel for focused entry
        SingleActivator(
          LogicalKeyboardKey.enter,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): () {
          if (isTextFieldFocused()) return;
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
            viewMode: _viewMode,
            selectedEntry: selectedEntry,
            focusedId: _focusedEntryId,
            multiSelectMode: _multiSelectMode,
            selectedIds: _selectedIds,
            isTrashView: isTrashView,
            isArchiveView: isArchiveView,
            exportFn: widget.exportFn,
            // `flat`, not `filteredEntries`: the range Shift+click selects has
            // to be the range the user sees between the two clicks, and only
            // `flat` has the current sort order applied (_flatEntries →
            // _applySortOrder, the same list the arrow keys walk).
            // `filteredEntries` is raw provider order, so with sort = oldest
            // or longest a Shift+click quietly selected a different set of
            // entries than the one highlighted on screen — and the next batch
            // Delete acted on that set.
            onEntryTap: (entry) => _handleEntryTap(entry, flat),
            onCopy: _copyEntry,
            onPin: _togglePin,
            onDelete: (entry) => _deleteEntry(entry),
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

  /// The gate shown in place of the entries while `historyHideOnOpen` is on
  /// or a History PIN is set, until the history is revealed; `null` when the
  /// entries may be shown. With a PIN it asks for it instead of offering a
  /// plain "Show history" button.
  Widget? _buildPrivacyGate(BuildContext context) {
    final history = ref.watch(settingsProvider).value?.history;
    final hasPin = history?.historyPin.isNotEmpty ?? false;
    final hideOnOpen = history?.historyHideOnOpen ?? false;
    if (!(hideOnOpen || hasPin) || ref.watch(historyRevealedProvider)) {
      return null;
    }
    final l10n = L10n.of(context);
    final importWaiting = ref.watch(audioImportRequestPendingProvider);
    final gate = hasPin
        ? WpEmptyState(
            key: kHistoryPrivacyGateKey,
            icon: LucideIcons.lock,
            title: l10n.historyPinGateTitle,
            hint: l10n.historyPinGateHint,
            actionLabel: l10n.historyPinUnlock,
            onAction: () =>
                showHistoryPinUnlockDialog(context, offerForgot: true),
          )
        : WpEmptyState(
            key: kHistoryPrivacyGateKey,
            icon: LucideIcons.eyeOff,
            title: l10n.historyPrivacyGateTitle,
            hint: l10n.historyPrivacyGateHint,
            actionLabel: l10n.historyPrivacyGateShow,
            onAction: () => ref.read(historyRevealedProvider.notifier).reveal(),
          );
    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(child: gate),
          if (importWaiting)
            Padding(
              padding: const EdgeInsets.all(WpSpacing.md),
              child: Semantics(
                identifier: 'history-import-request-hint',
                child: Text(
                  l10n.historyImportUnlockHint,
                  key: kHistoryImportRequestHintKey,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Any pointer or key input on the revealed page restarts the auto-lock
  /// countdown (`HistorySettings.historyAutoLockMinutes`).
  void _registerActivity() =>
      ref.read(historyRevealedProvider.notifier).registerActivity();

  /// Ends the multi-select mode. On a short window or at text scale 2.0 the
  /// selection bar takes the search row's place, so the search comes back
  /// with the focus in it (UX-097, compact mode).
  void _leaveSelection() {
    final focusSearch = historyHeadIsShort(context);
    setState(() {
      _multiSelectMode = false;
      _selectedIds.clear();
    });
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // A deep link may arrive while the page is already open.
    ref.listen(historyOpenEntryProvider, (_, id) {
      if (id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpenEntry());
      }
    });
    final privacyGate = _buildPrivacyGate(context);
    if (privacyGate != null) return privacyGate;
    return Listener(
      onPointerDown: (_) => _registerActivity(),
      onPointerSignal: (_) => _registerActivity(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, _) {
          _registerActivity();
          return KeyEventResult.ignored;
        },
        child: _buildHistory(context),
      ),
    );
  }

  /// Drops selected ids that the current results do not show (UIA-HIS-17), so
  /// batch actions never reach entries the user cannot see. Runs only once the
  /// results have loaded, never on the stale list of the previous query.
  void _dropSelectionOutsideResults(
    AsyncValue<List<HistoryEntry>> filteredAsync,
    List<HistoryEntry> filteredEntries,
  ) {
    if (_selectedIds.isEmpty || filteredAsync.isLoading) return;
    final visible = {for (final e in filteredEntries) e.id};
    final hidden = _selectedIds.where((id) => !visible.contains(id)).toList();
    if (hidden.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIds.removeAll(hidden);
        if (_selectedIds.isEmpty) _multiSelectMode = false;
      });
    });
  }

  Widget _buildHistory(BuildContext context) {
    final activeFilter = ref.watch(historyFilterProvider);
    final groupedAsync = ref.watch(groupedHistoryProvider);
    final filteredAsync = ref.watch(filteredHistoryProvider);
    final isTrashView = activeFilter == HistoryFilter.trash;
    final isArchiveView = activeFilter == HistoryFilter.archived;

    // Resolve the flat filtered list (for selection lookup & shift-click)
    final filteredEntries = filteredAsync.value ?? [];
    _dropSelectionOutsideResults(filteredAsync, filteredEntries);

    // Look up selected entry from current filtered list
    HistoryEntry? selectedEntry;
    if (_selectedEntryId != null) {
      final idx = filteredEntries.indexWhere((e) => e.id == _selectedEntryId);
      selectedEntry = idx >= 0 ? filteredEntries[idx] : null;
    }

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: AudioImportDropZone(
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
            child: LayoutBuilder(
              builder: (context, _) => Column(
                children: [
                  // Everything above the list is one column that takes its
                  // content height and never scrolls: the search bar stays in
                  // view and the header has one scroll owner or none (UX-097,
                  // UX-098). Its sections are one summary line each; the
                  // expanded sections show at most two rows inline.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Multi-select action bar (shown when items are selected)
                      if (_multiSelectMode && _selectedIds.isNotEmpty)
                        HistoryMultiSelectBar(
                          selectedCount: _selectedIds.length,
                          totalCount: filteredEntries.length,
                          isTrashView: isTrashView,
                          isArchiveView: isArchiveView,
                          onMerge: _selectedIds.length >= 2
                              ? _mergeSelected
                              : null,
                          onBatchCopy: _selectedIds.isNotEmpty
                              ? () => _copySelectedEntries(filteredEntries)
                              : null,
                          onBatchCopyMarkdown: _selectedIds.isNotEmpty
                              ? () => _copySelectedEntriesAsMarkdown(
                                  filteredEntries,
                                )
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
                          onCancelSelection: _leaveSelection,
                        ),
                      const HistoryStatusRow(),
                      const RecoveryBanner(),
                      const AudioImportPanel(),
                      // Search & filter bar. Stays up while selecting so the search
                      // can be narrowed without giving the selection up (UIA-HIS-17).
                      // Compact mode: the selection bar replaces the search row while
                      // entries are selected. Escape or "Cancel selection" brings
                      // the search back with the focus in it.
                      if (!(historyHeadIsShort(context) &&
                          _multiSelectMode &&
                          _selectedIds.isNotEmpty))
                        HistorySearchFilterBar(
                          controller: _searchController,
                          searchFocusNode: _searchFocusNode,
                          activeFilter: activeFilter,
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
                            // The selection survives a search change; entries the new
                            // results no longer show are dropped once they load (UIA-HIS-17).
                            // The detail panel and keyboard focus still reset.
                            setState(() {
                              _selectedEntryId = null;
                              _focusedEntryId = null;
                            });
                          },
                          resultCount: filteredEntries.length,
                          viewMode: _viewMode,
                          onViewModeChanged: (m) =>
                              setState(() => _viewMode = m),
                          multiSelectMode: _multiSelectMode,
                          onToggleMultiSelect: () => setState(() {
                            _multiSelectMode = !_multiSelectMode;
                            if (!_multiSelectMode) _selectedIds.clear();
                          }),
                          sortOrder: _sortOrder,
                          onSortOrderChanged: (s) =>
                              setState(() => _sortOrder = s),
                          onEmptyTrash:
                              isTrashView && filteredEntries.isNotEmpty
                              ? _emptyTrash
                              : null,
                        ),
                    ],
                  ),
                  // Master-detail content
                  Expanded(
                    key: const ValueKey('history-list-area'),
                    child: groupedAsync.when(
                      data: (groups) {
                        if (groups.isEmpty) {
                          return _emptyStateForFilter(activeFilter);
                        }
                        return _buildLoadedView(
                          groups,
                          filteredEntries,
                          selectedEntry,
                          isTrashView,
                          isArchiveView,
                        );
                      },
                      loading: () => const WpListSkeleton(
                        rowHeight: _historySkeletonRowHeight,
                      ),
                      error: (e, _) {
                        final l10n = L10n.of(context);
                        return WpEmptyState(
                          icon: LucideIcons.triangleAlert,
                          title: l10n.errorGeneric,
                          actionLabel: l10n.actionRetry,
                          onAction: () => _retryFilter(activeFilter),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyStateForFilter(HistoryFilter activeFilter) {
    final l10n = L10n.of(context);
    if (_searchController.text.isNotEmpty) {
      return WpEmptyState(
        icon: LucideIcons.searchX,
        title: l10n.historyNoResults,
        hint: l10n.historyNoResultsHint(_searchController.text),
        actionLabel: l10n.actionClearSearch,
        onAction: () {
          _searchController.clear();
        },
      );
    }
    final saveHistory =
        ref.watch(settingsProvider).value?.history.saveHistory ?? true;
    if (!saveHistory && activeFilter == HistoryFilter.all) {
      // Saving is off and nothing is stored: say why, and offer the way to the
      // switch in Settings (the Recordings section, privacy page).
      return WpEmptyState(
        icon: LucideIcons.micOff,
        title: l10n.historyOffTitle,
        hint: l10n.historyOffHint,
        actionLabel: l10n.historyOffAction,
        onAction: () {
          ref
              .read(settingsScrollTargetProvider.notifier)
              .set('privacy-history-save');
          ref.read(activePageProvider.notifier).setPage('settings');
        },
      );
    }
    if (activeFilter == HistoryFilter.trash) {
      // The period the app really applies, so the copy cannot drift from the
      // setting (BIZ-15). 0 means the trash is never purged automatically.
      final trashDays =
          ref.watch(settingsProvider).value?.history.historyAutoTrashDays ??
          AppSettings.defaults.history.historyAutoTrashDays;
      return WpEmptyState(
        icon: LucideIcons.trash2,
        title: l10n.historyTrashEmpty,
        hint: l10n.historyTrashEmptyHint(trashDays),
      );
    }
    if (activeFilter == HistoryFilter.archived) {
      return WpEmptyState(
        icon: LucideIcons.archive,
        title: l10n.historyNoArchivedItems,
        hint: l10n.historyNoArchivedItemsHint,
        actionLabel: l10n.historyShowAll,
        onAction: () =>
            ref.read(historyFilterProvider.notifier).set(HistoryFilter.all),
      );
    }
    if (activeFilter == HistoryFilter.pinned) {
      return WpEmptyState(
        icon: LucideIcons.star,
        title: l10n.historyNoPinned,
        hint: l10n.historyNoPinnedHint,
        actionLabel: l10n.historyShowAll,
        onAction: () =>
            ref.read(historyFilterProvider.notifier).set(HistoryFilter.all),
      );
    }
    if (activeFilter == HistoryFilter.today) {
      return WpEmptyState(
        icon: LucideIcons.calendar,
        title: l10n.historyNoToday,
        hint: l10n.historyNoTodayHint,
        actionLabel: l10n.historyShowAll,
        onAction: () =>
            ref.read(historyFilterProvider.notifier).set(HistoryFilter.all),
      );
    }
    if (activeFilter == HistoryFilter.week) {
      return WpEmptyState(
        icon: LucideIcons.calendarRange,
        title: l10n.historyNoThisWeek,
        hint: l10n.historyNoThisWeekHint,
        actionLabel: l10n.historyShowAll,
        onAction: () =>
            ref.read(historyFilterProvider.notifier).set(HistoryFilter.all),
      );
    }
    return WpEmptyState(
      icon: LucideIcons.mic,
      title: l10n.historyEmpty,
      hint: l10n.historyNoRecordingsHint,
    );
  }

  void _copyEntry(HistoryEntry entry) {
    ref.read(firstStepsNotifierProvider.notifier).recordingCopied();
    copyToClipboardWithToast(
      context: context,
      ref: ref,
      text: entry.content,
      category: 'history',
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

  /// Asks before a permanent delete (trash only). The purge cannot be undone,
  /// so the dialog names how many entries it removes (UIA-HIS-01).
  Future<bool> _confirmPermanentDelete(int count) {
    final l10n = L10n.of(context);
    return showWpConfirmDialog(
      context: context,
      title: l10n.historyDeletePermanentlyConfirm,
      message: l10n.historyDeletePermanentlyConfirmMessage(count),
      confirmLabel: l10n.historyDeletePermanently,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
  }

  /// Deletes [entry]. [focusAfter] takes the keyboard focus when the focused
  /// entry is the one removed (UIA-HIS-08).
  /// Reloads the source of the filter that failed (UIA-HIS-11). Retrying the
  /// all-entries list left trash/archive/search errors in place.
  void _retryFilter(HistoryFilter filter) {
    switch (filter) {
      case HistoryFilter.trash:
        ref.invalidate(trashEntriesProvider);
      case HistoryFilter.archived:
        ref.invalidate(archivedEntriesProvider);
      default:
        ref.invalidate(historyEntriesProvider);
    }
    ref.invalidate(filteredHistoryProvider);
  }

  void _deleteEntry(HistoryEntry entry, {String? focusAfter}) async {
    final isTrash = ref.read(historyFilterProvider) == HistoryFilter.trash;
    if (isTrash) {
      if (!await _confirmPermanentDelete(1) || !mounted) return;
    }
    try {
      if (isTrash) {
        await ref.read(historyDatabaseProvider).permanentDeleteEntry(entry.id);
      } else {
        await ref.read(historyDatabaseProvider).softDeleteEntry(entry.id);
      }
      await ref.read(pendingAudioQueueProvider).discard(entry.id);
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_selectedEntryId == entry.id) _selectedEntryId = null;
      if (_focusedEntryId == entry.id) _focusedEntryId = focusAfter;
    });
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

  /// Archives or un-archives [entry], confirms the move and offers undo
  /// (UIA-HIS-25).
  void _archiveEntry(HistoryEntry entry) async {
    final archiving = !entry.archived;
    if (!await _toggleArchive(entry)) return;
    if (_selectedEntryId == entry.id) {
      setState(() => _selectedEntryId = null);
    }
    if (!mounted) return;
    WpToast.show(
      context,
      message: archiving
          ? L10n.of(context).historyArchived
          : L10n.of(context).historyRestored,
      type: WpToastType.info,
      duration: const Duration(seconds: 4),
      actionLabel: L10n.of(context).historyUndo,
      onAction: () => _toggleArchive(entry),
    );
  }

  Future<bool> _toggleArchive(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).toggleArchive(entry.id);
      ref.invalidate(historyDetailProvider(entry.id));
      return true;
    } catch (e) {
      _showHistoryWriteFailedToast();
      return false;
    }
  }

  /// Takes [entry] out of the trash and confirms it (UIA-HIS-25). Undo puts
  /// it back in the trash.
  void _restoreEntry(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).restoreEntry(entry.id);
      ref.invalidate(historyDetailProvider(entry.id));
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    if (!mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).historyRestored,
      type: WpToastType.success,
      duration: const Duration(seconds: 4),
      actionLabel: L10n.of(context).historyUndo,
      onAction: () => _moveToTrashQuietly(entry),
    );
  }

  Future<void> _moveToTrashQuietly(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).softDeleteEntry(entry.id);
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

  String _formatEntryAsMarkdown(HistoryEntry entry) =>
      formatHistoryEntryAsMarkdown(entry, L10n.of(context));

  void _copyAsMarkdown(HistoryEntry entry) {
    AppClipboard.setText(_formatEntryAsMarkdown(entry));
    if (!mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).historyCopiedAsMarkdown,
      type: WpToastType.success,
      duration: const Duration(seconds: 2),
    );
  }

  /// Copies all selected entries as Markdown, joined by a blank line.
  void _copySelectedEntriesAsMarkdown(List<HistoryEntry> flat) {
    final selected = flat.where((e) => _selectedIds.contains(e.id)).toList();
    if (selected.isEmpty) return;

    final md = selected.map(_formatEntryAsMarkdown).join('\n');
    AppClipboard.setText(md);
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
    } catch (e) {
      _log.debug('Failed to parse tags JSON (falling back to empty list): $e');
    }
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
      // Merging rewrites the selected entries into one, so it overwrites data.
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    final db = ref.read(historyDatabaseProvider);
    final ids = _selectedIds.toList();
    final HistoryEntry? merged;
    try {
      merged = await db.mergeEntries(ids);
    } catch (e) {
      // Keep the selection so the user can retry; say why nothing changed.
      _showHistoryWriteFailedToast();
      return;
    }
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
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
    });
  }

  void _archiveSelected() async {
    final db = ref.read(historyDatabaseProvider);
    final ids = _selectedIds.toList();
    final message = L10n.of(context).historyBulkArchived(ids.length);
    try {
      await db.batchArchive(ids);
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    _clearSelection();
    _showBulkUndoToast(message, ids);
  }

  /// Confirms a bulk action and offers to take it back (UIA-HIS-06).
  void _showBulkUndoToast(String message, List<String> ids) {
    if (!mounted) return;
    WpToast.show(
      context,
      message: message,
      type: WpToastType.info,
      duration: const Duration(seconds: 4),
      actionLabel: L10n.of(context).historyUndo,
      onAction: () => _undoBulkRestore(ids),
    );
  }

  void _undoBulkRestore(List<String> ids) async {
    try {
      await ref.read(historyDatabaseProvider).batchRestore(ids);
    } catch (e) {
      _showHistoryWriteFailedToast();
    }
  }

  void _deleteSelected() async {
    final db = ref.read(historyDatabaseProvider);
    final isTrash = ref.read(historyFilterProvider) == HistoryFilter.trash;
    if (isTrash) {
      final count = _selectedIds.length;
      if (!await _confirmPermanentDelete(count) || !mounted) return;
    }
    final ids = _selectedIds.toList();
    final message = L10n.of(context).historyBulkMovedToTrash(ids.length);
    try {
      final ids = _selectedIds.toList();
      if (isTrash) {
        await db.batchPermanentDelete(ids);
      } else {
        await db.softDeleteEntries(ids);
      }
      final queue = ref.read(pendingAudioQueueProvider);
      for (final id in ids) {
        await queue.discard(id);
      }
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    _clearSelection();
    // Permanent delete stays without undo; it was confirmed above.
    if (!isTrash) _showBulkUndoToast(message, ids);
  }

  void _restoreSelected() async {
    final db = ref.read(historyDatabaseProvider);
    final count = _selectedIds.length;
    try {
      await db.batchRestore(_selectedIds.toList());
    } catch (e) {
      _showHistoryWriteFailedToast();
      return;
    }
    _clearSelection();
    if (!mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).historyBulkRestored(count),
      type: WpToastType.success,
      duration: const Duration(seconds: 3),
    );
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
    AppClipboard.setText(text);
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
    // Count what the purge will delete, not the rows on screen: a search can
    // hide part of the trash, and the purge takes all of it (UX-028).
    final pending = await ref.read(historyDatabaseProvider).countTrash();
    if (!mounted) return;
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.historyEmptyTrashConfirm,
      message: l10n.historyEmptyTrashConfirmMessage(pending),
      confirmLabel: l10n.historyEmptyTrash,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final db = ref.read(historyDatabaseProvider);
    final trashedIds = await db.trashedEntryIds();
    final count = await db.emptyTrash();
    final queue = ref.read(pendingAudioQueueProvider);
    for (final id in trashedIds) {
      await queue.discard(id);
    }
    if (!mounted) return;
    WpToast.show(
      context,
      message: l10n.historyTrashEmptied(count),
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

/// The entry that takes the focus when [id] leaves the list: the row below,
/// or the row above when [id] is the last one.
String? _neighbourEntryId(List<HistoryEntry> flat, String id) {
  final idx = flat.indexWhere((e) => e.id == id);
  if (idx < 0 || flat.length < 2) return null;
  return idx + 1 < flat.length ? flat[idx + 1].id : flat[idx - 1].id;
}

/// The Markdown copy of one history entry, with field labels in [l10n].
String formatHistoryEntryAsMarkdown(HistoryEntry entry, L10n l10n) {
  final md = StringBuffer();
  md.writeln(
    '# ${entry.title.isNotEmpty ? entry.title : l10n.historyUntitled}',
  );
  md.writeln();
  md.writeln(entry.content);
  md.writeln();
  md.writeln('---');
  md.writeln();
  final tags = _HistoryPageState._parseTags(entry.tags);
  if (tags.isNotEmpty) {
    md.writeln(
      '**${l10n.historyMdTags}:** ${tags.map((t) => '#$t').join(', ')}',
    );
  }
  md.writeln(
    '**${l10n.historyMdDate}:** ${DateFormat.yMMMd().add_Hm().format(entry.timestamp)}',
  );
  if (entry.model.isNotEmpty) {
    md.writeln('**${l10n.historyMdModel}:** ${entry.model}');
  }
  return md.toString();
}

/// History page — recorded transcriptions with search, filter, and grouping.
///
