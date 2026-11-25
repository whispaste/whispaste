import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/sorting/list_sort.dart';
import '../../../core/sorting/list_sort_preference.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/views/smart_view.dart';
import '../../../core/views/smart_view_providers.dart';
import '../../../widgets/wp_collection_page.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_search_field.dart';
import '../../../widgets/wp_sort_menu_button.dart';
import '../../views/smart_view_ui.dart';
import '../data/notes_view_options.dart';
import '../data/providers.dart';
import 'note_folder_dialogs.dart';

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
    this.onCreateFolder,
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

  /// Creates the first folder (#659). Offered in the filter popover only
  /// while no folder exists; afterwards the folder row above the list has
  /// its own button.
  final VoidCallback? onCreateFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final isActive = currentFilter == NotesFilter.active;
    final sort = ref.watch(notesSortProvider).value ?? kNotesDefaultSort;
    final tagFilter = ref.watch(notesTagFilterProvider);
    final usedTags = ref.watch(notesTagsInUseProvider);
    // Saved views (#658) narrow the active list only; Archive and Trash
    // leave the view (see `_setFilter` on the page).
    const scope = SmartViewScope.notes;
    final viewShown =
        isActive && ref.watch(shownSmartViewProvider(scope)) != null;
    Future<List<Tag>> loadTags() => ref.read(historyDatabaseProvider).allTags();
    final folders =
        ref.watch(noteFoldersProvider).value ?? const <NoteFolder>[];
    final foldersById = ref.watch(noteFoldersByIdProvider);
    final shownFolderId = isActive && !viewShown
        ? ref.watch(shownNoteFolderIdProvider)
        : null;
    final shownFolder = shownFolderId == null
        ? null
        : foldersById[shownFolderId];
    final viewMark = isActive
        ? smartViewActiveFilter(context, ref, scope: scope)
        : null;

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
    // (view, tags), result count, sort and "new note".
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
        // A view only shows what matches its rules, so a new note could
        // vanish from it at once; creating waits until the view is left, and
        // the tooltip says so (#658).
        tooltip: viewShown ? l10n.smartViewCreateLocked : l10n.notesNewNote,
        onPressed: viewShown ? null : onCreate,
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
              testId: 'notes-filter-archive',
              label: l10n.notesArchive,
              icon: LucideIcons.archive,
              isActive: currentFilter == NotesFilter.archive,
              onTap: () => onFilterChanged(NotesFilter.archive),
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
        if (isActive)
          smartViewFilterSection(
            context,
            ref,
            scope: scope,
            screenId: 'notes',
            loadTags: loadTags,
            folders: folders,
          ),
        // Folders stay out of sight until someone decides on one (ADR 0034):
        // the first one starts here, the rest from the folder row.
        if (isActive && folders.isEmpty && onCreateFolder != null)
          WpFilterSection(
            id: 'folders',
            label: l10n.notesFolders,
            children: [
              WpFilterChip(
                testId: 'notes-filter-folder-new',
                label: l10n.notesFolderNewEllipsis,
                icon: LucideIcons.folderPlus,
                isActive: false,
                onTap: onCreateFolder!,
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
            label: currentFilter == NotesFilter.archive
                ? l10n.notesArchive
                : l10n.notesTrash,
            onRemove: () => onFilterChanged(NotesFilter.active),
          ),
        ?viewMark,
        if (shownFolder != null)
          WpActiveFilter(
            id: 'folder',
            label: noteFolderPath(shownFolder, foldersById),
            onRemove: () =>
                ref.read(notesFolderFilterProvider.notifier).set(null),
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
        if (isActive)
          ...smartViewStatus(
            context,
            ref,
            scope: scope,
            screenId: 'notes',
            loadTags: loadTags,
            folders: folders,
          ),
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
      // The trash keeps its deletion order, so it has no sort menu. Select
      // and sort are the same tools as on Recordings and Snippets; a date
      // sort brings its day sections itself, as on Recordings.
      tools: [
        // The bordered icon button every toolbar control shares, as on
        // Recordings and Snippets; `selected` makes it the toggle and
        // announces its state (a Semantics wrapper was a second node, #1498).
        if (onToggleSelecting != null)
          WpIconButton(
            key: const ValueKey('notes-select-toggle'),
            testId: 'notes-select-toggle',
            icon: selecting ? LucideIcons.checkCheck : LucideIcons.listChecks,
            tooltip: l10n.notesSelectMode,
            selected: selecting,
            onPressed: onToggleSelecting,
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
        ],
      ],
    );
  }
}
