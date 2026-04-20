import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../data/providers.dart';
import '../data/recent_searches.dart';
import 'history_filter_chip.dart';
import 'history_helpers.dart';

// ---------------------------------------------------------------------------
// Suggestion type for autocomplete
// ---------------------------------------------------------------------------

enum _SuggestionType { none, tag, lang, smartPanel }

const _kLangOptions = [
  'de', 'en', 'fr', 'es', 'it', 'pt', 'nl', 'pl', 'ru', 'zh', 'ja', 'ko',
  'ar', 'tr', 'sv', 'da', 'fi', 'nb', 'cs', 'sk', 'hu', 'ro',
];

// ---------------------------------------------------------------------------
// Search & filter toolbar
// ---------------------------------------------------------------------------

class HistorySearchToolbar extends ConsumerStatefulWidget {
  const HistorySearchToolbar({
    super.key,
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
    required this.sortOrder,
    required this.onSortOrderChanged,
    this.searchFocusNode,
    this.onEmptyTrash,
  });

  final TextEditingController controller;
  final HistoryFilter activeFilter;
  final bool isDark;
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
  ConsumerState<HistorySearchToolbar> createState() =>
      _HistorySearchToolbarState();
}

class _HistorySearchToolbarState extends ConsumerState<HistorySearchToolbar> {
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
  }

  @override
  void didUpdateWidget(covariant HistorySearchToolbar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
    }
    if (old.searchFocusNode != widget.searchFocusNode) {
      old.searchFocusNode?.removeListener(_onFocusChange);
      widget.searchFocusNode?.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    widget.controller.removeListener(_onControllerChange);
    widget.searchFocusNode?.removeListener(_onFocusChange);
    super.dispose();
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
    final cursor =
        sel.isValid ? sel.baseOffset.clamp(0, text.length) : text.length;
    final before = text.substring(0, cursor);

    // Detect #tag trigger
    final tagMatch = RegExp(r'#([\w-]*)$').firstMatch(before);
    if (tagMatch != null) {
      _loadTagSuggestions(tagMatch.group(1)!.toLowerCase());
      return;
    }

    // Detect lang: trigger
    final langMatch =
        RegExp(r'\blang:([\w-]*)$', caseSensitive: false).firstMatch(before);
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
    final sorted = [...tagsWithCount]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final topTags = sorted.take(8).map((t) => t.$1.name).toList();
    // Only show panel if there's content
    if (topTags.isEmpty && recentList.isEmpty) return;
    setState(() {
      _recentSearches = recentList.take(3).toList();
      _quickTags = topTags;
      _suggestions = topTags;
      _suggestionType = _SuggestionType.smartPanel;
      _selectedIdx = 0;
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
    final filtered =
        tags.map((t) => t.name).where((n) => !existing.contains(n)).toList();
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

  void _selectSuggestion(String suggestion) {
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final cursor =
        sel.isValid ? sel.baseOffset.clamp(0, text.length) : text.length;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);

    String newBefore;
    if (_suggestionType == _SuggestionType.smartPanel) {
      // Insert full #tag from the smart panel
      newBefore = '$before#$suggestion ';
    } else if (_suggestionType == _SuggestionType.tag) {
      newBefore =
          before.replaceAll(RegExp(r'#[\w-]*$'), '#$suggestion ');
    } else {
      newBefore = before.replaceAll(
          RegExp(r'\blang:[\w-]*$', caseSensitive: false), 'lang:$suggestion ');
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
            for (final query in _recentSearches)
              _recentSearchItem(query, accent, textMuted),
          ],
          // Section: Popular Tags
          if (_quickTags.isNotEmpty) ...[
            if (_recentSearches.isNotEmpty)
              const SizedBox(height: WpSpacing.xs),
            _sectionHeader(l10n.historySearchQuickTags, textMuted),
            for (final tag in _quickTags)
              _tagItem(tag, accent, textMuted),
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
        WpSpacing.md, WpSpacing.xxs, WpSpacing.md, 2,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textMuted,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _recentSearchItem(String query, Color accent, Color textMuted) {
    return InkWell(
      onTap: () => _replayRecentSearch(query),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.xxs + 1,
        ),
        child: Row(
          children: [
            Icon(LucideIcons.clock, size: 13, color: textMuted),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                query,
                style: TextStyle(fontSize: 13, color: textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () {
                ref.read(recentSearchesProvider.notifier).removeSearch(query);
                setState(() {
                  _recentSearches =
                      _recentSearches.where((s) => s != query).toList();
                });
              },
              child: Icon(LucideIcons.x, size: 12, color: textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagItem(String tag, Color accent, Color textMuted) {
    return InkWell(
      onTap: () => _selectSuggestion(tag),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.xxs + 1,
        ),
        child: Row(
          children: [
            Icon(LucideIcons.tag, size: 13, color: textMuted),
            const SizedBox(width: WpSpacing.xs),
            Text(
              '#$tag',
              style: TextStyle(fontSize: 13, color: textMuted),
            ),
          ],
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
          color: accent.withValues(alpha: 0.08),
          borderRadius: WpRadius.borderFull,
          border: Border.all(color: accent.withValues(alpha: 0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      itemCount: _suggestions.length,
      itemBuilder: (ctx, i) {
        final selected = i == _selectedIdx;
        final s = _suggestions[i];
        return InkWell(
          onTap: () => _selectSuggestion(s),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.xs,
            ),
            color: selected
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            child: Row(
              children: [
                Icon(
                  _suggestionType == _SuggestionType.lang
                      ? LucideIcons.globe
                      : LucideIcons.tag,
                  size: 13,
                  color: selected ? accent : textMuted,
                ),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  _suggestionType == _SuggestionType.lang
                      ? 'lang:$s'
                      : '#$s',
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? accent : textMuted,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
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
    final activeCommands = <String>[];
    for (final tag in parsed.tagNames) {
      activeCommands.add('#$tag');
    }
    if (parsed.langCode != null) {
      activeCommands.add('lang:${parsed.langCode}');
    }

    final accent =
        widget.isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textMuted =
        widget.isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surface = widget.isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final borderCol = widget.isDark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.sm,
        WpSpacing.xl,
        WpSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Search field ────────────────────────────────────────────────
          TextField(
            controller: widget.controller,
            focusNode: widget.searchFocusNode,
            decoration: InputDecoration(
              hintText: l10n.historySearchTranscriptions,
              prefixIcon: Icon(
                LucideIcons.search,
                size: WpIconSize.sm,
                color: textMuted,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rawQuery.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        LucideIcons.x,
                        size: WpIconSize.sm,
                        color: textMuted,
                      ),
                      onPressed: () {
                        widget.controller.clear();
                        _clearSuggestions();
                      },
                    ),
                  _SearchHelpButton(isDark: widget.isDark),
                ],
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.xs + 2,
              ),
            ),
            onChanged: (_) {}, // handled by controller listener
          ),

          // ── Inline autocomplete suggestions ─────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _hasSuggestions
                ? Container(
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: WpRadius.borderSm,
                      border: Border.all(color: borderCol),
                    ),
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: _suggestionType == _SuggestionType.smartPanel
                        ? _buildSmartPanel(l10n, accent, textMuted)
                        : _buildSimpleSuggestionList(accent, textMuted),
                  )
                : const SizedBox.shrink(),
          ),

          // ── Active command chips ─────────────────────────────────────────
          if (activeCommands.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.xs),
            Wrap(
              spacing: WpSpacing.xs,
              runSpacing: WpSpacing.xxs,
              children: [
                for (final cmd in activeCommands)
                  _CommandChip(
                    label: cmd,
                    isDark: widget.isDark,
                    onRemove: () => _removeCommand(cmd),
                  ),
              ],
            ),
          ],

          const SizedBox(height: WpSpacing.sm),

          // ── Filter chips + controls ──────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      HistoryFilterChip(
                        label: l10n.historyAll,
                        isActive: widget.activeFilter == HistoryFilter.all,
                        onTap: () =>
                            widget.onFilterChanged(HistoryFilter.all),
                        isDark: widget.isDark,
                        count: searchCounts?[HistoryFilter.all],
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyToday,
                        isActive: widget.activeFilter == HistoryFilter.today,
                        onTap: () =>
                            widget.onFilterChanged(HistoryFilter.today),
                        isDark: widget.isDark,
                        count: searchCounts?[HistoryFilter.today],
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyThisWeek,
                        isActive: widget.activeFilter == HistoryFilter.week,
                        onTap: () =>
                            widget.onFilterChanged(HistoryFilter.week),
                        isDark: widget.isDark,
                        count: searchCounts?[HistoryFilter.week],
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyPinned,
                        icon: LucideIcons.star,
                        isActive:
                            widget.activeFilter == HistoryFilter.pinned,
                        onTap: () =>
                            widget.onFilterChanged(HistoryFilter.pinned),
                        isDark: widget.isDark,
                        count: searchCounts?[HistoryFilter.pinned],
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyArchived,
                        icon: LucideIcons.archive,
                        isActive:
                            widget.activeFilter == HistoryFilter.archived,
                        onTap: () =>
                            widget.onFilterChanged(HistoryFilter.archived),
                        isDark: widget.isDark,
                        count: searchCounts?[HistoryFilter.archived],
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      HistoryFilterChip(
                        label: l10n.historyTrash,
                        icon: LucideIcons.trash2,
                        isActive:
                            widget.activeFilter == HistoryFilter.trash,
                        onTap: () =>
                            widget.onFilterChanged(HistoryFilter.trash),
                        isDark: widget.isDark,
                        count: searchCounts?[HistoryFilter.trash],
                      ),
                    ],
                  ),
                ),
              ),
              // Result count
              if (rawQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: WpSpacing.sm),
                  child: Text(
                    l10n.historyResultCount(widget.resultCount),
                    style: TextStyle(fontSize: 12, color: textMuted),
                  ),
                ),
              const SizedBox(width: WpSpacing.xs),
              // Empty Trash button (only in trash view, when items exist)
              if (widget.onEmptyTrash != null)
                Tooltip(
                  message: l10n.historyEmptyTrash,
                  child: InkWell(
                    borderRadius: WpRadius.borderSm,
                    onTap: widget.onEmptyTrash,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WpSpacing.sm,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.trash2,
                            size: WpIconSize.sm,
                            color: widget.isDark
                                ? WpColorsDark.error
                                : WpColorsLight.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.historyEmptyTrash,
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark
                                  ? WpColorsDark.error
                                  : WpColorsLight.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Multi-select toggle
              Tooltip(
                message: widget.multiSelectMode
                    ? l10n.historyExitSelection
                    : l10n.historySelectMultiple,
                child: InkWell(
                  borderRadius: WpRadius.borderSm,
                  onTap: widget.onToggleMultiSelect,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      widget.multiSelectMode
                          ? LucideIcons.checkCheck
                          : LucideIcons.listChecks,
                      size: WpIconSize.sm,
                      color: widget.multiSelectMode
                          ? accent
                          : textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xxs),
              // Sort order dropdown
              _SortDropdown(
                sortOrder: widget.sortOrder,
                isDark: widget.isDark,
                onChanged: widget.onSortOrderChanged,
              ),
              const SizedBox(width: WpSpacing.xxs),
              // View mode toggle
              HistoryViewModeToggle(
                viewMode: widget.viewMode,
                isDark: widget.isDark,
                onChanged: widget.onViewModeChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active command chip (removable)
// ---------------------------------------------------------------------------

class _CommandChip extends StatelessWidget {
  const _CommandChip({
    required this.label,
    required this.isDark,
    required this.onRemove,
  });

  final String label;
  final bool isDark;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs + 2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onRemove,
            child: Icon(LucideIcons.x, size: 11, color: accent),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-select action bar
// ---------------------------------------------------------------------------

class HistoryMultiSelectBar extends StatelessWidget {
  const HistoryMultiSelectBar({
    super.key,
    required this.selectedCount,
    required this.isDark,
    required this.isTrashView,
    required this.isArchiveView,
    required this.onCancelSelection,
    this.onSelectAll,
    this.totalCount,
    this.onMerge,
    this.onBatchCopy,
    this.onArchive,
    this.onDelete,
    this.onRestore,
  });

  final int selectedCount;
  final bool isDark;
  final bool isTrashView;
  final bool isArchiveView;
  final VoidCallback onCancelSelection;
  final VoidCallback? onSelectAll;
  final int? totalCount;
  final VoidCallback? onMerge;
  final VoidCallback? onBatchCopy;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
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
          bottom: BorderSide(color: accent.withValues(alpha: 0.2), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Selection count
          Flexible(
            child: Container(
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
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          // Select All / Deselect All toggle
          if (onSelectAll != null)
            InkWell(
              borderRadius: WpRadius.borderSm,
              onTap: onSelectAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.xs,
                  vertical: 4,
                ),
                child: Text(
                  totalCount != null && selectedCount >= totalCount!
                      ? l10n.historyDeselectAll
                      : l10n.historySelectAll,
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          const SizedBox(width: WpSpacing.sm),
          // Action buttons — wrap in Flexible to prevent overflow
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onMerge != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.merge,
                      label: l10n.historyMerge,
                      shortcutHint: formatHotkeyShortcut(
                        'ctrl',
                        'm',
                        l10n: l10n,
                      ),
                      isDark: isDark,
                      onTap: onMerge!,
                    ),
                  if (onBatchCopy != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.copy,
                      label: l10n.historyCopyText,
                      shortcutHint: formatHotkeyShortcut(
                        'ctrl',
                        'c',
                        l10n: l10n,
                      ),
                      isDark: isDark,
                      onTap: onBatchCopy!,
                    ),
                  if (onRestore != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.undo2,
                      label: l10n.historyRestore,
                      isDark: isDark,
                      onTap: onRestore!,
                    ),
                  if (onArchive != null)
                    HistoryMultiSelectAction(
                      icon: isArchiveView
                          ? LucideIcons.archiveRestore
                          : LucideIcons.archive,
                      label: isArchiveView
                          ? l10n.historyUnarchive
                          : l10n.historyArchive,
                      isDark: isDark,
                      onTap: onArchive!,
                    ),
                  if (onDelete != null)
                    HistoryMultiSelectAction(
                      icon: LucideIcons.trash2,
                      label: isTrashView
                          ? l10n.historyDeleteForever
                          : l10n.actionDelete,
                      shortcutHint: hotkeyKeyLabel('delete', l10n: l10n),
                      isDark: isDark,
                      onTap: onDelete!,
                      isDestructive: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
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

// ---------------------------------------------------------------------------
// Multi-select action button
// ---------------------------------------------------------------------------

class HistoryMultiSelectAction extends StatefulWidget {
  const HistoryMultiSelectAction({
    super.key,
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.shortcutHint,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final String? shortcutHint;
  final bool isDestructive;

  @override
  State<HistoryMultiSelectAction> createState() =>
      _HistoryMultiSelectActionState();
}

class _HistoryMultiSelectActionState extends State<HistoryMultiSelectAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textSecondary = widget.isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final hoverColor = widget.isDestructive
        ? (widget.isDark ? WpColorsDark.error : WpColorsLight.error)
        : (widget.isDark
              ? WpColorsDark.textPrimary
              : WpColorsLight.textPrimary);
    final color = _hovered ? hoverColor : textSecondary;

    return Padding(
      padding: const EdgeInsets.only(right: WpSpacing.xs),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: widget.shortcutHint != null
              ? '${widget.label} (${widget.shortcutHint})'
              : widget.label,
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
// View mode toggle — segmented icon button group
// ---------------------------------------------------------------------------

class HistoryViewModeToggle extends StatelessWidget {
  const HistoryViewModeToggle({
    super.key,
    required this.viewMode,
    required this.isDark,
    required this.onChanged,
  });

  final HistoryViewMode viewMode;
  final bool isDark;
  final ValueChanged<HistoryViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: WpRadius.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HistoryViewModeButton(
            icon: LucideIcons.list,
            isActive: viewMode == HistoryViewMode.list,
            isDark: isDark,
            onTap: () => onChanged(HistoryViewMode.list),
          ),
          _HistoryViewModeButton(
            icon: LucideIcons.layoutGrid,
            isActive: viewMode == HistoryViewMode.cards,
            isDark: isDark,
            onTap: () => onChanged(HistoryViewMode.cards),
          ),
          _HistoryViewModeButton(
            icon: LucideIcons.rows3,
            isActive: viewMode == HistoryViewMode.compact,
            isDark: isDark,
            onTap: () => onChanged(HistoryViewMode.compact),
          ),
        ],
      ),
    );
  }
}

class _HistoryViewModeButton extends StatelessWidget {
  const _HistoryViewModeButton({
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
          decoration: BoxDecoration(color: bg, borderRadius: WpRadius.borderSm),
          child: Icon(icon, size: WpIconSize.sm, color: color),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search help tooltip button
// ---------------------------------------------------------------------------

class _SearchHelpButton extends StatelessWidget {
  const _SearchHelpButton({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final surface = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;

    return IconButton(
      icon: Icon(LucideIcons.info, size: 15, color: textMuted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: l10n.historySearchHelpTitle,
      onPressed: () {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null) return;
        final offset = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;

        showMenu<void>(
          context: context,
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy + size.height,
            offset.dx + size.width,
            offset.dy + size.height + 200,
          ),
          shape: RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
          color: surface,
          items: [
            PopupMenuItem<void>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.historySearchHelpTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  _HelpRow(
                    icon: LucideIcons.tag,
                    text: l10n.historySearchHelpTags,
                    example: '#meeting',
                    isDark: isDark,
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  _HelpRow(
                    icon: LucideIcons.globe,
                    text: l10n.historySearchHelpLang,
                    example: 'lang:en',
                    isDark: isDark,
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  _HelpRow(
                    icon: LucideIcons.textSearch,
                    text: l10n.historySearchHelpFreeText,
                    example: '',
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    required this.icon,
    required this.text,
    required this.example,
    required this.isDark,
  });

  final IconData icon;
  final String text;
  final String example;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: textMuted),
        const SizedBox(width: WpSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: textMuted),
          ),
        ),
        if (example.isNotEmpty) ...[
          const SizedBox(width: WpSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              example,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sort order dropdown
// ---------------------------------------------------------------------------

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({
    required this.sortOrder,
    required this.isDark,
    required this.onChanged,
  });

  final HistorySortOrder sortOrder;
  final bool isDark;
  final ValueChanged<HistorySortOrder> onChanged;

  IconData get _icon {
    switch (sortOrder) {
      case HistorySortOrder.newest:
        return LucideIcons.arrowDownWideNarrow;
      case HistorySortOrder.oldest:
        return LucideIcons.arrowUpNarrowWide;
      case HistorySortOrder.longest:
        return LucideIcons.ruler;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    final labels = {
      HistorySortOrder.newest: l10n.historySortNewest,
      HistorySortOrder.oldest: l10n.historySortOldest,
      HistorySortOrder.longest: l10n.historySortLongest,
    };

    return PopupMenuButton<HistorySortOrder>(
      icon: Icon(_icon, size: WpIconSize.sm, color: textMuted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: labels[sortOrder] ?? '',
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
      itemBuilder: (ctx) => HistorySortOrder.values.map((order) {
        final isSelected = order == sortOrder;
        return PopupMenuItem<HistorySortOrder>(
          value: order,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                order == HistorySortOrder.newest
                    ? LucideIcons.arrowDownWideNarrow
                    : order == HistorySortOrder.oldest
                        ? LucideIcons.arrowUpNarrowWide
                        : LucideIcons.ruler,
                size: 14,
                color: isSelected ? accent : textMuted,
              ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                labels[order] ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? accent : null,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
