import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';
import 'wp_cut_illustration.dart';

export 'wp_cut_illustration.dart' show WpEmptyMotif;

/// Empty state — centered illustration, title, hint, and one first action.
///
/// The base "nothing here yet" state of a collection page passes its
/// paper-cut [motif] ([WpCutIllustration], #1595: recordings, notes,
/// snippets). Every other state (filters, trash, errors) keeps the icon
/// still life ([WpEmptyIllustration]): two stacked blank cards on a soft
/// accent wash, the area's icon on a small accent badge. Both are built from
/// theme roles only, so light, dark and Marine each draw them in their own
/// tones; neither moves (#1076).
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
    this.motif,
  }) : _searchQuery = null,
       _panel = false;

  /// The same state sized for a narrow floating surface (side panel, snippet
  /// picker, #1757): no illustration, the area's icon in `textMuted`, a
  /// body-size title and a caption hint, and a dense secondary action, so a
  /// 360-pt panel keeps its list area calm.
  const WpEmptyState.panel({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.actionTestId,
  }) : footer = null,
       motif = null,
       _searchQuery = null,
       _panel = true;

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
       motif = null,
       _searchQuery = query,
       _panel = false;

  /// Set only by [WpEmptyState.searchNoMatches]; its texts come from L10n at
  /// build time.
  final String? _searchQuery;

  /// Set only by [WpEmptyState.panel].
  final bool _panel;

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

  /// The paper-cut motif of a page's base empty state; replaces the icon
  /// still life. Only the "nothing here yet" state of a collection sets it.
  final WpEmptyMotif? motif;

  @override
  Widget build(BuildContext context) {
    if (_panel) return _panelContent(context);
    // A low pane (minimum window height under a tall header, e.g. the
    // history's three filter rows) drops the decorative illustration and the
    // wide padding, so the first action stays above the fold instead of
    // hiding below a scroll (#1076). Needs bounded height: callers inside a
    // sliver use `SliverFillRemaining(hasScrollBody: true)`, because a
    // LayoutBuilder has no intrinsic size.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Example chips below the action need room of their own: with a
        // footer the illustration goes earlier, so the chips stay in view
        // instead of below the fold (#1845).
        // A paper-cut motif stands taller than the icon still life; the
        // thresholds grow by the difference so the action (and a footer)
        // keep the room they had (#1595).
        final extra = motif == null
            ? 0.0
            : WpCutIllustration.defaultSize - WpEmptyIllustration.height;
        final threshold =
            (footer == null
                ? compactBelowHeight
                : compactWithFooterBelowHeight) +
            extra;
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < threshold;
        return _content(context, compact: compact);
      },
    );
  }

  /// Pane height below which the state renders without its illustration.
  static const double compactBelowHeight = 400;

  /// The same threshold when a [footer] follows the action.
  static const double compactWithFooterBelowHeight = 560;

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
                if (motif case final motif?)
                  WpCutIllustration(motif: motif)
                else
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

extension _PanelContent on WpEmptyState {
  Widget _panelContent(BuildContext context) {
    final hint = this.hint;
    final actionLabel = this.actionLabel;
    // Scrollable like the full state: a long hint at 200 % text scale in the
    // narrow panel scrolls instead of overflowing.
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xl,
            vertical: WpSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: WpIconSize.xl, color: WpColors.textMuted),
              const SizedBox(height: WpSpacing.sm),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WpColors.textSecondary,
                  fontSize: WpTypography.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: WpSpacing.xxs),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: WpColors.textMuted,
                    fontSize: WpTypography.caption,
                    height: 1.35,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: WpSpacing.md),
                WpButton(
                  label: actionLabel,
                  testId: actionTestId,
                  variant: WpButtonVariant.secondary,
                  size: WpButtonSize.dense,
                  onPressed: onAction,
                ),
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
