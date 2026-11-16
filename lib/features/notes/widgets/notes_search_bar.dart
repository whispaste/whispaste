import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/sorting/list_sort.dart';
import '../../../core/sorting/list_sort_preference.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_collection_page.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_search_field.dart';
import '../../../widgets/wp_sort_menu_button.dart';
import '../data/notes_view_options.dart';
import '../data/providers.dart';

// ---------------------------------------------------------------------------
// Notes head — the page family's toolbar (`WpCollectionToolbar`,
// `internal-notes`) filled with the notes' search, chips and tools.
// ---------------------------------------------------------------------------

class NotesSearchBar extends ConsumerWidget {
  const NotesSearchBar({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.resultCount,
    required this.showResultCount,
    required this.onCreate,
    this.selecting = false,
    this.onToggleSelecting,
  });

  final NotesFilter currentFilter;
  final ValueChanged<NotesFilter> onFilterChanged;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// Reads [searchController]'s text itself — same contract as
  /// HistorySearchFilterBar's onSearchChanged.
  final VoidCallback onSearchChanged;
  final int resultCount;
  final bool showResultCount;

  /// Creates a new note — rendered as the trailing "new note" button.
  final VoidCallback onCreate;

  /// Whether multi-select is on (#655) — the toggle shows it as pressed.
  final bool selecting;

  /// Turns multi-select on or off; `null` hides the toggle (empty list).
  final VoidCallback? onToggleSelecting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final isActive = currentFilter == NotesFilter.active;
    final sort = ref.watch(notesSortProvider).value ?? kNotesDefaultSort;
    final grouped = ref.watch(notesGroupByDateProvider).value ?? false;
    final tagFilter = ref.watch(notesTagFilterProvider);
    final usedTags = ref.watch(notesTagsInUseProvider);

    String sortLabel(ListSort s) => wpSortOrderLabel(
      l10n,
      fieldLabel: switch (s.field) {
        ListSortField.title => l10n.listSortFieldTitle,
        ListSortField.added => l10n.listSortFieldAdded,
        _ => l10n.listSortFieldChanged,
      },
      isDate: s.field != ListSortField.title,
      reversed: s.reversed,
    );
    Future<void> chooseSort(ListSort next) => saveListSort(
      context,
      save: () => ref.read(notesSortProvider.notifier).choose(next),
      orderLabel: (_) => sortLabel(next),
    );

