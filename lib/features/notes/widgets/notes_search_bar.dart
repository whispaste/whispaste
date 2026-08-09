import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_search_field.dart';
import '../data/providers.dart';

// ---------------------------------------------------------------------------
// Notes search & filter bar — search field (Ticket 06) with the "new note"
// button beside it (same row layout as the replacements toolbar), above the
// active/trash toggle (Ticket 04).
// ---------------------------------------------------------------------------

class NotesSearchBar extends StatelessWidget {
  const NotesSearchBar({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.isDark,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.resultCount,
    required this.showResultCount,
    required this.onCreate,
  });

  final NotesFilter currentFilter;
  final ValueChanged<NotesFilter> onFilterChanged;
  final bool isDark;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// Reads [searchController]'s text itself — same contract as
  /// HistorySearchFilterBar's onSearchChanged.
  final VoidCallback onSearchChanged;
  final int resultCount;
  final bool showResultCount;

  /// Creates a new note — rendered as the trailing "new note" button.
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Padding(
      // Same side inset as every other list area's search bar (History,
      // Replacements, Snippets): xl left/right, sm top/bottom — so switching
      // areas via the sidebar never shifts the search field sideways.
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
          // ── Search field + "new note" button ─────────────────────────────
          Row(
            children: [
              Expanded(
                child: WpSearchField(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  hintText: l10n.notesSearchPlaceholder,
                  variant: WpSearchFieldVariant.outlined,
                  onChanged: (_) => onSearchChanged(),
                  semanticsLabel: l10n.notesSearchFieldLabel,
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              WpButton(
                label: l10n.notesNewNote,
                variant: WpButtonVariant.primary,
                icon: LucideIcons.plus,
                onPressed: onCreate,
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xs),
          // ── Filter chips + result count ──────────────────────────────────
          Row(
            children: [
              WpFilterChip(
                label: l10n.navNotes,
                icon: LucideIcons.stickyNote,
                isActive: currentFilter == NotesFilter.active,
                isDark: isDark,
                onTap: () => onFilterChanged(NotesFilter.active),
              ),
              const SizedBox(width: WpSpacing.xs),
              WpFilterChip(
                label: l10n.notesTrash,
                icon: LucideIcons.trash2,
                isActive: currentFilter == NotesFilter.trash,
                isDark: isDark,
                onTap: () => onFilterChanged(NotesFilter.trash),
              ),
              if (showResultCount) ...[
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(left: WpSpacing.sm),
                  child: Text(
                    l10n.notesResultCount(resultCount),
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      color: textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
