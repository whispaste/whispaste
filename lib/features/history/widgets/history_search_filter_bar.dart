import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/recording/recording_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/views/smart_view.dart';
import '../../views/smart_view_ui.dart';
import '../../../services/recording_orchestrator.dart';
import '../../../services/audio/import/audio_import_providers.dart';
import '../../../widgets/wp_button.dart';
import 'history_status_row.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_collection_page.dart';
import '../../../widgets/wp_search_field.dart';
import '../../../widgets/searchable_list_page.dart';
import '../../../widgets/wp_sort_menu_button.dart';
import '../data/providers.dart';
import '../data/recent_searches.dart';
import 'history_duration_chips.dart';
import 'history_helpers.dart';
import 'history_range_chips.dart';

// The multi-select bar moved to widgets/ (shared with Textbausteine); history
// code keeps importing it from here.
export '../../../widgets/wp_multi_select_bar.dart';

// ---------------------------------------------------------------------------
// Suggestion type for autocomplete
// ---------------------------------------------------------------------------

enum _SuggestionType { none, tag, lang, smartPanel }

const _kLangOptions = [
  'de',
  'en',
  'fr',
  'es',
  'it',
  'pt',
  'nl',
  'pl',
  'ru',
  'zh',
  'ja',
  'ko',
  'ar',
  'tr',
  'sv',
  'da',
  'fi',
  'nb',
  'cs',
  'sk',
  'hu',
  'ro',
];

// ---------------------------------------------------------------------------
// Search & filter bar
// ---------------------------------------------------------------------------

class HistorySearchFilterBar extends ConsumerStatefulWidget {
  const HistorySearchFilterBar({
    super.key,
    required this.controller,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.resultCount,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.multiSelectMode,
    required this.onToggleMultiSelect,
    required this.sortOrder,
    required this.onSortOrderChanged,
    this.searchFocusNode,
    this.onEmptyTrash,
  });

  final TextEditingController controller;
  final HistoryFilter activeFilter;
  final ValueChanged<HistoryFilter> onFilterChanged;
  final VoidCallback onSearchChanged;
  final int resultCount;
  final HistoryViewMode viewMode;
  final ValueChanged<HistoryViewMode> onViewModeChanged;
  final bool multiSelectMode;
  final VoidCallback onToggleMultiSelect;
  final HistorySortOrder sortOrder;
  final ValueChanged<HistorySortOrder> onSortOrderChanged;
  final FocusNode? searchFocusNode;
  final VoidCallback? onEmptyTrash;

  @override
  ConsumerState<HistorySearchFilterBar> createState() =>
      _HistorySearchFilterBarState();
}