    // Every control sits at the place the page family gives it
    // (`WpCollectionToolbar`, concept `internal-notes`, #1201), as on
    // Recordings: one row with search, filter marks, the filter popover
    // (view, tags), result count, sort, date grouping and "new note".
    return WpCollectionToolbar(
      screenId: 'notes',
      search: WpSearchField(
        key: const ValueKey('notes-search-field'),
        testId: 'notes-search-field',
        controller: searchController,
        focusNode: searchFocusNode,
        hintText: l10n.notesSearchPlaceholder,
        variant: WpSearchFieldVariant.outlined,
        onChanged: (_) => onSearchChanged(),
        semanticsLabel: l10n.notesSearchFieldLabel,
      ),
      // An icon button of the field's height (WpLayout.controlHeight,
      // UX-131); the label becomes the tooltip and the accessible name.
      primaryAction: WpIconButton(
        key: const ValueKey('notes-new-note'),
        testId: 'notes-new-note',
        icon: LucideIcons.plus,
        tooltip: l10n.notesNewNote,
        onPressed: onCreate,
      ),
      filterSections: [
        WpFilterSection(
          id: 'view',
          label: l10n.collectionFilterShow,
          children: [
            WpFilterChip(
              testId: 'notes-filter-active',
              label: l10n.navNotes,
              icon: LucideIcons.stickyNote,
              isActive: currentFilter == NotesFilter.active,
              onTap: () => onFilterChanged(NotesFilter.active),
            ),
            WpFilterChip(
              testId: 'notes-filter-trash',
              label: l10n.notesTrash,
              icon: LucideIcons.trash2,
              isActive: currentFilter == NotesFilter.trash,
              onTap: () => onFilterChanged(NotesFilter.trash),
            ),
          ],
        ),
        // The trash has no tags to filter by.
        if (isActive && usedTags.isNotEmpty)
          WpFilterSection(
            id: 'tags',
            label: l10n.notesTagFilterLabel,
            children: [
              for (final tag in usedTags)
                WpFilterChip(
                  testId: 'notes-tag-filter-${tag.id}',
                  label: tag.name,
                  icon: LucideIcons.tag,
                  isActive: tagFilter.contains(tag.id),
                  onTap: () =>
                      ref.read(notesTagFilterProvider.notifier).toggle(tag.id),
                ),
            ],
          ),
      ],
      activeFilters: [
        if (!isActive)
          WpActiveFilter(
            id: 'view',
            label: l10n.notesTrash,
            onRemove: () => onFilterChanged(NotesFilter.active),
          ),
        if (isActive)
          for (final tag in usedTags)
            if (tagFilter.contains(tag.id))
              WpActiveFilter(
                id: 'tag-${tag.id}',
                label: '#${tag.name}',
                onRemove: () =>
                    ref.read(notesTagFilterProvider.notifier).toggle(tag.id),
              ),
      ],
      status: [
        if (showResultCount)
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.notesResultCount(resultCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: WpTypography.small, color: textMuted),
            ),
          ),
      ],
      // The trash keeps its deletion order, so it has neither a sort menu nor
      // a date grouping. Up to three small icons (select, sort, grouping)
      // stay inline on every width (no overflow button needed).
      tools: [
        if (onToggleSelecting != null)
          Semantics(
            toggled: selecting,
            child: WpIconButton.ghost(
              key: const ValueKey('notes-select-toggle'),
              testId: 'notes-select-toggle',
              icon: selecting ? LucideIcons.checkCheck : LucideIcons.listChecks,
              tooltip: l10n.notesSelectMode,
              color: selecting ? WpColors.accent : null,
              onPressed: onToggleSelecting,
            ),
          ),
        if (isActive) ...[
          WpSortMenuButton<ListSortField>(
            testId: 'notes-sort',
            tooltip: l10n.listSortMenuTooltip(sortLabel(sort)),
            current: sort.field,
            options: [
              WpSortOption(
                value: ListSortField.title,
                id: 'title',
                label: l10n.listSortFieldTitle,
                icon: LucideIcons.type,
              ),
              WpSortOption(
                value: ListSortField.added,
                id: 'added',
                label: l10n.listSortFieldAdded,
                icon: LucideIcons.calendarPlus,
              ),
              WpSortOption(
                value: ListSortField.changed,
                id: 'changed',
                label: l10n.listSortFieldChanged,
                icon: LucideIcons.pencilLine,
              ),
            ],
            onChanged: (field) => chooseSort(ListSort(field)),
            reversed: sort.reversed,
            reverseLabel: l10n.listSortReverse,
            onReversedChanged: (reversed) =>
                chooseSort(ListSort(sort.field, reversed: reversed)),
          ),
          // Date grouping is a view option, so it sits with the view tools
          // (Recordings: list/cards/compact) instead of among the filters.
          // `selected` makes the button itself the toggle; a Semantics
          // wrapper around it was a second, unnamed checkbox node (#1498).
          if (canGroupByDate(sort))
            WpIconButton(
              key: const ValueKey('notes-group-by-date'),
              testId: 'notes-group-by-date',
              icon: LucideIcons.calendarDays,
              tooltip: l10n.notesGroupByDate,
              selected: grouped,
              onPressed: () =>
                  ref.read(notesGroupByDateProvider.notifier).choose(!grouped),
            ),
        ],
      ],
    );
  }
}
