import 'dart:async';

import '../../core/recording/recording_helpers.dart' show displayNameForModel;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/first_steps/first_steps_notifier.dart';
import '../../core/config/command_shortcut.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/navigation/page_state.dart';
import '../../core/navigation/work_state.dart';
import '../../core/text/markdown_plain_text.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/focus_helpers.dart';
import '../../widgets/dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_collection_page.dart';
import '../../widgets/wp_collection_split.dart';
import '../../widgets/wp_notice_bar.dart';
import '../../widgets/wp_list_skeleton.dart';

import 'package:whispaste/core/data/database.dart';

import '../../services/app_identity/app_identity_service.dart';
import '../../services/audio/import/audio_import_providers.dart';
import '../../services/pending_audio/pending_audio_providers.dart';
import '../../services/recording_orchestrator.dart'
    show recordingOrchestratorProvider;
import '../../services/history/history_exporter.dart' as history_exporter;
import 'data/history_detail_provider.dart';
import 'data/history_lock.dart';
import 'data/providers.dart';
import 'widgets/audio_import_drop_zone.dart';
import 'widgets/audio_import_panel.dart';
import 'widgets/history_duration_chips.dart';
import 'widgets/recovery_banner.dart';
import 'widgets/history_status_row.dart';
import 'widgets/history_pin_dialogs.dart';
import 'widgets/widgets.dart';
import '../../widgets/wp_copy_feedback.dart';
import '../../widgets/wp_page_notice.dart';
import 'widgets/history_write_failure.dart';

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
/// Copy target of the multi-select bar: the rows are not one place.
const kHistoryBatchCopyTarget = 'history-batch';

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
  bool _multiSelectMode = false;
  final Set<String> _selectedIds = {};

  /// Tracks last clicked entry for Shift+click range selection.
  String? _lastClickedId;

  /// Keyboard-focused entry ID (distinct from selected/detail entry).
  String? _focusedEntryId;
  final FocusNode _listFocusNode = FocusNode();

  /// Session holder this page restores from and saves to (#1074).
  late final HistoryWorkState _work;

  @override
  void initState() {
    super.initState();
    _restoreWorkState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpenEntry());
  }

  /// Picks up where the user left this page: selection, multi-selection and
  /// view, and the search text that [historySearchProvider] still applies
  /// (the field would otherwise show empty over filtered results). The sort
  /// order lives in [historySortOrderProvider] for the session.
  void _restoreWorkState() {
    _work = ref.read(historyWorkStateProvider);
    _selectedEntryId = _work.selectedEntryId;
    _focusedEntryId = _work.focusedEntryId;
    _lastClickedId = _work.lastClickedId;
    _multiSelectMode = _work.multiSelectMode;
    _selectedIds.addAll(_work.selectedIds);
    _viewMode = HistoryViewMode.values.firstWhere(
      (m) => m.name == _work.viewMode,
      orElse: () => _viewMode,
    );
    _searchController.text = ref.read(historySearchProvider);
  }

  void _saveWorkState() {
    _work
      ..selectedEntryId = _selectedEntryId
      ..focusedEntryId = _focusedEntryId
      ..lastClickedId = _lastClickedId
      ..multiSelectMode = _multiSelectMode
      ..selectedIds = {..._selectedIds}
      ..viewMode = _viewMode.name;
  }

  @override
  void dispose() {
    _saveWorkState();
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

  /// The entries in display order, for keyboard navigation and Shift+click
  /// ranges. The database already sorts (#1663), [groupedHistoryProvider]
  /// only splits the rows into sections.
  List<HistoryEntry> _flatEntries(List<DateGroup> groups) => [
    for (final g in groups) ...g.entries,
  ];

  /// Mirrors [historyHasMoreProvider]; kept as a field so scroll and key
  /// callbacks need not read providers while a build is in flight.
  bool _hasMore = false;

  void _moveFocus(int delta, List<HistoryEntry> flat) {
    if (flat.isEmpty) return;
    final currentIdx = flat.indexWhere((e) => e.id == _focusedEntryId);
    final int nextIdx;
    if (currentIdx < 0) {
      nextIdx = delta > 0 ? 0 : flat.length - 1;
    } else {
      nextIdx = (currentIdx + delta).clamp(0, flat.length - 1);
    }
    // Stepping past the last loaded row pulls in the next page.
    if (delta > 0 && currentIdx == flat.length - 1) {
      _loadMore();
    }
    setState(() => _focusedEntryId = flat[nextIdx].id);
  }

  /// Loads the next page when the main list is scrolled close to its end.
  bool _onListScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.metrics.extentAfter > 600) {
      return false;
    }
    if (n.context?.findAncestorWidgetOfExactType<HistoryDetailPanel>() !=
        null) {
      return false;
    }
    _loadMore();
    return false;
  }

  void _loadMore() {
    if (_hasMore) ref.read(historyPageLimitProvider.notifier).loadMore();
  }

  /// List, search, duration chip and order shown now: a database answer for
  /// another list is dropped (#1663).
  (HistoryFilter, String, HistoryDurationBucket, HistorySortOrder) _listKey() =>
      (
        ref.read(historyFilterProvider),
        ref.read(historySearchProvider).trim(),
        ref.read(historyDurationBucketProvider),
        ref.read(historySortOrderProvider),
      );

  /// "Alle auswählen" and Ctrl/Cmd+A (#1663): every recording the list holds,
  /// loaded or not, up to [historySelectAllLimit] in list order. The loaded
  /// rows are selected at once; when more pages follow, the ids of the rest
  /// come from the database and join the selection a moment later.
  Future<void> _selectAll(List<HistoryEntry> loaded) async {
    setState(() {
      _multiSelectMode = true;
      _selectedIds
        ..clear()
        ..addAll(loaded.map((e) => e.id));
    });
    final spec = ref.read(historyListSpecProvider);
    if (!_hasMore || spec == null) return;
    final key = _listKey();
    final selectedNow = _selectedIds.length;
    final List<String> ids;
    try {
      ids = await ref
          .read(historyDatabaseProvider)
          .historyIds(spec, sort: key.$4, limit: historySelectAllLimit);
    } catch (e) {
      // The loaded rows stay selected; the search failure has its notice.
      _log.warning('Select all: reading the ids failed: $e');
      return;
    }
    // Dropped when the list or the selection changed in the meantime.
    if (!mounted ||
        !_multiSelectMode ||
        _selectedIds.length != selectedNow ||
        _listKey() != key) {
      return;
    }
    setState(() {
      _selectedIds.addAll(ids);
      _prunedFor = (key, _selectedIds.length);
    });
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
    HistoryEntry? selectedEntry,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // In a text field every key, Ctrl/Cmd+A and +C included, stays with the
    // field so it selects and copies its own text.
    if (isTextFieldFocused()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (commandOnlyPressed()) {
      // Ctrl/Cmd+A: select every entry of the list, loaded or not.
      if (key == LogicalKeyboardKey.keyA) {
        _selectAll(flat);
        return KeyEventResult.handled;
      }
      // Ctrl/Cmd+C: copy the selected entries, else the open or focused one.
      if (key == LogicalKeyboardKey.keyC) {
        if (_multiSelectMode && _selectedIds.isNotEmpty) {
          _copySelectedEntries(flat);
        } else {
          final entry = selectedEntry ?? _focusedEntry(flat);
          if (entry != null) _copyEntry(entry);
        }
        return KeyEventResult.handled;
      }
    }
    // ↑/↓ and bare J/K: the shared list keyset (listStepFor).
    final step = listStepFor(key);
    if (step != null) {
      _moveFocus(step, flat);
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
    // F: toggle favourite on the focused entry. Only a bare F: Cmd/Ctrl+F
    // must reach the page shortcut that focuses the search (same as notes).
    if (key == LogicalKeyboardKey.keyF && noModifierPressed()) {
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
    final flat = _flatEntries(groups);

    return CallbackShortcuts(
      // Only modifier-combo shortcuts remain here.
      // Bare keys (arrows, enter, delete, backspace, escape, F)
      // are handled in Focus.onKeyEvent below so they can return
      // KeyEventResult.ignored when a text field has focus, allowing
      // DefaultTextEditingShortcuts to handle them for text editing.
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+Shift+A / Cmd+Shift+A: Deselect all
        commandActivator(LogicalKeyboardKey.keyA, shift: true): () {
          if (isTextFieldFocused()) return;
          setState(() {
            _selectedIds.clear();
            _multiSelectMode = false;
          });
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
        commandActivator(LogicalKeyboardKey.enter): () {
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
        onKeyEvent: (node, event) =>
            _handleListKeyEvent(node, event, flat, selectedEntry),
        child: GestureDetector(
          onTap: () => _listFocusNode.requestFocus(),
          behavior: HitTestBehavior.translucent,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onListScroll,
            child: Stack(
              children: [
                Positioned.fill(
                  child: WpCollectionSplit<HistoryEntry>(
                    selectedItem: selectedEntry,
                    idOf: (entry) => entry.id,
                    listBuilder: (context, selectedId) => HistoryEntryViews(
                      // The import panel scrolls with the rows (UX-104): it
                      // is the first row of the one list, so nothing above it
                      // can clip at a large text scale.
                      leading: const AudioImportPanel(),
                      groups: groups,
                      viewMode: _viewMode,
                      selectedId: selectedId,
                      focusedId: _focusedEntryId,
                      multiSelectMode: _multiSelectMode,
                      selectedIds: _selectedIds,
                      isTrashView: isTrashView,
                      // `flat`, not `filteredEntries`: the range Shift+click
                      // selects has to be the range the user sees between the
                      // two clicks, and only `flat` follows the sections on
                      // screen (the same list the arrow keys walk). In
                      // "Neueste" a pinned entry sits in its day's section,
                      // so `filteredEntries` (pins first) would select a
                      // different set than the one highlighted on screen.
                      onEntryTap: (entry) => _handleEntryTap(entry, flat),
                      onCopy: _copyEntry,
                      onPin: _togglePin,
                      onDelete: (entry) => _deleteEntry(entry),
                      onRestore: _restoreEntry,
                      onDuplicate: _duplicateEntry,
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
                    detailBuilder: (context, entry) => HistoryDetailPanel(
                      entry: entry,
                      isTrashView: isTrashView,
                      isArchiveView: isArchiveView,
                      onClose: () => setState(() => _selectedEntryId = null),
                      onCopy: () => _copyEntry(entry),
                      onPin: () => _togglePin(entry),
                      onDelete: () => _deleteEntry(entry),
                      onArchive: () => _archiveEntry(entry),
                      onRestore: () => _restoreEntry(entry),
                      onDuplicate: () => _duplicateEntry(entry),
                      onCopyMarkdown: () => _copyAsMarkdown(entry),
                      exportFn: widget.exportFn,
                    ),
                  ),
                ),
                if (ref.watch(historyHasMoreProvider))
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: WpSpacing.sm,
                    child: IgnorePointer(
                      child: Center(
                        child: SizedBox(
                          key: ValueKey('history-load-more'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
            actionTestId: 'history-gate-action',
            onAction: () =>
                showHistoryPinUnlockDialog(context, offerForgot: true),
          )
        : WpEmptyState(
            key: kHistoryPrivacyGateKey,
            icon: LucideIcons.eyeOff,
            title: l10n.historyPrivacyGateTitle,
            hint: l10n.historyPrivacyGateHint,
            actionLabel: l10n.historyPrivacyGateShow,
            actionTestId: 'history-gate-action',
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

  /// The list and selection size [_dropSelectionOutsideResults] last asked
  /// the database about, so a rebuild does not ask again.
  ((HistoryFilter, String, HistoryDurationBucket, HistorySortOrder), int)?
  _prunedFor;

  /// Drops selected ids that the current results do not hold (UIA-HIS-17), so
  /// batch actions never reach entries outside the list. Runs only once the
  /// results have loaded, never on the stale list of the previous query.
  /// While more pages follow, a selected id that is not loaded yet may still
  /// be a match ("Alle auswählen", #1663): the database decides.
  void _dropSelectionOutsideResults(
    AsyncValue<List<HistoryEntry>> filteredAsync,
    List<HistoryEntry> filteredEntries,
  ) {
    if (_selectedIds.isEmpty || filteredAsync.isLoading) return;
    final visible = {for (final e in filteredEntries) e.id};
    final hidden = _selectedIds.where((id) => !visible.contains(id)).toList();
    if (hidden.isEmpty) return;
    if (!_hasMore) {
      _dropSelected(hidden);
      return;
    }
    final spec = ref.read(historyListSpecProvider);
    if (spec == null) return;
    final key = _listKey();
    final asked = (key, _selectedIds.length);
    if (_prunedFor == asked) return;
    _prunedFor = asked;
    unawaited(
      ref
          .read(historyDatabaseProvider)
          .historyIdsAmong(spec, hidden)
          .then((kept) {
            if (!mounted || _listKey() != key) return;
            _dropSelected(hidden.where((id) => !kept.contains(id)).toList());
          })
          .catchError((Object e) {
            _log.warning('Selection check failed: $e');
          }),
    );
  }

  void _dropSelected(List<String> ids) {
    if (ids.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIds.removeAll(ids);
        if (_selectedIds.isEmpty) _multiSelectMode = false;
      });
    });
  }

  Widget _buildHistory(BuildContext context) {
    final activeFilter = ref.watch(historyFilterProvider);
    final groupedAsync = ref.watch(groupedHistoryProvider);
    final filteredAsync = ref.watch(filteredHistoryProvider);
    _hasMore = ref.watch(historyHasMoreProvider);
    final isTrashView = activeFilter == HistoryFilter.trash;
    final isArchiveView = activeFilter == HistoryFilter.archived;
    final sortOrder = ref.watch(historySortOrderProvider);

    // Resolve the flat filtered list (for selection lookup & shift-click)
    final filteredEntries = filteredAsync.value ?? [];
    _dropSelectionOutsideResults(filteredAsync, filteredEntries);
    // All recordings of the list, loaded or not (#1663). Without a further
    // page the loaded rows are all of them.
    final totalCount = _hasMore
        ? ref.watch(historyListCountProvider).value ?? filteredEntries.length
        : filteredEntries.length;

    // Look up selected entry from current filtered list
    HistoryEntry? selectedEntry;
    if (_selectedEntryId != null) {
      final idx = filteredEntries.indexWhere((e) => e.id == _selectedEntryId);
      // The list rows carry only previews: the open entry is read in full.
      selectedEntry = idx >= 0
          ? ref.watch(historyFullEntryProvider(_selectedEntryId!)).value
          : null;
    }

    // The page family's frame (`WpCollectionPage`, `internal-notes`):
    // selection bar, notices, toolbar, then list and detail. On a short window
    // or at text scale 2.0 the selection bar takes the toolbar's place while
    // entries are selected; Escape or "Cancel selection" brings the search
    // back with the focus in it (UX-097, compact mode). Otherwise the search
    // stays up while selecting, so it can be narrowed without giving the
    // selection up (UIA-HIS-17).
    return AudioImportDropZone(
      child: WpCollectionPage(
        screenId: 'history',
        searchFocusNode: _searchFocusNode,
        selectionBar: _multiSelectMode && _selectedIds.isNotEmpty
            ? WpCopyAnchor(
                target: kHistoryBatchCopyTarget,
                child: WpMultiSelectBar(
                  selectedCount: _selectedIds.length,
                  totalCount: totalCount,
                  isTrashView: isTrashView,
                  isArchiveView: isArchiveView,
                  onMerge: _selectedIds.length >= 2 ? _mergeSelected : null,
                  onBatchCopy: _selectedIds.isNotEmpty
                      ? () => _copySelectedEntries(filteredEntries)
                      : null,
                  onBatchCopyMarkdown: _selectedIds.isNotEmpty
                      ? () => _copySelectedEntriesAsMarkdown(filteredEntries)
                      : null,
                  onExport: _selectedIds.isNotEmpty
                      ? () => _exportSelectedEntries(filteredEntries)
                      : null,
                  onArchive: !isTrashView ? _archiveSelected : null,
                  onDelete: _deleteSelected,
                  onRestore: isTrashView ? _restoreSelected : null,
                  onSelectAll: () {
                    if (_selectedIds.length >= totalCount) {
                      // All selected → deselect all
                      setState(() {
                        _selectedIds.clear();
                        _multiSelectMode = false;
                      });
                    } else {
                      unawaited(_selectAll(filteredEntries));
                    }
                  },
                  onCancelSelection: _leaveSelection,
                ),
              )
            : null,
        notices: [
          const HistoryStatusRow(),
          WpPageNoticeSlot(
            page: WpNoticePage.history,
            // Only an entry whose detail is on screen has its own slot; one
            // the filter dropped keeps its failure here.
            openArea: selectedEntry?.id,
          ),
          const RecoveryBanner(),
        ],
        toolbar: HistorySearchFilterBar(
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
          resultCount: totalCount,
          viewMode: _viewMode,
          onViewModeChanged: (m) => setState(() => _viewMode = m),
          multiSelectMode: _multiSelectMode,
          onToggleMultiSelect: () => setState(() {
            _multiSelectMode = !_multiSelectMode;
            if (!_multiSelectMode) _selectedIds.clear();
          }),
          sortOrder: sortOrder,
          onSortOrderChanged: ref.read(historySortOrderProvider.notifier).set,
          onEmptyTrash: isTrashView && filteredEntries.isNotEmpty
              ? _emptyTrash
              : null,
        ),
        // Master-detail content
        body: groupedAsync.when(
          data: (groups) {
            if (groups.isEmpty) {
              return _withImportPanel(_emptyStateForFilter(activeFilter));
            }
            return _buildLoadedView(
              groups,
              filteredEntries,
              selectedEntry,
              isTrashView,
              isArchiveView,
            );
          },
          loading: () => _withImportPanel(
            const WpListSkeleton(rowHeight: _historySkeletonRowHeight),
          ),
          error: (e, _) {
            final l10n = L10n.of(context);
            return _withImportPanel(
              WpEmptyState(
                icon: LucideIcons.triangleAlert,
                title: l10n.errorGeneric,
                actionLabel: l10n.actionRetry,
                actionTestId: 'history-retry',
                onAction: () => _retryFilter(activeFilter),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Without rows the list area has no scroll owner, so the import panel sits
  /// above the empty, loading or error state: the way to add files stays.
  Widget _withImportPanel(Widget body) => Column(
    children: [
      const AudioImportPanel(),
      Expanded(child: body),
    ],
  );

  Widget _emptyStateForFilter(HistoryFilter activeFilter) {
    final l10n = L10n.of(context);
    // A duration chip that leaves nothing names itself and offers the way
    // back; the search, if any, stays (#879).
    final durationBucket = ref.watch(historyDurationBucketProvider);
    if (durationBucket != HistoryDurationBucket.all) {
      return WpEmptyState(
        icon: LucideIcons.timer,
        title: l10n.searchNoMatches,
        hint: l10n.historyDurationNoMatchHint(
          historyDurationLabel(l10n, durationBucket),
        ),
        actionLabel: l10n.historyDurationResetFilter,
        actionTestId: 'history-duration-reset',
        onAction: () => ref
            .read(historyDurationBucketProvider.notifier)
            .set(HistoryDurationBucket.all),
      );
    }
    if (_searchController.text.isNotEmpty) {
      return WpEmptyState.searchNoMatches(
        query: _searchController.text,
        testId: 'history-search-clear',
        onClear: _searchController.clear,
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
        actionTestId: 'history-off-settings',
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
        // A trash has nothing to start; its one way on is back to the list.
        actionLabel: l10n.historyShowAll,
        actionTestId: 'history-trash-show-all',
        onAction: () =>
            ref.read(historyFilterProvider.notifier).set(HistoryFilter.all),
      );
    }
    if (activeFilter == HistoryFilter.archived) {
      return WpEmptyState(
        icon: LucideIcons.archive,
        title: l10n.historyNoArchivedItems,
        hint: l10n.historyNoArchivedItemsHint,
        actionLabel: l10n.historyShowAll,
        actionTestId: 'history-archived-show-all',
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
        actionTestId: 'history-pinned-show-all',
        onAction: () =>
            ref.read(historyFilterProvider.notifier).set(HistoryFilter.all),
      );
    }
    return WpEmptyState(
      icon: LucideIcons.mic,
      title: l10n.historyEmpty,
      hint: l10n.historyNoRecordingsHint,
      // The history fills from a recording run, so its first action is the
      // same "Dictate" the dock offers (#1076).
      actionLabel: l10n.dockDictate,
      actionTestId: 'history-empty-dictate',
      onAction: () =>
          ref.read(recordingOrchestratorProvider.notifier).toggleRecording(),
    );
  }

  /// [rows] with their full texts: the lists carry only previews (#1324).
  Future<List<HistoryEntry>> _withFullTexts(List<HistoryEntry> rows) async {
    final db = ref.read(historyDatabaseProvider);
    final full = <HistoryEntry>[];
    for (final row in rows) {
      full.add(await db.fullEntry(row));
    }
    return full;
  }

  Future<void> _copyEntry(HistoryEntry row) async {
    final entry = (await _withFullTexts([row])).single;
    if (!mounted) return;
    ref.read(firstStepsNotifierProvider.notifier).recordingCopied();
    unawaited(
      copyWithFeedback(
        context,
        // Plain text by default (#644); "Copy as Markdown" keeps the markers.
        text: markdownToPlainText(entry.content),
        target: 'history-${entry.id}',
        category: 'history',
      ),
    );
  }

  void _togglePin(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).togglePin(entry.id);
      // Refresh detail panel if this entry is shown (Finding #3)
      ref.invalidate(historyDetailProvider(entry.id));
    } catch (e) {
      _showHistoryWriteFailed();
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
        ref.invalidate(pagedHistoryProvider);
    }
    ref.invalidate(historySearchPageProvider);
    ref.invalidate(filteredHistoryProvider);
  }

  void _deleteEntry(HistoryEntry entry, {String? focusAfter}) async {
    final isTrash = ref.read(historyFilterProvider) == HistoryFilter.trash;
    if (isTrash) {
      if (!await _confirmPermanentDelete(1) || !mounted) return;
    }
    try {
      if (isTrash) {
        final db = ref.read(historyDatabaseProvider);
        await db.permanentDeleteEntry(entry.id);
        await pruneAppIdentityCache(db, ref.read(appIdentityServiceProvider));
      } else {
        await ref.read(historyDatabaseProvider).softDeleteEntry(entry.id);
      }
      await ref.read(pendingAudioQueueProvider).discard(entry.id);
    } catch (e) {
      _showHistoryWriteFailed();
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_selectedEntryId == entry.id) _selectedEntryId = null;
      if (_focusedEntryId == entry.id) _focusedEntryId = focusAfter;
    });
    if (!mounted || isTrash) return;
    final l10n = L10n.of(context);
    showWpNotice(
      context,
      WpNotice(
        id: 'history-trashed',
        kind: WpNoticeKind.undo,
        message: l10n.historyMovedToTrash,
        actionLabel: l10n.historyUndo,
        onAction: () => _restoreEntry(entry),
      ),
    );
  }

  /// Archives or un-archives [entry], confirms the move and offers undo
  /// (UIA-HIS-25).
  void _archiveEntry(HistoryEntry entry) async {
    final archiving = !entry.archived;
    if (!await _toggleArchive(entry)) return;
    if (!mounted) return;
    if (_selectedEntryId == entry.id) {
      setState(() => _selectedEntryId = null);
    }
    showWpNotice(
      context,
      WpNotice(
        id: 'history-archived',
        kind: WpNoticeKind.undo,
        message: archiving
            ? L10n.of(context).historyArchived
            : L10n.of(context).historyRestored,
        actionLabel: L10n.of(context).historyUndo,
        onAction: () => _toggleArchive(entry),
      ),
    );
  }

  Future<bool> _toggleArchive(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).toggleArchive(entry.id);
      ref.invalidate(historyDetailProvider(entry.id));
      return true;
    } catch (e) {
      _showHistoryWriteFailed();
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
      _showHistoryWriteFailed();
      return;
    }
    if (!mounted) return;
    showWpNotice(
      context,
      WpNotice(
        id: 'history-restored',
        kind: WpNoticeKind.undo,
        message: L10n.of(context).historyRestored,
        actionLabel: L10n.of(context).historyUndo,
        onAction: () => _moveToTrashQuietly(entry),
      ),
    );
  }

  Future<void> _moveToTrashQuietly(HistoryEntry entry) async {
    try {
      await ref.read(historyDatabaseProvider).softDeleteEntry(entry.id);
      ref.invalidate(historyDetailProvider(entry.id));
    } catch (e) {
      _showHistoryWriteFailed();
    }
  }

  void _duplicateEntry(HistoryEntry entry) async {
    try {
      final dup = await ref
          .read(historyDatabaseProvider)
          .duplicateEntry(entry.id);
      if (!mounted || dup == null) return;
      setState(() => _selectedEntryId = dup.id);
    } catch (e) {
      _showHistoryWriteFailed();
    }
  }

  String _formatEntryAsMarkdown(HistoryEntry entry) =>
      formatHistoryEntryAsMarkdown(entry, L10n.of(context));

  Future<void> _copyAsMarkdown(HistoryEntry row) async {
    final entry = (await _withFullTexts([row])).single;
    if (!mounted) return;
    unawaited(
      copyWithFeedback(
        context,
        text: _formatEntryAsMarkdown(entry),
        target: 'history-${entry.id}',
      ),
    );
  }

  /// Full rows of every selected entry in list order: the loaded ones as
  /// they are listed, then those "Alle auswählen" took beyond the loaded
  /// pages (#1663), read from the database.
  Future<List<HistoryEntry>> _selectedEntries(List<HistoryEntry> flat) async {
    final rows = flat.where((e) => _selectedIds.contains(e.id)).toList();
    final selected = await _withFullTexts(rows);
    final loaded = {for (final e in rows) e.id};
    final rest = _selectedIds.where((id) => !loaded.contains(id)).toList();
    if (rest.isEmpty) return selected;
    final order = ref.read(historySortOrderProvider);
    final more = await ref.read(historyDatabaseProvider).entriesByIds(rest)
      ..sort((a, b) => compareHistoryEntries(order, a, b));
    return [...selected, ...more];
  }

  /// Copies all selected entries as Markdown, joined by a blank line.
  Future<void> _copySelectedEntriesAsMarkdown(List<HistoryEntry> flat) async {
    final selected = await _selectedEntries(flat);
    if (selected.isEmpty || !mounted) return;

    final md = selected.map(_formatEntryAsMarkdown).join('\n');
    unawaited(
      copyWithFeedback(context, text: md, target: kHistoryBatchCopyTarget),
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
      _showHistoryWriteFailed();
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _multiSelectMode = false;
      if (merged != null) _selectedEntryId = merged.id;
    });
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
      _showHistoryWriteFailed();
      return;
    }
    _clearSelection();
    _showBulkUndoToast(message, () => db.batchUnarchive(ids));
  }

  /// Confirms a bulk action and offers to take it back (UIA-HIS-06).
  void _showBulkUndoToast(String message, Future<void> Function() undo) {
    if (!mounted) return;
    showWpNotice(
      context,
      WpNotice(
        id: 'history-bulk',
        kind: WpNoticeKind.undo,
        message: message,
        actionLabel: L10n.of(context).historyUndo,
        onAction: () => _undoBulk(undo),
      ),
    );
  }

  /// Takes back a bulk action by reversing only the flag it set, so entries
  /// keep every other state (an archived entry that was trashed stays
  /// archived, UIA-HIS-06).
  void _undoBulk(Future<void> Function() undo) async {
    try {
      await undo();
    } catch (e) {
      _showHistoryWriteFailed();
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
      _showHistoryWriteFailed();
      return;
    }
    _clearSelection();
    // Permanent delete stays without undo; it was confirmed above.
    if (!isTrash) {
      _showBulkUndoToast(message, () => db.batchRestoreFromTrash(ids));
    }
  }

  void _restoreSelected() async {
    final db = ref.read(historyDatabaseProvider);
    try {
      final ids = _selectedIds.toList();
      if (ref.read(historyFilterProvider) == HistoryFilter.archived) {
        await db.batchUnarchive(ids);
      } else {
        await db.batchRestoreFromTrash(ids);
      }
    } catch (e) {
      _showHistoryWriteFailed();
      return;
    }
    _clearSelection();
    if (!mounted) return;
  }

  /// Run the export flow for the currently selected entries.
  ///
  /// Delegates to [HistoryPage.exportFn] (default: `exportEntries` from the
  /// `HistoryExporter` service). The exporter manages picker + notice + path
  /// resolution itself; nothing else to do here.
  Future<void> _exportSelectedEntries(List<HistoryEntry> flat) async {
    final selected = await _selectedEntries(flat);
    if (selected.isEmpty || !mounted) return;
    // Fire-and-forget: the exporter surfaces success/error as a page notice.
    widget.exportFn(context, selected);
  }

  /// Copy all selected entries' text to clipboard (joined by double newline).
  Future<void> _copySelectedEntries(List<HistoryEntry> flat) async {
    final selected = await _selectedEntries(flat);
    if (selected.isEmpty || !mounted) return;
    final text = selected
        .map((e) => markdownToPlainText(e.content))
        .join('\n\n');
    unawaited(
      copyWithFeedback(context, text: text, target: kHistoryBatchCopyTarget),
    );
  }

  /// The storage error, which stays on the page with its diagnostics.
  void _showHistoryWriteFailed() {
    if (!mounted) return;
    showHistoryWriteFailed(context);
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
    final List<String> trashedIds;
    try {
      trashedIds = await db.trashedEntryIds();
      await db.emptyTrash();
    } catch (e) {
      _showHistoryWriteFailed();
      return;
    }
    await pruneAppIdentityCache(db, ref.read(appIdentityServiceProvider));
    final queue = ref.read(pendingAudioQueueProvider);
    for (final id in trashedIds) {
      await queue.discard(id);
    }
    if (!mounted) return;
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
    md.writeln(
      '**${l10n.historyMdModel}:** ${displayNameForModel(entry.model, l10n)}',
    );
  }
  return md.toString();
}

/// History page — recorded transcriptions with search, filter, and grouping.
///