class _HistorySearchFilterBarState
    extends ConsumerState<HistorySearchFilterBar> {
  List<String> _suggestions = [];
  List<String> _recentSearches = [];
  List<String> _quickTags = [];
  _SuggestionType _suggestionType = _SuggestionType.none;
  int _selectedIdx = 0;
  int _tagSuggestionGeneration = 0;
  Timer? _searchDebounce;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    widget.searchFocusNode?.addListener(_onFocusChange);
    // The node belongs to _HistoryPageState and outlives this bar, so the
    // handler is installed here and cleared again in dispose/didUpdateWidget.
    // Same arrangement as settings_search_field.dart:62 — WpSearchField itself
    // never assigns onKeyEvent, it documents that callers may.
    widget.searchFocusNode?.onKeyEvent = _handleSearchKey;
  }

  @override
  void didUpdateWidget(covariant HistorySearchFilterBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
    if (old.searchFocusNode != widget.searchFocusNode) {
      old.searchFocusNode?.removeListener(_onFocusChange);
      old.searchFocusNode?.onKeyEvent = null;
      widget.searchFocusNode?.addListener(_onFocusChange);
      widget.searchFocusNode?.onKeyEvent = _handleSearchKey;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    widget.controller.removeListener(_onControllerChange);
    widget.searchFocusNode?.removeListener(_onFocusChange);
    widget.searchFocusNode?.onKeyEvent = null;
    super.dispose();
  }

  /// Arrow/Enter/Escape navigation for the tag and language autocomplete.
  ///
  /// The dropdown painted a highlight over `_selectedIdx` but nothing ever
  /// moved it: there was no key handler here and none in WpSearchField, so the
  /// suggestions could only be taken with the mouse. For an audience that
  /// dictates 5–100× a day and includes RSI sufferers — "ohne die Maus zu
  /// berühren" is the product's own litmus test — a mouse-only autocomplete on
  /// the most-opened screen is a dead end, not a shortcut.
  ///
  /// Returns [KeyEventResult.ignored] for everything it does not consume so
  /// DefaultTextEditingShortcuts keeps handling ordinary caret movement.
  KeyEventResult _handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Escape closes the dropdown first and only then gives up the field, so a
    // stray Escape never costs the user the query they just typed.
    if (key == LogicalKeyboardKey.escape) {
      if (_hasSuggestions) {
        _clearSuggestions();
      } else {
        node.unfocus();
      }
      return KeyEventResult.handled;
    }

    // The tag/lang lists and the smart panel (recent searches, then popular
    // tags) are navigable. The quick-action chips are not, and keep Tab.
    final navigable =
        _suggestionType == _SuggestionType.tag ||
        _suggestionType == _SuggestionType.lang ||
        _suggestionType == _SuggestionType.smartPanel;
    if (!navigable || _navigableCount == 0) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIdx = (_selectedIdx + 1) % _navigableCount;
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIdx = _selectedIdx <= 0
            ? _navigableCount - 1
            : _selectedIdx - 1;
      });
      return KeyEventResult.handled;
    }

    // Enter only — deliberately not Tab, even though shell-style completion is
    // tempting here. Consuming Tab while the list is open would take away the
    // one key that moves focus out of the search field into the filter chips,
    // i.e. it would trade a keyboard gap for a keyboard trap. Escape closes the
    // list and hands Tab straight back. Matches settings_search_field.dart:120,
    // which is also Enter-only.
    if (key == LogicalKeyboardKey.enter) {
      if (_selectedIdx >= 0 && _selectedIdx < _navigableCount) {
        _activateHighlighted();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  void _onFocusChange() {
    final focused = widget.searchFocusNode?.hasFocus ?? false;
    _hasFocus = focused;
    if (focused && widget.controller.text.isEmpty) {
      _loadSmartPanel();
    } else if (!focused) {
      // Delay clear so tap on suggestion can fire first
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        if (!(widget.searchFocusNode?.hasFocus ?? false)) {
          _clearSuggestions();
        }
      });
    }
  }

  void _onControllerChange() {
    _updateSuggestions();
    // Debounce the search provider update to avoid a DB query per keystroke.
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      widget.onSearchChanged();
      _saveRecentSearch();
    });
  }

  void _updateSuggestions() {
    if (!mounted) return;
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final cursor = sel.isValid
        ? sel.baseOffset.clamp(0, text.length)
        : text.length;
    final before = text.substring(0, cursor);

    // Detect #tag trigger
    final tagMatch = RegExp(r'#([\w-]*)$').firstMatch(before);
    if (tagMatch != null) {
      _loadTagSuggestions(tagMatch.group(1)!.toLowerCase());
      return;
    }

    // Detect lang: trigger
    final langMatch = RegExp(
      r'\blang:([\w-]*)$',
      caseSensitive: false,
    ).firstMatch(before);
    if (langMatch != null) {
      _updateLangSuggestions(langMatch.group(1)!.toLowerCase());
      return;
    }

    // Show smart panel if field is empty and focused
    if (text.isEmpty && _hasFocus) {
      _loadSmartPanel();
      return;
    }

    _clearSuggestions();
  }

  Future<void> _loadSmartPanel() async {
    final gen = ++_tagSuggestionGeneration;
    final db = ref.read(historyDatabaseProvider);
    final recentList = ref.read(recentSearchesProvider);
    final tagsWithCount = await db.allTagsWithCount();
    if (!mounted || gen != _tagSuggestionGeneration) return;
    // Top tags by usage count (max 8)
    final sorted = [...tagsWithCount]..sort((a, b) => b.$2.compareTo(a.$2));
    final topTags = sorted.take(8).map((t) => t.$1.name).toList();
    // Only show panel if there's content
    if (topTags.isEmpty && recentList.isEmpty) return;
    setState(() {
      _recentSearches = recentList.take(3).toList();
      _quickTags = topTags;
      _suggestions = topTags;
      _suggestionType = _SuggestionType.smartPanel;
      // Nothing highlighted until the user arrows in, so Enter cannot act on
      // an item they did not pick (UIA-HIS-14).
      _selectedIdx = -1;
    });
  }

  Future<void> _loadTagSuggestions(String prefix) async {
    final gen = ++_tagSuggestionGeneration;
    final db = ref.read(historyDatabaseProvider);
    final tags = await db.searchTags(prefix);
    if (!mounted || gen != _tagSuggestionGeneration) return;
    // Filter out tags already in the query
    final parsed = parseSearchQuery(widget.controller.text);
    final existing = parsed.tagNames.toSet();
    final filtered = tags
        .map((t) => t.name)
        .where((n) => !existing.contains(n))
        .toList();
    setState(() {
      _suggestions = filtered;
      _suggestionType = _SuggestionType.tag;
      _selectedIdx = 0;
    });
  }

  void _updateLangSuggestions(String prefix) {
    final filtered = prefix.isEmpty
        ? _kLangOptions
        : _kLangOptions.where((l) => l.startsWith(prefix)).toList();
    setState(() {
      _suggestions = filtered;
      _suggestionType = _SuggestionType.lang;
      _selectedIdx = 0;
    });
  }

  void _clearSuggestions() {
    if (_suggestions.isNotEmpty ||
        _recentSearches.isNotEmpty ||
        _quickTags.isNotEmpty ||
        _suggestionType != _SuggestionType.none) {
      setState(() {
        _suggestions = [];
        _recentSearches = [];
        _quickTags = [];
        _suggestionType = _SuggestionType.none;
        _selectedIdx = 0;
      });
    }
  }

  /// Items the arrow keys walk: in the smart panel the recent searches come
  /// first, then the popular tags (UIA-HIS-14).
  int get _navigableCount => _suggestionType == _SuggestionType.smartPanel
      ? _recentSearches.length + _quickTags.length
      : _suggestions.length;

  /// Runs the highlighted item: a recent search replays, a tag is inserted.
  void _activateHighlighted() {
    if (_suggestionType != _SuggestionType.smartPanel) {
      _selectSuggestion(_suggestions[_selectedIdx]);
      return;
    }
    if (_selectedIdx < _recentSearches.length) {
      _replayRecentSearch(_recentSearches[_selectedIdx]);
    } else {
      _selectSuggestion(_quickTags[_selectedIdx - _recentSearches.length]);
    }
  }

  void _selectSuggestion(String suggestion) {
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final cursor = sel.isValid
        ? sel.baseOffset.clamp(0, text.length)
        : text.length;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);

    String newBefore;
    if (_suggestionType == _SuggestionType.smartPanel) {
      // Insert full #tag from the smart panel
      newBefore = '$before#$suggestion ';
    } else if (_suggestionType == _SuggestionType.tag) {
      newBefore = before.replaceAll(RegExp(r'#[\w-]*$'), '#$suggestion ');
    } else {
      newBefore = before.replaceAll(
        RegExp(r'\blang:[\w-]*$', caseSensitive: false),
        'lang:$suggestion ',
      );
    }
    final newText = newBefore + after;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newBefore.length),
    );
    _clearSuggestions();
    // onSearchChanged already called by the controller listener
  }

  /// Replays a recent search query by setting it in the field.
  void _replayRecentSearch(String query) {
    widget.controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _clearSuggestions();
  }

  /// Persists the current query as a recent search (called on debounce).
  void _saveRecentSearch() {
    final query = widget.controller.text.trim();
    if (query.length >= 2) {
      ref.read(recentSearchesProvider.notifier).addSearch(query);
    }
  }

  /// Remove a command token from the raw query.
  void _removeCommand(String token) {
    final current = widget.controller.text;
    final cleaned = current
        .replaceAll(token, '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    widget.controller.text = cleaned;
    // listener fires onSearchChanged automatically
  }

  bool get _hasSuggestions {
    if (_suggestionType == _SuggestionType.none) return false;
    if (_suggestionType == _SuggestionType.smartPanel) {
      return _recentSearches.isNotEmpty || _quickTags.isNotEmpty;
    }
    return _suggestions.isNotEmpty;
  }

  // ── Smart panel: multi-section dropdown ────────────────────────────────

  Widget _buildSmartPanel(L10n l10n, Color accent, Color textMuted) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section: Recent Searches
          if (_recentSearches.isNotEmpty) ...[
            _sectionHeader(l10n.historyRecentSearches, textMuted),
            for (var i = 0; i < _recentSearches.length; i++)
              _recentSearchItem(
                _recentSearches[i],
                accent,
                textMuted,
                highlighted: _selectedIdx == i,
              ),
          ],
          // Section: Popular Tags
          if (_quickTags.isNotEmpty) ...[
            if (_recentSearches.isNotEmpty)
              const SizedBox(height: WpSpacing.xs),
            _sectionHeader(l10n.historySearchQuickTags, textMuted),
            for (var j = 0; j < _quickTags.length; j++)
              _tagItem(
                _quickTags[j],
                accent,
                textMuted,
                highlighted: _selectedIdx == _recentSearches.length + j,
              ),
          ],
          // Section: Quick Actions
          if (_recentSearches.isNotEmpty || _quickTags.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.xs),
            _sectionHeader(l10n.historyQuickActions, textMuted),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.xxs,
              ),
              child: Wrap(
                spacing: WpSpacing.xs,
                runSpacing: WpSpacing.xxs,
                children: [
                  _quickActionChip(
                    icon: LucideIcons.globe,
                    label: l10n.historyQuickActionAllLangs,
                    accent: accent,
                    textMuted: textMuted,
                    onTap: () {
                      widget.controller.text = 'lang:';
                      widget.controller.selection =
                          const TextSelection.collapsed(offset: 5);
                      _clearSuggestions();
                    },
                  ),
                  _quickActionChip(
                    icon: LucideIcons.star,
                    label: l10n.historyQuickActionFavorites,
                    accent: accent,
                    textMuted: textMuted,
                    onTap: () {
                      widget.onFilterChanged(HistoryFilter.pinned);
                      _clearSuggestions();
                      widget.searchFocusNode?.unfocus();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, Color textMuted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        WpSpacing.xxs,
        WpSpacing.md,
        WpSpacing.xxs,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: WpTypography.caption,
          fontWeight: FontWeight.w600,
          color: textMuted,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _recentSearchItem(
    String query,
    Color accent,
    Color textMuted, {
    bool highlighted = false,
  }) {
    return InkWell(
      onTap: () => _replayRecentSearch(query),
      child: Container(
        color: highlighted ? WpColors.accentActiveFill : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xxs + 1,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.clock, size: WpIconSize.xs, color: textMuted),
              const SizedBox(width: WpSpacing.xs),
              Expanded(
                child: Text(
                  query,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    color: textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _DismissIcon(
                testId: 'history-recent-search-remove',
                icon: LucideIcons.x,
                size: 12,
                color: textMuted,
                semanticLabel: L10n.of(context).historyRemoveRecentSearch,
                onTap: () {
                  ref.read(recentSearchesProvider.notifier).removeSearch(query);
                  setState(() {
                    _recentSearches = _recentSearches
                        .where((s) => s != query)
                        .toList();
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tagItem(
    String tag,
    Color accent,
    Color textMuted, {
    bool highlighted = false,
  }) {
    return InkWell(
      onTap: () => _selectSuggestion(tag),
      child: Container(
        color: highlighted ? WpColors.accentActiveFill : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xxs + 1,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.tag, size: WpIconSize.xs, color: textMuted),
              const SizedBox(width: WpSpacing.xs),
              Text(
                '#$tag',
                style: TextStyle(fontSize: WpTypography.body, color: textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionChip({
    required IconData icon,
    required String label,
    required Color accent,
    required Color textMuted,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: WpRadius.borderFull,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xxs + 1,
        ),
        decoration: BoxDecoration(
          color: WpColors.accentButtonFill,
          borderRadius: WpRadius.borderFull,
          border: Border.all(color: WpColors.accentBorder20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: WpIconSize.xxs, color: accent),
            const SizedBox(width: WpSpacing.xxs),
            Text(
              label,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Simple suggestion list (tag/lang autocomplete) ─────────────────────

  Widget _buildSimpleSuggestionList(Color accent, Color textMuted) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
      shrinkWrap: true,
      itemCount: _suggestions.length,
      itemBuilder: (ctx, i) {
        final selected = i == _selectedIdx;
        final s = _suggestions[i];
        // House idiom for a single-tap-target row (snippet picker, export
        // picker, tag input): MergeSemantics + a label-less Semantics, so the
        // name folds in from the rendered `#tag`/`lang:xx` text instead of
        // being announced twice. `selected: selected` is the load-bearing
        // half — the field keeps the only focus node while the arrow keys move
        // a background colour, so without the flag a screen reader reported
        // nothing at all as the user arrowed down the list.
        return MergeSemantics(
          child: Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              onTap: () => _selectSuggestion(s),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.md,
                  vertical: WpSpacing.xs,
                ),
                color: selected
                    ? (WpColors.accentActiveFill)
                    : Colors.transparent,
                child: Row(
                  children: [
                    Icon(
                      _suggestionType == _SuggestionType.lang
                          ? LucideIcons.globe
                          : LucideIcons.tag,
                      size: WpIconSize.xs,
                      color: selected ? accent : textMuted,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Text(
                      _suggestionType == _SuggestionType.lang
                          ? 'lang:$s'
                          : '#$s',
                      style: TextStyle(
                        fontSize: WpTypography.body,
                        color: selected ? accent : textMuted,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
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
    final searchCounts = ref.watch(searchCountsProvider).value;
    final rawQuery = widget.controller.text;
    final parsed = parseSearchQuery(rawQuery);
    final bucket = ref.watch(historyDurationBucketProvider);
    void setQuery(String value) => widget.controller.text = value;
    // Saved views (#658) narrow the live list only, not Archive or Trash.
    const scope = SmartViewScope.recordings;
    final viewsApply =
        widget.activeFilter != HistoryFilter.archived &&
        widget.activeFilter != HistoryFilter.trash;
    Future<List<Tag>> loadTags() => ref.read(historyDatabaseProvider).allTags();
    final viewMark = viewsApply
        ? smartViewActiveFilter(context, ref, scope: scope)
        : null;

    // Everything that narrows the list shows as a mark next to the search.
    // Tag, language and `longer:`/`shorter:` stay raw tokens: that is how
    // they were typed (length has one click path, the duration chips, #1176).
    final storageLabel = switch (widget.activeFilter) {
      HistoryFilter.all => null,
      HistoryFilter.pinned => l10n.historyPinned,
      HistoryFilter.archived => l10n.historyArchived,
      HistoryFilter.trash => l10n.historyTrash,
    };
    final dateRange = parsed.dateRange;
    final longer = parsed.longerThanSec;
    final shorter = parsed.shorterThanSec;
    final activeFilters = <WpActiveFilter>[
      if (storageLabel != null)
        WpActiveFilter(
          id: 'view',
          label: storageLabel,
          onRemove: () => widget.onFilterChanged(HistoryFilter.all),
        ),
      ?viewMark,
      for (final tag in parsed.tagNames)
        WpActiveFilter(
          id: 'tag-$tag',
          label: '#$tag',
          onRemove: () => _removeCommand('#$tag'),
        ),
      if (parsed.langCode != null)
        WpActiveFilter(
          id: 'lang',
          label: 'lang:${parsed.langCode}',
          onRemove: () => _removeCommand('lang:${parsed.langCode}'),
        ),
      if (dateRange != null)
        WpActiveFilter(
          id: 'period',
          label: historyRangeLabel(l10n, dateRange),
          onRemove: () => setQuery(withDateOperator(rawQuery, null)),
        ),
      if (longer != null)
        WpActiveFilter(
          id: 'longer',
          label: durationToken(HistoryDurationBound.longer, longer),
          onRemove: () => setQuery(
            withDurationOperator(rawQuery, HistoryDurationBound.longer, null),
          ),
        ),
      if (shorter != null)
        WpActiveFilter(
          id: 'shorter',
          label: durationToken(HistoryDurationBound.shorter, shorter),
          onRemove: () => setQuery(
            withDurationOperator(rawQuery, HistoryDurationBound.shorter, null),
          ),
        ),
      if (bucket != HistoryDurationBucket.all)
        WpActiveFilter(
          id: 'duration',
          label: historyDurationLabel(l10n, bucket),
          onRemove: () => ref
              .read(historyDurationBucketProvider.notifier)
              .set(HistoryDurationBucket.all),
        ),
    ];

    // Period and duration show only when there is something to refine
    // (concept §4, "risk of overload"): an empty history on a first run gets
    // no period and duration groups in the popover. Archive and Trash keep
    // them, so switching storage filters does not change the popover, and an
    // active refinement always stays reachable with its way back (#1176).
    final showRefinements =
        widget.activeFilter != HistoryFilter.all ||
        bucket != HistoryDurationBucket.all ||
        dateRange != null ||
        longer != null ||
        shorter != null ||
        (ref.watch(pagedHistoryProvider).value?.isNotEmpty ?? true);

    final accent = WpColors.accent;
    final textMuted = WpColors.textMuted;
    // The suggestion panel floats over whatever the list happens to show, so
    // it takes the *pre-composited* card material and the tinted rim that
    // goes with it — the same recipe `WpDropdown` uses for its menu. A
    // translucent frost over unknown content is not a material.
    final surface = WpColors.floatingSurface;
    final borderCol = WpColors.cardEdgeHighlight;

    // Every control sits at the place the page family gives it
    // (`WpCollectionToolbar`, concept `internal-notes`, #1201): one
    // row with search, filter marks, the filter popover (view, period,
    // length), status, view tools and "new recording".
    return WpCollectionToolbar(
      screenId: 'history',
      search: WpSearchField(
        testId: 'history-search',
        clearOnEscape: true,
        controller: widget.controller,
        focusNode: widget.searchFocusNode,
        hintText: l10n.historySearchTranscriptions,
        variant: WpSearchFieldVariant.outlined,
        onClear: _clearSuggestions,
        suffix: _SearchHelpButton(
          controller: widget.controller,
          focusNode: widget.searchFocusNode,
        ),
        semanticsLabel: l10n.historySearchFieldLabel,
      ),
      // Importing audio files is the second way to add a recording, so it
      // stands with "new recording" in the row's add group instead of a row
      // of its own (#1498). Drag and drop onto the page stays.
      addActions: const [_ImportFilesButton()],
      primaryAction: const _NewRecordingButton(),
      searchExtras: [
        // ── Inline autocomplete suggestions ─────────────────────────────
        // Spans the whole bar rather than stopping at the field's edge: inside
        // the search row's `Expanded` this [AnimatedSize] would be laid out
        // twice in one frame and restart its animation from inside its own
        // `performLayout`, a hard Flutter assert. The panel belongs to the
        // search *area* and ends flush with the button.
        WpAnimatedSize(
          duration: WpMotion.durationFor(context, WpMotion.fast),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _hasSuggestions
              ? Container(
                  // Hairline gap ([WpSpacing.xxxs]) so the suggestion
                  // panel reads as attached to the search field, not floating.
                  margin: const EdgeInsets.only(top: WpSpacing.xxxs),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: WpRadius.borderSm,
                    border: Border.all(color: borderCol),
                  ),
                  // `minWidth` rather than a wrapper, so the 240 dp height
                  // cap survives (`enforce()` clamps the infinite minimum
                  // down to the parent's own maximum).
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                    minWidth: double.infinity,
                  ),
                  child: _suggestionType == _SuggestionType.smartPanel
                      ? _buildSmartPanel(l10n, accent, textMuted)
                      : _buildSimpleSuggestionList(accent, textMuted),
                )
              : const SizedBox.shrink(),
        ),
      ],
      filterSections: [
        WpFilterSection(
          id: 'view',
          label: l10n.collectionFilterShow,
          children: [
            WpFilterChip(
              testId: 'history-filter-all',
              label: l10n.historyAll,
              isActive: widget.activeFilter == HistoryFilter.all,
              onTap: () => widget.onFilterChanged(HistoryFilter.all),
              count: searchCounts?[HistoryFilter.all],
            ),
            WpFilterChip(
              testId: 'history-filter-pinned',
              label: l10n.historyPinned,
              icon: LucideIcons.star,
              isActive: widget.activeFilter == HistoryFilter.pinned,
              onTap: () => widget.onFilterChanged(HistoryFilter.pinned),
              count: searchCounts?[HistoryFilter.pinned],
            ),
            WpFilterChip(
              testId: 'history-filter-archived',
              label: l10n.historyArchived,
              icon: LucideIcons.archive,
              isActive: widget.activeFilter == HistoryFilter.archived,
              onTap: () => widget.onFilterChanged(HistoryFilter.archived),
              count: searchCounts?[HistoryFilter.archived],
            ),
            WpFilterChip(
              testId: 'history-filter-trash',
              label: l10n.historyTrash,
              icon: LucideIcons.trash2,
              isActive: widget.activeFilter == HistoryFilter.trash,
              onTap: () => widget.onFilterChanged(HistoryFilter.trash),
              count: searchCounts?[HistoryFilter.trash],
            ),
          ],
        ),
        if (viewsApply)
          smartViewFilterSection(
            context,
            ref,
            scope: scope,
            screenId: 'history',
            loadTags: loadTags,
          ),
        // The period writes the search operator `date:`; the duration
        // buckets (#879) are the one click path for length, `longer:` and
        // `shorter:` stay typed operators (#1176).
        if (showRefinements) ...[
          WpFilterSection(
            id: 'period',
            label: l10n.historyRangeFilterGroup,
            children: [
              HistoryRangeChips(
                parsed: parsed,
                query: rawQuery,
                onQueryChanged: setQuery,
              ),
            ],
          ),
          WpFilterSection(
            id: 'duration',
            label: l10n.historyDurationFilterGroup,
            children: [
              HistoryDurationChips(
                active: bucket,
                onChanged: ref.read(historyDurationBucketProvider.notifier).set,
              ),
            ],
          ),
        ],
      ],
      activeFilters: activeFilters,
      status: [
        // Pending imports and interrupted recordings: icon buttons with a
        // count in this row, never a line of their own above the search.
        if (ref.watch(historyStatusPendingProvider)) const HistoryStatusRow(),
        if (viewsApply)
          ...smartViewStatus(
            context,
            ref,
            scope: scope,
            screenId: 'history',
            loadTags: loadTags,
          ),
        if (rawQuery.isNotEmpty)
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.historyResultCount(widget.resultCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: WpTypography.small, color: textMuted),
            ),
          ),
        // Empty Trash (only in trash view, when items exist): the same
        // dense ghost danger button the snippets page shows there.
        if (widget.onEmptyTrash != null)
          WpButton(
            testId: 'history-empty-trash',
            label: l10n.historyEmptyTrash,
            icon: LucideIcons.trash2,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.danger,
            size: WpButtonSize.dense,
            onPressed: widget.onEmptyTrash,
          ),
      ],
      tools: [
        // The bordered icon button every toolbar control shares (#1498);
        // `selected` makes it the toggle and announces its state. Like on
        // Notes and Snippets it only shows when there is something to select
        // (an open selection keeps it, so it can be left).
        if (widget.resultCount > 0 || widget.multiSelectMode)
          WpIconButton(
            key: const ValueKey('history-select-toggle'),
            testId: 'history-select-toggle',
            icon: widget.multiSelectMode
                ? LucideIcons.checkCheck
                : LucideIcons.listChecks,
            tooltip: widget.multiSelectMode
                ? l10n.historyExitSelection
                : l10n.historySelectMultiple,
            selected: widget.multiSelectMode,
            onPressed: widget.onToggleMultiSelect,
          ),
        WpSortMenuButton<HistorySortOrder>(
          testId: 'history-sort',
          tooltip: _historySortOptions(
            L10n.of(context),
          ).firstWhere((option) => option.value == widget.sortOrder).label,
          options: _historySortOptions(L10n.of(context)),
          current: widget.sortOrder,
          onChanged: widget.onSortOrderChanged,
        ),
        HistoryViewModeToggle(
          viewMode: widget.viewMode,
          onChanged: widget.onViewModeChanged,
        ),
      ],
      toolsOverflow: _HistoryToolsOverflowButton(
        multiSelectMode: widget.multiSelectMode,
        onToggleMultiSelect: widget.onToggleMultiSelect,
        sortOrder: widget.sortOrder,
        onSortOrderChanged: widget.onSortOrderChanged,
        viewMode: widget.viewMode,
        onViewModeChanged: widget.onViewModeChanged,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dismiss control of the recent-search rows
// ---------------------------------------------------------------------------

/// Small focusable "x" dismiss control of the recent-search rows
/// — keyboard focus + hover feedback, matching the [WpFocusRing]/[InkWell]
/// pattern every other dismiss/tag control in
/// this feature already uses (e.g. `_EntryTagChip`, `WpFilterChip`).
class _DismissIcon extends StatefulWidget {
  const _DismissIcon({
    required this.testId,
    required this.icon,
    required this.size,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

  final String testId;
  final IconData icon;
  final double size;
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_DismissIcon> createState() => _DismissIconState();
}

class _DismissIconState extends State<_DismissIcon> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: widget.testId,
      label: widget.semanticLabel,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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
            child: Icon(widget.icon, size: widget.size, color: widget.color),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// View mode toggle — segmented icon button group
// ---------------------------------------------------------------------------

class HistoryViewModeToggle extends StatelessWidget {
  const HistoryViewModeToggle({
    super.key,
    required this.viewMode,
    required this.onChanged,
  });

  final HistoryViewMode viewMode;
  final ValueChanged<HistoryViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    // The track wears the toolbar's icon-button shell (#1498): 44 px high,
    // `cardFillElevated` fill, `borderDefault` edge, 8 px corners, so the
    // segmented control and the filter, select, sort and add buttons beside
    // it read as one set. The active segment's accent fill is the only
    // raised part inside it.
    return Container(
      height: WpIconButton.extent,
      // Hairline step: classic segmented-control inset between the
      // track and its segments; xxs would make the track look chunky.
      padding: const EdgeInsets.all(WpSpacing.xxxs),
      decoration: BoxDecoration(
        color: WpColors.cardFillElevated,
        borderRadius: WpRadius.borderSm,
        border: Border.all(color: WpColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HistoryViewModeButton(
            icon: LucideIcons.list,
            testId: 'history-view-list',
            label: L10n.of(context).historyList,
            isActive: viewMode == HistoryViewMode.list,
            onTap: () => onChanged(HistoryViewMode.list),
          ),
          _HistoryViewModeButton(
            icon: LucideIcons.layoutGrid,
            testId: 'history-view-cards',
            label: L10n.of(context).historyCards,
            isActive: viewMode == HistoryViewMode.cards,
            onTap: () => onChanged(HistoryViewMode.cards),
          ),
          _HistoryViewModeButton(
            icon: LucideIcons.rows3,
            testId: 'history-view-compact',
            label: L10n.of(context).historyCompact,
            isActive: viewMode == HistoryViewMode.compact,
            onTap: () => onChanged(HistoryViewMode.compact),
          ),
        ],
      ),
    );
  }
}

class _HistoryViewModeButton extends StatefulWidget {
  const _HistoryViewModeButton({
    required this.testId,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String testId;
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_HistoryViewModeButton> createState() => _HistoryViewModeButtonState();
}

/// Side of one view segment: the track's inner height.
const double _segmentExtent = WpIconButton.extent - 2 * WpSpacing.xxxs - 2;

class _HistoryViewModeButtonState extends State<_HistoryViewModeButton> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'HistoryViewModeButton');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? (WpColors.accent) : (WpColors.textMuted);
    // Same rung as WpFilterChip's active fill (ticket 03, point 6): the two
    // are the app's selectable controls and sit side by side in this very
    // bar, so "selected" has to mean the same amount of accent in both. The
    // former `accentSubtle` was off-ladder and theme-asymmetric.
    final bg = widget.isActive
        ? (WpColors.accentActiveFill)
        : Colors.transparent;
    return Semantics(
      identifier: widget.testId,
      label: widget.label,
      button: true,
      // Icon-only segments: without this flag the three announce identically
      // whichever one is on, so a screen-reader user cannot tell which view
      // they are in — only that three view buttons exist. Same mapping as
      // WpFilterChip, the app's other selectable control.
      selected: widget.isActive,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        // InkWell rather than the previous GestureDetector: this was the only
        // control in the filter bar Tab could not reach, so switching the view
        // meant reaching for the mouse — the one thing this audience must never
        // have to do. Focus visuals come from WpFocusRing, as everywhere else.
        child: InkWell(
          onTap: widget.onTap,
          focusNode: _focusNode,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.sm,
            // A square segment filling the track's height (44 - 2 × 2 inset
            // - 2 × 1 edge = 38 px), with the toolbar's 20 px glyph, so the
            // three views are as easy to hit as the icon buttons beside them.
            child: Container(
              width: _segmentExtent,
              height: _segmentExtent,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: WpRadius.borderSm,
              ),
              child: Icon(widget.icon, size: WpIconSize.md, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "New recording" — the page's primary action
// ---------------------------------------------------------------------------

/// The button beside the search field, mirroring Notes' "New note" and the
/// Replacements/Snippets "Add": every list screen offers the one thing that
/// puts an item *into* that list, in the same place.
///
/// It is deliberately a second trigger for the existing pipeline rather than a
/// recording path of its own — [RecordingOrchestrator.toggleRecording] is the
/// exact method the systemwide hotkey handler calls (the onboarding test
/// recording routes through it for the same reason). Everything downstream
/// therefore behaves identically to a hotkey start, including the case where
/// WhisPaste itself holds the focus and there is nothing to paste into: the
/// orchestrator leaves the text in the clipboard and says so. The History
/// entry is written either way.
///
/// And because `toggleRecording` *toggles*, the same button stops the
/// recording it started. That is the point rather than a side effect: the
/// recording overlay can be switched off, and a hotkey is not always where the
/// hand is — someone who started a recording from this button has to be able
/// to end it from this button. So it never greys out while a recording runs;
/// it changes what it says it will do.
///
/// The two states borrow [WpVoiceInputButton]'s vocabulary rather than
/// inventing a second one: microphone glyph to start, filled square to stop,
/// and the stop state carries the `danger` tone, which is the same red that
/// button uses for "running, tap to end". `danger` here reads as "this ends
/// something that is live", not "this destroys data" — the label says which.
///
/// Transcribing is the one state that does disable, and only because
/// `toggleRecording` is a documented no-op there: the audio is already on its
/// way through the pipeline, and nothing sensible remains to stop. The
/// spinner says so, the tooltip names the phase.
class _NewRecordingButton extends ConsumerWidget {
  const _NewRecordingButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final phase = ref.watch(recordingPhaseProvider);
    final isRecording = phase == RecordingPhase.recording;
    // Smart Mode v2 (ticket 02): `refining` extends the same in-flight
    // window `transcribing` used to cover alone — `toggleRecording` is a
    // no-op there too, so the button must keep disabling through it.
    final isTranscribing =
        phase == RecordingPhase.transcribing ||
        phase == RecordingPhase.refining;
    // Inside a saved view nothing new starts from here (#658): the new
    // recording might not match the view. A running recording still stops,
    // and the global hotkey is never touched (Nordstern).
    final locked =
        !isRecording && ref.watch(shownHistorySmartViewProvider) != null;

    // Beside the search field: an icon button of the same height
    // (WpLayout.controlHeight, UX-131). Its label is the tooltip and accessible name.
    return WpIconButton(
      testId: 'history-new-recording',
      icon: isRecording ? LucideIcons.square : LucideIcons.mic,
      // While transcribing the tooltip says why the press does nothing.
      tooltip: isTranscribing
          ? l10n.statusTranscribing
          : locked
          ? l10n.smartViewCreateLocked
          : isRecording
          ? l10n.historyStopRecording
          : l10n.historyNewRecording,
      danger: isRecording,
      loading: isTranscribing,
      // Live in every phase but `transcribing` — `toggleRecording` decides
      // what the press means (start from idle/done/error, stop while
      // recording), exactly as it does for the hotkey.
      onPressed: isTranscribing || locked
          ? null
          : () => ref
                .read(recordingOrchestratorProvider.notifier)
                .toggleRecording(),
    );
  }
}

/// Opens the file dialog of the import. The dialog itself belongs to
/// `AudioImportPanel`, which takes the request, so a press here, the tray
/// entry and the panel's own listener stay one path.
class _ImportFilesButton extends ConsumerWidget {
  const _ImportFilesButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    // Imports add recordings, so inside a saved view they wait (#658).
    final locked = ref.watch(shownHistorySmartViewProvider) != null;
    return WpIconButton(
      key: const ValueKey('history-import-add'),
      testId: 'history-import-add',
      icon: LucideIcons.filePlus,
      tooltip: locked ? l10n.smartViewCreateLocked : l10n.historyImportAddFiles,
      onPressed: locked
          ? null
          : () => ref.read(audioImportPickRequestProvider.notifier).request(),
    );
  }
}

// ---------------------------------------------------------------------------
// Search help tooltip button
// ---------------------------------------------------------------------------

class _SearchHelpButton extends StatelessWidget {
  const _SearchHelpButton({required this.controller, this.focusNode});

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// Appends [token] to the query and puts the caret after it, so the next
  /// keystroke completes the filter (`#` → tag suggestions open). The
  /// controller listener runs the search.
  void _start(String token) {
    final text = controller.text;
    final glue = text.isEmpty || text.endsWith(' ') ? '' : ' ';
    final next = '$text$glue$token';
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // The tips are the shared list menu (#1757): each tip is also the way to
    // use it, a pick starts that filter in the field.
    return Builder(
      builder: (buttonContext) => WpIconButton.ghost(
        testId: 'history-search-help',
        icon: LucideIcons.info,
        tooltip: l10n.historySearchHelpTitle,
        onPressed: () => unawaited(
          showWpListMenu(buttonContext, [
            WpListMenuAction(
              itemKey: const ValueKey('history-search-help-tags'),
              label: l10n.historySearchHelpTags,
              hint: '#meeting',
              icon: LucideIcons.tag,
              onSelected: () => _start('#'),
            ),
            WpListMenuAction(
              itemKey: const ValueKey('history-search-help-lang'),
              label: l10n.historySearchHelpLang,
              hint: 'lang:en',
              icon: LucideIcons.globe,
              onSelected: () => _start('lang:'),
            ),
            WpListMenuAction(
              itemKey: const ValueKey('history-search-help-range'),
              label: l10n.historySearchHelpRange,
              hint: 'date:7d',
              icon: LucideIcons.calendarRange,
              onSelected: () => _start('date:'),
            ),
            WpListMenuAction(
              itemKey: const ValueKey('history-search-help-text'),
              label: l10n.historySearchHelpFreeText,
              icon: LucideIcons.textSearch,
              onSelected: () => focusNode?.requestFocus(),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort order options (the control itself is the shared WpSortMenuButton)
// ---------------------------------------------------------------------------

List<WpSortOption<HistorySortOrder>> _historySortOptions(L10n l10n) => [
  WpSortOption(
    value: HistorySortOrder.newest,
    id: 'newest',
    label: l10n.historySortNewest,
    icon: LucideIcons.arrowDownWideNarrow,
  ),
  WpSortOption(
    value: HistorySortOrder.oldest,
    id: 'oldest',
    label: l10n.historySortOldest,
    icon: LucideIcons.arrowUpNarrowWide,
  ),
  WpSortOption(
    value: HistorySortOrder.longest,
    id: 'longest',
    label: l10n.historySortLongest,
    icon: LucideIcons.ruler,
  ),
];

// ---------------------------------------------------------------------------
// Collapsed view tools (narrow filter row)
// ---------------------------------------------------------------------------

/// The one toolbar icon button that stands in for the select, sort and view tools
/// on a narrow filter row. Its menu lists the same three controls; the current
/// view, sort order and selection mode carry a check.
class _HistoryToolsOverflowButton extends StatefulWidget {
  const _HistoryToolsOverflowButton({
    required this.multiSelectMode,
    required this.onToggleMultiSelect,
    required this.sortOrder,
    required this.onSortOrderChanged,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final bool multiSelectMode;
  final VoidCallback onToggleMultiSelect;
  final HistorySortOrder sortOrder;
  final ValueChanged<HistorySortOrder> onSortOrderChanged;
  final HistoryViewMode viewMode;
  final ValueChanged<HistoryViewMode> onViewModeChanged;

  @override
  State<_HistoryToolsOverflowButton> createState() =>
      _HistoryToolsOverflowButtonState();
}

class _HistoryToolsOverflowButtonState
    extends State<_HistoryToolsOverflowButton> {
  String _viewLabel(L10n l10n, HistoryViewMode mode) => switch (mode) {
    HistoryViewMode.list => l10n.historyList,
    HistoryViewMode.cards => l10n.historyCards,
    HistoryViewMode.compact => l10n.historyCompact,
  };

  static const Map<HistoryViewMode, IconData> _viewIcons = {
    HistoryViewMode.list: LucideIcons.list,
    HistoryViewMode.cards: LucideIcons.layoutGrid,
    HistoryViewMode.compact: LucideIcons.rows3,
  };

  /// The collapsed tools as the shared list menu (#1757): view, sort and
  /// selection, one group each, the current choice checked.
  void _openMenu(BuildContext buttonContext, L10n l10n) {
    final sortOptions = _historySortOptions(l10n);
    unawaited(
      showWpListMenu(buttonContext, [
        for (final mode in HistoryViewMode.values)
          WpListMenuAction(
            itemKey: ValueKey('history-toolbar-view-${mode.name}'),
            label: _viewLabel(l10n, mode),
            icon: _viewIcons[mode]!,
            checked: widget.viewMode == mode,
            onSelected: () => widget.onViewModeChanged(mode),
          ),
        for (final (index, option) in sortOptions.indexed)
          WpListMenuAction(
            itemKey: ValueKey('history-toolbar-sort-${option.value.name}'),
            label: option.label,
            icon: option.icon,
            checked: widget.sortOrder == option.value,
            dividerBefore: index == 0,
            onSelected: () => widget.onSortOrderChanged(option.value),
          ),
        WpListMenuAction(
          itemKey: const ValueKey('history-toolbar-select'),
          label: widget.multiSelectMode
              ? l10n.historyExitSelection
              : l10n.historySelectMultiple,
          icon: LucideIcons.listChecks,
          checked: widget.multiSelectMode,
          dividerBefore: true,
          onSelected: widget.onToggleMultiSelect,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // The bordered icon button the filter, sort and new-recording controls
    // share (#1498). The accent glyph says that selection mode is on.
    return WpIconButton(
      key: const ValueKey('history-toolbar-overflow'),
      testId: 'history-tools-more',
      icon: LucideIcons.slidersHorizontal,
      tooltip: l10n.historyToolsMenu,
      color: widget.multiSelectMode ? WpColors.accent : null,
      onPressed: () => _openMenu(context, l10n),
    );
  }
}
