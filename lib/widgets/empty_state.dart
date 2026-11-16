import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';

/// Empty state — centered illustration, title, hint, and one first action.
///
/// The illustration ([WpEmptyIllustration]) is a calm, flat still life: two
/// stacked blank cards on a soft accent wash, the area's icon on a small
/// accent badge. Built from theme roles only, so light, dark and Marine
/// each draw it in their own tones; it never moves (#1076).
///
/// When to pass an action — one rule, the same on every page: **every empty
/// state offers exactly one first action.** The area's main action whenever
/// it has one; that the action is also reachable elsewhere (a toolbar
/// button, say) is no reason to leave it out, because an empty area is where
/// the user looks for it most urgently. Use the same wording in both places.
/// Areas that fill from elsewhere point there: the history and the
/// statistics offer "Dictate", a trash leads back to its list, dictionary
/// suggestions lead to the recordings where corrections are made. Error
/// states offer "try again". A search-found-nothing state offers "clear
/// search" without exception — history, notes and snippets own their field,
/// settings resets it through its query provider, and the shared
/// [WpSearchableListPage] covers replacements. On the collection pages the
/// empty state is also the one place for the page's own hint (#1498).
///
/// "Search found nothing" has one look everywhere: [WpEmptyState.searchNoMatches]
/// (title "No matches", a hint that names the query, "Clear search" with the
/// test id `<screen>-search-clear`).
class WpEmptyState extends StatelessWidget {
  const WpEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.actionTestId,
    this.footer,
  }) : _searchQuery = null;

  /// The one "search found nothing" state of every list with a search field
  /// (#1498): the shared title and a hint naming [query], and "Clear search"
  /// as the way back. [testId] follows `<screen>-search-clear`.
  const WpEmptyState.searchNoMatches({
    super.key,
    required String query,
    required VoidCallback onClear,
    required String testId,
  }) : icon = LucideIcons.searchX,
       title = '',
       hint = null,
       actionLabel = null,
       onAction = onClear,
       actionTestId = testId,
       footer = null,
       _searchQuery = query;

  /// Set only by [WpEmptyState.searchNoMatches]; its texts come from L10n at
  /// build time.
  final String? _searchQuery;

  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Stable, language-independent id of the action button.
  final String? actionTestId;

  /// Optional content below the action, e.g. example chips that teach the
  /// area by showing what an entry looks like. It never adds anything alone.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    // A low pane (minimum window height under a tall header, e.g. the
    // history's three filter rows) drops the decorative illustration and the
    // wide padding, so the first action stays above the fold instead of
    // hiding below a scroll (#1076). Needs bounded height: callers inside a
    // sliver use `SliverFillRemaining(hasScrollBody: true)`, because a
    // LayoutBuilder has no intrinsic size.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedHeight &&
            constraints.maxHeight < compactBelowHeight;
        return _content(context, compact: compact);
      },
    );
  }

  /// Pane height below which the state renders without its illustration.
  static const double compactBelowHeight = 400;

  Widget _content(BuildContext context, {required bool compact}) {
    final searchQuery = _searchQuery;
    final l10n = searchQuery == null ? null : L10n.of(context);
    final title = l10n?.searchNoMatches ?? this.title;
    final hint = l10n?.searchNoMatchesHint(searchQuery!.trim()) ?? this.hint;
    final actionLabel = l10n?.actionClearSearch ?? this.actionLabel;
    // Scrollable so a tight viewport still degrades to scrolling instead of
    // a RenderFlex overflow.
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(compact ? WpSpacing.lg : WpSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                WpEmptyIllustration(icon: icon),
                const SizedBox(height: WpSpacing.xl),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (hint != null) ...[
                const SizedBox(height: WpSpacing.xs),
                SizedBox(
                  width: 300,
                  child: Text(
                    hint,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: WpSpacing.lg),
                WpButton(
                  label: actionLabel,
                  testId: actionTestId,
                  variant: WpButtonVariant.primary,
                  onPressed: onAction,
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: WpSpacing.lg),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The calm still life above an empty state's title: a back card turned a
/// few degrees, a front card with two blank text lines, and the area's icon
/// on an accent badge at the front card's corner, all on a soft accent wash.
/// Decorative — the title says what is empty — so it is excluded from
/// semantics. Static by design: nothing here animates, so "reduce motion"
/// needs no branch.
class WpEmptyIllustration extends StatelessWidget {
  const WpEmptyIllustration({super.key, required this.icon});

  final IconData icon;

  static const double width = 136;
  static const double height = 104;

  @override
  Widget build(BuildContext context) {
    final card = BoxDecoration(
      color: WpColors.surfaceElevated,
      borderRadius: WpRadius.borderMd,
      border: Border.all(color: WpColors.borderDefault),
    );
    Widget line(double w) => Container(
      width: w,
      height: 6,
      decoration: BoxDecoration(
        color: WpColors.borderSubtle,
        borderRadius: WpRadius.borderFull,
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Soft wash behind the cards.
            Positioned(
              left: 18,
              top: 2,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: WpColors.accentSubtle,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Back card, turned a few degrees.
            Positioned(
              left: 40,
              top: 14,
              child: Transform.rotate(
                angle: 0.12,
                child: Container(
                  width: 64,
                  height: 72,
                  decoration: card.copyWith(color: WpColors.surface),
                ),
              ),
            ),
            // Front card with two blank text lines.
            Positioned(
              left: 28,
              top: 24,
              child: Container(
                width: 68,
                height: 72,
                padding: const EdgeInsets.all(WpSpacing.md),
                decoration: card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(40),
                    const SizedBox(height: WpSpacing.sm),
                    line(28),
                  ],
                ),
              ),
            ),
            // The area's icon on an accent badge at the front card's corner.
            Positioned(
              left: 76,
              top: 58,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WpColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(color: WpColors.accentBorder30, width: 2),
                ),
                child: Icon(icon, size: WpIconSize.md, color: WpColors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
