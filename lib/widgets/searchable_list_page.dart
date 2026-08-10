import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/tokens.dart';
import 'dialog.dart';
import 'empty_state.dart';
import 'page_shell.dart';
import 'wp_button.dart';
import 'wp_list_skeleton.dart';
import 'wp_search_field.dart';

/// Shared scaffold for the searchable-list settings features (Replacements,
/// Snippets): a toolbar with search field and Add button above a searchable
/// list, with loading / error / empty / no-matches states.
///
/// Purely visual — data loading, dialogs, and deletion stay with the owning
/// page and are injected via callbacks. Rendering is pixel-identical to the
/// per-feature pages this was extracted from.
class WpSearchableListPage<T> extends StatefulWidget {
  const WpSearchableListPage({
    super.key,
    required this.asyncAll,
    required this.searchMatches,
    required this.searchHint,
    required this.addLabel,
    required this.onAdd,
    required this.onRetry,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    required this.emptyActionLabel,
    required this.noMatchesTitle,
    required this.noMatchesHint,
    required this.itemBuilder,
    this.contentWrapper,
    this.header,
  });

  /// The feature's full item list, as exposed by its Riverpod provider.
  final AsyncValue<List<T>> asyncAll;

  /// Whether [item] matches the search query. Called only for non-empty
  /// queries; `query` is a precompiled case-insensitive regex.
  final bool Function(T item, RegExp query) searchMatches;

  /// Hint text of the toolbar search field.
  final String searchHint;

  /// Label of the toolbar Add button.
  final String addLabel;

  /// Opens the feature's add dialog (toolbar button and empty-state CTA).
  final VoidCallback onAdd;

  /// Retries loading after an error (typically `ref.invalidate(provider)`).
  final VoidCallback onRetry;

  /// Icon, title, hint, and CTA label of the no-items-yet empty state.
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;
  final String emptyActionLabel;

  /// Title and hint of the search-found-nothing empty state.
  final String noMatchesTitle;
  final String noMatchesHint;

  /// Builds one list tile. [isDark] is the current theme brightness, passed
  /// through so tiles don't each re-derive it.
  final Widget Function(BuildContext context, T item, bool isDark) itemBuilder;

  /// Optional wrapper around the list / empty-state area (e.g. dimming via
  /// `AnimatedOpacity` while the feature is disabled).
  final Widget Function(BuildContext context, Widget child)? contentWrapper;

  /// Optional widget above the toolbar, shown in every load state (e.g. the
  /// Snippets page's picker-trigger field). Include your own outer padding.
  final Widget? header;

  @override
  State<WpSearchableListPage<T>> createState() =>
      _WpSearchableListPageState<T>();
}

/// Placeholder-bar height of the loading skeleton, matched to the real rows.
/// Measured at full list width: a Snippets tile and a Replacements tile both
/// render at exactly 70 dp (identical anatomy — `md`/`sm` padding around a
/// title line plus a one-line preview), so the two features share one value
/// instead of each guessing its own.
const _searchableListSkeletonRowHeight = 70.0;

