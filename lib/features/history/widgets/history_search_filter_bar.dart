import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_labels.dart';
import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/recording/recording_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/recording_orchestrator.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_search_field.dart';
import '../data/providers.dart';
import '../data/recent_searches.dart';
import 'history_helpers.dart';

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

    // Only the simple tag/lang list is navigable. The smart panel renders three
    // heterogeneous sections and ignores _selectedIdx entirely, so consuming
    // arrows there would swallow the caret keys for no visible effect —
    // deliberately left to a follow-up ticket.
    if (_suggestionType != _SuggestionType.tag &&
        _suggestionType != _SuggestionType.lang) {
      return KeyEventResult.ignored;
    }
    if (_suggestions.isEmpty) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIdx = (_selectedIdx + 1) % _suggestions.length;
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIdx = _selectedIdx <= 0
            ? _suggestions.length - 1
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
      if (_selectedIdx >= 0 && _selectedIdx < _suggestions.length) {
        _selectSuggestion(_suggestions[_selectedIdx]);
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
            for (final query in _recentSearches)
              _recentSearchItem(query, accent, textMuted),
          ],
          // Section: Popular Tags
          if (_quickTags.isNotEmpty) ...[
            if (_recentSearches.isNotEmpty)
              const SizedBox(height: WpSpacing.xs),
            _sectionHeader(l10n.historySearchQuickTags, textMuted),
            for (final tag in _quickTags) _tagItem(tag, accent, textMuted),
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
                style: TextStyle(fontSize: WpTypography.body, color: textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _DismissIconState.build
            _DismissIcon(
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
              style: TextStyle(fontSize: WpTypography.body, color: textMuted),
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
          color: WpColors.accentButtonFill,
          borderRadius: WpRadius.borderFull,
          border: Border.all(color: WpColors.accentBorder20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: accent),
            const SizedBox(width: 4),
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
                      size: 13,
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
    final activeCommands = <String>[];
    for (final tag in parsed.tagNames) {
      activeCommands.add('#$tag');
    }
    if (parsed.langCode != null) {
      activeCommands.add('lang:${parsed.langCode}');
    }

    const accent = WpColors.accent;
    const textMuted = WpColors.textMuted;
    const surface = WpColors.surfaceElevated;
    const borderCol = WpColors.borderDefault;

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
          // ── Search field + "new recording" button ────────────────────────
          //
          // Same row shape as Notes and Replacements/Snippets: the field takes
          // everything the row has and stops one `WpSpacing.sm` short of the
          // primary button. Both boxes are 48 dp — the field's icon-slot
          // floor, the button's Material tap target — so the row's default
          // centring lands them on exactly the same two edges.
          Row(
            children: [
              Expanded(
                child: WpSearchField(
                  controller: widget.controller,
                  focusNode: widget.searchFocusNode,
                  hintText: l10n.historySearchTranscriptions,
                  variant: WpSearchFieldVariant.outlined,
                  onClear: _clearSuggestions,
                  suffix: const _SearchHelpButton(),
                  semanticsLabel: l10n.historySearchFieldLabel,
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              const _NewRecordingButton(),
            ],
          ),

          // A one-time `WpDiscoverabilityHint` used to sit here, teaching the
          // `#tag` and `lang:xx` operators in a line of its own. It was the
          // only reason this bar stood 21 dp taller than every other search
          // bar in the app until someone dismissed it, and it said nothing
          // the info button *inside the field* doesn't already say better:
          // that popover names both operators with a worked example each
          // (`#meeting`, `lang:en`) plus the free-text case. One place for
          // the same lesson, and the search area is now the same height
          // everywhere from the first frame on.

          // ── Inline autocomplete suggestions ─────────────────────────────
          // Spans the whole bar rather than stopping at the field's right
          // edge, and that is a decision rather than an oversight. Nesting it
          // inside the `Expanded` above would align it with the field, but it
          // also puts this [AnimatedSize] inside a flex child, where it gets
          // laid out twice in one frame and restarts its animation from
          // inside its own `performLayout` — a hard Flutter assert, caught by
          // the store screenshot goldens. Full-bar width is the honest
          // alternative: the panel belongs to the search *area*, it ends
          // flush with the button, and nothing about it has to know how wide
          // that button's label made it.
          WpAnimatedSize(
            duration: WpMotion.durationFor(context, WpMotion.fast),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _hasSuggestions
                ? Container(
                    // Off-scale on purpose: hairline gap so the suggestion
                    // panel reads as attached to the search field, not floating.
                    margin: const EdgeInsets.only(top: 2),
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

          // ── Active command chips ─────────────────────────────────────────
          if (activeCommands.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.xs),
            Wrap(
              spacing: WpSpacing.xs,
              runSpacing: WpSpacing.xxs,
              children: [
                for (final cmd in activeCommands)
                  _CommandChip(label: cmd, onRemove: () => _removeCommand(cmd)),
              ],
            ),
          ],

          // Same gap Notes puts between its search row and its filter chips.
          // It used to be `sm` here, which made this whole bar 4 dp taller
          // than the Notes one although both stack the same two rows between
          // the same `xl/sm` padding — the kind of drift the maintainer reads
          // as "the search on History is taller than the other searches", and
          // the reason a search *bar* height equality is now pinned in
          // `search_field_geometry_consistency_test.dart` alongside the
          // field's own.
          const SizedBox(height: WpSpacing.xs),

          // ── Filter chips + controls ──────────────────────────────────────
          //
          // `OverflowBar`, not a `Row`, and two `Wrap`s inside it — this row
          // used to squash and then overflow (ticket 03, point 7). Three
          // separate causes, all of them fixed here:
          //
          //   1. The trailing controls (result count, "Empty trash", three
          //      icon controls) were plain `Row` children, so they were laid
          //      out at their *unbounded* intrinsic width and whatever was
          //      left over went to the chips' `Expanded`. Once the controls
          //      alone were wider than the panel that leftover went negative
          //      and the row overflowed — measured at a 340 px panel it
          //      already overflowed by 7.7 px at 1.0x with the trash button
          //      showing, and by 266 px at 2.6x.
          //   2. The chips sat in a `SizedBox(height: minTouchTarget)`, a
          //      hard 48 dp cap. At 2.6x a chip's own text is taller than
          //      that, so the pills were clipped rather than merely tight.
          //      They no longer need it: `WpFilterChip` carries its own
          //      `minHeight: WpLayout.minTouchTarget` tap surface.
          //   3. The chips scrolled horizontally, which meant the answer to
          //      "the filters do not fit" was "hide some of them behind a
          //      gesture with no affordance". Wrapping shows all six.
          //
          // `OverflowBar` keeps the wide-panel look exactly as it was —
          // chips left, controls flush right on one line — and stacks the
          // two groups onto separate lines the moment their intrinsic
          // widths stop fitting, which is the "wrap, don't squash" the
          // ticket asks for. No width threshold to guess or maintain.
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.start,
            overflowSpacing: WpSpacing.xs,
            children: [
              Wrap(
                spacing: WpSpacing.xs,
                runSpacing: WpSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  WpFilterChip(
                    label: l10n.historyAll,
                    isActive: widget.activeFilter == HistoryFilter.all,
                    onTap: () => widget.onFilterChanged(HistoryFilter.all),
                    count: searchCounts?[HistoryFilter.all],
                  ),
                  WpFilterChip(
                    label: l10n.historyToday,
                    isActive: widget.activeFilter == HistoryFilter.today,
                    onTap: () => widget.onFilterChanged(HistoryFilter.today),
                    count: searchCounts?[HistoryFilter.today],
                  ),
                  WpFilterChip(
                    label: l10n.historyThisWeek,
                    isActive: widget.activeFilter == HistoryFilter.week,
                    onTap: () => widget.onFilterChanged(HistoryFilter.week),
                    count: searchCounts?[HistoryFilter.week],
                  ),
                  WpFilterChip(
                    label: l10n.historyPinned,
                    icon: LucideIcons.star,
                    isActive: widget.activeFilter == HistoryFilter.pinned,
                    onTap: () => widget.onFilterChanged(HistoryFilter.pinned),
                    count: searchCounts?[HistoryFilter.pinned],
                  ),
                  WpFilterChip(
                    label: l10n.historyArchived,
                    icon: LucideIcons.archive,
                    isActive: widget.activeFilter == HistoryFilter.archived,
                    onTap: () => widget.onFilterChanged(HistoryFilter.archived),
                    count: searchCounts?[HistoryFilter.archived],
                  ),
                  WpFilterChip(
                    label: l10n.historyTrash,
                    icon: LucideIcons.trash2,
                    isActive: widget.activeFilter == HistoryFilter.trash,
                    onTap: () => widget.onFilterChanged(HistoryFilter.trash),
                    count: searchCounts?[HistoryFilter.trash],
                  ),
                ],
              ),
              // Trailing controls. Also a Wrap, for the same reason: at large
              // text scales the group's own intrinsic width can exceed the
              // panel even on its own line, and stacking two groups only helps
              // if each of them can then break internally.
              Wrap(
                spacing: WpSpacing.xs,
                runSpacing: WpSpacing.xxs,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Result count
                  if (rawQuery.isNotEmpty)
                    Text(
                      l10n.historyResultCount(widget.resultCount),
                      style: const TextStyle(
                        fontSize: WpTypography.small,
                        color: textMuted,
                      ),
                    ),
                  // Empty Trash button (only in trash view, when items exist)
                  if (widget.onEmptyTrash != null)
                    // Tooltip dropped, MergeSemantics added — house rule 1 for a
                    // single tap target whose label is already on screen. The
                    // tooltip repeated the visible caption word for word: a hover
                    // card that teaches nothing, and a screen reader saying "Empty
                    // trash" twice (label plus tooltip field).
                    MergeSemantics(
                      child: Semantics(
                        button: true,
                        child: InkWell(
                          borderRadius: WpRadius.borderSm,
                          onTap: widget.onEmptyTrash,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: WpSpacing.sm,
                              vertical: WpSpacing.xxs,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.trash2,
                                  size: WpIconSize.sm,
                                  color: WpColors.error,
                                ),
                                const SizedBox(width: 4),
                                // Flexible for the same reason as
                                // WpFilterChip's label: inside the trailing
                                // `Wrap` this button is measured against a
                                // finite run width, and its caption is the
                                // longest string in the group.
                                Flexible(
                                  child: Text(
                                    l10n.historyEmptyTrash,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: WpTypography.small,
                                      color: WpColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
                        // Off-scale on purpose: matches the dense icon-button
                        // padding in WpRowAction so toolbar icons stay uniform.
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          widget.multiSelectMode
                              ? LucideIcons.checkCheck
                              : LucideIcons.listChecks,
                          size: WpIconSize.sm,
                          color: widget.multiSelectMode ? accent : textMuted,
                        ),
                      ),
                    ),
                  ),
                  // Sort order dropdown
                  _SortDropdown(
                    sortOrder: widget.sortOrder,
                    onChanged: widget.onSortOrderChanged,
                  ),
                  // View mode toggle
                  HistoryViewModeToggle(
                    viewMode: widget.viewMode,
                    onChanged: widget.onViewModeChanged,
                  ),
                ],
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

/// Small focusable "x" dismiss control shared by recent-search rows and
/// active-filter command chips — keyboard focus + hover feedback, matching
/// the [WpFocusRing]/[InkWell] pattern every other dismiss/tag control in
/// this feature already uses (e.g. `_EntryTagChip`, `WpFilterChip`).
class _DismissIcon extends StatefulWidget {
  const _DismissIcon({
    required this.icon,
    required this.size,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

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

class _CommandChip extends StatelessWidget {
  const _CommandChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    const accent = WpColors.accent;
    return Container(
      // Vertical 2 stays off-scale on purpose: the active-filter pill hugs its
      // small text; xxs would visibly inflate it.
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs + 2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: WpColors.accentActiveFill,
        borderRadius: WpRadius.borderFull,
        border: Border.all(color: WpColors.accentBorder30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: WpTypography.small,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          const SizedBox(width: 3),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _DismissIconState.build
          _DismissIcon(
            icon: LucideIcons.x,
            size: 11,
            color: accent,
            semanticLabel: L10n.of(context).historyRemoveFilter,
            onTap: onRemove,
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
    required this.isTrashView,
    required this.isArchiveView,
    required this.onCancelSelection,
    this.onSelectAll,
    this.totalCount,
    this.onMerge,
    this.onBatchCopy,
    this.onBatchCopyMarkdown,
    this.onExport,
    this.onArchive,
    this.onDelete,
    this.onRestore,
  });

  final int selectedCount;
  final bool isTrashView;
  final bool isArchiveView;
  final VoidCallback onCancelSelection;
  final VoidCallback? onSelectAll;
  final int? totalCount;
  final VoidCallback? onMerge;
  final VoidCallback? onBatchCopy;
  final VoidCallback? onBatchCopyMarkdown;
  final VoidCallback? onExport;
  final VoidCallback? onArchive;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const accent = WpColors.accent;
    const bg = WpColors.surfaceElevated;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xl,
        vertical: WpSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: WpColors.accentBorder20, width: 1),
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
                color: WpColors.accentBadgeFill,
                borderRadius: WpRadius.borderFull,
              ),
              child: Text(
                l10n.historyItemsSelected(selectedCount),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: WpTypography.body,
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
                  vertical: WpSpacing.xxs,
                ),
                child: Text(
                  totalCount != null && selectedCount >= totalCount!
                      ? l10n.historyDeselectAll
                      : l10n.historySelectAll,
                  style: const TextStyle(
                    fontSize: WpTypography.small,
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
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryMultiSelectActionState.build
                    HistoryMultiSelectAction(
                      icon: LucideIcons.merge,
                      label: l10n.historyMerge,
                      shortcutHint: formatHotkeyShortcut(
                        'ctrl',
                        'm',
                        l10n: l10n,
                      ),
                      onTap: onMerge!,
                    ),
                  if (onBatchCopy != null)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryMultiSelectActionState.build
                    HistoryMultiSelectAction(
                      icon: LucideIcons.copy,
                      label: l10n.historyCopyText,
                      shortcutHint: formatHotkeyShortcut(
                        'ctrl',
                        'c',
                        l10n: l10n,
                      ),
                      onTap: onBatchCopy!,
                    ),
                  if (onBatchCopyMarkdown != null)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryMultiSelectActionState.build
                    HistoryMultiSelectAction(
                      icon: LucideIcons.fileText,
                      label: l10n.historyCopyAsMarkdown,
                      onTap: onBatchCopyMarkdown!,
                    ),
                  if (onExport != null)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryMultiSelectActionState.build
                    HistoryMultiSelectAction(
                      icon: LucideIcons.download,
                      label: l10n.historyExportAction,
                      onTap: onExport!,
                    ),
                  if (onRestore != null)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryMultiSelectActionState.build
                    HistoryMultiSelectAction(
                      icon: LucideIcons.undo2,
                      label: l10n.historyRestore,
                      onTap: onRestore!,
                    ),
                  if (onArchive != null)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryMultiSelectActionState.build
                    HistoryMultiSelectAction(
                      icon: isArchiveView
                          ? LucideIcons.archiveRestore
                          : LucideIcons.archive,
                      label: isArchiveView
                          ? l10n.historyUnarchive
                          : l10n.historyArchive,
                      onTap: onArchive!,
                    ),
                  if (onDelete != null)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryMultiSelectActionState.build
                    HistoryMultiSelectAction(
                      icon: LucideIcons.trash2,
                      label: isTrashView
                          ? l10n.historyDeleteForever
                          : l10n.actionDelete,
                      shortcutHint: hotkeyKeyLabel('delete', l10n: l10n),
                      onTap: onDelete!,
                      isDestructive: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          // Cancel
          // loam-ignore: a11y-interactive-semantics – semantics provided in WpButton.build
          WpButton(
            label: l10n.actionCancel,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            icon: LucideIcons.x,
            onPressed: onCancelSelection,
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
    required this.onTap,
    this.shortcutHint,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
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
    const textSecondary = WpColors.textSecondary;
    final hoverColor = widget.isDestructive
        ? (WpColors.error)
        : (WpColors.textPrimary);
    final color = _hovered ? hoverColor : textSecondary;

    // House idiom (`no_double_announcement_test.dart`, `wp_hero_button.dart`):
    // one tap target whose label is its own visible text → MergeSemantics plus
    // a *label-less* Semantics. An explicit `label: widget.label` here is not a
    // replacement for the subtree's text, it is prepended to it, so the
    // `Text(widget.label)` below made every batch action announce itself twice
    // ("Zusammenführen, Zusammenführen"). Merging folds the name in from the
    // rendered text while the button role and the tap action survive, and the
    // Tooltip's shortcut hint folds in with it — which is exactly what the
    // keyboard-first audience needs to hear.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Padding(
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
                      // WpIconSize.sm (not .md): matches WpRowAction and
                      // HistoryPopupMenuRow's fixed 16 for the same action set —
                      // .md would overwhelm this pill's 12px label.
                      Icon(widget.icon, size: WpIconSize.sm, color: color),
                      const SizedBox(width: 4),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
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
    required this.onChanged,
  });

  final HistoryViewMode viewMode;
  final ValueChanged<HistoryViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const bgColor = WpColors.surfaceVariant;
    return Container(
      // Off-scale on purpose: classic 2px segmented-control inset between the
      // track and its segments; xxs would make the track look chunky.
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: WpRadius.borderSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryViewModeButton.build
          _HistoryViewModeButton(
            icon: LucideIcons.list,
            label: L10n.of(context).historyList,
            isActive: viewMode == HistoryViewMode.list,
            onTap: () => onChanged(HistoryViewMode.list),
          ),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryViewModeButton.build
          _HistoryViewModeButton(
            icon: LucideIcons.layoutGrid,
            label: L10n.of(context).historyCards,
            isActive: viewMode == HistoryViewMode.cards,
            onTap: () => onChanged(HistoryViewMode.cards),
          ),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryViewModeButton.build
          _HistoryViewModeButton(
            icon: LucideIcons.rows3,
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
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_HistoryViewModeButton> createState() => _HistoryViewModeButtonState();
}

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
            // 4 + 16 + 4 = a 24px target, where WpFilterChip two widgets to the
            // left stretches to WpLayout.minTouchTarget (48). Left as is on
            // purpose: 24px still clears WCAG 2.2 AA (2.5.8), and the whole
            // right-hand toolbar cluster is deliberately dense — see the
            // multi-select button above, whose 6px padding is commented as
            // "matches WpRowAction so toolbar icons stay uniform".
            // Growing only this segment would trade a uniform cluster for a
            // lone tall one; growing the cluster is a design decision across
            // history + WpRowAction and needs the HITL gate. Bewusst nicht
            // umgesetzt, künftiges Ticket.
            child: Container(
              padding: const EdgeInsets.all(WpSpacing.xxs),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: WpRadius.borderSm,
              ),
              child: Icon(widget.icon, size: WpIconSize.sm, color: color),
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
    final isTranscribing = phase == RecordingPhase.transcribing;

    return WpButton(
      label: isRecording ? l10n.historyStopRecording : l10n.historyNewRecording,
      variant: WpButtonVariant.primary,
      tone: isRecording ? WpButtonTone.danger : WpButtonTone.accent,
      icon: isRecording ? LucideIcons.square : LucideIcons.mic,
      isLoading: isTranscribing,
      disabledTooltip: isTranscribing ? l10n.statusTranscribing : null,
      // Live in every phase but `transcribing` — `toggleRecording` decides
      // what the press means (start from idle/done/error, stop while
      // recording), exactly as it does for the hotkey.
      onPressed: isTranscribing
          ? null
          : () => ref
                .read(recordingOrchestratorProvider.notifier)
                .toggleRecording(),
    );
  }
}

// ---------------------------------------------------------------------------
// Search help tooltip button
// ---------------------------------------------------------------------------

class _SearchHelpButton extends StatelessWidget {
  const _SearchHelpButton();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const textMuted = WpColors.textMuted;
    const textPrimary = WpColors.textPrimary;
    const surface = WpColors.surfaceElevated;

    return IconButton(
      icon: const Icon(LucideIcons.info, size: 15, color: textMuted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: WpLayout.minTouchTarget,
        minHeight: WpLayout.minTouchTarget,
      ),
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
                    style: const TextStyle(
                      fontSize: WpTypography.body,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  _HelpRow(
                    icon: LucideIcons.tag,
                    text: l10n.historySearchHelpTags,
                    example: '#meeting',
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  _HelpRow(
                    icon: LucideIcons.globe,
                    text: l10n.historySearchHelpLang,
                    example: 'lang:en',
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  _HelpRow(
                    icon: LucideIcons.textSearch,
                    text: l10n.historySearchHelpFreeText,
                    example: '',
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
  });

  final IconData icon;
  final String text;
  final String example;

  @override
  Widget build(BuildContext context) {
    const textMuted = WpColors.textMuted;
    const accent = WpColors.accent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: textMuted),
        const SizedBox(width: WpSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: WpTypography.small,
              color: textMuted,
            ),
          ),
        ),
        if (example.isNotEmpty) ...[
          const SizedBox(width: WpSpacing.xs),
          Container(
            // Vertical 1 stays off-scale on purpose: the example mini-chip hugs
            // its caption text; xxs would double the chip height.
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.xxs,
              vertical: 1,
            ),
            decoration: BoxDecoration(
              color: WpColors.accentChipFill,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              example,
              style: const TextStyle(
                fontSize: WpTypography.caption,
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
  const _SortDropdown({required this.sortOrder, required this.onChanged});

  final HistorySortOrder sortOrder;
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
    const textMuted = WpColors.textMuted;
    const accent = WpColors.accent;

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
                  fontSize: WpTypography.body,
                  color: isSelected ? accent : null,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
