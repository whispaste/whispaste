import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'dialog.dart';
import 'empty_state.dart';
import 'page_shell.dart';

/// Shared scaffold for the searchable-list settings features (Replacements,
/// Automations, Snippets): a toolbar with search field and Add button above
/// a searchable list, with loading / error / empty / no-matches states.
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
    this.toolbarTrailing = const [],
    this.contentWrapper,
  });

  /// The feature's full item list, as exposed by its Riverpod provider.
  final AsyncValue<List<T>> asyncAll;

  /// Whether [item] matches the search query. Called only for non-empty
  /// queries; `query` is already lowercased.
  final bool Function(T item, String query) searchMatches;

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

  /// Extra toolbar widgets between the search field and the Add button
  /// (e.g. the Replacements enable/disable switch). Include your own
  /// trailing spacing.
  final List<Widget> toolbarTrailing;

  /// Optional wrapper around the list / empty-state area (e.g. dimming via
  /// `AnimatedOpacity` while the feature is disabled).
  final Widget Function(BuildContext context, Widget child)? contentWrapper;

  @override
  State<WpSearchableListPage<T>> createState() =>
      _WpSearchableListPageState<T>();
}

class _WpSearchableListPageState<T> extends State<WpSearchableListPage<T>> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<T> _filtered(List<T> all) {
    if (_searchQuery.isEmpty) return all;
    final q = _searchQuery.toLowerCase();
    return all.where((item) => widget.searchMatches(item, q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: widget.asyncAll.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: widget.searchHint,
                          prefixIcon: Icon(
                            LucideIcons.search,
                            size: WpIconSize.sm,
                            color: isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: WpSpacing.md,
                            vertical: WpSpacing.xs + 2,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    ...widget.toolbarTrailing,
                    // Add button
                    ElevatedButton.icon(
                      onPressed: widget.onAdd,
                      icon: const Icon(LucideIcons.plus, size: WpIconSize.sm),
                      label: Text(widget.addLabel),
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