class _WpSearchableListPageState<T> extends State<WpSearchableListPage<T>> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Resets the search from outside the field (the no-matches empty state).
  /// Mirrors what the field's own clear button does — [TextEditingController]
  /// fires no `onChanged`, so the query has to be reset alongside the text.
  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  List<T> _filtered(List<T> all) {
    if (_searchQuery.isEmpty) return all;
    final q = RegExp(RegExp.escape(_searchQuery), caseSensitive: false);
    return all.where((item) => widget.searchMatches(item, q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final body = widget.asyncAll.when(
      // Same list-shaped placeholder History and Notes use. A centred spinner
      // used to sit here, which made these two the only list surfaces in the
      // app whose loading state neither reserved the rows' space nor matched
      // its siblings — the list visibly re-flowed the moment data arrived.
      loading: () => WpListSkeleton(
        isDark: isDark,
        rowHeight: _searchableListSkeletonRowHeight,
        // The real rows below sit on the `xl` gutter, not the skeleton's
        // history/notes default — pass it so the bars land on their edge.
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xl,
          vertical: WpSpacing.xs,
        ),
      ),
      error: (e, _) => WpEmptyState(
        icon: LucideIcons.triangleAlert,
        title: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        onAction: widget.onRetry,
      ),
      data: (all) {
        final visible = _filtered(all);
        final content = all.isEmpty
            ? WpEmptyState(
                icon: widget.emptyIcon,
                title: widget.emptyTitle,
                hint: widget.emptyHint,
                actionLabel: widget.emptyActionLabel,
                onAction: widget.onAdd,
              )
            : visible.isEmpty
            ? WpEmptyState(
                icon: LucideIcons.searchX,
                title: widget.noMatchesTitle,
                hint: widget.noMatchesHint,
                // Per the WpEmptyState rule the search-empty state offers its
                // main action: get out of the search. Verlauf and Notizen say
                // the same thing with their own keys, whose wording is
                // byte-identical to the generic one in every locale — so this
                // reuses the generic key instead of minting a fourth string.
                actionLabel: l10n.actionClearSearch,
                onAction: _clearSearch,
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.xl,
                  vertical: WpSpacing.xs,
                ),
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: WpSpacing.xs),
                itemBuilder: (context, index) =>
                    widget.itemBuilder(context, visible[index], isDark),
              );
        return Column(
          children: [
            // Toolbar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WpSpacing.xl,
                WpSpacing.sm,
                WpSpacing.xl,
                WpSpacing.sm,
              ),
              child: Row(
                children: [
                  // Search
                  Expanded(
                    child: WpSearchField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hintText: widget.searchHint,
                      variant: WpSearchFieldVariant.outlined,
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // Add button
                  WpButton(
                    label: widget.addLabel,
                    variant: WpButtonVariant.primary,
                    icon: LucideIcons.plus,
                    onPressed: widget.onAdd,
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.contentWrapper?.call(context, content) ?? content,
            ),
          ],
        );
      },
    );

    // Ctrl+F / Cmd+F focuses the search field — the one shortcut History,
    // Notes and Settings all bind. Snippets and Replacements were the only
    // searchable surfaces without it, so the muscle memory broke on exactly
    // two of five screens. Binding it on the shared shell fixes both at once.
    //
    // Ctrl+N / Cmd+N adds an item, for the same reason: Notes had it, its two
    // sibling list screens did not, so "create without reaching for the
    // mouse" was a skill that only worked on one of the three. No
    // text-field guard, deliberately — Ctrl/Cmd+N is not a text-editing
    // binding on any of the three platforms (Flutter binds Ctrl+N to
    // "line down" only in its macOS Emacs set, and there we send Cmd+N), so
    // consuming it while the search field has focus costs nothing and firing
    // it there is what every desktop app does.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): _searchFocusNode.requestFocus,
        SingleActivator(
          LogicalKeyboardKey.keyN,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): widget.onAdd,
      },
      // `skipTraversal` so this wrapper never becomes a Tab stop of its own;
      // it exists only to give the shortcut a focused descendant to bubble
      // from, exactly as `SettingsPage` does it.
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: WpPageShell(
          scrollable: false,
          padding: EdgeInsets.zero,
          child: widget.header == null
              ? body
              : Column(
                  children: [
                    widget.header!,
                    Expanded(child: body),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Shared delete-confirmation flow of the searchable-list features: shows the
/// standard destructive [showWpConfirmDialog] (Delete / Cancel labels) and
/// runs [onConfirm] only when the user confirmed.
Future<void> showWpDeleteConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required VoidCallback onConfirm,
}) async {
  final l10n = L10n.of(context);
  final confirmed = await showWpConfirmDialog(
    context: context,
    title: title,
    message: message,
    confirmLabel: l10n.actionDelete,
    cancelLabel: l10n.actionCancel,
    destructive: true,
  );
  if (confirmed) onConfirm();
}
